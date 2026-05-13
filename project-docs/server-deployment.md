# Whetstone server proxy + TLS

This repo includes a **tiny Node proxy** (`server/whetstone-proxy/`) that forwards OpenAI-compatible chat requests to Groq.

## Standalone app (no Mac at runtime)

A built **Whetstone** binary does **not** depend on your Mac after install. The phone reads **`AI_BASE_URL`** from **`Whetstone/Info.plist`** and POSTs chat traffic to **your VPS over HTTPS**. The VPS holds **`GROQ_API_KEY`** and attaches it when calling Groq. Your Mac is only used to **compile and upload** the app — not to serve AI traffic.

Your **Groq API key stays on the VPS**, not in the iPhone binary.

The iOS target calls the proxy via **`Whetstone/Info.plist`** (`AI_BASE_URL`; merged at build time):

`https://149-28-38-55.sslip.io/v1/chat/completions`

The hostname **`149-28-38-55.sslip.io`** resolves to **`149.28.38.55`** ([sslip.io](https://sslip.io)). If your VPS IP changes, update **`AI_BASE_URL`** in **`Whetstone/Info.plist`** (and TLS hostname).

### VPS checklist (nothing else required from your Mac at runtime)

| Requirement | Purpose |
|-------------|---------|
| **`GROQ_API_KEY`** in **`/etc/whetstone-proxy.env`** | Proxy can call Groq |
| **`systemctl enable --now whetstone-proxy`** | Proxy listens on localhost |
| **nginx** + TLS hostname matching **`AI_BASE_URL`** | iPhone ATS + routing to proxy |
| **UFW** allows **80/tcp** and **443/tcp** (if UFW enabled) | Let’s Encrypt + HTTPS |

Optional hardening: **`WHETSTONE_APP_TOKEN`** on the server + same value in app **`AI_APP_TOKEN`** (see §5).

---

## 1. Get SSH working

Automated SSH from this environment failed with **Permission denied** (common causes: wrong password, root login disabled, password auth off).

1. Use your host’s **web console** (e.g. Vultr / Linode) if SSH fails.
2. Prefer **SSH keys** and disable password login after setup.
3. **Rotate** any password that was stored in plaintext (e.g. `project-docs/server login info.rtf`).

---

## 2. Upload `server/` to the VPS

From your Mac (replace user/host):

```bash
cd "/path/to/Whetstone"
scp -r server root@149.28.38.55:/root/whetstone-server
```

Or use `rsync`.

---

## 3. Run the installer (on the VPS)

```bash
ssh root@149.28.38.55
cd /root/whetstone-server
sudo bash deploy/install-on-server.sh
```

Then edit secrets:

```bash
nano /etc/whetstone-proxy.env
# Set:
#   GROQ_API_KEY=gsk_...
#   DATABASE_URL=postgres://...
#   SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co   # JWKS for user JWTs (ES256/RSA) — required after JWT signing-key migration
#   SUPABASE_JWT_SECRET=...    # Legacy HS256 secret — optional once all tokens are asymmetric
# Optional shared secret (must match Xcode AI_APP_TOKEN):
#   WHETSTONE_APP_TOKEN=some-long-random-string
systemctl restart whetstone-proxy whetstone-api
```

---

## 4. HTTPS with Let’s Encrypt

iOS needs **HTTPS**. After HTTP works:

```bash
certbot --nginx -d 149-28-38-55.sslip.io --redirect --agree-tos -m YOUR_EMAIL
```

Verify:

```bash
curl -sS https://149-28-38-55.sslip.io/health
```

---

## 5. Optional app token

1. Add `WHETSTONE_APP_TOKEN` on the server env file.
2. Set **`AI_APP_TOKEN`** in **`Whetstone/Info.plist`** (same value as on the server).
3. The app sends `Authorization: Bearer <token>`; the proxy checks it before calling Groq.

---

## Troubleshooting

| Symptom | Check |
|--------|--------|
| `500` **`GROQ_API_KEY missing`** | `/etc/whetstone-proxy.env` must set `GROQ_API_KEY=…`; then `systemctl restart whetstone-proxy`. Confirm key length: `awk -F= '/^GROQ_API_KEY=/{print length($2)}' /etc/whetstone-proxy.env` (must not print `0`). |
| `502` / upstream error | `journalctl -u whetstone-proxy -f`, Groq key valid |
| iOS ATS errors | Certbot completed; URL must be `https://` |
| 401 from proxy | Token mismatch vs `WHETSTONE_APP_TOKEN` |
| 401 from **`whetstone-api`** / conversation sync | Ensure **`SUPABASE_URL`** is set to `https://<ref>.supabase.co` (JWKS verification for ES256 user tokens). Keep **`SUPABASE_JWT_SECRET`** only for legacy HS256 tokens until revoked in Supabase. See `project-docs/supabase-jwt-signing-keys-vps.md`. |

Proxy source: `server/whetstone-proxy/index.mjs` (no npm runtime deps; Node 18+).
