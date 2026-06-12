(defpackage #:lovemotion.engine.rules
  (:use #:cl)
  (:import-from #:lovemotion.model.companion #:companion)
  (:export #:rule #:make-rule #:rule-id #:rule-category #:rule-weight #:rule-veto-threshold
           #:rule-description #:rule-evaluate
           #:defrule #:*rule-registry* #:active-rules #:gate-rules #:weighted-rules
           #:evaluate-rule #:rule-result #:make-rule-result
           #:rule-result-score #:rule-result-explanation
           #:rule-result-veto-p #:rule-result-rule-id #:rule-result-category
           #:find-rule-by-id))

(in-package #:lovemotion.engine.rules)

;;; A rule takes two companion structs and returns a RULE-RESULT.
;;; Rules are the unit of explainability: every match comes with the list
;;; of rules that fired and their contributions.

(defstruct rule
  (id          nil :type symbol)
  (category    nil :type keyword)   ; :gate :growth :values :readiness :contribution :practical
  (weight      nil)                 ; float 0.0-1.0, or nil for gate rules
  (veto-threshold nil)              ; float, nil means no veto
  (description "" :type string)
  (evaluate    nil))                ; function: (companion companion) -> float or nil

(defstruct rule-result
  (rule-id     nil :type symbol)
  (category    nil :type keyword)
  (score       0.0 :type float)
  (explanation "" :type string)
  (veto-p      nil))

(defvar *rule-registry* '()
  "Ordered list of all active rules. Gate rules fire first.")

(defun find-rule-by-id (id)
  "Look up a rule in the registry by its symbol ID."
  (find id *rule-registry* :key #'rule-id))

(defmacro defrule (name &key category weight veto-threshold description evaluate)
  "Define a matching rule and register it globally.
   :category  — :gate :growth :values :readiness :contribution :practical
   :weight    — float 0.0-1.0 for weighted rules; nil for gate rules
   :veto-threshold — if score falls below this, veto the pair (gate rules only)
   :description — human-readable explanation string
   :evaluate  — (lambda (companion-a companion-b) -> float 0.0-1.0 or nil)"
  `(progn
     (defparameter ,name
       (make-rule :id ',name
                  :category ,category
                  :weight ,weight
                  :veto-threshold ,veto-threshold
                  :description ,description
                  :evaluate ,evaluate))
     (setf *rule-registry*
           (cons ,name (remove ',name *rule-registry* :key #'rule-id)))
     ',name))

(defun gate-rules ()
  "All rules that can veto a match."
  (remove-if-not #'rule-veto-threshold *rule-registry*))

(defun weighted-rules ()
  "All rules that contribute a weighted score (non-gate)."
  (remove-if-not #'rule-weight *rule-registry*))

(defun active-rules ()
  "Gate rules first, then weighted rules."
  (append (gate-rules) (weighted-rules)))

(defun evaluate-rule (rule companion-a companion-b)
  "Fire a single rule against a companion pair. Returns RULE-RESULT."
  (let* ((raw-score (handler-case
                        (funcall (rule-evaluate rule) companion-a companion-b)
                      (error (e)
                        (log:warn "Rule ~a errored: ~a" (rule-id rule) e)
                        0.0)))
         (score (if (numberp raw-score)
                    (max 0.0 (min 1.0 (float raw-score)))
                    0.0))
         (veto-p (and (rule-veto-threshold rule)
                      (< score (rule-veto-threshold rule)))))
    (make-rule-result
     :rule-id     (rule-id rule)
     :category    (rule-category rule)
     :score       score
     :explanation (format nil "~a: ~,3f" (rule-description rule) score)
     :veto-p      veto-p)))
