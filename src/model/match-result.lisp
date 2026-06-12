(defpackage #:lovemotion.model.match-result
  (:use #:cl #:postmodern)
  (:export #:store-match-result #:unconsumed-matches #:mark-consumed))

(in-package #:lovemotion.model.match-result)

(defun store-match-result (companion-id-a companion-id-b score explanation run-id)
  "Persist a match result. Canonical ordering: id-a < id-b."
  (let ((a (if (string< companion-id-a companion-id-b) companion-id-a companion-id-b))
        (b (if (string< companion-id-a companion-id-b) companion-id-b companion-id-a)))
    (postmodern:execute
     (format nil
       "INSERT INTO match_results
        (companion_id_a, companion_id_b, score, explanation, ready, pipeline_run_id)
        VALUES ($1, $2, $3, $4::jsonb, TRUE, $5)
        ON CONFLICT (companion_id_a, companion_id_b, pipeline_run_id) DO NOTHING"
       )
     a b score explanation run-id)))

(defun unconsumed-matches (&optional since)
  "Return all ready matches not yet consumed by HeyU, optionally filtered by time."
  (if since
      (postmodern:query
       (format nil
         "SELECT mr.match_id, ca.heyu_user_ref, cb.heyu_user_ref,
                 mr.score, mr.explanation, mr.simulated_at
          FROM match_results mr
          JOIN companions ca ON ca.companion_id = mr.companion_id_a
          JOIN companions cb ON cb.companion_id = mr.companion_id_b
          WHERE mr.ready = TRUE
            AND mr.consumed_by_heyu_at IS NULL
            AND mr.simulated_at >= $1
          ORDER BY mr.score DESC")
       since
       :rows)
      (postmodern:query
       "SELECT mr.match_id, ca.heyu_user_ref, cb.heyu_user_ref,
               mr.score, mr.explanation, mr.simulated_at
        FROM match_results mr
        JOIN companions ca ON ca.companion_id = mr.companion_id_a
        JOIN companions cb ON cb.companion_id = mr.companion_id_b
        WHERE mr.ready = TRUE
          AND mr.consumed_by_heyu_at IS NULL
        ORDER BY mr.score DESC"
       :rows)))

(defun mark-consumed (match-id)
  (postmodern:execute
   "UPDATE match_results SET consumed_by_heyu_at = NOW() WHERE match_id = $1"
   match-id))
