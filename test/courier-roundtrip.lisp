;;;; courier-roundtrip.lisp — golden payload through MessagePack and back.
;;;;
;;;; Run: (asdf:test-system :lovemotion/courier)
;;;;
;;;; Deliberately asserts field-by-field against the blessed golden
;;;; values rather than comparing to the output of payload->wire — the
;;;; converter must not be its own oracle.

(defpackage :lovemotion.courier-test
  (:use :cl)
  (:export #:courier-roundtrip-test))

(in-package :lovemotion.courier-test)

(defvar *failures*)

(defun check (label got expected)
  (unless (equalp got expected)
    (push (format nil "~a: expected ~s, got ~s" label expected got)
          *failures*)))

(defun courier-roundtrip-test ()
  (let* ((*failures* '())
         (payload (lovemotion:run-matching lovemotion:*fixture-twins*))
         (wire (lovemotion.courier:bytes->payload
                (lovemotion.courier:payload->bytes payload)))
         (match (aref (gethash "matches" wire) 0))
         (findings (gethash "findings" match))
         (worst (aref findings 0))
         (annotated (aref findings 2)))
    (check "contract-version" (gethash "contract-version" wire) 1)
    (check "run-id" (gethash "run-id" wire) "run-local-0")
    (check "pool-size" (gethash "pool-size" wire) 2)
    (check "matrix-versions/conflict-style"
           (gethash "conflict-style" (gethash "matrix-versions" wire)) 0)
    (check "matches count" (length (gethash "matches" wire)) 1)
    (check "twin-a" (gethash "twin-a" match) "tw_alpha")
    (check "twin-b" (gethash "twin-b" match) "tw_bravo")
    ;; float32 must round-trip the blessed score exactly
    (check "score" (gethash "score" match) 0.778125)
    (check "findings count" (length findings) 3)
    (check "weakest axis" (gethash "axis" worst) "humor")
    (check "weakest code" (gethash "code" worst) "maintenance")
    (check "weakest detail" (gethash "detail" worst) 0.5)
    (check "weakest severity" (gethash "severity" worst) "watch")
    (check "annotated code" (gethash "code" annotated) "asymmetric-pairing")
    (check "annotated detail" (gethash "detail" annotated)
           #("direct-loud" "calm-dissect"))
    (cond ((null *failures*)
           (format t "~&COURIER-ROUNDTRIP-OK (~d bytes)~%"
                   (length (lovemotion.courier:payload->bytes payload)))
           t)
          (t
           (format t "~&COURIER-ROUNDTRIP-FAILED~%~{  ~a~%~}" *failures*)
           nil))))
