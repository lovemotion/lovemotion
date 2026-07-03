;;;; lovemotion.asd
;;;;
;;;; The :lovemotion system is the pure engine — no dependencies, no I/O.
;;;; Adapters (Postgres, courier) are separate systems layered on top so
;;;; the core stays loadable and testable anywhere SBCL runs.

(defsystem "lovemotion"
  :description "LoveMotion v0 — pure in-memory matching engine: twin-set -> match payload."
  :author "Danny Simon"
  :license "Apache-2.0"
  :version "0.1.0"
  :serial t
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "engine")
                             (:file "fixtures"))))
  :in-order-to ((test-op (test-op "lovemotion/test"))))

(defsystem "lovemotion/test"
  :description "Golden test: one equal over one blessed payload."
  :depends-on ("lovemotion")
  :components ((:module "test"
                :components ((:file "golden"))))
  :perform (test-op (o c)
             (unless (symbol-call :lovemotion-test :golden-test)
               (error "GOLDEN-TEST-FAILED — engine payload no longer matches the blessed payload in test/golden.lisp"))))

(defsystem "lovemotion/courier"
  :description "Payload serialization for the Spaces courier (MessagePack). Transport deliberately not here yet."
  :depends-on ("lovemotion" "cl-messagepack")
  :components ((:module "src"
                :components ((:file "courier"))))
  :in-order-to ((test-op (test-op "lovemotion/courier-test"))))

(defsystem "lovemotion/courier-test"
  :description "Golden payload through MessagePack and back, field-by-field."
  :depends-on ("lovemotion/courier")
  :components ((:module "test"
                :components ((:file "courier-roundtrip"))))
  :perform (test-op (o c)
             (unless (symbol-call :lovemotion.courier-test :courier-roundtrip-test)
               (error "COURIER-ROUNDTRIP-TEST failed"))))

(defsystem "lovemotion/db"
  :description "Postgres adapter: fetch/persist seams around the pure engine."
  :depends-on ("lovemotion" "postmodern" "jonathan")
  :components ((:module "src"
                :components ((:file "db")))))

(defsystem "lovemotion/db-test"
  :description "Round-trip integration test — needs a live lovemotion_v0 database (scripts/schema.sql + seed-v0.sql applied). Not part of plain test-op; run explicitly."
  :depends-on ("lovemotion/db" "lovemotion/test")
  :components ((:module "test"
                :components ((:file "db-roundtrip"))))
  :perform (test-op (o c)
             (unless (symbol-call :lovemotion.db-test :db-roundtrip-test)
               (error "DB-ROUNDTRIP-TEST failed"))))
