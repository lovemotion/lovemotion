#!/usr/bin/env bash
# Deploy the static landing page + nginx config to the droplet.
#
#   deploy/deploy-site.sh [host]     (default: lovemotion.io — user/key
#                                     come from ~/.ssh/config; the remote
#                                     user needs passwordless sudo)
#
# Safe by construction: backs up the live nginx conf, tests with
# nginx -t before reloading, and rolls the conf back if the test fails.
# The API (/v1/*, /admin/*) is proxied through unchanged.
set -euo pipefail

HOST="${1:-lovemotion.io}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

echo "==> site files -> $HOST:/var/www/lovemotion/site/"
ssh "$HOST" "sudo mkdir -p /var/www/lovemotion/site"
rsync -av --delete --rsync-path="sudo rsync" \
      "$REPO/site/" "$HOST:/var/www/lovemotion/site/"

echo "==> nginx conf (backup + test + reload, rollback on failure)"
scp "$REPO/deploy/nginx-lovemotion.io.conf" "$HOST:/tmp/lovemotion.io.conf.new"
ssh "$HOST" sudo bash -s "$STAMP" <<'REMOTE'
set -euo pipefail
STAMP="$1"
CONF=/etc/nginx/sites-available/lovemotion.io
cp "$CONF" "$CONF.bak.$STAMP"
cp /tmp/lovemotion.io.conf.new "$CONF"
if nginx -t; then
    systemctl reload nginx
    echo "reloaded; previous conf saved at $CONF.bak.$STAMP"
else
    cp "$CONF.bak.$STAMP" "$CONF"
    echo "nginx -t FAILED — conf rolled back, nginx untouched" >&2
    exit 1
fi
REMOTE

echo "==> verify"
curl -sS -o /dev/null -w "landing page:  %{http_code}\n" https://lovemotion.io/
curl -sS -o /dev/null -w "favicon:       %{http_code}\n" https://lovemotion.io/assets/favicon.ico
curl -sS -o /dev/null -w "api health:    %{http_code}\n" https://lovemotion.io/v1/health
