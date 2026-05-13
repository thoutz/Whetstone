#!/usr/bin/env bash
# Run on VPS as root after /root/whetstone-server-deploy.tgz is extracted (server/ at /root/server).
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq postgresql postgresql-contrib
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y -qq nodejs
fi

PGPASS="$(openssl rand -hex 16)"
export WHETSTONE_PG_PASSWORD="$PGPASS"
bash /root/server/deploy/postgres-whetstone.sh

DATABASE_URL="postgres://whetstone:${PGPASS}@127.0.0.1:5432/whetstone_conv"
mkdir -p /opt/whetstone-api
cp -f /root/server/whetstone-api/index.mjs /root/server/whetstone-api/package.json /opt/whetstone-api/
(cd /opt/whetstone-api && npm install --omit=dev)

chown -R www-data:www-data /opt/whetstone-api

install -m 644 /root/server/deploy/whetstone-api.service /etc/systemd/system/whetstone-api.service

ENV=/etc/whetstone-proxy.env
touch "$ENV"
append_if_missing() {
  local k="$1"
  local v="$2"
  if ! grep -q "^${k}=" "$ENV" 2>/dev/null; then
    echo "${k}=${v}" >>"$ENV"
  fi
}

append_if_missing DATABASE_URL "$DATABASE_URL"
append_if_missing WHETSTONE_API_PORT 3001
append_if_missing WHETSTONE_API_BIND 127.0.0.1
append_if_missing SUPABASE_JWT_SECRET ""

chgrp www-data "$ENV"
chmod 640 "$ENV"

cat >/etc/nginx/sites-available/whetstone <<'NGINX_EOF'
# Whetstone + Certbot-managed TLS

server {
    server_name 149-28-38-55.sslip.io;

    client_max_body_size 50m;

    location ^~ /whetstone/api/ {
        proxy_pass http://127.0.0.1:3001/whetstone/api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 50m;
    }

    location / {
        proxy_pass http://127.0.0.1:8787;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
    }

    listen 443 ssl; # managed by Certbot
    listen [::]:443 ssl ipv6only=on; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/149-28-38-55.sslip.io/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/149-28-38-55.sslip.io/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot

}


server {
    if ($host = 149-28-38-55.sslip.io) {
        return 301 https://$host$request_uri;
    } # managed by Certbot


    listen 80;
    listen [::]:80;
    server_name 149-28-38-55.sslip.io;
    return 404; # managed by Certbot


}
NGINX_EOF

nginx -t
systemctl daemon-reload
systemctl enable --now whetstone-api
systemctl reload nginx

sleep 2
curl -fsS http://127.0.0.1:3001/whetstone/api/health || true

echo ""
echo "=== Postgres DATABASE_URL (also in /etc/whetstone-proxy.env if newly appended):"
echo "$DATABASE_URL"
echo "=== REQUIRED: Set SUPABASE_JWT_SECRET in /etc/whetstone-proxy.env (Supabase Dashboard → Settings → API → JWT Secret), then: systemctl restart whetstone-api"
