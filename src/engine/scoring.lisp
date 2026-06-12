(defpackage #:lovemotion.engine.scoring
  (:use #:cl)
  (:import-from #:lovemotion.engine.rules
                #:rule-result-score #:rule-result-rule-id
                #:rule-weight #:find-rule-by-id)
  (:export #:weighted-score #:cosine-similarity #:dot-product #:vector-magnitude))

(in-package #:lovemotion.engine.scoring)

(defun weighted-score (rule-results)
  "Compute a weighted average score from a list of rule-results."
  (let ((total-weight 0.0)
        (weighted-sum 0.0))
    (dolist (result rule-results)
      (let* ((rule (find-rule-by-id (rule-result-rule-id result)))
             (w    (if rule (or (rule-weight rule) 0.0) 0.0)))
        (when (> w 0.0)
          (incf total-weight w)
          (incf weighted-sum (* w (rule-result-score result))))))
    (if (> total-weight 0.0)
        (/ weighted-sum total-weight)
        0.0)))

(defun dot-product (vec-a vec-b)
  (reduce #'+ (mapcar #'* vec-a vec-b) :initial-value 0.0))

(defun vector-magnitude (vec)
  (sqrt (reduce #'+ (mapcar (lambda (x) (* x x)) vec) :initial-value 0.0)))

(defun cosine-similarity (vec-a vec-b)
  "Cosine similarity between two float vectors. Returns 0.0-1.0."
  (let ((mag-a (vector-magnitude vec-a))
        (mag-b (vector-magnitude vec-b)))
    (if (or (zerop mag-a) (zerop mag-b))
        0.0
        (max 0.0 (/ (dot-product vec-a vec-b) (* mag-a mag-b))))))
