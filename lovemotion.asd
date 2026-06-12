(defsystem "lovemotion"
  :description "Companion-to-Companion Pre-Connection Simulation Engine"
  :version "0.1.0"
  :author "Danny Simon"
  :license "Apache-2.0"
  :depends-on ("hunchentoot"
               "postmodern"
               "jonathan"
               "bordeaux-threads"
               "log4cl"
               "cl-ppcre"
               "uiop")
  :components ((:file "src/config")
               (:file "src/database"   :depends-on ("src/config"))
               (:file "src/model/companion"  :depends-on ("src/database"))
               (:file "src/model/match-result" :depends-on ("src/database" "src/model/companion"))
               (:file "src/engine/rules"      :depends-on ("src/model/companion"))
               (:file "src/engine/scoring"    :depends-on ("src/engine/rules"))
               (:file "src/engine/rules/gates"        :depends-on ("src/engine/rules" "src/model/companion"))
               (:file "src/engine/rules/growth"       :depends-on ("src/engine/rules" "src/engine/scoring" "src/model/companion"))
               (:file "src/engine/rules/contribution" :depends-on ("src/engine/rules" "src/model/companion"))
               (:file "src/engine/rules/values"       :depends-on ("src/engine/rules" "src/model/companion"))
               (:file "src/engine/rules/readiness"    :depends-on ("src/engine/rules" "src/model/companion"))
               (:file "src/engine/rules/practical"    :depends-on ("src/engine/rules" "src/model/companion"))
               (:file "src/engine/simulation" :depends-on ("src/engine/rules" "src/engine/scoring"
                                                            "src/engine/rules/gates"
                                                            "src/engine/rules/growth"
                                                            "src/engine/rules/contribution"
                                                            "src/engine/rules/values"
                                                            "src/engine/rules/readiness"
                                                            "src/engine/rules/practical"))
               (:file "src/matching/pgvector" :depends-on ("src/database" "src/model/companion"))
               (:file "src/matching/pipeline" :depends-on ("src/engine/simulation" "src/matching/pgvector" "src/model/match-result"))
               (:file "src/matching/scheduler" :depends-on ("src/matching/pipeline"))
               (:file "src/api/health"        :depends-on ("src/database" "src/matching/scheduler"))
               (:file "src/api/companions"    :depends-on ("src/model/companion"))
               (:file "src/api/matches"       :depends-on ("src/model/match-result"))
               (:file "src/server"            :depends-on ("src/api/health" "src/api/companions" "src/api/matches"))
               (:file "src/main"              :depends-on ("src/server" "src/matching/scheduler"))))
