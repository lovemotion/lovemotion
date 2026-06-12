(defpackage #:lovemotion.model.companion
  (:use #:cl #:postmodern)
  (:export #:companion #:make-companion
           #:companion-id #:companion-heyu-user-ref #:companion-growth-level
           #:companion-proof-of-work-score #:companion-contribution-score
           #:companion-attachment-style #:companion-growth-velocity
           #:companion-eligible-for-matching #:companion-snapshot-at
           #:upsert-companion #:find-companion-by-ref #:find-companion-by-id
           #:delete-companion #:eligible-companions
           #:mark-eligible #:set-cooldown))

(in-package #:lovemotion.model.companion)

;;; A Growth Companion snapshot. Embedding vectors are stored in postgres
;;; as pgvector columns; we represent them in Lisp as simple-array float32.

(defstruct companion
  id
  heyu-user-ref
  (growth-level          1)
  (proof-of-work-score   0.0)
  (contribution-score    0.0)
  attachment-style
  (growth-velocity       0.0)
  geographic-region
  lifestyle-axes         ; plist
  last-circle-signals    ; plist
  (eligible-for-matching nil)
  match-cooldown-until
  snapshot-at
  created-at
  updated-at)

(defun upsert-companion (ref &key growth-level proof-of-work-score contribution-score
                               attachment-style growth-velocity geographic-region
                               lifestyle-axes last-circle-signals embedding
                               trajectory-direction snapshot-at)
  "Insert or update a companion snapshot. Returns companion-id."
  (declare (ignore embedding trajectory-direction))  ; stored separately via raw SQL
  (postmodern:query
   (:insert-into 'companions
    :set 'heyu_user_ref ref
         'growth_level (or growth-level 1)
         'proof_of_work_score (or proof-of-work-score 0.0)
         'contribution_score (or contribution-score 0.0)
         'attachment_style attachment-style
         'growth_velocity (or growth-velocity 0.0)
         'geographic_region geographic-region
         'lifestyle_axes (jonathan:to-json (or lifestyle-axes '()))
         'last_circle_signals (jonathan:to-json (or last-circle-signals '()))
         'snapshot_at (or snapshot-at (:now))
         'updated_at (:now)
    :on-conflict 'heyu_user_ref
    :do-update-set
      'growth_level (:excluded 'growth_level)
      'proof_of_work_score (:excluded 'proof_of_work_score)
      'contribution_score (:excluded 'contribution_score)
      'attachment_style (:excluded 'attachment_style)
      'growth_velocity (:excluded 'growth_velocity)
      'geographic_region (:excluded 'geographic_region)
      'lifestyle_axes (:excluded 'lifestyle_axes)
      'last_circle_signals (:excluded 'last_circle_signals)
      'snapshot_at (:excluded 'snapshot_at)
      'updated_at (:excluded 'updated_at)
    :returning 'companion_id)
   :single))

(defun find-companion-by-ref (heyu-user-ref)
  "Fetch companion by HeyU opaque reference. Returns companion struct or nil."
  (let ((row (postmodern:query
              (:select 'companion_id 'heyu_user_ref 'growth_level
                       'proof_of_work_score 'contribution_score
                       'attachment_style 'growth_velocity
                       'geographic_region 'eligible_for_matching
                       'match_cooldown_until 'snapshot_at 'created_at 'updated_at
               :from 'companions
               :where (:= 'heyu_user_ref heyu-user-ref))
              :row)))
    (when row
      (apply #'row->companion row))))

(defun find-companion-by-id (companion-id)
  "Fetch companion by internal UUID. Returns companion struct or nil."
  (let ((row (postmodern:query
              (:select 'companion_id 'heyu_user_ref 'growth_level
                       'proof_of_work_score 'contribution_score
                       'attachment_style 'growth_velocity
                       'geographic_region 'eligible_for_matching
                       'match_cooldown_until 'snapshot_at 'created_at 'updated_at
               :from 'companions
               :where (:= 'companion_id companion-id))
              :row)))
    (when row
      (apply #'row->companion row))))

(defun delete-companion (heyu-user-ref)
  "Delete companion and all associated match data. User sovereignty."
  (postmodern:execute
   (:delete-from 'companions
    :where (:= 'heyu_user_ref heyu-user-ref))))

(defun eligible-companions ()
  "Return all companions eligible for matching (passed proof-of-work gate, not in cooldown)."
  (let ((rows (postmodern:query
               (:select 'companion_id 'heyu_user_ref 'growth_level
                        'proof_of_work_score 'contribution_score
                        'attachment_style 'growth_velocity
                        'geographic_region 'eligible_for_matching
                        'match_cooldown_until 'snapshot_at 'created_at 'updated_at
                :from 'companions
                :where (:and (:= 'eligible_for_matching t)
                             (:or (:is-null 'match_cooldown_until)
                                  (:< 'match_cooldown_until (:now)))))
               :rows)))
    (mapcar (lambda (row) (apply #'row->companion row)) rows)))

(defun mark-eligible (companion-id eligible-p)
  (postmodern:execute
   (:update 'companions
    :set 'eligible_for_matching eligible-p 'updated_at (:now)
    :where (:= 'companion_id companion-id))))

(defun set-cooldown (companion-id until-timestamp)
  (postmodern:execute
   (:update 'companions
    :set 'match_cooldown_until until-timestamp 'updated_at (:now)
    :where (:= 'companion_id companion-id))))

(defun row->companion (id ref level pow contribution attachment velocity region eligible cooldown snapshot created updated)
  (make-companion
   :id id
   :heyu-user-ref ref
   :growth-level level
   :proof-of-work-score (or pow 0.0)
   :contribution-score (or contribution 0.0)
   :attachment-style attachment
   :growth-velocity (or velocity 0.0)
   :geographic-region region
   :eligible-for-matching eligible
   :match-cooldown-until cooldown
   :snapshot-at snapshot
   :created-at created
   :updated-at updated))
