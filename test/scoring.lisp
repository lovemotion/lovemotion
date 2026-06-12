(in-package #:lovemotion.test)

(def-suite :scoring :in :lovemotion
  :description "weighted-score and vector math")

(in-suite :scoring)

(test weighted-score-empty
  "Empty result list yields 0.0."
  (is (= 0.0 (weighted-score '()))))

(test weighted-score-single
  "Single rule: score passes through unchanged."
  (with-isolated-registry
    (let ((r (make-stub-result 'stub-single 1.0 0.75)))
      (is (= 0.75 (weighted-score (list r)))))))

(test weighted-score-equal-weights
  "Equal weights: result is simple average."
  (with-isolated-registry
    (let ((r1 (make-stub-result 'stub-eq-a 0.5 1.0))
          (r2 (make-stub-result 'stub-eq-b 0.5 0.0)))
      (is (= 0.5 (weighted-score (list r1 r2)))))))

(test weighted-score-unequal-weights
  "Heavier weight dominates score."
  ;; weight 0.8 at 1.0 + weight 0.2 at 0.0 → (0.8 + 0.0) / 1.0 = 0.8
  (with-isolated-registry
    (let ((r1 (make-stub-result 'stub-heavy 0.8 1.0))
          (r2 (make-stub-result 'stub-light 0.2 0.0)))
      (is (= 0.8 (weighted-score (list r1 r2)))))))

(test weighted-score-clamped
  "Score is always 0.0–1.0 even with extreme inputs."
  (with-isolated-registry
    (let ((r (make-stub-result 'stub-clamp 1.0 0.5)))
      (let ((s (weighted-score (list r))))
        (is (>= s 0.0))
        (is (<= s 1.0))))))

;;; Vector math functions take lists (mapcar-based), not arrays.

(test cosine-similarity-identical
  "Identical vectors have cosine similarity 1.0."
  (let ((v '(1.0 0.0 0.0)))
    (is (= 1.0 (cosine-similarity v v)))))

(test cosine-similarity-orthogonal
  "Orthogonal vectors have cosine similarity 0.0."
  (is (= 0.0 (cosine-similarity '(1.0 0.0) '(0.0 1.0)))))

(test cosine-similarity-opposite
  "cosine-similarity clamps at 0.0 — opposite vectors return 0.0, not -1.0."
  (is (= 0.0 (cosine-similarity '(1.0 0.0) '(-1.0 0.0)))))

(test cosine-similarity-scaled
  "Scaling a vector does not change cosine similarity."
  (is (= 1.0 (cosine-similarity '(3.0 4.0) '(6.0 8.0)))))

(test vector-magnitude-unit
  "Unit vector has magnitude 1.0."
  (is (= 1.0 (vector-magnitude '(1.0 0.0 0.0)))))

(test vector-magnitude-pythagorean
  "3-4-5 triangle: magnitude = 5.0."
  (is (= 5.0 (vector-magnitude '(3.0 4.0)))))

(test dot-product-basic
  "Dot product of simple vectors."
  (is (= 12.0 (dot-product '(1.0 2.0 3.0) '(1.0 1.0 3.0)))))
