(defpackage #:lovemotion.engine.rules.growth
  (:use #:cl)
  (:import-from #:lovemotion.engine.rules #:defrule)
  (:import-from #:lovemotion.engine.scoring #:cosine-similarity)
  (:import-from #:lovemotion.model.companion
                #:companion-growth-velocity #:companion-growth-level))

(in-package #:lovemotion.engine.rules.growth)

;;; Growth rules evaluate the compatibility of two companions' trajectories.
;;; The key insight from the spec: we match on trajectory, not current state.
;;; "You're not matching on who they are today, matching on where they're going."

(defrule growth-velocity-harmony
  :category :growth
  :weight 0.15
  :veto-threshold nil
  :description "Companions growing at compatible rates"
  :evaluate (lambda (a b)
              ;; Two companions both growing fast is compatible.
              ;; One growing fast and one stalled is not — not because of judgment,
              ;; but because the timing of readiness won't align.
              (let* ((va (companion-growth-velocity a))
                     (vb (companion-growth-velocity b))
                     (avg (/ (+ (abs va) (abs vb)) 2.0))
                     (delta (abs (- va vb))))
                (if (zerop avg)
                    0.5
                    (max 0.0 (- 1.0 (/ delta avg)))))))

(defrule growth-level-complementarity
  :category :growth
  :weight 0.10
  :veto-threshold nil
  :description "Companion growth levels are close enough for mutual recognition"
  :evaluate (lambda (a b)
              ;; Identical levels = high compatibility.
              ;; 1 apart = good. 2 apart = acceptable. Gate handles > 2.
              (let ((delta (abs (- (companion-growth-level a)
                                  (companion-growth-level b)))))
                (case delta
                  (0 1.0)
                  (1 0.85)
                  (2 0.60)
                  (otherwise 0.0)))))
