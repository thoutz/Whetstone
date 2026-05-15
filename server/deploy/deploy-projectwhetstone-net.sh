#!/usr/bin/env bash
# Deploy marketing site + admin Node API to projectwhetstone.net VPS (149.28.38.55 by default).
#
# This VPS uses **password** root login. Password is read from:
#   project-docs/server-login-info.txt — line after "Password (...)" header (awk),
#   fallback LOGIN_LINE (default 5), using **sshpass**.
# The password file is preferred over a stray SSHPASS in the environment (CI / IDE).
# You can still set SSHPASS explicitly when that file is absent.
#
# If sshpass or that file is unavailable, falls back to public-key BatchMode ssh.
#
# Usage (from repo root):
#   ./server/deploy/deploy-projectwhetstone-net.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEPLOY_HOST="${DEPLOY_HOST:-149.28.38.55}"
DEPLOY_USER="${DEPLOY_USER:-root}"
REMOTE_WEB="${REMOTE_WEB:-/var/www/whetstone-website}"
REMOTE_ADMIN="${REMOTE_ADMIN:-/opt/whetstone-admin}"
REMOTE_API="${REMOTE_API:-/opt/whetstone-api}"
REMOTE_SHARED="${REMOTE_SHARED:-/opt/whetstone-shared}"
ENV_REMOTE="${ENV_REMOTE:-/etc/whetstone-proxy.env}"
LOGIN_LINE="${LOGIN_LINE:-5}"
PASSWORD_FILE="${ROOT}/project-docs/server-login-info.txt"

read_ssh_pass_from_notes() {
  # Matches the helper documented in server-login-info.txt (line after "Password (...)" header).
  local pw=""
  pw="$(awk '/^Password \(copy exactly/{ getline; gsub(/\r$/,"",$0); print; exit}' "$PASSWORD_FILE")"
  if [[ -z "$pw" ]] || [[ "$pw" =~ ^SSH_PASS ]] || [[ "$pw" =~ ^Scripted ]]; then
    pw="$(sed -n "${LOGIN_LINE}p" "$PASSWORD_FILE" | tr -d '\r')"
  fi
  printf '%s' "$pw"
}

TARGET="${DEPLOY_USER}@${DEPLOY_HOST}"

# Prefer notes file password over stray SSHPASS (IDE/CI environments).
declare -a SSH_PASS_PRE=()
RSYNC_TUNNEL_KEY="ssh -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new"
RSYNC_TUNNEL_PASS="ssh -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password -o PubkeyAuthentication=no"

if command -v sshpass >/dev/null 2>&1 && [[ -f "$PASSWORD_FILE" ]]; then
  export SSHPASS
  SSHPASS="$(read_ssh_pass_from_notes)"
  echo "Using sshpass + password extracted from ${PASSWORD_FILE}."
  SSH_PASS_PRE=(sshpass -e)
  RSYNC_TUNNEL="$RSYNC_TUNNEL_PASS"
elif [[ -n "${SSHPASS:-}" ]] && command -v sshpass >/dev/null 2>&1; then
  echo "Using SSHPASS from environment (value not shown)."
  SSH_PASS_PRE=(sshpass -e)
  RSYNC_TUNNEL="$RSYNC_TUNNEL_PASS"
else
  echo "Using public-key ssh (BatchMode)."
  RSYNC_TUNNEL="$RSYNC_TUNNEL_KEY"
fi

do_rsync() {
  if [[ ${#SSH_PASS_PRE[@]} -gt 0 ]]; then
    "${SSH_PASS_PRE[@]}" rsync -avz -e "$RSYNC_TUNNEL" "$@"
  else
    rsync -avz -e "$RSYNC_TUNNEL" "$@"
  fi
}

do_ssh() {
  if [[ ${#SSH_PASS_PRE[@]} -gt 0 ]]; then
    "${SSH_PASS_PRE[@]}" $RSYNC_TUNNEL "$TARGET" "$@"
  else
    $RSYNC_TUNNEL "$TARGET" "$@"
  fi
}

echo "Deploying to ${TARGET} …"
cd "$ROOT"

do_rsync server/whetstone-website/ "${TARGET}:${REMOTE_WEB}/"
do_rsync --exclude node_modules server/whetstone-shared/ "${TARGET}:${REMOTE_SHARED}/"
do_rsync --exclude node_modules server/whetstone-api/ "${TARGET}:${REMOTE_API}/"
do_rsync --exclude node_modules server/whetstone-admin/ "${TARGET}:${REMOTE_ADMIN}/"
do_rsync server/deploy/nginx-projectwhetstone.conf "${TARGET}:/etc/nginx/sites-available/projectwhetstone"
do_rsync server/deploy/generate-web-app-config.py "${TARGET}:/tmp/generate-web-app-config.py"

do_ssh "set -euo pipefail
ln -sf /etc/nginx/sites-available/projectwhetstone /etc/nginx/sites-enabled/projectwhetstone
mkdir -p \"${REMOTE_WEB}/.well-known/acme-challenge\"
chown www-data:www-data \"${REMOTE_WEB}/.well-known/acme-challenge\" 2>/dev/null || true
chown -R www-data:www-data ${REMOTE_WEB}
(cd '${REMOTE_SHARED}' && npm ci --omit=dev)
(cd '${REMOTE_ADMIN}' && npm ci --omit=dev)
(cd '${REMOTE_API}' && npm ci --omit=dev)
chmod +x /tmp/generate-web-app-config.py
/tmp/generate-web-app-config.py '${ENV_REMOTE}' '${REMOTE_WEB}/app/config.json'
chown www-data:www-data '${REMOTE_WEB}/app/config.json' 2>/dev/null || true
nginx -t
systemctl reload nginx
systemctl restart whetstone-admin
systemctl restart whetstone-api || true
systemctl restart whetstone-proxy || true
sleep 1
(curl -sfS http://127.0.0.1:3002/admin/api/health && echo '') || echo 'WARN: localhost:3002 admin health unreachable (service may still be booting).'
(curl -sfS http://127.0.0.1:3001/whetstone/api/health && echo '') || echo 'WARN: localhost:3001 whetstone-api health unreachable.'
grep -q storageWrap '${REMOTE_WEB}/admin/index.html' && echo 'VPS: admin/index.html includes storageWrap.'
"

echo "Done."
