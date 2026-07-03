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

(defun fixture-twin-full (id &rest specs)
  "Like FIXTURE-TWIN but each SPEC is (axis-id value &key confidence
provenance), for twins that are supposed to look real: mixed confidence,
mixed provenance. CONFIDENCE has no default on purpose."
  (let ((tw (make-twin :id id)))
    (dolist (spec specs)
      (destructuring-bind (axis-id value
                           &key (confidence (error "confidence is required"))
                                (provenance :observed))
          spec
        (setf (gethash axis-id (twin-axis-values tw))
              (make-axis-value :axis-id axis-id
                               :value value
                               :confidence confidence
                               :provenance provenance
                               :observed-at (get-universal-time)))))
    tw))

(defparameter *fixture-twins-mixed*
  (list
   ;; delta x echo is the one match: every axis weight discounted by
   ;; min(confA, confB), so this pair exercises the involuntary-channels
   ;; multiply that the 1.0-confidence golden twins never touch.
   (fixture-twin-full "tw_delta"
                      '(:work-ethic 0.80 :confidence 0.90)
                      '(:chronotype 0.70 :confidence 0.90)
                      '(:home-vs-outside 0.60 :confidence 0.80)
                      '(:conflict-style :slow-burn :confidence 0.70
                        :provenance :self-reported)
                      '(:attachment :secure :confidence 0.60
                        :provenance :inferred)
                      '(:ambition 0.50 :confidence 0.90)
                      '(:humor (:dry :slapstick) :confidence 0.50
                        :provenance :inferred)
                      '(:curiosity 0.60 :confidence 0.80)
                      '(:family-plans :yes :confidence 1.0
                        :provenance :self-reported))
   (fixture-twin-full "tw_echo"
                      '(:work-ethic 0.75 :confidence 0.80)
                      '(:chronotype 0.80 :confidence 0.70)
                      '(:home-vs-outside 0.70 :confidence 0.90)
                      '(:conflict-style :calm-dissect :confidence 0.80
                        :provenance :self-reported)
                      '(:attachment :secure :confidence 0.90
                        :provenance :self-reported)
                      '(:ambition 0.60 :confidence 0.70)
                      '(:humor (:dry :observational :wordplay)
                        :confidence 0.60 :provenance :inferred)
                      '(:curiosity 0.75 :confidence 0.90)
                      '(:family-plans :yes :confidence 1.0
                        :provenance :self-reported))
   ;; Unassessed, not ineligible: work ethic below the floor but the
   ;; observation is under :gate-min-confidence — never gate on noise.
   ;; v0 pool policy still excludes it (only :eligible enter).
   (fixture-twin-full "tw_foxtrot"
                      '(:work-ethic 0.20 :confidence 0.50)
                      '(:chronotype 0.50 :confidence 0.90)
                      '(:attachment :secure :confidence 0.90
                        :provenance :self-reported))
   ;; Eligible and in the pool, but dealbroken against both delta and
   ;; echo on family plans — scores against no one.
   (fixture-twin-full "tw_golf"
                      '(:work-ethic 0.90 :confidence 0.95)
                      '(:chronotype 0.40 :confidence 0.90)
                      '(:home-vs-outside 0.50 :confidence 0.90)
                      '(:conflict-style :calm-dissect :confidence 0.90
                        :provenance :self-reported)
                      '(:attachment :secure :confidence 0.90
                        :provenance :self-reported)
                      '(:ambition 0.70 :confidence 0.90)
                      '(:curiosity 0.80 :confidence 0.90)
                      '(:family-plans :no :confidence 1.0
                        :provenance :self-reported))))

(defun smoke-test ()
  "Run the fixtures through the whole pipeline and print the payload.
Expected: pool-size 2 (charlie gated), one match (alpha x bravo),
three :watch findings — humor and attachment as relative maintenance
items, plus the :asymmetric-pairing annotation on direct-loud x
calm-dissect."
  (let ((payload (run-matching *fixture-twins*)))
    (format t "~&~s~%" payload)
    payload))

(defun smoke-test-mixed ()
  "The mixed-confidence pipeline run. Expected: pool-size 3 (foxtrot
unassessed, excluded; golf eligible but dealbroken against everyone),
one match (delta x echo) with confidence-discounted weights, humor
:low-band at :attention plus conflict-style :maintenance."
  (let ((payload (run-matching *fixture-twins-mixed* :run-id "run-local-mixed-0")))
    (format t "~&~s~%" payload)
    payload))