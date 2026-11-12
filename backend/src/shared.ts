/**
 * Primitives shared by the account API (`index.ts`) and the admin API (`admin.ts`).
 */

export interface Env {
  DB: D1Database;
  JWT_SECRET: string;
  /** Set with `wrangler secret put ADMIN_PASSWORD`. Unset disables the admin console. */
  ADMIN_PASSWORD?: string;
}

export const MIN_PASSWORD_LENGTH = 6;

export function json(data: any, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Device-Name, X-Device-Model',
    },
  });
}

export async function sha256(text: string): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text)));
}

// Helpers crypto natifs Web Crypto (compatibles Cloudflare Workers sans dépendance lourde)
export async function hashPassword(password: string): Promise<string> {
  return Array.from(await sha256(password + 'stremiotv_salt'))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

async function hmacKey(secret: string, usage: 'sign' | 'verify'): Promise<CryptoKey> {
  return crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, [usage]);
}

/** Signs `payload` as `base64(json).base64(hmac)`; the caller sets `exp` (seconds). */
export async function signToken(payload: object, secret: string): Promise<string> {
  const str = btoa(JSON.stringify(payload));
  const signature = await crypto.subtle.sign('HMAC', await hmacKey(secret, 'sign'), new TextEncoder().encode(str));
  return `${str}.${btoa(String.fromCharCode(...new Uint8Array(signature)))}`;
}

/** Returns the payload of a correctly signed, unexpired token, else null. */
export async function readToken(token: string, secret: string): Promise<any | null> {
  try {
    const [payloadStr, sigStr] = token.split('.');
    if (!payloadStr || !sigStr) return null;
    const sigBytes = Uint8Array.from(atob(sigStr), (c) => c.charCodeAt(0));
    const valid = await crypto.subtle.verify('HMAC', await hmacKey(secret, 'verify'), sigBytes, new TextEncoder().encode(payloadStr));
    if (!valid) return null;
    const payload = JSON.parse(atob(payloadStr));
    if (payload.exp < Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch {
    return null;
  }
}

export type LogePlan = 'free' | 'pro' | 'ultra';

export interface PlanLimits {
  maxProfiles: number;
  maxAddons: number;
  maxTVSessions: number;
  maxBrowserSessions: number;
  cloudSync: boolean;
  canRenameDevices: boolean;
}

export function limitsFor(plan: LogePlan): PlanLimits {
  switch (plan) {
    case 'pro':
      return { maxProfiles: 3, maxAddons: 5, maxTVSessions: 2, maxBrowserSessions: 1, cloudSync: true, canRenameDevices: true };
    case 'ultra':
      return { maxProfiles: 6, maxAddons: 20, maxTVSessions: 4, maxBrowserSessions: 2, cloudSync: true, canRenameDevices: true };
    default:
      return { maxProfiles: 1, maxAddons: 1, maxTVSessions: 1, maxBrowserSessions: 1, cloudSync: false, canRenameDevices: false };
  }
}

export function parsePlan(value: unknown): LogePlan {
  return value === 'pro' || value === 'ultra' ? value : 'free';
}

/** The stored plan falls back to Free once its expiry has passed. */
export function effectivePlan(plan: unknown, expiresAtMs: unknown, now = Date.now()): LogePlan {
  const expired = typeof expiresAtMs === 'number' && expiresAtMs > 0 && expiresAtMs < now;
  return expired ? 'free' : parsePlan(plan);
}
