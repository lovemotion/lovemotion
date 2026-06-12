(defpackage #:lovemotion.matching.pipeline
  (:use #:cl)
  (:import-from #:lovemotion.model.companion #:eligible-companions #:companion-id)
  (:import-from #:lovemotion.engine.simulation
                #:simulate #:simulation-result-ready-p #:simulation-result-score
                #:simulation-result-explanation #:simulation-result-vetoed-by)
  (:export #:run-pipeline))

(in-package #:lovemotion.matching.pipeline)

(defun run-pipeline ()
  "Full matching pipeline run. Returns a plist summary of results."
  (let* (;; Create log entry first so PostgreSQL generates the run-id
         (run-id (lovemotion.database:with-db
                   (postmodern:query
                    "INSERT INTO simulation_log (started_at) VALUES (NOW()) RETURNING run_id::text"
                    :single)))
         (started-at  (get-universal-time))
         (candidates  (lovemotion.database:with-db (eligible-companions)))
         (n-candidates (length candidates))
         (pairs-simulated 0)
         (matches-produced 0))
    (log:info "Pipeline ~a: ~a eligible companions." run-id n-candidates)
    ;; For each companion A, find ANN candidates, simulate pairs
    (dolist (companion-a candidates)
      (let ((ann-candidates (lovemotion.database:with-db
                              (lovemotion.matching.pgvector:find-candidates companion-a))))
        (dolist (companion-b ann-candidates)
          ;; Canonical ordering to avoid duplicate pairs
          (when (string< (companion-id companion-a) (companion-id companion-b))
            (let ((result (simulate companion-a companion-b)))
              (incf pairs-simulated)
              (when (simulation-result-ready-p result)
                (incf matches-produced)
                (lovemotion.database:with-db
                  (postmodern:execute
                   "INSERT INTO match_results
                    (companion_id_a, companion_id_b, score, explanation, ready, pipeline_run_id)
                    VALUES ($1::uuid, $2::uuid, $3, $4::jsonb, TRUE, $5::uuid)
                    ON CONFLICT (companion_id_a, companion_id_b, pipeline_run_id) DO NOTHING"
                   (companion-id companion-a)
                   (companion-id companion-b)
                   (simulation-result-score result)
                   (jonathan:to-json (simulation-result-explanation result))
                   run-id))))))))
    ;; Update run log
    (lovemotion.database:with-db
      (postmodern:execute
       "UPDATE simulation_log
        SET completed_at = NOW(), companions_evaluated = $1,
            pairs_simulated = $2, matches_produced = $3
        WHERE run_id = $4::uuid"
       n-candidates pairs-simulated matches-produced run-id))
    (log:info "Pipeline ~a done. Pairs: ~a, Matches: ~a (elapsed: ~as)"
              run-id pairs-simulated matches-produced
              (- (get-universal-time) started-at))
    (list :run-id run-id
          :pairs-simulated pairs-simulated
          :matches-produced matches-produced)))
