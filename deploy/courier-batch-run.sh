#!/usr/bin/env bash
# One courier batch: drain twins/v1, run matching if anything new
# arrived, ship matches/v1. Invoked by lovemotion-batch.timer; the
# LM_DB_* / LM_SPACES_* environment comes from /etc/lovemotion/batch.env
# via the service unit. Exit status is the batch's: a poison batch or
# dead courier fails loudly and shows in systemctl status.
set -euo pipefail
cd "$(dirname "$0")/.."
exec sbcl --dynamic-space-size 700 --non-interactive \
  --load "$HOME/.quicklisp/setup.lisp" \
  --eval '(push (uiop:getcwd) asdf:*central-registry*)' \
  --eval '(ql:quickload :lovemotion/batch :silent t)' \
  --eval '(let ((result (lovemotion.batch:courier-batch-run)))
            (format t "courier-batch-run: drained ~d~@[, shipped ~a~]~%"
                    (length (getf result :drained))
                    (getf result :shipped-key)))'
