(defpackage #:lovemotion.config
  (:use #:cl)
  (:export #:*db-host* #:*db-port* #:*db-name* #:*db-user* #:*db-pass*
           #:*http-port* #:*api-key* #:*log-level*
           #:*introduction-threshold* #:*match-window-cron*
           #:*companion-vector-dimensions* #:*trajectory-vector-dimensions*
           #:*min-growth-level-for-matching*
           #:*ann-candidate-count*
           #:load-config))

(in-package #:lovemotion.config)

;;; All config reads from environment variables with sane defaults.
;;; In production, set these via the systemd unit EnvironmentFile.

(defvar *db-host*    (uiop:getenv "LM_DB_HOST")    )
(defvar *db-port*    (parse-integer (or (uiop:getenv "LM_DB_PORT") "5432")))
(defvar *db-name*    (or (uiop:getenv "LM_DB_NAME") "lovemotion"))
(defvar *db-user*    (or (uiop:getenv "LM_DB_USER") "lovemotion"))
(defvar *db-pass*    (or (uiop:getenv "LM_DB_PASS") "lovemotion_dev"))

(defvar *http-port*  (parse-integer (or (uiop:getenv "LM_HTTP_PORT") "8080")))
(defvar *api-key*    (or (uiop:getenv "LM_API_KEY") "dev-key-change-in-production"))
(defvar *log-level*  (or (uiop:getenv "LM_LOG_LEVEL") "info"))

;;; Matching parameters
(defvar *introduction-threshold*       0.72)
(defvar *match-window-cron*            "0 2 * * *")   ; nightly at 2 AM
(defvar *companion-vector-dimensions*  1536)
(defvar *trajectory-vector-dimensions* 32)
(defvar *min-growth-level-for-matching* 2)
(defvar *ann-candidate-count*          50)            ; top-K from pgvector ANN

(defun load-config ()
  "Re-reads environment variables. Call after setenv in tests."
  (setf *db-host*   (uiop:getenv "LM_DB_HOST")
        *db-port*   (parse-integer (or (uiop:getenv "LM_DB_PORT") "5432"))
        *db-name*   (or (uiop:getenv "LM_DB_NAME") "lovemotion")
        *db-user*   (or (uiop:getenv "LM_DB_USER") "lovemotion")
        *db-pass*   (or (uiop:getenv "LM_DB_PASS") "lovemotion_dev")
        *http-port* (parse-integer (or (uiop:getenv "LM_HTTP_PORT") "8080"))
        *api-key*   (or (uiop:getenv "LM_API_KEY") "dev-key-change-in-production")))
