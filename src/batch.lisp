;;;; batch.lisp — the off-hours courier entrypoint (action #4, last piece).
;;;;
;;;; Wires the transport (COURIER.md) to the DB adapter: drain inbound
;;;; twin batches into Postgres, run matching, ship the payload. This is
;;;; the consumer half of the cursor handshake; the cursor lives in the
;;;; courier_cursor table, idempotency in courier_batches. Domain code
;;;; (src/engine.lisp) still knows nothing about any of it.
;;;;
;;;; Failure posture, consistent with the rest of the system:
;;;;   * A decode failure stops the drain with the cursor still pointing
;;;;     before the bad key — a poison batch blocks the queue loudly
;;;;     rather than being skipped silently.
;;;;   * Each batch persists in its own transaction, cursor advance
;;;;     included, so a crash never leaves a half-loaded batch or a
;;;;     cursor ahead of its data.
;;;;   * A batch-id already in courier_batches is a no-op (re-uploaded
;;;;     or double-listed object); the cursor still advances past it.
;;;;   * Two DIFFERENT batches carrying the same (twin, axis, observed-at)
;;;;     hit the axis_values PK and abort that batch loudly — that is a
;;;;     producer bug, not something to absorb.

(defpackage :lovemotion.batch
  (:use :cl)
  (:export #:drain-twin-batches
           #:courier-batch-run))

(in-package :lovemotion.batch)

(defun universal->pg (universal-time)
  "Universal-time -> a timestamptz literal Postgres can cast, UTC."
  (multiple-value-bind (sec min hour day month year)
      (decode-universal-time universal-time 0)
    (format nil "~4,'0d-~2,'0d-~2,'0d ~2,'0d:~2,'0d:~2,'0d+00"
            year month day hour min sec)))

;;; ---------------------------------------------------------------------
;;; Cursor + idempotency ledger (call inside with-db)
;;; ---------------------------------------------------------------------

(defun twin-cursor ()
  "Last twins/v1/ key processed, or NIL if none yet (first run, or the
row doesn't exist yet)."
  (let ((row (first (postmodern:query
                     "SELECT last_key FROM courier_cursor WHERE prefix = $1"
                     lovemotion.transport:+twins-prefix+))))
    (when (and row (not (eq (first row) :null)))
      (first row))))

(defun advance-twin-cursor (key)
  (postmodern:query
   "INSERT INTO courier_cursor (prefix, last_key) VALUES ($1, $2)
    ON CONFLICT (prefix) DO UPDATE
      SET last_key = EXCLUDED.last_key, updated_at = now()"
   lovemotion.transport:+twins-prefix+ key :none))

(defun batch-processed-p (batch-id)
  (postmodern:query
   "SELECT 1 FROM courier_batches WHERE batch_id = $1" batch-id))

(defun record-batch (batch key)
  (postmodern:query
   "INSERT INTO courier_batches (batch_id, object_key, generated_at)
    VALUES ($1, $2, $3::timestamptz)"
   (getf batch :batch-id) key
   (universal->pg (getf batch :generated-at)) :none))

;;; ---------------------------------------------------------------------
;;; Ingest — one decoded batch through the DB seams
;;; ---------------------------------------------------------------------

(defun persist-batch (batch)
  (dolist (twin (getf batch :twins))
    (lovemotion.db:store-twin (lovemotion:twin-id twin))
    (loop for av being the hash-values
            of (lovemotion:twin-axis-values twin)
          using (hash-key axis-id)
          do (lovemotion.db:record-axis-value
              (lovemotion:twin-id twin) axis-id
              (lovemotion:axis-value-value av)
              :confidence (lovemotion:axis-value-confidence av)
              :provenance (lovemotion:axis-value-provenance av)
              :observed-at (universal->pg
                            (lovemotion:axis-value-observed-at av))))))

;;; ---------------------------------------------------------------------
;;; The drain and the entrypoint
;;; ---------------------------------------------------------------------

(defun drain-twin-batches (transport)
  "Consumer half of COURIER.md: list keys strictly after the cursor,
oldest first; fetch, decode, persist, advance — one transaction per
batch. Returns the keys processed this call (including any skipped as
already-seen batch-ids; they still moved the cursor)."
  (lovemotion.db:with-db
    (let ((keys (lovemotion.transport:new-twin-batch-keys
                 transport (twin-cursor))))
      (dolist (key keys keys)
        (let ((batch (lovemotion.transport:fetch-twin-batch transport key)))
          (postmodern:with-transaction (batch-tx)
            (declare (ignorable batch-tx))
            (unless (batch-processed-p (getf batch :batch-id))
              (persist-batch batch)
              (record-batch batch key))
            (advance-twin-cursor key)))))))

(defun courier-batch-run
    (&key (transport (lovemotion.transport:make-spaces-transport-from-env))
          force-run)
  "The whole off-hours batch: drain twins/v1/, and if anything new
arrived (or FORCE-RUN), run matching from the DB and ship the payload
to matches/v1/. Returns (:drained keys :payload payload-or-nil
:shipped-key key-or-nil) — both nil when the courier was quiet and the
run was skipped."
  (let ((drained (drain-twin-batches transport)))
    (if (or drained force-run)
        (let ((payload (lovemotion.db:run-matching-from-db)))
          (list :drained drained
                :payload payload
                :shipped-key (lovemotion.transport:ship-matches
                              transport payload)))
        (list :drained nil :payload nil :shipped-key nil))))
