(defpackage #:lovemotion.server
  (:use #:cl #:hunchentoot)
  (:shadow #:start #:stop)
  (:import-from #:lovemotion.config #:*http-port* #:*api-key*)
  (:export #:start #:stop #:*acceptor*))

(in-package #:lovemotion.server)

(defvar *acceptor* nil)

(defun authorized-p ()
  (let ((header (hunchentoot:header-in* :authorization)))
    (and header (string= header (concatenate 'string "Bearer " *api-key*)))))

(defun json-body (data &optional (status 200))
  (setf (hunchentoot:content-type*) "application/json")
  (setf (hunchentoot:return-code*) status)
  (jonathan:to-json data))

(defun require-auth (handler-fn)
  (if (authorized-p)
      (funcall handler-fn)
      (json-body (list :|error| "Unauthorized") 401)))

(defun route ()
  "Route the current request to the correct handler."
  (let ((method (hunchentoot:request-method*))
        (uri    (hunchentoot:script-name*)))
    (handler-case
        (cond
          ((string= uri "/v1/health")
           (lovemotion.api.health:handle))

          ((and (eq method :post) (string= uri "/v1/companions"))
           (require-auth #'lovemotion.api.companions:handle-create))

          ((and (eq method :delete)
                (cl-ppcre:scan "^/v1/companions/" uri))
           (require-auth #'lovemotion.api.companions:handle-delete))

          ((and (eq method :get) (string= uri "/v1/matches"))
           (require-auth #'lovemotion.api.matches:handle-list))

          ((and (eq method :post) (string= uri "/admin/scheduler/run"))
           (if (string= (hunchentoot:remote-addr*) "127.0.0.1")
               (progn (lovemotion.matching.scheduler:run-now)
                      (json-body (list :|triggered| t)))
               (json-body (list :|error| "Forbidden") 403)))

          (t
           (json-body (list :|error| "Not found") 404)))
      (error (e)
        (log:error "Request error ~a ~a: ~a" method uri e)
        (json-body (list :|error| "Internal server error") 500)))))

(hunchentoot:define-easy-handler (main-handler :uri (lambda (r)
                                                       (declare (ignore r)) t)) ()
  (route))

(defun start ()
  (unless *acceptor*
    (setf hunchentoot:*dispatch-table*
          (list 'hunchentoot:dispatch-easy-handlers))
    (setf *acceptor*
          (make-instance 'hunchentoot:easy-acceptor
                         :port *http-port*
                         :access-log-destination nil
                         :message-log-destination nil))
    (hunchentoot:start *acceptor*)
    (log:info "LoveMotion HTTP server started on port ~a" *http-port*)))

(defun stop ()
  (when *acceptor*
    (hunchentoot:stop *acceptor*)
    (setf *acceptor* nil)
    (log:info "LoveMotion HTTP server stopped.")))
