#!/bin/bash
# Build a standalone SBCL executable with all deps pre-loaded.
# Run once; restart systemd after to pick up the new binary.
set -e

REPO=/home/danny/development/lovemotion
OUT=$REPO/bin/lovemotion

mkdir -p "$REPO/bin"

echo "Loading system (this takes ~15s)..."
sbcl --noinform \
     --load ~/.quicklisp/setup.lisp \
     --eval "(push #p\"$REPO/\" asdf:*central-registry*)" \
     --eval "(ql:quickload :lovemotion :silent t)" \
     --eval "(sb-ext:save-lisp-and-die \"$OUT\" :executable t :toplevel #'lovemotion:main :compression t)"

echo "Built: $OUT ($(du -sh "$OUT" | cut -f1))"
echo "Now run: sudo systemctl restart lovemotion"
