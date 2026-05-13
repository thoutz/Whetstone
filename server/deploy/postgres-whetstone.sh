#!/usr/bin/env bash
# Initializes Postgres DB + role for Whetstone API (run on VPS as root).
# Usage: WHETSTONE_PG_PASSWORD='your-secret' sudo -E bash deploy/postgres-whetstone.sh
# If WHETSTONE_PG_PASSWORD is unset, a random one is printed — add it to /etc/whetstone-proxy.env as DATABASE_URL.
set -euo pipefail

if [[ "$(id -u)" != "0" ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB_NAME=whetstone_conv
DB_USER=whetstone

if [[ -z "${WHETSTONE_PG_PASSWORD:-}" ]]; then
  WHETSTONE_PG_PASSWORD="$(openssl rand -base64 32 | tr -d '/+=\n' | head -c 28)"
  echo "Generated password (persist in /etc/whetstone-proxy.env): $WHETSTONE_PG_PASSWORD"
fi

ESC_PASS="${WHETSTONE_PG_PASSWORD//\'/\'\'}"

sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB_USER') THEN
    CREATE ROLE $DB_USER LOGIN PASSWORD '$ESC_PASS';
  ELSE
    ALTER ROLE $DB_USER PASSWORD '$ESC_PASS';
  END IF;
END
\$\$;

SELECT 'CREATE DATABASE $DB_NAME OWNER $DB_USER TEMPLATE template0 ENCODING ''UTF8'''
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME')\gexec
SQL

sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$DB_NAME" < <( cat "$ROOT/deploy/schema-conversations.sql" )
sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$DB_NAME" -c \
  "GRANT ALL ON SCHEMA public TO $DB_USER; GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER; GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER; ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;"

echo ""
echo "Add to /etc/whetstone-proxy.env:"
echo "DATABASE_URL=postgres://$DB_USER:$WHETSTONE_PG_PASSWORD@127.0.0.1:5432/$DB_NAME"
echo "SUPABASE_JWT_SECRET=<Supabase Dashboard → Settings → API → JWT Secret>"
echo ""
