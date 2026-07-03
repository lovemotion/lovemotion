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
           #:write-payload-file))

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
