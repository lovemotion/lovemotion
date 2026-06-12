(in-package #:lovemotion.test)

;;; Fixture helpers — build companion structs for testing without a DB.
;;; All tests run in-process; no DB or HTTP connections needed.

(defun companion-defaults ()
  "Base keyword args for a well-formed, eligible companion."
  (list :id "test-id-a"
        :heyu-user-ref "ref-a"
        :growth-level 3
        :proof-of-work-score 0.70
        :contribution-score 0.65
        :attachment-style "secure"
        :growth-velocity 0.40
        :geographic-region "northeast-us"
        :lifestyle-axes '(:fitness "high" :social "medium")
        :last-circle-signals '(:engagement 0.8 :recency 5)
        :eligible-for-matching t
        :match-cooldown-until nil))

(defun make-test-companion (&rest overrides)
  "Create a test companion, merging overrides into the defaults."
  (let ((args (copy-list (companion-defaults))))
    (loop for (k v) on overrides by #'cddr
          do (setf (getf args k) v))
    (apply #'make-companion args)))

(defun companion-a ()
  (make-test-companion :id "a" :heyu-user-ref "ref-a"))

(defun companion-b ()
  (make-test-companion :id "b" :heyu-user-ref "ref-b"
                       :proof-of-work-score 0.65
                       :contribution-score 0.70
                       :growth-velocity 0.35))

;;; Stub rule-results for scoring tests.
;;; IMPORTANT: registering stub rules via defrule pollutes *rule-registry* and
;;; would distort simulation tests that run later. Always wrap stub-creating
;;; code in WITH-ISOLATED-REGISTRY to save and restore the registry.

(defmacro with-isolated-registry (&body body)
  "Execute body with *rule-registry* saved and restored on exit."
  `(let ((saved lovemotion.engine.rules:*rule-registry*))
     (unwind-protect (progn ,@body)
       (setf lovemotion.engine.rules:*rule-registry* saved))))

(defun make-stub-result (rule-id weight score)
  "Create a rule-result backed by a stub rule. Call inside WITH-ISOLATED-REGISTRY."
  (eval `(defrule ,rule-id
           :category :test
           :weight ,weight
           :veto-threshold nil
           :description "stub"
           :evaluate (lambda (a b) (declare (ignore a b)) ,score)))
  (lovemotion.engine.rules:make-rule-result
   :rule-id rule-id
   :category :test
   :score (float score)
   :explanation (format nil "stub ~a: ~a" rule-id score)
   :veto-p nil))
