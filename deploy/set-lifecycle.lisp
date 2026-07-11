;;;; set-lifecycle.lisp — one-shot: put the 30-day expiry rule on the
;;;; courier bucket (COURIER.md "Retention"), then read it back.
;;;;
;;;; NEEDS A FULL-ACCESS SPACES KEY in LM_SPACES_KEY/SECRET for this one
;;;; run — DO's bucket-scoped keys get AccessDenied on lifecycle config
;;;; (verified 2026-07-11; object ops unaffected), and the control panel
;;;; has no lifecycle UI. The scoped key in .env stays the runtime
;;;; credential; don't overwrite it.
;;;;
;;;; Run: LM_SPACES_KEY=<full> LM_SPACES_SECRET=<full> \
;;;;   LM_SPACES_BUCKET=lovemotion-courier \
;;;;   LM_SPACES_ENDPOINT=sfo3.digitaloceanspaces.com LM_SPACES_REGION=sfo3 \
;;;;   sbcl --non-interactive --load ~/.quicklisp/setup.lisp --load deploy/set-lifecycle.lisp

(push #p"/home/danny/development/lovemotion/" asdf:*central-registry*)
(ql:quickload :lovemotion/transport :silent t)

(defun env (name)
  (or (uiop:getenv name) (error "~a not set" name)))

(let* ((bucket (env "LM_SPACES_BUCKET"))
       ;; Same DO-dialect bindings as with-spaces in transport.lisp:
       ;; HTTPS mandatory, bucket baked into the endpoint.
       (zs3:*credentials* (list (env "LM_SPACES_KEY") (env "LM_SPACES_SECRET")))
       (zs3:*s3-endpoint* (format nil "~a.~a" bucket (env "LM_SPACES_ENDPOINT")))
       (zs3:*s3-region* (env "LM_SPACES_REGION"))
       (zs3:*use-ssl* t))
  (setf (zs3:bucket-lifecycle bucket)
        (list (zs3:lifecycle-rule :id "expire-30d" :prefix "" :days 30)))
  (format t "~&PUT ok; reading back:~%")
  (dolist (rule (zs3:bucket-lifecycle bucket))
    (format t "  rule ~s prefix ~s days ~s enabled ~s~%"
            (zs3::id rule) (zs3::prefix rule)
            (zs3::days rule) (zs3::enabledp rule))))
