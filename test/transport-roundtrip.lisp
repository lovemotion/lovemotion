;;;; transport-roundtrip.lisp — the full courier loop, minus the network.
;;;;
;;;; Run: (asdf:test-system :lovemotion/transport)
;;;;
;;;; Plays both sides of COURIER.md through the local transport: encodes
;;;; the fixture pools as twin batches (HeyU's role), publishes them,
;;;; drains them with the cursor handshake, runs the engine on what came
;;;; off the wire, and asserts the results equal the blessed golden
;;;; payloads. The Spaces transport is the same protocol behind the same
;;;; high-level calls; only the byte-moving differs.

(defpackage :lovemotion.transport-test
  (:use :cl)
  (:export #:transport-roundtrip-test))

(in-package :lovemotion.transport-test)

(defvar *failures*)

(defun check (label got expected)
  (unless (equalp got expected)
    (push (format nil "~a: expected ~s, got ~s" label expected got)
          *failures*)))

;; Fixed timestamps: keys must be deterministic to assert on.
(defparameter +t1+ (encode-universal-time 0 0 2 4 7 2026 0))   ; 02:00:00Z
(defparameter +t2+ (encode-universal-time 30 15 3 4 7 2026 0)) ; 03:15:30Z
(defparameter +t3+ (encode-universal-time 0 30 3 4 7 2026 0))  ; 03:30:00Z

(defun check-key-logic ()
  (check "matches-key int id"
         (lovemotion.transport:matches-key 42 +t2+)
         "matches/v1/20260704T031530Z-run-000042.msgpack")
  (check "matches-key string id passthrough"
         (lovemotion.transport:matches-key "run-local-0" +t2+)
         "matches/v1/20260704T031530Z-run-local-0.msgpack")
  (check "twin-batch-key"
         (lovemotion.transport:twin-batch-key 117 +t1+)
         "twins/v1/20260704T020000Z-batch-000117.msgpack")
  (let ((keys (list "twins/v1/b" "twins/v1/c" "twins/v1/a")))
    (check "keys-after nil cursor sorts everything"
           (lovemotion.transport:keys-after keys nil)
           '("twins/v1/a" "twins/v1/b" "twins/v1/c"))
    (check "keys-after cursor is strict"
           (lovemotion.transport:keys-after keys "twins/v1/b")
           '("twins/v1/c"))))

(defun publish-batch (transport twins batch-id generated-at)
  (lovemotion.transport:courier-put
   transport
   (lovemotion.transport:twin-batch-key batch-id generated-at)
   (lovemotion.courier:twins->bytes twins :batch-id batch-id
                                          :generated-at generated-at)))

(defun check-inbound (transport)
  "Three batches in, drained oldest-first by cursor, each run off the
wire must hit its blessed payload bit-for-bit."
  (publish-batch transport lovemotion:*fixture-twins* 117 +t1+)
  (publish-batch transport lovemotion:*fixture-twins-mixed* 118 +t2+)
  (publish-batch transport lovemotion:*fixture-twins-dealbreakers* 119 +t3+)
  (let ((keys (lovemotion.transport:new-twin-batch-keys transport nil)))
    (check "all batches listed, oldest first"
           keys
           (list (lovemotion.transport:twin-batch-key 117 +t1+)
                 (lovemotion.transport:twin-batch-key 118 +t2+)
                 (lovemotion.transport:twin-batch-key 119 +t3+)))
    (check "cursor skips processed batches"
           (lovemotion.transport:new-twin-batch-keys transport (first keys))
           (rest keys))
    (flet ((run-off-wire (key run-id)
             (let ((batch (lovemotion.transport:fetch-twin-batch
                           transport key)))
               (lovemotion:run-matching (getf batch :twins)
                                        :run-id run-id))))
      (check "batch-id survives the wire"
             (getf (lovemotion.transport:fetch-twin-batch
                    transport (first keys))
                   :batch-id)
             117)
      (check "base pool off the wire = blessed payload"
             (run-off-wire (first keys) "run-local-0")
             lovemotion-test:+golden-payload+)
      (check "mixed pool off the wire = blessed payload"
             (run-off-wire (second keys) "run-local-mixed-0")
             lovemotion-test:+golden-payload-mixed+)
      (check "dealbreaker pool off the wire = blessed payload"
             (run-off-wire (third keys) "run-local-dealbreakers-0")
             lovemotion-test:+golden-payload-dealbreakers+))))

(defun check-outbound (transport)
  "Ship the golden payload; the stored bytes must be exactly what
payload->bytes produces — transport is a dumb copy."
  (let* ((payload (lovemotion:run-matching lovemotion:*fixture-twins*))
         (key (lovemotion.transport:ship-matches transport payload
                                                 :shipped-at +t3+)))
    (check "ship-matches key"
           key "matches/v1/20260704T033000Z-run-local-0.msgpack")
    (check "shipped bytes are byte-identical"
           (lovemotion.transport:courier-get transport key)
           (lovemotion.courier:payload->bytes payload))
    (check "matches listing sees only matches"
           (lovemotion.transport:courier-list
            transport lovemotion.transport:+matches-prefix+)
           (list key))))

(defun malformed-batch-bytes ()
  "A twin batch whose one axis-value is missing confidence."
  (let ((av (make-hash-table :test #'equal))
        (tw (make-hash-table :test #'equal))
        (batch (make-hash-table :test #'equal)))
    (setf (gethash "axis" av) "chronotype"
          (gethash "kind" av) "scalar"
          (gethash "value" av) 0.5
          (gethash "provenance" av) "self-reported"
          (gethash "observed-at" av) 1782000000)
    (setf (gethash "id" tw) "tw_malformed"
          (gethash "axis-values" tw) (list av))
    (setf (gethash "contract-version" batch) 1
          (gethash "batch-id" batch) 999
          (gethash "generated-at" batch) 1782000000
          (gethash "twins" batch) (list tw))
    (messagepack:encode batch)))

(defun check-decode-guards ()
  "Missing confidence must be a decode error, never a default (iron
rule), and must signal the courier's own condition."
  (check "missing confidence signals twin-batch-decode-error"
         (handler-case
             (progn (lovemotion.courier:bytes->twins (malformed-batch-bytes))
                    :decoded-anyway)
           (lovemotion.courier:twin-batch-decode-error () :signaled))
         :signaled))

(defun transport-roundtrip-test ()
  (let* ((*failures* '())
         (root (merge-pathnames "lovemotion-transport-test/"
                                (uiop:temporary-directory)))
         (transport (lovemotion.transport:make-local-transport root)))
    (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore)
    (unwind-protect
         (progn
           (check-key-logic)
           (check-inbound transport)
           (check-outbound transport)
           (check-decode-guards))
      (uiop:delete-directory-tree root :validate t
                                       :if-does-not-exist :ignore))
    (cond ((null *failures*)
           (format t "~&TRANSPORT-ROUNDTRIP-OK~%")
           t)
          (t
           (format t "~&TRANSPORT-ROUNDTRIP-FAILED~%~{  ~a~%~}"
                   (reverse *failures*))
           nil))))
