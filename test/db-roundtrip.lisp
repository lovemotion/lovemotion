;;;; db-roundtrip.lisp — integration test for the Postgres adapter.
;;;;
;;;; Needs a live database (default lovemotion_v0) with scripts/schema.sql
;;;; and scripts/seed-v0.sql applied. DESTRUCTIVE: truncates all twin and
;;;; run data — point it only at a dev/test DB.
;;;;
;;;; Run: (asdf:test-system :lovemotion/db-test)
;;;;
;;;; The assertion is the same golden payload as test/golden.lisp: feeding
;;;; the fixture twins through Postgres must be bit-identical to feeding
;;;; them through memory (that is what the single-float coercion at the
;;;; fetch seam buys). Then the stored run must replay bit-identically.

(defpackage :lovemotion.db-test
  (:use :cl)
  (:export #:db-roundtrip-test))

(in-package :lovemotion.db-test)

(defun reset-twin-data ()
  (postmodern:query
   "TRUNCATE match_results, run_twins, runs, axis_values, twins" :none))

(defun store-fixtures ()
  "Push the golden twins through the ingest seam."
  (dolist (twin lovemotion:*fixture-twins*)
    (lovemotion.db:store-twin (lovemotion:twin-id twin))
    (loop for av being the hash-values of (lovemotion:twin-axis-values twin)
          using (hash-key axis-id)
          do (lovemotion.db:record-axis-value
              (lovemotion:twin-id twin) axis-id
              (lovemotion::axis-value-value av)
              :confidence (lovemotion::axis-value-confidence av)
              :provenance (lovemotion::axis-value-provenance av)))))

(defun matches-equal-golden-p (payload)
  "The golden payload minus the parts that legitimately differ in DB runs
(:run-id is a UUID here, not \"run-local-0\")."
  (and (equal (getf payload :pool-size)
              (getf lovemotion-test:+golden-payload+ :pool-size))
       (equal (getf payload :matches)
              (getf lovemotion-test:+golden-payload+ :matches))
       (equal (getf payload :matrix-versions)
              (getf lovemotion-test:+golden-payload+ :matrix-versions))))

(defun db-roundtrip-test ()
  (lovemotion.db:with-db
    (reset-twin-data)
    (store-fixtures))
  (let* ((payload (lovemotion.db:run-matching-from-db))
         (run-id (getf payload :run-id))
         (replayed (lovemotion.db:replay-run run-id))
         (stored-rows (lovemotion.db:with-db
                        (postmodern:query
                         "SELECT (SELECT count(*) FROM run_twins),
                                 (SELECT count(*) FROM match_results)"
                         :row))))
    (cond ((and (matches-equal-golden-p payload)
                (equal (getf payload :matches) (getf replayed :matches))
                (equal stored-rows '(3 1)))
           (format t "~&DB-ROUNDTRIP-OK (run ~a)~%" run-id)
           t)
          (t
           (format t "~&DB-ROUNDTRIP-FAILED~%~
                      golden-match: ~a~%replay-match: ~a~%~
                      rows (run_twins match_results): ~s~%~
                      payload:~%~s~%"
                   (matches-equal-golden-p payload)
                   (equal (getf payload :matches) (getf replayed :matches))
                   stored-rows payload)
           nil))))
