(defpackage #:lovemotion.matching.scheduler
  (:use #:cl)
  (:export #:start-scheduler #:stop-scheduler #:*scheduler-running-p* #:run-now))

(in-package #:lovemotion.matching.scheduler)

(defvar *scheduler-running-p* nil)
(defvar *scheduler-thread*    nil)
(defvar *scheduler-interval-seconds* (* 24 60 60))   ; 24h default

(defun start-scheduler (&key (interval-seconds *scheduler-interval-seconds*))
  (when *scheduler-running-p*
    (log:warn "Scheduler already running."))
  (setf *scheduler-running-p* t)
  (setf *scheduler-thread*
        (bordeaux-threads:make-thread
         (lambda ()
           (log:info "Matching scheduler started. Interval: ~as" interval-seconds)
           (loop while *scheduler-running-p* do
             (handler-case
                 (progn
                   (log:info "Scheduler: starting matching pipeline run.")
                   (lovemotion.matching.pipeline:run-pipeline)
                   (log:info "Scheduler: pipeline run complete."))
               (error (e)
                 (log:error "Scheduler: pipeline error: ~a" e)))
             (when *scheduler-running-p*
               (sleep interval-seconds))))
         :name "lovemotion-scheduler"))
  (log:info "Scheduler thread launched."))

(defun stop-scheduler ()
  (setf *scheduler-running-p* nil)
  (when *scheduler-thread*
    (bordeaux-threads:destroy-thread *scheduler-thread*)
    (setf *scheduler-thread* nil))
  (log:info "Scheduler stopped."))

(defun run-now ()
  "Trigger an immediate pipeline run outside the scheduler window. For admin use."
  (bordeaux-threads:make-thread
   (lambda ()
     (handler-case
         (lovemotion.matching.pipeline:run-pipeline)
       (error (e)
         (log:error "Manual pipeline run error: ~a" e))))
   :name "lovemotion-manual-run"))
