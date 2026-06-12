(defpackage #:lovemotion
  (:use #:cl)
  (:export #:start #:stop))

(in-package #:lovemotion)

(defun start (&key (scheduler t))
  "Start LoveMotion: verify DB connection, start HTTP server, start scheduler."
  (log:info "LoveMotion v0.1.0 starting...")
  (lovemotion.config:load-config)
  (unless (lovemotion.database:check-connection)
    (error "Cannot connect to database ~a@~a:~a"
           lovemotion.config:*db-name*
           (or lovemotion.config:*db-host* "localhost")
           lovemotion.config:*db-port*))
  (log:info "Database connection verified.")
  (lovemotion.server:start)
  (when scheduler
    (lovemotion.matching.scheduler:start-scheduler))
  (log:info "LoveMotion ready on port ~a" lovemotion.config:*http-port*))

(defun stop ()
  (log:info "LoveMotion shutting down...")
  (lovemotion.matching.scheduler:stop-scheduler)
  (lovemotion.server:stop)
  (log:info "LoveMotion stopped."))

(defun main ()
  (start)
  (loop (sleep 3600)))
