(defpackage #:lovemotion.api.health
  (:use #:cl)
  (:export #:handle))

(in-package #:lovemotion.api.health)

(defun handle ()
  (jonathan:to-json
   (list :|status|    (if (lovemotion.database:check-connection) "ok" "degraded")
         :|version|   "0.1.0"
         :|database|  (if (lovemotion.database:check-connection) "connected" "unreachable")
         :|scheduler| (if lovemotion.matching.scheduler:*scheduler-running-p*
                          "running"
                          "stopped"))))
