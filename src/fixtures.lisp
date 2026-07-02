;;;; fixtures.lisp — the golden twins + smoke test.

(in-package :lovemotion)

(defun fixture-twin (id &rest specs)
  "SPECS is a plist of axis-id -> value. Fixtures are self-reported at
confidence 1.0 by design; real twins will never look like this."
  (let ((tw (make-twin :id id)))
    (loop for (axis-id value) on specs by #'cddr
          do (setf (gethash axis-id (twin-axis-values tw))
                   (make-axis-value :axis-id axis-id
                                    :value value
                                    :confidence 1.0
                                    :provenance :self-reported
                                    :observed-at (get-universal-time))))
    tw))

(defparameter *fixture-twins*
  (list
   (fixture-twin "tw_alpha"
                 :work-ethic 0.85
                 :chronotype 0.20          ; lark
                 :home-vs-outside 0.40
                 :conflict-style :direct-loud
                 :attachment :secure
                 :ambition 0.80
                 :humor '(:dark :dry :wordplay)
                 :curiosity 0.90
                 :family-plans :yes
                 :must-have-pet t)
   (fixture-twin "tw_bravo"
                 :work-ethic 0.90
                 :chronotype 0.35
                 :home-vs-outside 0.50
                 :conflict-style :calm-dissect
                 :attachment :anxious
                 :ambition 0.70
                 :humor '(:dry :observational :wordplay)
                 :curiosity 0.80
                 :family-plans :yes)
   ;; Gated: strong everything, work ethic below the floor. Never scored.
   (fixture-twin "tw_charlie"
                 :work-ethic 0.20
                 :chronotype 0.30
                 :home-vs-outside 0.45
                 :conflict-style :calm-dissect
                 :attachment :secure
                 :ambition 0.90
                 :humor '(:dry :wordplay)
                 :curiosity 0.95
                 :family-plans :yes)))

(defun smoke-test ()
  "Run the fixtures through the whole pipeline and print the payload.
Expected: pool-size 2 (charlie gated), one match (alpha x bravo),
three :watch findings — humor and attachment as relative maintenance
items, plus the :asymmetric-pairing annotation on direct-loud x
calm-dissect."
  (let ((payload (run-matching *fixture-twins*)))
    (format t "~&~s~%" payload)
    payload))