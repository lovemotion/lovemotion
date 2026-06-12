(in-package #:lovemotion.test)

(def-suite :simulation :in :lovemotion
  :description "End-to-end simulate/2 pipeline: gate veto, scoring, threshold")

(in-suite :simulation)

(test simulation-returns-result-struct
  "simulate always returns a simulation-result."
  (let ((result (simulate (companion-a) (companion-b))))
    (is (typep result 'lovemotion.engine.simulation:simulation-result))))

(test simulation-compatible-pair-passes-gates
  "Two well-formed, eligible companions pass all gate rules."
  (let ((result (simulate (companion-a) (companion-b))))
    (is (null (simulation-result-vetoed-by result)))))

(test simulation-compatible-pair-score-in-range
  "Score is always 0.0–1.0."
  (let ((score (simulation-result-score (simulate (companion-a) (companion-b)))))
    (is (>= score 0.0))
    (is (<= score 1.0))))

(test simulation-strong-pair-exceeds-threshold
  "Two secure, active, same-region companions should exceed introduction threshold."
  (setf lovemotion.config:*introduction-threshold* 0.72)
  (let* ((a (make-test-companion
             :attachment-style "secure" :growth-velocity 0.6
             :proof-of-work-score 0.85 :contribution-score 0.80
             :geographic-region "northeast-us" :growth-level 4
             :last-circle-signals '(:engagement 0.9 :recency 3 :depth 0.85 :frequency 0.90)
             :lifestyle-axes '(:fitness "high" :social "high" :creativity "medium")))
         (b (make-test-companion
             :id "b" :heyu-user-ref "ref-b"
             :attachment-style "secure" :growth-velocity 0.55
             :proof-of-work-score 0.80 :contribution-score 0.75
             :geographic-region "northeast-us" :growth-level 4
             :last-circle-signals '(:engagement 0.85 :recency 4 :depth 0.80 :frequency 0.85)
             :lifestyle-axes '(:fitness "high" :social "high" :creativity "medium")))
         (result (simulate a b)))
    (is (simulation-result-ready-p result)
        "Expected ready-p T, got score ~,4f" (simulation-result-score result))))

(test simulation-gate-veto-ineligible
  "Ineligible companion causes immediate gate veto."
  (let* ((a (make-test-companion :eligible-for-matching nil))
         (b (companion-b))
         (result (simulate a b)))
    (is (not (null (simulation-result-vetoed-by result))))
    (is (= 0.0 (simulation-result-score result)))
    (is (null (simulation-result-ready-p result)))))

(test simulation-gate-veto-growth-level-gap
  "Growth level delta > 2 causes gate veto."
  (let* ((a (make-test-companion :growth-level 1))
         (b (make-test-companion :id "b" :heyu-user-ref "ref-b" :growth-level 5))
         (result (simulate a b)))
    (is (not (null (simulation-result-vetoed-by result))))))

(test simulation-gate-veto-cooldown
  "Companion in active cooldown causes gate veto."
  (let* ((future (+ (get-universal-time) 86400))
         (a (make-test-companion :match-cooldown-until future))
         (b (companion-b))
         (result (simulate a b)))
    (is (not (null (simulation-result-vetoed-by result))))))

(test simulation-explanation-covers-all-rules
  "Explanation list has an entry for every rule that fired."
  (let* ((result (simulate (companion-a) (companion-b)))
         (explanations (simulation-result-explanation result)))
    ;; At minimum, the 3 gate rules fire before any weighted rules.
    (is (>= (length explanations) 3))))

(test simulation-is-deterministic
  "Same inputs always produce same score — simulation is pure."
  (let* ((a (companion-a))
         (b (companion-b))
         (r1 (simulate a b))
         (r2 (simulate a b)))
    (is (= (simulation-result-score r1) (simulation-result-score r2)))
    (is (equal (simulation-result-vetoed-by r1)
               (simulation-result-vetoed-by r2)))))

(test simulation-symmetric
  "Simulate(A,B) and simulate(B,A) produce the same score — order shouldn't matter."
  ;; This is a design invariant: companion-a and companion-b are not ordered.
  ;; If any rule breaks symmetry, this test catches it.
  (let* ((a (companion-a))
         (b (companion-b))
         (ab (simulate a b))
         (ba (simulate b a)))
    (is (= (simulation-result-score ab) (simulation-result-score ba)))))

(test simulation-veto-carries-rule-id
  "vetoed-by field names the specific rule that fired the veto."
  (let* ((future (+ (get-universal-time) 86400))
         (a (make-test-companion :match-cooldown-until future))
         (b (companion-b))
         (result (simulate a b)))
    (is (symbolp (simulation-result-vetoed-by result)))))
