# HTTPS / firewall fix — Groq proxy VPS (May 2026)

## Goal

Make the Whetstone Groq proxy reachable over **HTTPS** from the iPhone (ATS) and document what blocked Let’s Encrypt.

## What was wrong

1. **`install-on-server.sh` health check raced systemd** — `curl http://127.0.0.1:8787/health` sometimes ran before Node finished binding; the service was fine afterward.
2. **UFW allowed only SSH (22)** — ports **80** and **443** were denied, so Let’s Encrypt HTTP-01 validation timed out (`connection` error from the CA).
3. **Certbot had not completed** until 80/443 were open; afterwards TLS deployed successfully.

## What we did on the server

- Opened firewall (UFW): `ufw allow 80/tcp`, `ufw allow 443/tcp`.
- Ran:

  ```bash
  certbot --nginx -d 149-28-38-55.sslip.io --redirect --agree-tos \
    --register-unsafely-without-email --non-interactive
  ```

- Verified from a laptop:

  ```bash
  curl -sS https://149-28-38-55.sslip.io/health
  # {"ok":true,"service":"whetstone-proxy"}
  ```

## Repo changes

- **`server/deploy/install-on-server.sh`**
  - If UFW is **active**, automatically allow **80/tcp** and **443/tcp** before TLS instructions.
  - Retry **localhost** `/health` up to ~6 seconds to avoid the race false negative.
  - Certbot hint updated to include `--register-unsafely-without-email` for unattended runs.

## Still required for chat completions

- **`/etc/whetstone-proxy.env`** must contain a real **`GROQ_API_KEY`**, then:

  ```bash
  systemctl restart whetstone-proxy
  ```

  `/health` does **not** need the key; Groq calls do.

## Optional hardening

- Rotate the root password if it lives in repo docs; prefer **SSH keys** and disable password auth once keys work.
