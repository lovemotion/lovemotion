;;;; package.lisp — LoveMotion package definition and boundary contract.
;;;;
;;;; LoveMotion matching engine — v0 skeleton.
;;;; Pure in-memory pipeline: twin-set -> match payload.
;;;; No DB, no I/O. Postgres is an adapter to be bolted on underneath
;;;; fetch/persist seams later; nothing in here may know about it.
;;;;
;;;; Pipeline (locked 2026-07-01):
;;;;   eligibility gate -> pair dealbreakers -> 7-axis scoring
;;;;   -> weighted composite -> findings (min 1, max 4)
;;;;   -> versioned payload
;;;;
;;;; Contract: LoveMotion emits codes; HeyU owns all prose.
;;;; Per-axis scores never cross the boundary.

(defpackage :lovemotion
  (:use :cl)
  (:export #:run-matching
           #:eligibility
           #:score-pair
           #:fixture-twin
           #:*fixture-twins*
           #:*default-config*
           #:smoke-test))
