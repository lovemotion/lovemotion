(defpackage #:lovemotion.database
  (:use #:cl)
  (:import-from #:lovemotion.config
                #:*db-host* #:*db-port* #:*db-name* #:*db-user* #:*db-pass*)
  (:export #:with-db #:check-connection))

(in-package #:lovemotion.database)

;;; Per-request connections via postmodern:with-connection.
;;; This is safe for Hunchentoot's threaded request model.
;;; Connection pooling can be added later via pgclpool or similar.

(defmacro with-db (&body body)
  "Execute body with a fresh database connection."
  `(postmodern:with-connection (list *db-name* *db-user* *db-pass*
                                     (or *db-host* "localhost")
                                     :port *db-port*)
     ,@body))

(defun check-connection ()
  "Returns T if a database connection can be established, NIL otherwise."
  (handler-case
      (progn (with-db (postmodern:query "SELECT 1" :single)) t)
    (error () nil)))
