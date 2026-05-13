-- Whetstone conversation sync (runs on VPS Postgres).
-- Loaded by deploy/postgres-whetstone.sh or manually:
--   sudo -u postgres psql -v ON_ERROR_STOP=1 -d whetstone_conv -f schema-conversations.sql
--
-- Ownership: conversations.user_id is the signed-in Supabase Auth user UUID (JWT claim `sub`).
-- No FK to hosted Supabase — the app sends Bearer tokens; whetstone-api verifies via JWKS (`SUPABASE_URL`) for ES256/RS256 and/or legacy `SUPABASE_JWT_SECRET` for HS256.

CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL,
    title TEXT NOT NULL DEFAULT 'New conversation',
    total_tokens_used INTEGER NOT NULL DEFAULT 0,
    api_history JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_conversations_user_updated
    ON conversations (user_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    role TEXT NOT NULL,
    content TEXT,
    payload JSONB,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_messages_conv_sort ON messages (conversation_id, sort_order ASC);
