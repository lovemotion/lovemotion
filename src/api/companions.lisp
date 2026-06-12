(defpackage #:lovemotion.api.companions
  (:use #:cl #:hunchentoot)
  (:export #:handle-create #:handle-update #:handle-delete))

(in-package #:lovemotion.api.companions)

(defun parse-json-body ()
  (let ((body (hunchentoot:raw-post-data :force-text t)))
    (when body (jonathan:parse body))))

(defun handle-create ()
  (let ((payload (parse-json-body)))
    (unless payload
      (setf (hunchentoot:return-code*) hunchentoot:+http-bad-request+)
      (return-from handle-create (jonathan:to-json '(:error "Invalid JSON body"))))
    (let ((ref (getf payload :|heyu_user_ref|)))
      (unless ref
        (setf (hunchentoot:return-code*) hunchentoot:+http-bad-request+)
        (return-from handle-create (jonathan:to-json '(:error "heyu_user_ref required"))))
      (let* ((companion-id
              (lovemotion.database:with-db
                (lovemotion.model.companion:upsert-companion
                 ref
                 :growth-level          (getf payload :|growth_level| 1)
                 :proof-of-work-score   (getf payload :|proof_of_work_score| 0.0)
                 :contribution-score    (getf payload :|contribution_score| 0.0)
                 :attachment-style      (getf payload :|attachment_style|)
                 :growth-velocity       (getf payload :|growth_velocity| 0.0)
                 :geographic-region     (getf payload :|geographic_region|)
                 :lifestyle-axes        (getf payload :|lifestyle_axes|)
                 :last-circle-signals   (getf payload :|last_circle_signals|))))
             (eligible-p
              ;; Companion is eligible when proof-of-work clears the minimum gate
              (>= (getf payload :|proof_of_work_score| 0.0)
                  (/ lovemotion.config:*min-growth-level-for-matching* 7.0))))
        (lovemotion.database:with-db
          (lovemotion.model.companion:mark-eligible companion-id eligible-p))
        (setf (hunchentoot:return-code*) hunchentoot:+http-created+)
        (jonathan:to-json
         (list :|companion_id|          companion-id
               :|accepted|              t
               :|eligible_for_matching| eligible-p))))))

(defun handle-delete ()
  (let* ((uri   (hunchentoot:request-uri*))
         (ref   (car (last (cl-ppcre:split "/" uri)))))
    (lovemotion.database:with-db
      (lovemotion.model.companion:delete-companion ref))
    (jonathan:to-json (list :|deleted| t :|heyu_user_ref| ref))))
