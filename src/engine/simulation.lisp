(defpackage #:lovemotion.engine.simulation
  (:use #:cl)
  (:import-from #:lovemotion.model.companion #:companion)
  (:import-from #:lovemotion.engine.rules
                #:active-rules #:evaluate-rule #:rule-weight #:rule-veto-threshold
                #:find-rule-by-id #:rule-result-score #:rule-result-veto-p
                #:rule-result-explanation #:rule-result-rule-id #:rule-result-category)
  (:import-from #:lovemotion.engine.scoring #:weighted-score)
  (:export #:simulation-result
           #:simulation-result-score #:simulation-result-ready-p
           #:simulation-result-explanation #:simulation-result-vetoed-by
           #:simulate))

(in-package #:lovemotion.engine.simulation)

(defstruct simulation-result
  (score       0.0 :type float)
  (ready-p     nil)
  (explanation '())    ; list of rule-result explanation strings
  (vetoed-by   nil))   ; rule-id that caused rejection, or nil

;;; The core: pure, stateless, deterministic.
;;; Given the same two companions, always returns the same result.

(defun simulate (companion-a companion-b)
  "Run all rules against a companion pair. Returns SIMULATION-RESULT.
   Gate rules fire first — any veto short-circuits immediately.
   Weighted rules then accumulate a score."
  (let ((rules (active-rules))
        (results '()))
    ;; Phase 1: gate rules
    (dolist (rule (remove-if-not #'rule-veto-threshold rules))
      (let ((result (evaluate-rule rule companion-a companion-b)))
        (push result results)
        (when (rule-result-veto-p result)
          (return-from simulate
            (make-simulation-result
             :score       0.0
             :ready-p     nil
             :explanation (mapcar #'rule-result-explanation (nreverse results))
             :vetoed-by   (rule-result-rule-id result))))))
    ;; Phase 2: weighted rules
    (dolist (rule (remove-if #'rule-veto-threshold rules))
      (push (evaluate-rule rule companion-a companion-b) results))
    ;; Score aggregation
    (let* ((all-results  (nreverse results))
           (weighted     (remove-if (lambda (r) (null (rule-weight (find-rule-by-id (rule-result-rule-id r)))))
                                    all-results))
           (score        (weighted-score weighted))
           (threshold    lovemotion.config:*introduction-threshold*))
      (make-simulation-result
       :score       score
       :ready-p     (>= score threshold)
       :explanation (mapcar #'rule-result-explanation all-results)
       :vetoed-by   nil))))

