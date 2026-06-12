(defpackage #:lovemotion.engine.rules.gates
  (:use #:cl)
  (:import-from #:lovemotion.engine.rules #:defrule)
  (:import-from #:lovemotion.model.companion
                #:companion-proof-of-work-score #:companion-eligible-for-matching
                #:companion-growth-level #:companion-match-cooldown-until))

(in-package #:lovemotion.engine.rules.gates)

;;; Gate rules veto a match entirely if either companion fails.
;;; These are non-negotiable prerequisites. No score can compensate.

(defrule proof-of-work-gate
  :category :gate
  :weight nil
  :veto-threshold 1.0        ; score is 1.0 only if both pass, 0.0 otherwise
  :description "Both companions must demonstrate minimum proof of work"
  :evaluate (lambda (a b)
              (let ((min-pow (/ lovemotion.config:*min-growth-level-for-matching* 7.0)))
                (if (and (>= (companion-proof-of-work-score a) min-pow)
                         (>= (companion-proof-of-work-score b) min-pow)
                         (companion-eligible-for-matching a)
                         (companion-eligible-for-matching b))
                    1.0
                    0.0))))

(defrule growth-level-window-gate
  :category :gate
  :weight nil
  :veto-threshold 1.0
  :description "Companions must be within 2 growth levels of each other"
  :evaluate (lambda (a b)
              (let ((delta (abs (- (companion-growth-level a)
                                  (companion-growth-level b)))))
                (if (<= delta 2) 1.0 0.0))))

(defrule cooldown-gate
  :category :gate
  :weight nil
  :veto-threshold 1.0
  :description "Neither companion is in post-introduction cooldown"
  :evaluate (lambda (a b)
              (let ((now (get-universal-time)))
                (flet ((in-cooldown-p (c)
                         (let ((until (companion-match-cooldown-until c)))
                           (and until (> until now)))))
                  (if (or (in-cooldown-p a) (in-cooldown-p b))
                      0.0
                      1.0)))))
