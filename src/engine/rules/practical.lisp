(defpackage #:lovemotion.engine.rules.practical
  (:use #:cl)
  (:import-from #:lovemotion.engine.rules #:defrule)
  (:import-from #:lovemotion.model.companion
                #:companion-geographic-region #:companion-lifestyle-axes))

(in-package #:lovemotion.engine.rules.practical)

;;; Practical rules are the lowest-weighted category — they shouldn't override
;;; deep compatibility, but they're real friction signals. Two people who share
;;; values and trajectory but can never be in the same room will feel it.

(defrule geographic-compatibility
  :category :practical
  :weight 0.07
  :veto-threshold nil
  :description "Companions are in compatible geographic regions"
  :evaluate (lambda (a b)
              (let ((ra (companion-geographic-region a))
                    (rb (companion-geographic-region b)))
                (cond
                  ((or (null ra) (null rb)) 0.50) ; unknown — can't penalize what we don't know
                  ((string= ra rb)          1.00) ; same region
                  (t                        0.50))))) ; different — soft penalty, not a veto

(defun lifestyle-key-count (axes)
  "Count of distinct lifestyle axes keys reported."
  (if (null axes)
      0
      (length (loop for (k) on axes by #'cddr collect k))))

(defrule lifestyle-investment-parity
  :category :practical
  :weight 0.03
  :veto-threshold nil
  :description "Both companions have invested similar energy in lifestyle self-description"
  :evaluate (lambda (a b)
              ;; Proxy for intentionality and self-awareness about lifestyle preferences.
              ;; Two people who've both thought carefully about their lifestyle (many axes)
              ;; are more likely to surface real compatibility signals — and to appreciate
              ;; that their match was thoughtful rather than arbitrary.
              (let* ((ca (lifestyle-key-count (companion-lifestyle-axes a)))
                     (cb (lifestyle-key-count (companion-lifestyle-axes b)))
                     (total (+ ca cb)))
                (if (zerop total)
                    0.50          ; neither filled in — neutral, not a penalty
                    (let ((larger  (max ca cb))
                          (smaller (min ca cb)))
                      ;; Score falls as the ratio diverges from 1:1.
                      ;; One person with 10 axes, other with 0 = 0.0 score.
                      (float (/ smaller larger)))))))
