(defpackage #:lovemotion.engine.rules.contribution
  (:use #:cl)
  (:import-from #:lovemotion.engine.rules #:defrule)
  (:import-from #:lovemotion.model.companion
                #:companion-contribution-score #:companion-proof-of-work-score))

(in-package #:lovemotion.engine.rules.contribution)

;;; Contribution rules measure giving orientation.
;;; The spec is explicit: "any work to improve others will also be granted points."
;;; Two people who both give are a fundamentally different pairing than two takers.

(defrule mutual-contribution-orientation
  :category :contribution
  :weight 0.20
  :veto-threshold nil
  :description "Both companions demonstrate orientation toward giving"
  :evaluate (lambda (a b)
              ;; Score is high when BOTH give. One giver + one taker = low.
              ;; This deliberately weights against pairing a generous person
              ;; with someone who hasn't developed giving orientation yet.
              (let ((ca (companion-contribution-score a))
                    (cb (companion-contribution-score b)))
                (sqrt (* ca cb)))))   ; geometric mean penalizes imbalance

(defrule proof-of-work-alignment
  :category :contribution
  :weight 0.10
  :veto-threshold nil
  :description "Proof-of-work scores are in compatible ranges"
  :evaluate (lambda (a b)
              (let* ((pa (companion-proof-of-work-score a))
                     (pb (companion-proof-of-work-score b))
                     (delta (abs (- pa pb))))
                ;; Similar PoW means both put in comparable effort.
                ;; Very different PoW often means different readiness stages.
                (max 0.0 (- 1.0 delta)))))
