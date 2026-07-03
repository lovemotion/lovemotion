;;;; db.lisp — Postgres adapter around the pure core.
;;;;
;;;; The engine stays a pure function twin-set -> payload; this file owns
;;;; the fetch/persist seams. Nothing in src/engine.lisp knows it exists.
;;;;
;;;; Reproducibility contract (Handoff.md):
;;;;   * axis_values is append-only; each run reads latest-per-(twin,axis)
;;;;     as of runs.started_at via DISTINCT ON.
;;;;   * run_twins freezes the set of twins considered; eligibility is
;;;;     recomputed on replay, never stored.
;;;;   * Snapshot + read + write happen inside one REPEATABLE READ
;;;;     transaction.
;;;;   * Canonical pair order (twin_a < twin_b) is enforced by the engine
;;;;     at its single write site; the DB CHECK is a tripwire only.

(defpackage :lovemotion.db
  (:use :cl)
  (:export #:*db-spec*
           #:with-db
           #:check-connection
           #:store-twin
           #:record-axis-value
           #:fetch-twins-as-of
           #:load-config
           #:run-matching-from-db
           #:replay-run))

(in-package :lovemotion.db)

;;; ---------------------------------------------------------------------
;;; Connection
;;; ---------------------------------------------------------------------

(defun env (name default)
  (or (uiop:getenv name) default))

(defparameter *db-spec*
  (list (env "LM_DB_NAME" "lovemotion_v0")
        (env "LM_DB_USER" "lovemotion")
        (env "LM_DB_PASS" "lovemotion")
        (env "LM_DB_HOST" "localhost")
        :port (parse-integer (env "LM_DB_PORT" "5432"))
        :pooled-p t))

(defmacro with-db (&body body)
  `(postmodern:with-connection *db-spec*
     ,@body))

(defun check-connection ()
  (handler-case (with-db (postmodern:query "SELECT 1" :single) t)
    (error () nil)))

;;; ---------------------------------------------------------------------
;;; Value conversion — keywords/lists on the Lisp side, text/arrays in PG
;;; ---------------------------------------------------------------------

(defun kw (string)
  (intern (string-upcase string) :keyword))

(defun kw-name (keyword)
  (string-downcase (symbol-name keyword)))

(defun lisp-value->columns (value)
  "Typed-value trio: exactly one of (scalar categorical tagset).
Booleans ride in categorical as true/false; T reads back as T, false
reads back as NIL so predicate code sees CL truth."
  (etypecase value
    (real    (values value :null :null))
    (symbol  (values :null
                     (case value ((t) "true") ((nil) "false")
                           (t (kw-name value)))
                     :null))
    (cons    (values :null :null
                     (coerce (mapcar #'kw-name value) 'vector)))))

(defun columns->lisp-value (scalar categorical tagset)
  (cond ((not (eq scalar :null))
         ;; NUMERIC arrives as a rational; the engine's arithmetic is
         ;; single-float. Coerce here so DB-fed runs are bit-identical
         ;; to in-memory runs.
         (coerce scalar 'single-float))
        ((not (eq categorical :null))
         (cond ((string= categorical "true") t)
               ((string= categorical "false") nil)
               (t (kw categorical))))
        (t (map 'list #'kw tagset))))

;;; ---------------------------------------------------------------------
;;; Ingest seam
;;; ---------------------------------------------------------------------

(defun store-twin (twin-id)
  (postmodern:query
   "INSERT INTO twins (twin_id) VALUES ($1) ON CONFLICT DO NOTHING"
   twin-id :none))

(defun record-axis-value (twin-id axis-id value
                          &key (confidence (error "confidence is required"))
                               (provenance (error "provenance is required"))
                               observed-at)
  "Append one observation. CONFIDENCE has no default on purpose — it must
never silently become 1.0. OBSERVED-AT defaults to now() in the DB."
  (multiple-value-bind (scalar categorical tagset) (lisp-value->columns value)
    (postmodern:query
     "INSERT INTO axis_values
        (twin_id, axis_id, observed_at, scalar_value, categorical_value,
         tagset_value, confidence, provenance)
      VALUES ($1, $2, coalesce($3::timestamptz, now()), $4, $5, $6, $7, $8)"
     twin-id (kw-name axis-id) (or observed-at :null)
     scalar categorical tagset
     confidence (kw-name provenance) :none)))

;;; ---------------------------------------------------------------------
;;; Fetch seam — the as-of read
;;; ---------------------------------------------------------------------

(defun fetch-twins-as-of (timestamp-expr)
  "All twins with their latest-per-axis observations as of TIMESTAMP-EXPR
\(a timestamptz literal or column expression already in the DB's hands —
callers pass a run's started_at). Twins with no observations at all are
still returned: :unassessed is a gate outcome, not a fetch filter."
  (let ((twins (make-hash-table :test #'equal)))
    (dolist (id (postmodern:query "SELECT twin_id FROM twins" :column))
      (setf (gethash id twins) (lovemotion:make-twin :id id)))
    (dolist (row (postmodern:query
                  "SELECT DISTINCT ON (twin_id, axis_id)
                          twin_id, axis_id, scalar_value, categorical_value,
                          tagset_value, confidence, provenance,
                          extract(epoch FROM observed_at)::bigint
                   FROM axis_values
                   WHERE observed_at <= $1
                   ORDER BY twin_id, axis_id, observed_at DESC"
                  timestamp-expr))
      (destructuring-bind (twin-id axis-id scalar categorical tagset
                           confidence provenance epoch) row
        (let ((twin (gethash twin-id twins))
              (axis-kw (kw axis-id)))
          (when twin
            (setf (gethash axis-kw (lovemotion:twin-axis-values twin))
                  (lovemotion:make-axis-value
                   :axis-id axis-kw
                   :value (columns->lisp-value scalar categorical tagset)
                   :confidence (coerce confidence 'single-float)
                   :provenance (kw provenance)
                   ;; universal-time = unix epoch + 70 years of seconds
                   :observed-at (+ epoch 2208988800)))))))
    (loop for twin being the hash-values of twins collect twin)))

;;; ---------------------------------------------------------------------
;;; Config
;;; ---------------------------------------------------------------------

(defun load-config ()
  "The config table merged over *default-config* (DB wins). Integers stay
integers (:max-findings feeds subseq); fractions become single-floats."
  (let ((config (copy-list lovemotion:*default-config*)))
    (dolist (row (postmodern:query "SELECT key, value FROM config"))
      (destructuring-bind (key value) row
        (setf (getf config (kw key))
              (if (integerp value) value (coerce value 'single-float)))))
    config))

(defun check-matrix-versions (config)
  "Tripwire: the engine's in-code matrices must agree with the DB's
active-version pointers. Divergence means someone tuned the DB without
shipping matching engine code (or vice versa) — refuse to run."
  (loop for (axis-id version) on lovemotion:*matrix-versions* by #'cddr
        for pointer = (getf config (kw (format nil "~a-active-version"
                                               (kw-name axis-id))))
        unless (eql pointer version)
          do (error "Matrix version mismatch on ~a: engine has v~a, DB ~
                     active pointer is ~a" axis-id version pointer)))

;;; ---------------------------------------------------------------------
;;; Persist seam
;;; ---------------------------------------------------------------------

(defun finding->jsonable (finding)
  (let ((table (make-hash-table :test #'equal)))
    (loop for (key value) on finding by #'cddr
          do (setf (gethash (kw-name key) table)
                   (typecase value
                     (keyword (kw-name value))
                     (cons (mapcar #'kw-name value))
                     (t value))))
    table))

(defun config->jsonable (config)
  (let ((table (make-hash-table :test #'equal)))
    (loop for (key value) on config by #'cddr
          do (setf (gethash (kw-name key) table) value))
    table))

(defun create-run (config)
  "Insert the run row; returns (values run-id started-at) where
started-at is the row's own timestamptz, reused verbatim for the as-of
read so snapshot and fetch can never disagree."
  (first (postmodern:query
          "INSERT INTO runs (config_snapshot, matrix_versions)
           VALUES ($1::jsonb, $2::jsonb)
           RETURNING run_id, started_at::text"
          (jonathan:to-json (config->jsonable config))
          (jonathan:to-json (config->jsonable lovemotion:*matrix-versions*)))))

(defun snapshot-pool (run-id twins)
  (dolist (twin twins)
    (postmodern:query
     "INSERT INTO run_twins (run_id, twin_id) VALUES ($1, $2)"
     run-id (lovemotion:twin-id twin) :none)))

(defun store-results (run-id payload)
  (dolist (match (getf payload :matches))
    (postmodern:query
     "INSERT INTO match_results (run_id, twin_a, twin_b, score, findings)
      VALUES ($1, $2, $3, $4, $5::jsonb)"
     run-id
     (getf match :twin-a)
     (getf match :twin-b)
     (getf match :score)
     (jonathan:to-json (mapcar #'finding->jsonable (getf match :findings)))
     :none))
  (postmodern:query
   "UPDATE runs SET finished_at = now() WHERE run_id = $1" run-id :none))

;;; ---------------------------------------------------------------------
;;; The orchestration — one transaction, snapshot to results
;;; ---------------------------------------------------------------------

(defun run-matching-from-db ()
  "Create a run, freeze the pool, feed the pure engine, persist results.
Returns the payload. One REPEATABLE READ transaction end to end."
  (with-db
    (postmodern:with-transaction (run-tx :repeatable-read-rw)
      (declare (ignorable run-tx))
      (let ((config (load-config)))
        (check-matrix-versions config)
        (destructuring-bind (run-id started-at) (create-run config)
          (let ((twins (fetch-twins-as-of started-at)))
            (snapshot-pool run-id twins)
            (let ((payload (lovemotion:run-matching
                            twins :config config :run-id run-id)))
              (store-results run-id payload)
              payload)))))))

(defun replay-run (run-id)
  "Recompute a historical run from its own frozen inputs: the run_twins
pool, the config snapshot's knobs as stored via load-config semantics,
and axis_values as of the original started_at. Returns the recomputed
payload; does not write. Bit-for-bit equality with the stored results is
the reproducibility guarantee."
  (with-db
    (postmodern:with-transaction (replay-tx :repeatable-read-ro)
      (declare (ignorable replay-tx))
      (destructuring-bind (started-at snapshot)
          (first (postmodern:query
                  "SELECT started_at::text, config_snapshot::text
                   FROM runs WHERE run_id = $1" run-id))
        ;; cl-postgres returns text as a non-simple vector; jonathan
        ;; needs a simple-string.
        (let* ((raw (jonathan:parse (coerce snapshot 'simple-string)
                                    :as :alist))
               (config (loop for (key . value) in raw
                             append (list (kw key)
                                          (if (integerp value)
                                              value
                                              (coerce value 'single-float)))))
               (pool-ids (postmodern:query
                          "SELECT twin_id FROM run_twins WHERE run_id = $1"
                          run-id :column))
               (twins (remove-if-not
                       (lambda (tw) (member (lovemotion:twin-id tw)
                                            pool-ids :test #'string=))
                       (fetch-twins-as-of started-at))))
          (lovemotion:run-matching twins :config config :run-id run-id))))))
