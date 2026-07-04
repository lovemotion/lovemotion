;;;; courier.lisp — payload serialization for the Spaces courier.
;;;;
;;;; Action #4, first half. The engine's s-expression IS the payload
;;;; (contract v1, versioned inside the body); this file only translates
;;;; it to MessagePack for the wire. Transport (DigitalOcean Spaces
;;;; upload/download) is deliberately last and does not exist yet.
;;;;
;;;; Wire shape mirrors the match_results JSONB shape: maps with
;;;; downcased string keys, keywords as strings, tag/value lists as
;;;; arrays, scores as float32. The conversion is deliberately
;;;; schema-driven, not generic: a findings :detail can be a bare list
;;;; of keywords, which a generic plist walker would misread as a plist.
;;;; When the contract changes, this file changes with it — that is the
;;;; point of :contract-version.

(defpackage :lovemotion.courier
  (:use :cl)
  (:export #:payload->bytes
           #:bytes->payload
           #:write-payload-file
           ;; Inbound twin batches (wire shape: COURIER.md).
           #:twins->bytes
           #:bytes->twins
           #:twin-batch-decode-error))

(in-package :lovemotion.courier)

(defun kw-name (keyword)
  (string-downcase (symbol-name keyword)))

(defun wire-map (&rest keys-and-values)
  (let ((table (make-hash-table :test #'equal)))
    (loop for (key value) on keys-and-values by #'cddr
          do (setf (gethash key table) value))
    table))

(defun detail->wire (detail)
  "A finding :detail is a score (number) or categorical values (keyword
or list of keywords)."
  (etypecase detail
    (real detail)
    (keyword (kw-name detail))
    (cons (mapcar #'kw-name detail))))

(defun finding->wire (finding)
  (wire-map "axis"     (kw-name (getf finding :axis))
            "code"     (kw-name (getf finding :code))
            "detail"   (detail->wire (getf finding :detail))
            "severity" (kw-name (getf finding :severity))))

(defun match->wire (match)
  (wire-map "twin-a"   (getf match :twin-a)
            "twin-b"   (getf match :twin-b)
            "score"    (getf match :score)
            "findings" (mapcar #'finding->wire (getf match :findings))))

(defun matrix-versions->wire (versions)
  (apply #'wire-map
         (loop for (axis-id version) on versions by #'cddr
               append (list (kw-name axis-id) version))))

(defun payload->wire (payload)
  (wire-map "contract-version" (getf payload :contract-version)
            "run-id"           (getf payload :run-id)
            "matrix-versions"  (matrix-versions->wire
                                (getf payload :matrix-versions))
            "pool-size"        (getf payload :pool-size)
            "matches"          (mapcar #'match->wire
                                       (getf payload :matches))))

(defun payload->bytes (payload)
  "Engine payload plist -> MessagePack octets. This is what crosses the
boundary; per-axis scores are already absent by construction."
  (messagepack:encode (payload->wire payload)))

(defun bytes->payload (bytes)
  "MessagePack octets -> wire tree (nested equal-keyed hash tables /
vectors / strings / numbers). Used by tests and any future consumer-side
tooling; HeyU's real consumer is Elixir."
  (messagepack:decode bytes))

(defun write-payload-file (payload path)
  "Serialize PAYLOAD to PATH. The courier's job will be moving exactly
these bytes; producing them locally keeps transport a dumb copy."
  (with-open-file (out path :direction :output
                            :element-type '(unsigned-byte 8)
                            :if-exists :supersede)
    (write-sequence (payload->bytes payload) out))
  path)

;;; ---------------------------------------------------------------------
;;; Inbound: twin batches (COURIER.md, twins/v1)
;;;
;;; The decoder is the real consumer-side code. The encoder exists so
;;; the wire contract is executable and testable from this repo — HeyU's
;;; production encoder is Elixir and must produce these exact shapes.
;;; ---------------------------------------------------------------------

(define-condition twin-batch-decode-error (error)
  ((detail :initarg :detail :reader twin-batch-decode-error-detail))
  (:report (lambda (c stream)
             (format stream "twin batch decode failed: ~a"
                     (twin-batch-decode-error-detail c)))))

(defun decode-error (format &rest args)
  (error 'twin-batch-decode-error
         :detail (apply #'format nil format args)))

(defconstant +epoch-offset+ 2208988800
  "Seconds between the CL universal-time epoch (1900) and unix (1970).
Wire timestamps are unix epoch seconds; everything in-process is
universal-time.")

(defun wire-kw (string)
  (unless (stringp string)
    (decode-error "expected a string, got ~s" string))
  (intern (string-upcase string) :keyword))

(defun wire-epoch (value what)
  "Unix epoch seconds off the wire -> universal-time."
  (unless (integerp value)
    (decode-error "~a: expected epoch seconds, got ~s" what value))
  (+ value +epoch-offset+))

(defun value->wire (value)
  "Lisp axis value -> (kind . wire-value). Booleans ride as categorical
\"true\"/\"false\" — the DB's typed trio has no boolean, so neither does
the wire."
  (typecase value
    (boolean (cons "categorical" (if value "true" "false")))
    (real (cons "scalar" (coerce value 'single-float)))
    (keyword (cons "categorical" (kw-name value)))
    (cons (cons "tagset" (mapcar #'kw-name value)))
    (t (error "unencodable axis value: ~s" value))))

(defun axis-value->wire (av)
  (destructuring-bind (kind . wire-value)
      (value->wire (lovemotion:axis-value-value av))
    (wire-map "axis"        (kw-name (lovemotion:axis-value-axis-id av))
              "kind"        kind
              "value"       wire-value
              "confidence"  (coerce (lovemotion:axis-value-confidence av)
                                    'single-float)
              "provenance"  (kw-name (lovemotion:axis-value-provenance av))
              "observed-at" (- (lovemotion:axis-value-observed-at av)
                               +epoch-offset+))))

(defun twin->wire (twin)
  (wire-map "id" (lovemotion:twin-id twin)
            "axis-values"
            (loop for av being the hash-values
                    of (lovemotion:twin-axis-values twin)
                  collect (axis-value->wire av))))

(defun twins->bytes (twins &key batch-id generated-at)
  "Twin structs -> MessagePack twin-batch octets (COURIER.md wire shape).
BATCH-ID and GENERATED-AT (universal-time) are required — the batch id
is the consumer's idempotency key, so it must never be invented here."
  (unless (and batch-id generated-at)
    (error "twins->bytes needs :batch-id and :generated-at explicitly"))
  (messagepack:encode
   (wire-map "contract-version" 1
             "batch-id"         batch-id
             "generated-at"     (- generated-at +epoch-offset+)
             "twins"            (mapcar #'twin->wire twins))))

(defun require-field (map key)
  (unless (hash-table-p map)
    (decode-error "expected a map, got ~s" map))
  (multiple-value-bind (value present) (gethash key map)
    (unless present
      (decode-error "missing required field ~s" key))
    value))

(defun wire->value (kind wire-value axis)
  "Wire value -> Lisp axis value, validated against KIND — the wire
mirror of the DB trio's num_nonnulls CHECK. Categorical \"true\"/\"false\"
come back as booleans."
  (cond
    ((equal kind "scalar")
     (unless (realp wire-value)
       (decode-error "~a: scalar kind but value ~s" axis wire-value))
     (coerce wire-value 'single-float))
    ((equal kind "categorical")
     (unless (stringp wire-value)
       (decode-error "~a: categorical kind but value ~s" axis wire-value))
     (cond ((equal wire-value "true") t)
           ((equal wire-value "false") nil)
           (t (wire-kw wire-value))))
    ((equal kind "tagset")
     (unless (and (vectorp wire-value) (every #'stringp wire-value))
       (decode-error "~a: tagset kind but value ~s" axis wire-value))
     (map 'list #'wire-kw wire-value))
    (t (decode-error "~a: unknown kind ~s" axis kind))))

(defun wire->axis-value (map)
  (let* ((axis (require-field map "axis"))
         (confidence (require-field map "confidence"))
         (provenance (wire-kw (require-field map "provenance"))))
    ;; Confidence is required by the iron rule: it must never silently
    ;; default — least of all to 1.0 — at the system's front door.
    (unless (realp confidence)
      (decode-error "~a: confidence ~s is not a number" axis confidence))
    (unless (member provenance '(:observed :self-reported :inferred))
      (decode-error "~a: unknown provenance ~s" axis provenance))
    (lovemotion:make-axis-value
     :axis-id (wire-kw axis)
     :value (wire->value (require-field map "kind")
                         (require-field map "value")
                         axis)
     :confidence (coerce confidence 'single-float)
     :provenance provenance
     :observed-at (wire-epoch (require-field map "observed-at")
                              (format nil "~a observed-at" axis)))))

(defun require-array (map key)
  (let ((value (require-field map key)))
    (unless (vectorp value)
      (decode-error "~s: expected an array, got ~s" key value))
    value))

(defun wire->twin (map)
  (let ((twin (lovemotion:make-twin :id (require-field map "id"))))
    (loop for av-map across (require-array map "axis-values")
          for av = (wire->axis-value av-map)
          do (setf (gethash (lovemotion:axis-value-axis-id av)
                            (lovemotion:twin-axis-values twin))
                   av))
    twin))

(defun bytes->twins (bytes)
  "Twin-batch octets -> (:contract-version N :batch-id N :generated-at
universal-time :twins (twin ...)). Signals TWIN-BATCH-DECODE-ERROR on any
shape violation — a malformed batch must never half-load."
  (let ((wire (messagepack:decode bytes)))
    (unless (hash-table-p wire)
      (decode-error "top level is not a map"))
    (let ((version (require-field wire "contract-version")))
      (unless (eql version 1)
        (decode-error "contract-version ~s, expected 1" version)))
    (list :contract-version 1
          :batch-id (require-field wire "batch-id")
          :generated-at (wire-epoch (require-field wire "generated-at")
                                    "generated-at")
          :twins (map 'list #'wire->twin (require-array wire "twins")))))
