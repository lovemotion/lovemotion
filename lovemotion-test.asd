(defsystem "lovemotion-test"
  :description "FiveAM test suite for LoveMotion"
  :depends-on ("lovemotion" "fiveam")
  :components ((:file "test/package")
               (:file "test/fixtures"   :depends-on ("test/package"))
               (:file "test/scoring"    :depends-on ("test/fixtures"))
               (:file "test/rules"      :depends-on ("test/fixtures"))
               (:file "test/simulation" :depends-on ("test/fixtures")))
  :perform (test-op (op system)
    (funcall (read-from-string "fiveam:run!") :lovemotion)))
