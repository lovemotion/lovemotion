(defpackage #:lovemotion.test
  (:use #:cl #:fiveam)
  (:import-from #:lovemotion.model.companion #:make-companion)
  (:import-from #:lovemotion.engine.rules
                #:*rule-registry* #:gate-rules #:weighted-rules
                #:evaluate-rule #:rule-result-score #:rule-result-veto-p
                #:rule-result-rule-id #:defrule)
  (:import-from #:lovemotion.engine.scoring
                #:weighted-score #:cosine-similarity #:dot-product #:vector-magnitude)
  (:import-from #:lovemotion.engine.simulation
                #:simulate #:simulation-result-score #:simulation-result-ready-p
                #:simulation-result-vetoed-by #:simulation-result-explanation)
  (:export #:run-all))

(in-package #:lovemotion.test)

(def-suite :lovemotion
  :description "LoveMotion full test suite")

(defun run-all ()
  (run! :lovemotion))
