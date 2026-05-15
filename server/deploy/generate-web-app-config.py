#!/usr/bin/env python3
"""Emit /var/www/whetstone-website/app/config.json from /etc/whetstone-proxy.env (no secrets echoed)."""

from __future__ import annotations

import json
import pathlib
import sys


def load_env(path: pathlib.Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.is_file():
        return out
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        k = k.strip()
        v = v.strip()
        if len(v) >= 2 and ((v[0] == v[-1] == '"') or (v[0] == v[-1] == "'")):
            v = v[1:-1]
        out[k] = v
    return out


def main() -> int:
    env_path = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path("/etc/whetstone-proxy.env")
    out_path = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else pathlib.Path("/var/www/whetstone-website/app/config.json")
    env = load_env(env_path)
    anon = env.get("SUPABASE_ANON_KEY", "") or env.get("NEXT_PUBLIC_SUPABASE_ANON_KEY", "")
    app_tok = env.get("WHETSTONE_APP_TOKEN", "") or env.get("AI_APP_TOKEN", "")
    cfg = {
        "supabaseUrl": env.get("SUPABASE_URL", ""),
        "supabaseAnonKey": anon,
        "aiAppToken": app_tok,
        "aiModel": env.get("AI_MODEL", "meta-llama/llama-4-scout-17b-16e-instruct"),
        "adminOwnerEmailLower": env.get("ADMIN_EMAIL", "").strip().lower(),
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
