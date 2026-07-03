;;;; golden.lisp
;;;;
;;;; Golden test for the v0 pipeline. The payload below was produced by
;;;; (lovemotion:smoke-test) on 2026-07-02 and blessed as canonical.
;;;; Any behavior change in the engine must either preserve this payload
;;;; bit-for-bit or consciously re-bless it.
;;;;
;;;; Run: (asdf:test-system :lovemotion)
;;;;
;;;; No test framework on purpose: the contract is one `equal` over one
;;;; s-expression. Floats compare exactly — the pipeline is deterministic
;;;; and the literals below are SBCL's own round-trip printing.

(defpackage :lovemotion-test
  (:use :cl)
  (:export #:golden-test #:+golden-payload+ #:+golden-payload-mixed+))

(in-package :lovemotion-test)

(defparameter +golden-payload+
  '(:contract-version 1
    :run-id "run-local-0"
    :matrix-versions (:conflict-style 0 :attachment 0)
    :pool-size 2
    :matches
    ((:twin-a "tw_alpha" :twin-b "tw_bravo" :score 0.778125
      :findings
      ((:axis :humor :code :maintenance :detail 0.5 :severity :watch)
       (:axis :attachment :code :maintenance :detail 0.65 :severity :watch)
       (:axis :conflict-style :code :asymmetric-pairing
        :detail (:direct-loud :calm-dissect) :severity :watch)))))
  "Blessed 2026-07-02 from the v0 smoke-test.
Pool: alpha, bravo (charlie gated on work ethic 0.20 < floor 0.40).
Composite 0.778125 = 6.225 / 8.0 total weight.
Findings: humor 0.5 and attachment 0.65 are the two relative-weakest
axes (universal maintenance rule); direct-loud x calm-dissect carries
the :asymmetric-pairing cell annotation. All :watch — no low-band
(humor 0.5 is not < 0.50) and no :attention/:structural cells hit.")

(defparameter +golden-payload-mixed+
  '(:contract-version 1
    :run-id "run-local-mixed-0"
    :matrix-versions (:conflict-style 0 :attachment 0)
    :pool-size 3
    :matches
    ((:twin-a "tw_delta" :twin-b "tw_echo" :score 0.7752293
      :findings
      ((:axis :humor :code :low-band :detail 0.25 :severity :attention)
       (:axis :conflict-style :code :maintenance :detail 0.6
        :severity :watch)))))
  "Blessed 2026-07-03 from smoke-test-mixed. Covers what the 1.0-confidence
golden twins can't: confidence-discounted weights (composite 0.7752293
= 4.225 / 5.45, every axis weight multiplied by min(confA, confB)),
an :unassessed exclusion (foxtrot: work ethic 0.20 under the floor but
confidence 0.50 < gate-min-confidence — excluded as unassessed, NOT
gated), a dealbreaker veto (golf: family-plans :no against both :yes
twins — in the pool, matches no one), a :low-band finding outranking
its own :maintenance finding on the same axis (humor 0.25), and an
:attention finding sorting before a :watch.")

(defun first-difference (a b &optional (path '()))
  "Walk two trees; return the path and differing leaves, or NIL if equal."
  (cond ((equal a b) nil)
        ((and (consp a) (consp b))
         (or (first-difference (car a) (car b) (cons :car path))
             (first-difference (cdr a) (cdr b) (cons :cdr path))))
        (t (list :path (reverse path) :expected a :got b))))

(defun check-golden (label payload blessed)
  (cond ((equal payload blessed)
         (format t "~&GOLDEN-TEST-OK (~a)~%" label)
         t)
        (t
         (format t "~&GOLDEN-TEST-FAILED (~a)~%first difference: ~s~%~
                    full payload:~%~s~%"
                 label (first-difference blessed payload) payload)
         nil)))

(defun golden-test ()
  ;; No short-circuit: report both verdicts even when the first fails.
  (let ((base (check-golden "base"
                            (lovemotion:run-matching lovemotion:*fixture-twins*)
                            +golden-payload+))
        (mixed (check-golden "mixed-confidence"
                             (lovemotion:run-matching
                              lovemotion:*fixture-twins-mixed*
                              :run-id "run-local-mixed-0")
                             +golden-payload-mixed+)))
    (and base mixed)))
