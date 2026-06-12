(in-package #:lovemotion.test)

(def-suite :rules :in :lovemotion
  :description "Rule registry, evaluation, and individual rule logic")

(in-suite :rules)

;;; --- Registry ---

(test registry-not-empty
  "All rule files loaded — registry has rules."
  (is (> (length *rule-registry*) 0)))

(test registry-has-gates
  "At least the three standard gate rules are registered."
  (let ((gates (mapcar #'lovemotion.engine.rules:rule-id (gate-rules))))
    (is (member 'lovemotion.engine.rules.gates::proof-of-work-gate gates))
    (is (member 'lovemotion.engine.rules.gates::growth-level-window-gate gates))
    (is (member 'lovemotion.engine.rules.gates::cooldown-gate gates))))

(test registry-has-weighted
  "At least ten weighted rules are registered."
  (is (>= (length (weighted-rules)) 10)))

(test gate-rules-have-no-weight
  "Gate rules must have nil weight."
  (is (every (lambda (r) (null (lovemotion.engine.rules:rule-weight r)))
             (gate-rules))))

(test weighted-rules-have-weight
  "Weighted rules must have a numeric weight."
  (is (every (lambda (r) (numberp (lovemotion.engine.rules:rule-weight r)))
             (weighted-rules))))

;;; --- evaluate-rule ---

(test evaluate-rule-returns-result
  "evaluate-rule always returns a rule-result struct."
  (let* ((rule (car (gate-rules)))
         (a (companion-a))
         (b (companion-b))
         (result (evaluate-rule rule a b)))
    (is (typep result 'lovemotion.engine.rules:rule-result))))

(test evaluate-rule-score-clamped
  "Rule scores are always clamped 0.0–1.0."
  (let ((a (companion-a)) (b (companion-b)))
    (dolist (rule *rule-registry*)
      (let ((score (rule-result-score (evaluate-rule rule a b))))
        (is (>= score 0.0) "Score ~a for rule ~a below 0" score (lovemotion.engine.rules:rule-id rule))
        (is (<= score 1.0) "Score ~a for rule ~a above 1" score (lovemotion.engine.rules:rule-id rule))))))

;;; --- Gate rule logic ---

(test proof-of-work-gate-passes
  "Eligible companions with sufficient PoW pass the gate."
  (setf lovemotion.config:*min-growth-level-for-matching* 2)
  (let* ((a (companion-a))
         (b (companion-b))
         (rule (lovemotion.engine.rules:find-rule-by-id
                'lovemotion.engine.rules.gates::proof-of-work-gate))
         (result (evaluate-rule rule a b)))
    (is (= 1.0 (rule-result-score result)))
    (is (null (rule-result-veto-p result)))))

(test proof-of-work-gate-vetos-ineligible
  "Ineligible companion triggers veto."
  (let* ((a (make-test-companion :eligible-for-matching nil))
         (b (companion-b))
         (rule (lovemotion.engine.rules:find-rule-by-id
                'lovemotion.engine.rules.gates::proof-of-work-gate))
         (result (evaluate-rule rule a b)))
    (is (= 0.0 (rule-result-score result)))
    (is (rule-result-veto-p result))))

(test growth-level-window-gate-passes-same-level
  "Same growth level always passes."
  (let* ((a (make-test-companion :growth-level 3))
         (b (make-test-companion :growth-level 3))
         (rule (lovemotion.engine.rules:find-rule-by-id
                'lovemotion.engine.rules.gates::growth-level-window-gate))
         (result (evaluate-rule rule a b)))
    (is (= 1.0 (rule-result-score result)))))

(test growth-level-window-gate-vetos-large-delta
  "Delta > 2 levels triggers veto."
  (let* ((a (make-test-companion :growth-level 1))
         (b (make-test-companion :growth-level 5))
         (rule (lovemotion.engine.rules:find-rule-by-id
                'lovemotion.engine.rules.gates::growth-level-window-gate))
         (result (evaluate-rule rule a b)))
    (is (= 0.0 (rule-result-score result)))
    (is (rule-result-veto-p result))))

(test cooldown-gate-passes-no-cooldown
  "No cooldown set → gate passes."
  (let* ((a (companion-a))  ; cooldown-until = nil
         (b (companion-b))
         (rule (lovemotion.engine.rules:find-rule-by-id
                'lovemotion.engine.rules.gates::cooldown-gate))
         (result (evaluate-rule rule a b)))
    (is (= 1.0 (rule-result-score result)))))

(test cooldown-gate-vetos-active-cooldown
  "Companion in active cooldown triggers veto."
  (let* ((future (+ (get-universal-time) 86400))  ; 24h from now
         (a (make-test-companion :match-cooldown-until future))
         (b (companion-b))
         (rule (lovemotion.engine.rules:find-rule-by-id
                'lovemotion.engine.rules.gates::cooldown-gate))
         (result (evaluate-rule rule a b)))
    (is (= 0.0 (rule-result-score result)))
    (is (rule-result-veto-p result))))

;;; --- Values rule logic ---

(test attachment-secure-secure-highest-score
  "Secure + secure attachment scores 1.0."
  (let* ((a (make-test-companion :attachment-style "secure"))
         (b (make-test-companion :attachment-style "secure"))
         (rule (lovemotion.engine.rules:find-rule-by-id
                'lovemotion.engine.rules.values::attachment-style-compatibility))
         (result (evaluate-rule rule a b)))
    (is (= 1.0 (rule-result-score result)))))

(test attachment-anxious-avoidant-lowest-score
  "Anxious + avoidant attachment scores 0.2 — the pursuer/distancer trap."
  (let* ((a (make-test-companion :attachment-style "anxious"))
         (b (make-test-companion :attachment-style "avoidant"))
         (rule (lovemotion.engine.rules:find-rule-by-id
                'lovemotion.engine.rules.values::attachment-style-compatibility))
         (result (evaluate-rule rule a b)))
    (is (= 0.2 (rule-result-score result)))))

(test attachment-unknown-is-neutral
  "Unknown/nil attachment style returns 0.5 — neutral."
  (let* ((a (make-test-companion :attachment-style nil))
         (b (make-test-companion :attachment-style "secure"))
         (rule (lovemotion.engine.rules:find-rule-by-id
                'lovemotion.engine.rules.values::attachment-style-compatibility))
         (result (evaluate-rule rule a b)))
    (is (= 0.5 (rule-result-score result)))))

;;; --- Practical rule logic ---

(test geographic-same-region-full-score
  "Same region scores 1.0."
  (let* ((a (make-test-companion :geographic-region "west-coast"))
         (b (make-test-companion :geographic-region "west-coast"))
         (rule (lovemotion.engine.rules:find-rule-by-id
                'lovemotion.engine.rules.practical::geographic-compatibility))
         (result (evaluate-rule rule a b)))
    (is (= 1.0 (rule-result-score result)))))

(test geographic-different-region-half-score
  "Different regions yield 0.5 — a soft penalty, not a veto."
  (let* ((a (make-test-companion :geographic-region "northeast-us"))
         (b (make-test-companion :geographic-region "west-coast"))
         (rule (lovemotion.engine.rules:find-rule-by-id
                'lovemotion.engine.rules.practical::geographic-compatibility))
         (result (evaluate-rule rule a b)))
    (is (= 0.5 (rule-result-score result)))))

(test geographic-nil-region-neutral
  "Unknown region yields 0.5 — we can't penalize what we don't know."
  (let* ((a (make-test-companion :geographic-region nil))
         (b (make-test-companion :geographic-region "northeast-us"))
         (rule (lovemotion.engine.rules:find-rule-by-id
                'lovemotion.engine.rules.practical::geographic-compatibility))
         (result (evaluate-rule rule a b)))
    (is (= 0.5 (rule-result-score result)))))
