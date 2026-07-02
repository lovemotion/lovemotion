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
