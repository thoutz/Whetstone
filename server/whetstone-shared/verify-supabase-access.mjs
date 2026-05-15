/**
 * Shared Supabase user access-token verification for Whetstone services.
 *
 * Env:
 *   SUPABASE_URL — required for ES256/RS256 (JWKS)
 *   SUPABASE_JWT_SECRET — optional HS256 legacy
 */
import { URL } from "node:url";
import * as jose from "jose";
import jwt from "jsonwebtoken";

/**
 * @param {{ SUPABASE_URL: string; SUPABASE_JWT_SECRET?: string }} env
 * @param {string|undefined} authHeader Authorization: Bearer ...
 * @returns {Promise<{ sub: string; email: string|null }>}
 */
export async function verifySupabaseAccessToken(env, authHeader) {
  const SUPABASE_URL = (env.SUPABASE_URL || "").trim().replace(/\/+$/, "");
  const JWT_SECRET = env.SUPABASE_JWT_SECRET || "";

  const m = /^Bearer\s+(.+)$/i.exec(authHeader || "");
  if (!m) throw Object.assign(new Error("missing token"), { code: "auth" });
  const token = m[1].trim();

  const decodedComplete = jwt.decode(token, { complete: true });
  const alg = decodedComplete?.header?.alg;

  const issuer = SUPABASE_URL ? `${SUPABASE_URL}/auth/v1` : null;

  const jwks = SUPABASE_URL
    ? jose.createRemoteJWKSet(new URL(`${SUPABASE_URL}/auth/v1/.well-known/jwks.json`))
    : null;

  /** @type {import('jose').JWTPayload} */
  let payload;

  if (alg === "HS256" && JWT_SECRET) {
    payload = jwt.verify(token, JWT_SECRET, {
      algorithms: ["HS256"],
      clockTolerance: 30,
    });
  } else if ((alg === "ES256" || alg === "RS256") && jwks && issuer) {
    try {
      const v = await jose.jwtVerify(token, jwks, {
        issuer,
        clockTolerance: "30s",
      });
      payload = v.payload;
    } catch (e) {
      throw Object.assign(new Error(String(e?.message || e)), { code: "auth" });
    }
  } else if (JWT_SECRET) {
    try {
      payload = jwt.verify(token, JWT_SECRET, {
        algorithms: ["HS256"],
        clockTolerance: 30,
      });
    } catch {
      throw Object.assign(
        new Error(
          alg === "ES256" || alg === "RS256"
            ? "Asymmetric JWT: set SUPABASE_URL on the server for JWKS verification"
            : `Unsupported JWT alg ${alg || "?"} — set SUPABASE_JWT_SECRET (HS256) and/or SUPABASE_URL (JWKS)`
        ),
        { code: "auth" }
      );
    }
  } else {
    throw Object.assign(
      new Error(
        alg === "ES256" || alg === "RS256"
          ? "Asymmetric JWT: set SUPABASE_URL on the server for JWKS verification"
          : `Unsupported JWT alg ${alg || "?"} — set SUPABASE_JWT_SECRET (HS256) and/or SUPABASE_URL (JWKS)`
      ),
      { code: "auth" }
    );
  }

  const sub = payload?.sub;
  if (!sub || typeof sub !== "string") throw Object.assign(new Error("invalid sub"), { code: "auth" });

  const emailRaw = payload.email;
  const email =
    typeof emailRaw === "string" && emailRaw.trim()
      ? emailRaw.trim().toLowerCase()
      : typeof payload?.user_metadata?.email === "string"
        ? String(payload.user_metadata.email).trim().toLowerCase()
        : null;

  return { sub, email };
}
