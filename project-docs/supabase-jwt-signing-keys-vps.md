# Supabase JWT signing keys + VPS conversation API

## Why 401 persisted

Supabase can rotate from **legacy HS256** (single shared **JWT Secret**) to **asymmetric signing keys** (e.g. ECC **ES256**). User **access tokens** are then signed with the new key. Our Node verifier used **only** `jsonwebtoken` + **`SUPABASE_JWT_SECRET`** + **`HS256`**, so **`jwt.verify` always failed** for new tokens → **`401 Unauthorized`**.

This is unrelated to iOS refresh logic or Postgres linkage.

## Fix (implemented)

[`server/whetstone-api/index.mjs`](../server/whetstone-api/index.mjs):

1. **`SUPABASE_URL`** — e.g. `https://eqymsphqkskaleprmlds.supabase.co` (no trailing slash).
2. Fetch JWKS from **`{SUPABASE_URL}/auth/v1/.well-known/jwks.json`** (Supabase docs: [JWT Signing Keys](https://supabase.com/docs/guides/auth/signing-keys)).
3. Verify **`ES256`** / **`RS256`** tokens with **`jose`** (`jwtVerify` + `createRemoteJWKSet`).
4. **`issuer`** enforced as **`{SUPABASE_URL}/auth/v1`** (matches GoTrue `iss` on user JWTs).
5. Keep **`SUPABASE_JWT_SECRET`** path for **`HS256`** tokens until the legacy key is revoked in the dashboard.

Dependency: **`jose`** in [`server/whetstone-api/package.json`](../server/whetstone-api/package.json).

## VPS env (`/etc/whetstone-proxy.env`)

Add:

```bash
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
```

Keep **`SUPABASE_JWT_SECRET`** while Supabase still lists a **Previously used** HS256 key with active tokens.

Then:

```bash
cd /opt/whetstone-api && npm install --omit=dev
systemctl restart whetstone-api
```

Deployed 2026-05-11: **`SUPABASE_URL=https://eqymsphqkskaleprmlds.supabase.co`** appended on the production VPS when missing.

## References

- Supabase: “Verifying a JWT from Supabase” / JWKS discovery  
- PR discussion: asymmetric keys + `kid` in JWT header
