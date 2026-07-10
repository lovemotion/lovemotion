;;;; batch-roundtrip.lisp — the courier entrypoint against a live DB.
;;;;
;;;; Needs a live database (default lovemotion_v0) with scripts/schema.sql
;;;; and scripts/seed-v0.sql applied. DESTRUCTIVE: truncates all twin,
;;;; run, and courier state — point it only at a dev/test DB.
;;;;
;;;; Run: (asdf:test-system :lovemotion/batch-test)
;;;;
;;;; Plays HeyU's side into a local transport, then exercises the whole
;;;; consumer loop: quiet courier -> no run; one batch -> drain, match,
;;;; ship (bit-identical to the golden matches); the same batch
;;;; re-uploaded under a later key -> cursor advances but nothing
;;;; persists (idempotency by batch-id); caught-up cursor -> quiet again.

(defpackage :lovemotion.batch-test
  (:use :cl)
  (:export #:batch-roundtrip-test))

(in-package :lovemotion.batch-test)

(defvar *failures*)

(defun check (label got expected)
  (unless (equalp got expected)
    (push (format nil "~a: expected ~s, got ~s" label expected got)
          *failures*)))

(defparameter +t1+ (encode-universal-time 0 0 2 4 7 2026 0))   ; 02:00:00Z
(defparameter +t2+ (encode-universal-time 30 15 3 4 7 2026 0)) ; 03:15:30Z

(defun reset ()
  (postmodern:query
   "TRUNCATE match_results, run_twins, runs, axis_values, twins,
             courier_batches, courier_cursor" :none))

(defun publish-batch (transport twins batch-id generated-at)
  (lovemotion.transport:courier-put
   transport
   (lovemotion.transport:twin-batch-key batch-id generated-at)
   (lovemotion.courier:twins->bytes twins :batch-id batch-id
                                          :generated-at generated-at)))

(defun axis-value-count ()
  (lovemotion.db:with-db
    (first (first (postmodern:query "SELECT count(*) FROM axis_values")))))

(defun batch-roundtrip-test ()
  (let* ((*failures* '())
         (root (merge-pathnames "lovemotion-batch-test/"
                                (uiop:temporary-directory)))
         (transport (lovemotion.transport:make-local-transport root)))
    (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore)
    (unwind-protect
         (progn
           (lovemotion.db:with-db (reset))
           ;; Quiet courier: no drain, no run, nothing shipped.
           (let ((result (lovemotion.batch:courier-batch-run
                          :transport transport)))
             (check "quiet courier drains nothing" (getf result :drained) nil)
             (check "quiet courier runs nothing" (getf result :payload) nil)
             (check "quiet courier ships nothing"
                    (getf result :shipped-key) nil))
           ;; One batch in: drained, matched, shipped.
           (publish-batch transport lovemotion:*fixture-twins* 117 +t1+)
           (let* ((result (lovemotion.batch:courier-batch-run
                           :transport transport))
                  (payload (getf result :payload)))
             (check "one key drained" (length (getf result :drained)) 1)
             (check "pool-size = golden"
                    (getf payload :pool-size)
                    (getf lovemotion-test:+golden-payload+ :pool-size))
             (check "matches = golden"
                    (getf payload :matches)
                    (getf lovemotion-test:+golden-payload+ :matches))
             (check "shipped bytes are exactly the payload"
                    (lovemotion.transport:courier-get
                     transport (getf result :shipped-key))
                    (lovemotion.courier:payload->bytes payload)))
           ;; Same batch-id re-uploaded under a later key: the key is
           ;; listed and the cursor moves past it, but nothing persists.
           (let ((count-before (axis-value-count)))
             (publish-batch transport lovemotion:*fixture-twins* 117 +t2+)
             (let ((result (lovemotion.batch:courier-batch-run
                            :transport transport)))
               (check "re-upload is drained past"
                      (length (getf result :drained)) 1)
               (check "re-upload persists nothing"
                      (axis-value-count) count-before)))
           ;; Cursor is caught up: quiet again.
           (let ((result (lovemotion.batch:courier-batch-run
                          :transport transport)))
             (check "cursor caught up" (getf result :drained) nil)))
      (uiop:delete-directory-tree root :validate t
                                       :if-does-not-exist :ignore))
    (cond ((null *failures*)
           (format t "~&BATCH-ROUNDTRIP-OK~%")
           t)
          (t
           (format t "~&BATCH-ROUNDTRIP-FAILED~%~{  ~a~%~}"
                   (reverse *failures*))
           nil))))
