;;;; transport.lisp — moving courier bytes (COURIER.md, action #4 second half).
;;;;
;;;; This file implements COURIER.md exactly; when that document changes,
;;;; this file changes with it. Two transports behind one protocol:
;;;;
;;;;   local-transport   — a directory. Real code, fully tested; also the
;;;;                       dev/debug transport (drop a batch file in, run).
;;;;   spaces-transport  — DigitalOcean Spaces via zs3 (S3-compatible).
;;;;                       A thin mapping onto the same protocol; goes
;;;;                       live the moment bucket + credentials exist.
;;;;
;;;; Everything above the protocol (key naming, cursor logic, ship/fetch)
;;;; is transport-agnostic and pure where possible, so the local tests
;;;; exercise the same code paths Spaces will run.

(defpackage :lovemotion.transport
  (:use :cl)
  (:export ;; protocol
           #:courier-put
           #:courier-get
           #:courier-list
           ;; transports
           #:make-local-transport
           #:make-spaces-transport
           #:make-spaces-transport-from-env
           ;; key logic (pure)
           #:+matches-prefix+
           #:+twins-prefix+
           #:matches-key
           #:twin-batch-key
           #:keys-after
           ;; high level
           #:ship-matches
           #:new-twin-batch-keys
           #:fetch-twin-batch))

(in-package :lovemotion.transport)

;;; ---------------------------------------------------------------------
;;; Key logic — pure functions, no I/O. Lexicographic = chronological is
;;; the property the cursor handshake rides on; guard it here.
;;; ---------------------------------------------------------------------

(defparameter +matches-prefix+ "matches/v1/")
(defparameter +twins-prefix+ "twins/v1/")

(defun utc-stamp (universal-time)
  "Basic ISO-8601 UTC: 20260704T031500Z. Fixed width so keys sort."
  (multiple-value-bind (sec min hour day month year)
      (decode-universal-time universal-time 0)
    (format nil "~4,'0d~2,'0d~2,'0dT~2,'0d~2,'0d~2,'0dZ"
            year month day hour min sec)))

(defun id-slug (prefix id)
  "run-000042 / batch-000117; string ids (e.g. \"run-local-0\") pass
through — they already carry their own name."
  (etypecase id
    (integer (format nil "~a-~6,'0d" prefix id))
    (string id)))

(defun matches-key (run-id shipped-at)
  (format nil "~a~a-~a.msgpack"
          +matches-prefix+ (utc-stamp shipped-at) (id-slug "run" run-id)))

(defun twin-batch-key (batch-id generated-at)
  (format nil "~a~a-~a.msgpack"
          +twins-prefix+ (utc-stamp generated-at) (id-slug "batch" batch-id)))

(defun keys-after (keys cursor)
  "Keys strictly after CURSOR (nil = everything), lexicographic order —
the consumer-side half of the COURIER.md handshake."
  (sort (remove-if-not (lambda (key)
                         (or (null cursor) (string> key cursor)))
                       (coerce keys 'list))
        #'string<))

;;; ---------------------------------------------------------------------
;;; Protocol
;;; ---------------------------------------------------------------------

(defgeneric courier-put (transport key bytes)
  (:documentation "Store BYTES at KEY. One payload = one object; the put
is the entire publish — no markers, no manifests."))

(defgeneric courier-get (transport key)
  (:documentation "Fetch the octets at KEY."))

(defgeneric courier-list (transport prefix)
  (:documentation "All keys under PREFIX, as strings, order unspecified
(KEYS-AFTER owns ordering)."))

;;; ---------------------------------------------------------------------
;;; Local transport — a directory
;;; ---------------------------------------------------------------------

(defstruct (local-transport (:constructor %make-local-transport))
  root)   ; directory pathname

(defun make-local-transport (root)
  (%make-local-transport :root (uiop:ensure-directory-pathname root)))

(defun key-path (transport key)
  (merge-pathnames key (local-transport-root transport)))

(defmethod courier-put ((transport local-transport) key bytes)
  (let ((path (key-path transport key)))
    (ensure-directories-exist path)
    (with-open-file (out path :direction :output
                              :element-type '(unsigned-byte 8)
                              :if-exists :supersede)
      (write-sequence bytes out))
    key))

(defmethod courier-get ((transport local-transport) key)
  (with-open-file (in (key-path transport key)
                      :element-type '(unsigned-byte 8))
    (let ((bytes (make-array (file-length in)
                             :element-type '(unsigned-byte 8))))
      (read-sequence bytes in)
      bytes)))

(defmethod courier-list ((transport local-transport) prefix)
  (let ((root (local-transport-root transport)))
    (loop for path in (directory
                       (merge-pathnames "**/*.msgpack" root))
          for key = (uiop:unix-namestring (uiop:enough-pathname path root))
          when (uiop:string-prefix-p prefix key)
            collect key)))

;;; ---------------------------------------------------------------------
;;; Spaces transport — zs3 against the DO endpoint
;;;
;;; Untestable without bucket + credentials by design; kept to a thin,
;;; obviously-correct mapping for exactly that reason.
;;; ---------------------------------------------------------------------

(defstruct (spaces-transport (:constructor %make-spaces-transport))
  bucket
  endpoint
  region
  credentials)   ; (access-key secret-key) — a zs3-acceptable credential

(defun make-spaces-transport (&key bucket endpoint region access-key secret-key)
  (%make-spaces-transport :bucket bucket
                          :endpoint endpoint
                          :region region
                          :credentials (list access-key secret-key)))

(defun make-spaces-transport-from-env ()
  "Configuration enters through the environment (COURIER.md) — domain
code never sees it."
  (flet ((env (name)
           (or (uiop:getenv name)
               (error "~a is not set — see COURIER.md for the required ~
                       LM_SPACES_* environment" name))))
    (make-spaces-transport :bucket (env "LM_SPACES_BUCKET")
                           :endpoint (env "LM_SPACES_ENDPOINT")
                           :region (env "LM_SPACES_REGION")
                           :access-key (env "LM_SPACES_KEY")
                           :secret-key (env "LM_SPACES_SECRET"))))

(defmacro with-spaces ((transport) &body body)
  `(let ((zs3:*credentials* (spaces-transport-credentials ,transport))
         (zs3:*s3-endpoint* (spaces-transport-endpoint ,transport))
         (zs3:*s3-region* (spaces-transport-region ,transport)))
     ,@body))

(defun sha256-hex (bytes)
  (ironclad:byte-array-to-hex-string
   (ironclad:digest-sequence :sha256 bytes)))

(defmethod courier-put ((transport spaces-transport) key bytes)
  (with-spaces (transport)
    (zs3:put-vector bytes (spaces-transport-bucket transport) key
                    :content-type "application/msgpack"
                    :metadata (list (cons "payload-sha256"
                                          (sha256-hex bytes)))))
  key)

(defmethod courier-get ((transport spaces-transport) key)
  (with-spaces (transport)
    (zs3:get-vector (spaces-transport-bucket transport) key)))

(defmethod courier-list ((transport spaces-transport) prefix)
  (with-spaces (transport)
    (map 'list #'zs3:name
         (zs3:all-keys (spaces-transport-bucket transport)
                       :prefix prefix))))

;;; ---------------------------------------------------------------------
;;; High level — what the pipeline actually calls
;;; ---------------------------------------------------------------------

(defun ship-matches (transport payload
                     &key (shipped-at (get-universal-time)))
  "Serialize PAYLOAD and publish it under matches/v1/. Returns the key.
The payload is already PII-free and per-axis-score-free by construction;
transport is a dumb copy."
  (courier-put transport
               (matches-key (getf payload :run-id) shipped-at)
               (lovemotion.courier:payload->bytes payload)))

(defun new-twin-batch-keys (transport cursor)
  "Twin-batch keys strictly after CURSOR (the last key this consumer
processed; nil on first run), oldest first. The caller advances its
cursor only after a batch fully persists — idempotency by batch-id
covers the crash window in between."
  (keys-after (courier-list transport +twins-prefix+) cursor))

(defun fetch-twin-batch (transport key)
  "Fetch + decode one twin batch: (:contract-version _ :batch-id _
:generated-at _ :twins (...)). Decode failures signal
LOVEMOTION.COURIER:TWIN-BATCH-DECODE-ERROR."
  (lovemotion.courier:bytes->twins (courier-get transport key)))
