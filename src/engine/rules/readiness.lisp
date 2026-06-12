(defpackage #:lovemotion.engine.rules.readiness
  (:use #:cl)
  (:import-from #:lovemotion.engine.rules #:defrule)
  (:import-from #:lovemotion.model.companion
                #:companion-growth-velocity #:companion-last-circle-signals
                #:companion-proof-of-work-score #:companion-growth-level))

(in-package #:lovemotion.engine.rules.readiness)

;;; Readiness rules measure timing alignment — whether both companions are
;;; in a moment of life where connection is likely to land.
;;;
;;; The spec's core insight: "matching on where they're going, not where they are."
;;; Two people may be compatible in every other dimension but misaligned on timing.
;;; One at peak readiness, one in a protective withdrawal, is a mismatch.

(defun circle-signal-strength (signals)
  "Score 0.0–1.0 based on presence and richness of recent circle signals.
   Non-nil, non-empty signals indicate recent active engagement in circles."
  (cond
    ((null signals)     0.10)   ; no recent circle activity — low readiness signal
    ((null (cdr signals)) 0.40) ; minimal data — some signal
    (t
     ;; Richness proxy: number of distinct signal keys reported
     (let ((key-count (length (loop for (k) on signals by #'cddr collect k))))
       (min 1.0 (+ 0.40 (* key-count 0.12)))))))

(defrule circle-engagement-signal
  :category :readiness
  :weight 0.12
  :veto-threshold nil
  :description "Both companions show recent Growth Circle engagement"
  :evaluate (lambda (a b)
              ;; Geometric mean: one disengaged companion pulls the pair score down.
              ;; Both must show current engagement for high readiness.
              (let ((sa (circle-signal-strength (companion-last-circle-signals a)))
                    (sb (circle-signal-strength (companion-last-circle-signals b))))
                (sqrt (* sa sb)))))

(defrule active-growth-readiness
  :category :readiness
  :weight 0.08
  :veto-threshold nil
  :description "Both companions are in active growth phases, not stalled"
  :evaluate (lambda (a b)
              ;; Positive velocity = currently growing = more open/available.
              ;; Stalled velocity doesn't mean bad — it means the window may be wrong.
              ;; Score: average of how "active" each companion is, sigmoid-scaled.
              (flet ((velocity-readiness (v)
                       (cond
                         ((> v  0.5) 1.00)
                         ((> v  0.0) 0.75)
                         ((= v  0.0) 0.45)  ; plateau — not wrong, just uncertain
                         ((> v -0.3) 0.30)  ; mild regression
                         (t          0.15))));; significant regression
                (let ((ra (velocity-readiness (companion-growth-velocity a)))
                      (rb (velocity-readiness (companion-growth-velocity b))))
                  ;; Arithmetic mean: both matter, but one growing while other
                  ;; regresses is better than geometric mean would suggest —
                  ;; the growing companion can offer stability.
                  (/ (+ ra rb) 2.0)))))
