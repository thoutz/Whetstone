#!/usr/bin/env bash
# On the VPS (as root), after uploading the whole `server/` directory from this repo:
#   sudo bash deploy/install-on-server.sh
# Optional Postgres + schema:
#   WHETSTONE_SETUP_POSTGRES=1 WHETSTONE_PG_PASSWORD='...' sudo -E bash deploy/install-on-server.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET=/opt/whetstone-proxy

if [[ "$(id -u)" != "0" ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl ca-certificates nginx certbot python3-certbot-nginx

# Let's Encrypt HTTP-01 and HTTPS must reach nginx from the internet.
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
  ufw allow 80/tcp comment 'HTTP ACME/nginx' >/dev/null || true
  ufw allow 443/tcp comment 'HTTPS' >/dev/null || true
fi

if ! command -v node >/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y -qq nodejs
fi

mkdir -p "$TARGET"
cp -f "$ROOT/whetstone-proxy/index.mjs" "$ROOT/whetstone-proxy/package.json" "$TARGET/"
cd "$TARGET"
npm install --omit=dev

API_TARGET=/opt/whetstone-api
mkdir -p "$API_TARGET"
cp -f "$ROOT/whetstone-api/index.mjs" "$ROOT/whetstone-api/package.json" "$API_TARGET/"
(cd "$API_TARGET" && npm install --omit=dev)
install -m 644 "$ROOT/deploy/whetstone-api.service" /etc/systemd/system/whetstone-api.service
chown -R www-data:www-data "$API_TARGET"

if [[ "${WHETSTONE_SETUP_POSTGRES:-}" == "1" ]]; then
  echo "Installing PostgreSQL + Whetstone schema (WHETSTONE_PG_PASSWORD recommended)..."
  apt-get install -y -qq postgresql postgresql-contrib
  bash "$ROOT/deploy/postgres-whetstone.sh"
fi

if [[ ! -f /etc/whetstone-proxy.env ]]; then
  umask 077
  cat >/etc/whetstone-proxy.env << 'EOF'
GROQ_API_KEY=
PORT=8787
BIND=127.0.0.1
DATABASE_URL=
SUPABASE_URL=
SUPABASE_JWT_SECRET=
WHETSTONE_API_PORT=3001
WHETSTONE_API_BIND=127.0.0.1
EOF
  umask 022
  echo "Created /etc/whetstone-proxy.env — add your Groq key, DATABASE_URL, SUPABASE_URL (JWKS), and SUPABASE_JWT_SECRET (legacy HS256)."
fi

chgrp www-data /etc/whetstone-proxy.env
chmod 640 /etc/whetstone-proxy.env

install -m 644 "$ROOT/deploy/whetstone-proxy.service" /etc/systemd/system/whetstone-proxy.service
chown -R www-data:www-data "$TARGET"
systemctl daemon-reload
systemctl enable --now whetstone-proxy
systemctl enable --now whetstone-api

DOMAIN="${WHETSTONE_SSL_DOMAIN:-149-28-38-55.sslip.io}"
install -m 644 "$ROOT/deploy/nginx-whetstone.conf" "/etc/nginx/sites-available/whetstone"
sed -i "s|149-28-38-55.sslip.io|${DOMAIN}|g" /etc/nginx/sites-available/whetstone
ln -sf /etc/nginx/sites-available/whetstone /etc/nginx/sites-enabled/whetstone
nginx -t
systemctl reload nginx

echo ""
echo "=== TLS (HTTPS required for iPhone) ==="
echo "certbot --nginx -d $DOMAIN --redirect --agree-tos --register-unsafely-without-email --non-interactive"
echo "(or use -m your@email instead of --register-unsafely-without-email)"
echo ""
proxy_ok=false
for _ in 1 2 3 4 5 6; do
  if curl -fsS "http://127.0.0.1:8787/health" 2>/dev/null; then
    echo " (proxy OK)"
    proxy_ok=true
    break
  fi
  sleep 1
done
if [[ "$proxy_ok" != true ]]; then
  echo "proxy failed — systemd journal: journalctl -u whetstone-proxy -n 50"
fi

api_ok=false
for _ in 1 2 3 4 5 6; do
  if curl -fsS "http://127.0.0.1:3001/whetstone/api/health" 2>/dev/null | grep -q whetstone-api; then
    echo " (whetstone-api OK)"
    api_ok=true
    break
  fi
  sleep 1
done
if [[ "$api_ok" != true ]]; then
  echo "whetstone-api not healthy — journalctl -u whetstone-api -n 50"
fi

curl -fsS "http://${DOMAIN}/health" && echo " (via nginx)" || echo "nginx/public DNS not ready yet"
