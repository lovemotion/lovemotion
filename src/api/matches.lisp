(defpackage #:lovemotion.api.matches
  (:use #:cl #:hunchentoot)
  (:export #:handle-list))

(in-package #:lovemotion.api.matches)

(defun handle-list ()
  "Return ready, unconsumed matches. Optional ?since=ISO8601 filter."
  (let ((since (hunchentoot:get-parameter "since")))
    (lovemotion.database:with-db
      (let ((rows (lovemotion.model.match-result:unconsumed-matches since)))
        (jonathan:to-json
         (list :|matches|
               (mapcar (lambda (row)
                         (destructuring-bind (id ref-a ref-b score explanation simulated-at) row
                           (list :|match_id|     (format nil "~a" id)
                                 :|companion_a|  ref-a
                                 :|companion_b|  ref-b
                                 :|score|        score
                                 :|explanation|  explanation
                                 :|simulated_at| (format nil "~a" simulated-at))))
                       rows)))))))
