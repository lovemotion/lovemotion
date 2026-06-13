(defpackage #:lovemotion.matching.pgvector
  (:use #:cl #:postmodern)
  (:import-from #:lovemotion.model.companion #:companion-id #:companion-growth-level)
  (:import-from #:lovemotion.config #:*ann-candidate-count*)
  (:export #:find-candidates))

(in-package #:lovemotion.matching.pgvector)

;;; pgvector ANN search using the <=> (cosine distance) operator.
;;; This is Stage 1 of the pipeline: fast approximate candidate generation.
;;; The rules engine (Stage 2) does the expensive fine-grained simulation.

(defun find-candidates (companion)
  "Return up to *ANN-CANDIDATE-COUNT* companion structs most similar
   to COMPANION by embedding cosine similarity, within ±2 growth levels."
  (let* ((id    (companion-id companion))
         (level (companion-growth-level companion))
         (rows  (postmodern:query
                 ;; Raw SQL: pgvector <=> (cosine distance); S-SQL lacks custom-operator support
                 "SELECT companion_id, heyu_user_ref, growth_level,
                         proof_of_work_score, contribution_score,
                         attachment_style, growth_velocity, geographic_region,
                         eligible_for_matching, match_cooldown_until,
                         snapshot_at, created_at, updated_at
                  FROM companions
                  WHERE companion_id != $1
                    AND eligible_for_matching = TRUE
                    AND (match_cooldown_until IS NULL OR match_cooldown_until < NOW())
                    AND ABS(growth_level - $2) <= 2
                    AND embedding IS NOT NULL
                  ORDER BY embedding <=> (
                    SELECT embedding FROM companions WHERE companion_id = $1
                  )
                  LIMIT $3"
                 id level *ann-candidate-count*
                 :rows)))
    (mapcar (lambda (row)
              (apply #'lovemotion.model.companion::row->companion row))
            rows)))
