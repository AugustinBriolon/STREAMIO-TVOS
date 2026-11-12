/**
 * Cloudflare Worker Backend for Loge
 * Handles Authentication, Device Flow Pairing (QR Code), and Multi-Device Cloud Sync.
 */

import { renderWebPortal } from './pages/web-portal.ts';
import { renderAdminPortal } from './pages/admin-portal.ts';
import { privacyPolicyHTML, supportHTML } from './pages/legal.ts';
import { handleAdminApi } from './admin.ts';
import {
  json,
  hashPassword,
  signToken,
  readToken,
  limitsFor,
  effectivePlan,
  inferSessionKind,
  MIN_PASSWORD_LENGTH,
} from './shared.ts';
import type { Env, LogePlan, PlanLimits, SessionKind } from './shared.ts';

export type { Env } from './shared.ts';

async function generateToken(accountId: string, secret: string, sessionId: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  return signToken({ sub: accountId, sid: sessionId, iat: now, exp: now + 60 * 60 * 24 * 365 }, secret);
}

interface TokenClaims {
  accountId: string;
  /** Null for tokens issued before device sessions existed (ADR 0022): they stay valid until they expire. */
  sessionId: string | null;
}

async function verifyToken(token: string, secret: string): Promise<TokenClaims | null> {
  const payload = await readToken(token, secret);
  // Admin tokens carry a role and no account: they must never pass as a sid-less legacy account token.
  if (!payload || payload.role || typeof payload.sub !== 'string') return null;
  return { accountId: payload.sub, sessionId: payload.sid ?? null };
}

/** Writing last-seen on every request would cost a D1 write per call; once every few minutes is enough for a device list. */
const LAST_SEEN_RESOLUTION_MS = 5 * 60 * 1000;

/** A valid signature is not enough: the token's device session must not have been revoked. */
async function authenticate(token: string, env: Env): Promise<TokenClaims | null> {
  const claims = await verifyToken(token, env.JWT_SECRET);
  if (!claims || !claims.sessionId) return claims;
  const session: any = await env.DB.prepare(
    'SELECT revoked_at_ms, last_seen_at_ms FROM sessions WHERE id = ? AND account_id = ?'
  ).bind(claims.sessionId, claims.accountId).first();
  if (!session || session.revoked_at_ms != null) return null;
  const now = Date.now();
  if (now - (session.last_seen_at_ms || 0) > LAST_SEEN_RESOLUTION_MS) {
    await env.DB.prepare('UPDATE sessions SET last_seen_at_ms = ? WHERE id = ?').bind(now, claims.sessionId).run();
  }
  return claims;
}

function cleanLabel(value: unknown, fallback: string): string {
  const text = typeof value === 'string' ? value.trim().slice(0, 60) : '';
  return text || fallback;
}

function rankPlan(plan: LogePlan): number {
  switch (plan) {
    case 'ultra': return 2;
    case 'pro': return 1;
    default: return 0;
  }
}

function planForProductId(productId: string): LogePlan | null {
  switch (productId) {
    case 'loge.pro.monthly':
    case 'loge.pro.yearly':
      return 'pro';
    case 'loge.ultra.monthly':
    case 'loge.ultra.yearly':
    case 'loge.ultra.lifetime':
      return 'ultra';
    default:
      return null;
  }
}

/** shortcut: decode JWS payload only — Apple already verified on device; upgrade to App Store Server API sig check when ASN keys are configured. */
function decodeAppleTransactionJWS(jws: string): any {
  const parts = jws.split('.');
  if (parts.length < 2) throw new Error('jws');
  let payload = parts[1].replace(/-/g, '+').replace(/_/g, '/');
  const pad = (4 - (payload.length % 4)) % 4;
  if (pad) payload += '='.repeat(pad);
  const json = atob(payload);
  return JSON.parse(json);
}

function resolveSessionKind(request: Request, explicit?: unknown): SessionKind {
  const fromBody = typeof explicit === 'string' ? explicit.toLowerCase() : '';
  if (fromBody === 'tv' || fromBody === 'browser') return fromBody;
  const header = (request.headers.get('X-Client-Kind') || '').trim().toLowerCase();
  if (header === 'tv' || header === 'browser') return header;
  const ua = (request.headers.get('User-Agent') || '').toLowerCase();
  if (ua.includes('apple tv') || ua.includes('appletv') || ua.includes('cfnetwork')) return 'tv';
  return 'browser';
}

/** Web uses lowercase UUIDs; tvOS `uuidString` is uppercase. D1 UNIQUE is case-sensitive → duplicates. */
function normalizeProfileId(id: unknown): string | null {
  if (typeof id !== 'string') return null;
  const trimmed = id.trim();
  if (!/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(trimmed)) {
    return null;
  }
  return trimmed.toLowerCase();
}

/** Prefer the lowercase row when a legacy uppercase twin still exists. */
function dedupeProfilesById(rows: any[]): any[] {
  const byId = new Map<string, any>();
  for (const row of rows) {
    const id = normalizeProfileId(row?.id);
    if (!id) continue;
    const normalized = { ...row, id };
    const prev = byId.get(id);
    if (!prev || String(row.id) === id) byId.set(id, normalized);
  }
  return Array.from(byId.values());
}

/** Same contract as tvOS AddonStore.cleanURL — strip /manifest.json so D1 UNIQUE cannot be bypassed. */
function normalizeAddonUrl(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  let base = raw.trim();
  if (base.toLowerCase().startsWith('stremio://')) {
    base = 'https://' + base.slice('stremio://'.length);
  }
  while (base.endsWith('/')) base = base.slice(0, -1);
  if (base.toLowerCase().endsWith('/manifest.json')) {
    base = base.slice(0, -'/manifest.json'.length);
  }
  while (base.endsWith('/')) base = base.slice(0, -1);
  if (!/^https?:\/\//i.test(base)) return null;
  try {
    const u = new URL(base);
    if (!u.host) return null;
  } catch {
    return null;
  }
  return base;
}

/** Collapse /manifest.json twins and rewrite rows to the canonical base URL. */
async function canonicalizeAddons(env: Env, accountId: string): Promise<string[]> {
  const rows = await env.DB.prepare(
    'SELECT manifest_url FROM addons WHERE account_id = ? ORDER BY installed_at ASC'
  ).bind(accountId).all();
  const canonical: string[] = [];
  const seen = new Set<string>();
  for (const row of rows.results as any[]) {
    const raw = String(row.manifest_url || '');
    const norm = normalizeAddonUrl(raw);
    if (!norm) {
      await env.DB.prepare(
        'DELETE FROM addons WHERE account_id = ? AND manifest_url = ?'
      ).bind(accountId, raw).run();
      continue;
    }
    if (seen.has(norm)) {
      await env.DB.prepare(
        'DELETE FROM addons WHERE account_id = ? AND manifest_url = ?'
      ).bind(accountId, raw).run();
      continue;
    }
    seen.add(norm);
    if (raw !== norm) {
      await env.DB.prepare(
        'DELETE FROM addons WHERE account_id = ? AND manifest_url = ?'
      ).bind(accountId, raw).run();
      await env.DB.prepare(
        `INSERT INTO addons (account_id, manifest_url, installed_at)
         VALUES (?, ?, CURRENT_TIMESTAMP)
         ON CONFLICT(account_id, manifest_url) DO NOTHING`
      ).bind(accountId, norm).run();
    }
    canonical.push(norm);
  }
  return canonical;
}

async function accountPlan(env: Env, accountId: string): Promise<{ plan: LogePlan; limits: PlanLimits; expiresAtMs: number | null }> {
  const row: any = await env.DB.prepare(
    'SELECT plan, plan_expires_at_ms FROM accounts WHERE id = ?'
  ).bind(accountId).first();
  const expiresAtMs = typeof row?.plan_expires_at_ms === 'number' ? row.plan_expires_at_ms : null;
  const plan = effectivePlan(row?.plan, expiresAtMs);
  return { plan, limits: limitsFor(plan), expiresAtMs };
}

/** Opens a device session and returns a token bound to it. Kicks oldest sessions in the same kind pool when over cap. */
async function openSession(
  env: Env,
  accountId: string,
  deviceName: unknown,
  deviceModel: unknown,
  kind: SessionKind = 'browser'
): Promise<{ token: string; sessionId: string }> {
  const { limits } = await accountPlan(env, accountId);
  const max = kind === 'tv' ? limits.maxTVSessions : limits.maxBrowserSessions;
  const active = await env.DB.prepare(
    `SELECT id FROM sessions
     WHERE account_id = ? AND revoked_at_ms IS NULL AND IFNULL(device_kind, 'tv') = ?
     ORDER BY last_seen_at_ms ASC`
  ).bind(accountId, kind).all();
  const overflow = (active.results?.length || 0) + 1 - max;
  if (overflow > 0) {
    const now = Date.now();
    for (let i = 0; i < overflow; i++) {
      const id = (active.results[i] as any)?.id;
      if (!id) break;
      await env.DB.prepare(
        'UPDATE sessions SET revoked_at_ms = ? WHERE id = ? AND account_id = ? AND revoked_at_ms IS NULL'
      ).bind(now, id, accountId).run();
    }
  }

  const sessionId = crypto.randomUUID();
  const now = Date.now();
  const fallbackName = kind === 'tv' ? 'Apple TV' : 'Navigateur web';
  await env.DB.prepare(
    `INSERT INTO sessions (id, account_id, device_name, device_model, device_kind, created_at_ms, last_seen_at_ms)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  ).bind(sessionId, accountId, cleanLabel(deviceName, fallbackName), cleanLabel(deviceModel, ''), kind, now, now).run();
  return { sessionId, token: await generateToken(accountId, env.JWT_SECRET, sessionId) };
}

async function issueToken(
  env: Env,
  accountId: string,
  deviceName: unknown,
  deviceModel: unknown,
  kind: SessionKind = 'browser'
): Promise<string> {
  return (await openSession(env, accountId, deviceName, deviceModel, kind)).token;
}

/** Prefer the client header; otherwise the last pairing name (Apple TV sends UIDevice.current.name there). */
async function resolveDeviceIdentity(
  env: Env,
  accountId: string,
  request: Request
): Promise<{ name: string; model: string }> {
  const headerName = (request.headers.get('X-Device-Name') || '').trim();
  const headerModel = (request.headers.get('X-Device-Model') || '').trim();
  if (headerName) {
    return { name: cleanLabel(headerName, 'Apple TV'), model: cleanLabel(headerModel, '') };
  }
  const paired: any = await env.DB.prepare(
    `SELECT device_name FROM pairing_codes
     WHERE account_id = ? AND IFNULL(device_name, '') != ''
     ORDER BY expires_at DESC LIMIT 1`
  ).bind(accountId).first();
  if (paired?.device_name) {
    return { name: cleanLabel(paired.device_name, 'Apple TV'), model: '' };
  }
  return { name: 'Apple TV', model: '' };
}

/** Keep the listed name in sync when the device starts sending X-Device-* headers. */
async function refreshSessionIdentity(env: Env, sessionId: string, request: Request): Promise<void> {
  const headerName = (request.headers.get('X-Device-Name') || '').trim();
  if (!headerName) return;
  const name = cleanLabel(headerName, '');
  const model = cleanLabel(request.headers.get('X-Device-Model'), '');
  if (!name) return;
  const kind = resolveSessionKind(request);
  await env.DB.prepare(
    `UPDATE sessions SET
       device_name = ?,
       device_model = CASE WHEN ? != '' THEN ? ELSE device_model END,
       device_kind = ?,
       last_seen_at_ms = ?
     WHERE id = ?`
  ).bind(name, model, model, kind, Date.now(), sessionId).run();
}

/** Pre-ADR-0022 JWTs have no sid: mint a session so the device list is not empty forever. */
async function upgradeLegacySession(
  env: Env,
  session: TokenClaims,
  request: Request
): Promise<{ sessionId: string; token: string } | null> {
  if (session.sessionId) {
    await refreshSessionIdentity(env, session.sessionId, request);
    return null;
  }
  const { name: deviceName, model: deviceModel } = await resolveDeviceIdentity(env, session.accountId, request);

  // Reuse by name so a legacy client that never stores the new token does not spawn a row per request.
  let existing: any = await env.DB.prepare(
    'SELECT id FROM sessions WHERE account_id = ? AND revoked_at_ms IS NULL AND device_name = ? ORDER BY last_seen_at_ms DESC LIMIT 1'
  ).bind(session.accountId, deviceName).first();

  // Claim the placeholder row created before we had a real name.
  if (!existing?.id && deviceName !== 'Appareil') {
    existing = await env.DB.prepare(
      `SELECT id FROM sessions
       WHERE account_id = ? AND revoked_at_ms IS NULL AND device_name = 'Appareil'
       ORDER BY last_seen_at_ms DESC LIMIT 1`
    ).bind(session.accountId).first();
  }

  if (existing?.id) {
    const now = Date.now();
    const kind = resolveSessionKind(request);
    await env.DB.prepare(
      `UPDATE sessions SET
         device_name = ?,
         device_model = CASE WHEN ? != '' THEN ? ELSE device_model END,
         device_kind = ?,
         last_seen_at_ms = ?
       WHERE id = ?`
    ).bind(deviceName, deviceModel, deviceModel, kind, now, existing.id).run();
    return { sessionId: existing.id, token: await generateToken(session.accountId, env.JWT_SECRET, existing.id) };
  }
  return openSession(env, session.accountId, deviceName, deviceModel, resolveSessionKind(request));
}

/** Profile ids deleted on any device or on the web: they must never be recreated by a later push. */
async function deletedProfileIds(env: Env, accountId: string): Promise<Set<string>> {
  const rows = await env.DB.prepare(
    "SELECT entity_id FROM sync_tombstones WHERE account_id = ? AND entity_type = 'profile'"
  ).bind(accountId).all();
  return new Set(
    rows.results
      .map((r: any) => normalizeProfileId(r.entity_id) || String(r.entity_id).toLowerCase())
      .filter(Boolean)
  );
}

async function deleteProfileEverywhere(env: Env, accountId: string, profileId: string, deletedAtMs: number) {
  const pid = normalizeProfileId(profileId) || profileId.toLowerCase();
  await env.DB.batch([
    env.DB.prepare('DELETE FROM profiles WHERE account_id = ? AND lower(id) = ?').bind(accountId, pid),
    env.DB.prepare('DELETE FROM my_list WHERE account_id = ? AND lower(profile_id) = ?').bind(accountId, pid),
    env.DB.prepare('DELETE FROM playback_progress WHERE account_id = ? AND lower(profile_id) = ?').bind(accountId, pid),
    env.DB.prepare(`
      INSERT INTO sync_tombstones (account_id, profile_id, entity_type, entity_id, deleted_at_ms)
      VALUES (?, ?, 'profile', ?, ?)
      ON CONFLICT(account_id, profile_id, entity_type, entity_id) DO UPDATE SET
        deleted_at_ms = MAX(deleted_at_ms, excluded.deleted_at_ms)
    `).bind(accountId, pid, pid, deletedAtMs),
  ]);
}

function htmlPage(body: string): Response {
  return new Response(body, {
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      // Corporate proxies / Safari otherwise keep serving a stale foyer page after deploy.
      'Cache-Control': 'no-store, no-cache, must-revalidate',
      'Pragma': 'no-cache',
      'X-Frame-Options': 'DENY',
      'Referrer-Policy': 'no-referrer',
    },
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Device-Name, X-Device-Model, X-Client-Kind',
        },
      });
    }

    // MARK: - Web Companion Interface (HTML pour iPhone/Mac lors du scan QR)
    if (url.pathname === '/' || url.pathname === '/pair') {
      return htmlPage(renderWebPortal(url.searchParams.get('code') || ''));
    }

    // MARK: - Admin console (HTML) and its API
    if (url.pathname === '/admin') {
      return htmlPage(renderAdminPortal());
    }
    if (url.pathname.startsWith('/api/admin/')) {
      return handleAdminApi(request, env, url);
    }

    if (url.pathname === '/privacy') {
      return new Response(privacyPolicyHTML, {
        headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' },
      });
    }

    if (url.pathname === '/support') {
      return new Response(supportHTML, {
        headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' },
      });
    }

    // Helper auth header
    const authHeader = request.headers.get('Authorization') || '';
    const token = authHeader.replace(/^Bearer\s+/i, '');

    // MARK: - POST /api/auth/register
    if (url.pathname === '/api/auth/register' && request.method === 'POST') {
      const { email, password, deviceName, deviceModel, clientKind } = (await request.json()) as any;
      if (!email || !password || password.length < MIN_PASSWORD_LENGTH) {
        return json({ error: 'Email invalide ou mot de passe trop court (6 car. min).' }, 400);
      }
      const existing = await env.DB.prepare('SELECT id FROM accounts WHERE email = ?').bind(email.toLowerCase()).first();
      if (existing) {
        return json({ error: 'Un compte existe déjà avec cette adresse email.' }, 409);
      }
      const accountId = crypto.randomUUID();
      const pwHash = await hashPassword(password);
      await env.DB.prepare('INSERT INTO accounts (id, email, password_hash) VALUES (?, ?, ?)')
        .bind(accountId, email.toLowerCase(), pwHash)
        .run();

      const kind = resolveSessionKind(request, clientKind);
      const jwt = await issueToken(env, accountId, deviceName, deviceModel, kind);
      return json({ token: jwt, accountId, email: email.toLowerCase() });
    }

    // MARK: - POST /api/auth/login
    if (url.pathname === '/api/auth/login' && request.method === 'POST') {
      const { email, password, deviceName, deviceModel, clientKind } = (await request.json()) as any;
      if (!email || !password) return json({ error: 'Identifiants requis.' }, 400);
      const pwHash = await hashPassword(password);
      const account: any = await env.DB.prepare('SELECT id, email FROM accounts WHERE email = ? AND password_hash = ?')
        .bind(email.toLowerCase(), pwHash)
        .first();
      if (!account) {
        return json({ error: 'Email ou mot de passe incorrect.' }, 401);
      }
      const kind = resolveSessionKind(request, clientKind);
      const jwt = await issueToken(env, account.id, deviceName, deviceModel, kind);
      return json({ token: jwt, accountId: account.id, email: account.email });
    }

    // MARK: - POST /api/device/code (Apple TV demande un code d'appairage)
    if (url.pathname === '/api/device/code' && request.method === 'POST') {
      const body = (await request.json().catch(() => ({}))) as any;
      const deviceName = body.deviceName || 'Apple TV';
      // Short pairing code, e.g. LOGE-4821
      const randomDigits = Math.floor(1000 + Math.random() * 9000);
      const code = `LOGE-${randomDigits}`;
      const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString(); // 10 minutes

      await env.DB.prepare(
        'INSERT INTO pairing_codes (code, status, device_name, expires_at) VALUES (?, ?, ?, ?)'
      )
        .bind(code, 'pending', deviceName, expiresAt)
        .run();

      const verifyUrl = `${url.origin}/pair?code=${code}`;
      return json({ code, verifyUrl, expiresIn: 600 });
    }

    // MARK: - POST /api/device/poll (Apple TV vérifie si le code a été validé)
    if (url.pathname === '/api/device/poll' && request.method === 'POST') {
      const { code, deviceName, deviceModel } = (await request.json()) as any;
      if (!code) return json({ error: 'Code requis' }, 400);

      const entry: any = await env.DB.prepare(
        'SELECT account_id, status, expires_at, device_name FROM pairing_codes WHERE code = ?'
      )
        .bind(code)
        .first();

      if (!entry) return json({ error: 'Code inconnu ou expiré' }, 404);

      if (new Date(entry.expires_at) < new Date()) {
        return json({ status: 'expired' });
      }

      if (entry.status === 'consumed') {
        return json({ status: 'expired' });
      }

      if (entry.status === 'authorized' && entry.account_id) {
        // A code yields one token: replaying the poll must not open a second session.
        const consumed = await env.DB.prepare(
          "UPDATE pairing_codes SET status = 'consumed' WHERE code = ? AND status = 'authorized'"
        ).bind(code).run();
        if (consumed.meta.changes === 0) return json({ status: 'expired' });
        const account: any = await env.DB.prepare('SELECT email FROM accounts WHERE id = ?')
          .bind(entry.account_id)
          .first();
        const jwt = await issueToken(env, entry.account_id, deviceName || entry.device_name, deviceModel, 'tv');
        return json({ status: 'authorized', token: jwt, email: account?.email });
      }

      return json({ status: 'pending' });
    }

    // MARK: - POST /api/device/confirm (Le navigateur du smartphone confirme l'appairage)
    if (url.pathname === '/api/device/confirm' && request.method === 'POST') {
      const session = await authenticate(token, env);
      const accountId = session?.accountId;
      if (!accountId) return json({ error: 'Non authentifié' }, 401);

      const { code } = (await request.json()) as any;
      if (!code) return json({ error: 'Code requis' }, 400);

      const res = await env.DB.prepare(
        'UPDATE pairing_codes SET status = ?, account_id = ? WHERE code = ? AND status = ?'
      )
        .bind('authorized', accountId, code, 'pending')
        .run();

      if (res.meta.changes === 0) {
        return json({ error: 'Code invalide ou déjà utilisé' }, 400);
      }

      return json({ success: true, message: 'Apple TV jumelée avec succès !' });
    }

    // MARK: - GET /api/account (Données du compte connecté pour le web)
    if (url.pathname === '/api/account' && request.method === 'GET') {
      const session = await authenticate(token, env);
      const accountId = session?.accountId;
      if (!accountId || !session) return json({ error: 'Non authentifié' }, 401);

      const upgraded = await upgradeLegacySession(env, session, request);

      const account: any = await env.DB.prepare('SELECT email, nickname, plan, plan_expires_at_ms FROM accounts WHERE id = ?')
        .bind(accountId)
        .first();
      const { plan, limits, expiresAtMs } = await accountPlan(env, accountId);

      const profiles = await env.DB.prepare('SELECT id, name, avatar_json, sort_order FROM profiles WHERE account_id = ? ORDER BY sort_order ASC')
        .bind(accountId)
        .all();

      const addonUrls = await canonicalizeAddons(env, accountId);

      return json({
        email: account?.email || '',
        nickname: account?.nickname || '',
        plan,
        planExpiresAtMs: expiresAtMs,
        limits,
        profiles: dedupeProfilesById(profiles.results as any[]),
        addons: addonUrls,
        ...(upgraded ? { token: upgraded.token } : {}),
      });
    }

    // MARK: - POST /api/account/nickname
    if (url.pathname === '/api/account/nickname' && request.method === 'POST') {
      const session = await authenticate(token, env);
      const accountId = session?.accountId;
      if (!accountId) return json({ error: 'Non authentifié' }, 401);

      const { nickname } = (await request.json().catch(() => ({}))) as any;
      const clean = (nickname || '').trim();

      await env.DB.prepare('UPDATE accounts SET nickname = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?')
        .bind(clean, accountId)
        .run();

      return json({ success: true, nickname: clean });
    }

    // MARK: - POST /api/account/password
    if (url.pathname === '/api/account/password' && request.method === 'POST') {
      const session = await authenticate(token, env);
      const accountId = session?.accountId;
      if (!accountId) return json({ error: 'Non authentifié' }, 401);

      const { currentPassword, newPassword } = (await request.json().catch(() => ({}))) as any;
      if (!currentPassword || !newPassword) {
        return json({ error: 'Veuillez renseigner tous les champs de mot de passe.' }, 400);
      }
      if (newPassword.length < MIN_PASSWORD_LENGTH) {
        return json({ error: 'Le nouveau mot de passe doit comporter au moins 6 caractères.' }, 400);
      }

      const curHash = await hashPassword(currentPassword);
      const account: any = await env.DB.prepare('SELECT id FROM accounts WHERE id = ? AND password_hash = ?')
        .bind(accountId, curHash)
        .first();

      if (!account) {
        return json({ error: 'Le mot de passe actuel est incorrect.' }, 400);
      }

      const newHash = await hashPassword(newPassword);
      await env.DB.prepare('UPDATE accounts SET password_hash = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?')
        .bind(newHash, accountId)
        .run();

      return json({ success: true, message: 'Mot de passe modifié avec succès.' });
    }

    // MARK: - POST /api/account/profile (Créer ou modifier un profil)
    if (url.pathname === '/api/account/profile' && request.method === 'POST') {
      const session = await authenticate(token, env);
      const accountId = session?.accountId;
      if (!accountId) return json({ error: 'Non authentifié' }, 401);

      const { id, name, avatar } = (await request.json().catch(() => ({}))) as any;
      const cleanName = (name || '').trim();
      if (!cleanName) return json({ error: 'Le nom du profil ne peut pas être vide.' }, 400);
      if (cleanName.length > 16) return json({ error: 'Le nom est trop long (16 caractères maximum).' }, 400);

      const profileId = normalizeProfileId(id) || crypto.randomUUID().toLowerCase();
      let avatarJson: string;
      if (avatar && typeof avatar === 'object') {
        avatarJson = JSON.stringify(avatar);
      } else if (id) {
        // Rename-only updates must keep the existing avatar (TV contract).
        const existing: any = await env.DB.prepare(
          'SELECT avatar_json FROM profiles WHERE account_id = ? AND lower(id) = ?'
        ).bind(accountId, profileId).first();
        avatarJson = existing?.avatar_json || JSON.stringify({ color: 'blue', symbol: 'face.smiling' });
      } else {
        avatarJson = JSON.stringify({ color: 'blue', symbol: 'face.smiling' });
      }

      if (!id) {
        const { plan, limits } = await accountPlan(env, accountId);
        const countRes: any = await env.DB.prepare(
          'SELECT COUNT(DISTINCT lower(id)) AS c FROM profiles WHERE account_id = ?'
        ).bind(accountId).first();
        const count = Number(countRes?.c ?? 0);
        if (count >= limits.maxProfiles) {
          return json({
            error: `Nombre maximum de profils atteint (${limits.maxProfiles} en ${plan}).`,
            code: 'plan_limit',
            plan,
            limits,
          }, 403);
        }
      } else {
        // Collapse a legacy uppercase row into the canonical lowercase id before upsert.
        await env.DB.prepare(
          'DELETE FROM profiles WHERE account_id = ? AND lower(id) = ? AND id != ?'
        ).bind(accountId, profileId, profileId).run();
      }

      await env.DB.prepare(`
        INSERT INTO profiles (account_id, id, name, avatar_json, sort_order, updated_at)
        VALUES (?, ?, ?, ?, 0, CURRENT_TIMESTAMP)
        ON CONFLICT(account_id, id) DO UPDATE SET
          name = excluded.name,
          avatar_json = excluded.avatar_json,
          updated_at = CURRENT_TIMESTAMP
      `).bind(accountId, profileId, cleanName, avatarJson).run();

      return json({ success: true, id: profileId, name: cleanName });
    }

    // MARK: - DELETE /api/account/profile
    if (url.pathname === '/api/account/profile' && request.method === 'DELETE') {
      const session = await authenticate(token, env);
      const accountId = session?.accountId;
      if (!accountId) return json({ error: 'Non authentifié' }, 401);

      const { id } = (await request.json().catch(() => ({}))) as any;
      if (!id) return json({ error: 'Identifiant de profil requis.' }, 400);

      const countRes: any = await env.DB.prepare(
        'SELECT COUNT(DISTINCT lower(id)) as c FROM profiles WHERE account_id = ?'
      ).bind(accountId).first();
      if (countRes && Number(countRes.c) <= 1) {
        return json({ error: 'Impossible de supprimer le dernier profil restant.' }, 400);
      }

      await deleteProfileEverywhere(env, accountId, id, Date.now());

      return json({ success: true });
    }

    // MARK: - POST /api/account/addons
    if (url.pathname === '/api/account/addons' && request.method === 'POST') {
      const session = await authenticate(token, env);
      const accountId = session?.accountId;
      if (!accountId) return json({ error: 'Non authentifié' }, 401);

      const { manifestUrl } = (await request.json().catch(() => ({}))) as any;
      const clean = normalizeAddonUrl(manifestUrl);
      if (!clean) {
        return json({ error: 'URL d\'addon invalide (doit commencer par https://).' }, 400);
      }

      const { plan, limits } = await accountPlan(env, accountId);
      const existing = await canonicalizeAddons(env, accountId);
      if (existing.includes(clean)) {
        return json({ success: true, manifestUrl: clean, plan, limits });
      }
      if (existing.length >= limits.maxAddons) {
        return json({
          error: `Nombre maximum d'addons atteint (${limits.maxAddons} en ${plan}).`,
          code: 'plan_limit',
          plan,
          limits,
        }, 403);
      }

      await env.DB.prepare(
        'INSERT INTO addons (account_id, manifest_url, installed_at) VALUES (?, ?, CURRENT_TIMESTAMP) ON CONFLICT DO NOTHING'
      ).bind(accountId, clean).run();

      return json({ success: true, manifestUrl: clean, plan, limits });
    }

    // MARK: - DELETE /api/account/addons
    if (url.pathname === '/api/account/addons' && request.method === 'DELETE') {
      const session = await authenticate(token, env);
      const accountId = session?.accountId;
      if (!accountId) return json({ error: 'Non authentifié' }, 401);

      const { manifestUrl } = (await request.json().catch(() => ({}))) as any;
      const clean = normalizeAddonUrl(manifestUrl) || (typeof manifestUrl === 'string' ? manifestUrl.trim() : '');
      if (!clean) return json({ error: 'URL d\'addon requise.' }, 400);

      // Drop every spelling of the same addon (with/without /manifest.json).
      const rows = await env.DB.prepare(
        'SELECT manifest_url FROM addons WHERE account_id = ?'
      ).bind(accountId).all();
      for (const row of rows.results as any[]) {
        const raw = String(row.manifest_url || '');
        if (raw === clean || normalizeAddonUrl(raw) === clean) {
          await env.DB.prepare(
            'DELETE FROM addons WHERE account_id = ? AND manifest_url = ?'
          ).bind(accountId, raw).run();
        }
      }

      return json({ success: true });
    }

    // MARK: - GET /api/sync/pull (Récupération des données du foyer)
    if (url.pathname === '/api/sync/pull' && request.method === 'GET') {
      const session = await authenticate(token, env);
      const accountId = session?.accountId;
      if (!accountId || !session) return json({ error: 'Non authentifié' }, 401);
      const { plan, limits } = await accountPlan(env, accountId);
      if (!limits.cloudSync) {
        return json({ error: 'La synchronisation cloud est réservée à Pro et Ultra.', code: 'plan_required', plan, limits }, 402);
      }
      const upgraded = await upgradeLegacySession(env, session, request);

      const profiles = await env.DB.prepare('SELECT id, name, avatar_json, sort_order FROM profiles WHERE account_id = ? ORDER BY sort_order ASC')
        .bind(accountId)
        .all();

      const progress = await env.DB.prepare('SELECT profile_id, video_id, item_json, position, duration, updated_at, updated_at_ms FROM playback_progress WHERE account_id = ?')
        .bind(accountId)
        .all();

      const myList = await env.DB.prepare('SELECT profile_id, item_id, item_json, added_at, updated_at_ms FROM my_list WHERE account_id = ? ORDER BY added_at DESC')
        .bind(accountId)
        .all();

      const tombstones = await env.DB.prepare('SELECT profile_id, entity_type, entity_id, deleted_at_ms FROM sync_tombstones WHERE account_id = ?')
        .bind(accountId)
        .all();

      const deletedMyList = tombstones.results
        .filter((r: any) => r.entity_type === 'my_list')
        .map((r: any) => ({ profile_id: r.profile_id, item_id: r.entity_id, deleted_at_ms: r.deleted_at_ms }));

      const deletedProgress = tombstones.results
        .filter((r: any) => r.entity_type === 'progress')
        .map((r: any) => ({ profile_id: r.profile_id, video_id: r.entity_id, deleted_at_ms: r.deleted_at_ms }));

      const deletedProfiles = tombstones.results
        .filter((r: any) => r.entity_type === 'profile')
        .map((r: any) => ({ id: r.entity_id, deleted_at_ms: r.deleted_at_ms }));

      const addonUrls = await canonicalizeAddons(env, accountId);

      return json({
        plan,
        limits,
        profiles: dedupeProfilesById(profiles.results as any[]),
        deletedProfiles: deletedProfiles.map((d: any) => ({
          ...d,
          id: normalizeProfileId(d.id) || d.id,
        })),
        progress: progress.results,
        myList: myList.results,
        deletedMyList,
        deletedProgress,
        addons: addonUrls,
        ...(upgraded ? { token: upgraded.token } : {}),
      });
    }

    // MARK: - POST /api/sync/push (Envoi des modifications locales de l'Apple TV)
    if (url.pathname === '/api/sync/push' && request.method === 'POST') {
      const session = await authenticate(token, env);
      const accountId = session?.accountId;
      if (!accountId || !session) return json({ error: 'Non authentifié' }, 401);
      const { plan, limits: pushLimits } = await accountPlan(env, accountId);
      if (!pushLimits.cloudSync) {
        return json({ error: 'La synchronisation cloud est réservée à Pro et Ultra.', code: 'plan_required', plan, limits: pushLimits }, 402);
      }
      const upgraded = await upgradeLegacySession(env, session, request);

      const data = (await request.json()) as any;

      // 0. Profils supprimés (tombstones) : appliqués avant tout le reste
      if (Array.isArray(data.deletedProfiles)) {
        for (const del of data.deletedProfiles) {
          if (!del.id) continue;
          const delMs = typeof del.deletedAtMs === 'number' ? del.deletedAtMs : Date.now();
          await deleteProfileEverywhere(env, accountId, del.id, delMs);
        }
      }
      const deletedProfiles = await deletedProfileIds(env, accountId);
      const isLive = (profileId: unknown) => {
        const pid = normalizeProfileId(profileId) || String(profileId || '').toLowerCase();
        return !!pid && !deletedProfiles.has(pid);
      };

      // 1. Profils (updates always OK; new ids only while under plan cap)
      if (Array.isArray(data.profiles)) {
        const existingProfileRows = await env.DB.prepare(
          'SELECT id FROM profiles WHERE account_id = ?'
        ).bind(accountId).all();
        const existingProfileIds = new Set(
          existingProfileRows.results
            .map((r: any) => normalizeProfileId(r.id))
            .filter((id: string | null): id is string => !!id)
        );
        let profileSlots = Math.max(0, pushLimits.maxProfiles - existingProfileIds.size);
        for (const p of data.profiles) {
          const pid = normalizeProfileId(p.id);
          if (!pid || !isLive(pid)) continue;
          const isExisting = existingProfileIds.has(pid);
          if (!isExisting) {
            if (profileSlots <= 0) continue;
            profileSlots -= 1;
            existingProfileIds.add(pid);
          } else {
            await env.DB.prepare(
              'DELETE FROM profiles WHERE account_id = ? AND lower(id) = ? AND id != ?'
            ).bind(accountId, pid, pid).run();
          }
          await env.DB.prepare(`
            INSERT INTO profiles (account_id, id, name, avatar_json, sort_order, updated_at)
            VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(account_id, id) DO UPDATE SET
              name = excluded.name,
              avatar_json = excluded.avatar_json,
              sort_order = excluded.sort_order,
              updated_at = CURRENT_TIMESTAMP
          `).bind(accountId, pid, p.name, JSON.stringify(p.avatar), p.sortOrder || 0).run();
        }
      }

      // 2a. Suppressions de progression de lecture (tombstones)
      if (Array.isArray(data.deletedProgress)) {
        for (const del of data.deletedProgress) {
          const pid = normalizeProfileId(del.profileId);
          if (!pid || !isLive(pid) || !del.videoId) continue;
          const delMs = typeof del.deletedAtMs === 'number' ? del.deletedAtMs : Date.now();
          const existing: any = await env.DB.prepare(
            'SELECT updated_at_ms FROM playback_progress WHERE account_id = ? AND lower(profile_id) = ? AND video_id = ?'
          ).bind(accountId, pid, del.videoId).first();

          if (!existing || existing.updated_at_ms == null || delMs >= existing.updated_at_ms) {
            await env.DB.prepare(
              'DELETE FROM playback_progress WHERE account_id = ? AND lower(profile_id) = ? AND video_id = ?'
            ).bind(accountId, pid, del.videoId).run();

            await env.DB.prepare(`
              INSERT INTO sync_tombstones (account_id, profile_id, entity_type, entity_id, deleted_at_ms)
              VALUES (?, ?, 'progress', ?, ?)
              ON CONFLICT(account_id, profile_id, entity_type, entity_id) DO UPDATE SET
                deleted_at_ms = MAX(deleted_at_ms, excluded.deleted_at_ms)
            `).bind(accountId, pid, del.videoId, delMs).run();
          }
        }
      }

      // 2b. Progression de lecture
      if (Array.isArray(data.progress)) {
        for (const pr of data.progress) {
          const pid = normalizeProfileId(pr.profileId);
          if (!pid || !isLive(pid)) continue;
          const itemJson = typeof pr.item === 'string' ? pr.item : JSON.stringify(pr.item);
          const updatedAtMs = typeof pr.updatedAtMs === 'number' ? pr.updatedAtMs : Date.now();
          const tomb: any = await env.DB.prepare(
            "SELECT deleted_at_ms FROM sync_tombstones WHERE account_id = ? AND lower(profile_id) = ? AND entity_type = 'progress' AND entity_id = ?"
          ).bind(accountId, pid, pr.videoId).first();

          if (tomb && tomb.deleted_at_ms >= updatedAtMs) {
            continue;
          }
          if (tomb && updatedAtMs > tomb.deleted_at_ms) {
            await env.DB.prepare(
              "DELETE FROM sync_tombstones WHERE account_id = ? AND lower(profile_id) = ? AND entity_type = 'progress' AND entity_id = ?"
            ).bind(accountId, pid, pr.videoId).run();
          }

          // Drop legacy uppercase twin rows so ON CONFLICT hits the canonical id.
          await env.DB.prepare(
            'DELETE FROM playback_progress WHERE account_id = ? AND lower(profile_id) = ? AND profile_id != ? AND video_id = ?'
          ).bind(accountId, pid, pid, pr.videoId).run();

          await env.DB.prepare(`
            INSERT INTO playback_progress (account_id, profile_id, video_id, item_json, position, duration, updated_at, updated_at_ms)
            VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, ?)
            ON CONFLICT(account_id, profile_id, video_id) DO UPDATE SET
              position = CASE WHEN excluded.updated_at_ms >= COALESCE(updated_at_ms, 0) THEN excluded.position ELSE position END,
              duration = CASE WHEN excluded.updated_at_ms >= COALESCE(updated_at_ms, 0) THEN excluded.duration ELSE duration END,
              item_json = CASE WHEN excluded.updated_at_ms >= COALESCE(updated_at_ms, 0) THEN excluded.item_json ELSE item_json END,
              updated_at_ms = MAX(COALESCE(updated_at_ms, 0), excluded.updated_at_ms),
              updated_at = CURRENT_TIMESTAMP
          `).bind(accountId, pid, pr.videoId, itemJson, pr.position, pr.duration, updatedAtMs).run();
        }
      }

      // 3a. Suppressions de Ma liste (tombstones)
      if (Array.isArray(data.deletedMyList)) {
        for (const del of data.deletedMyList) {
          const pid = normalizeProfileId(del.profileId);
          if (!pid || !isLive(pid) || !del.itemId) continue;
          const delMs = typeof del.deletedAtMs === 'number' ? del.deletedAtMs : Date.now();
          const existing: any = await env.DB.prepare(
            'SELECT updated_at_ms FROM my_list WHERE account_id = ? AND lower(profile_id) = ? AND item_id = ?'
          ).bind(accountId, pid, del.itemId).first();

          if (!existing || existing.updated_at_ms == null || delMs >= existing.updated_at_ms) {
            await env.DB.prepare(
              'DELETE FROM my_list WHERE account_id = ? AND lower(profile_id) = ? AND item_id = ?'
            ).bind(accountId, pid, del.itemId).run();

            await env.DB.prepare(`
              INSERT INTO sync_tombstones (account_id, profile_id, entity_type, entity_id, deleted_at_ms)
              VALUES (?, ?, 'my_list', ?, ?)
              ON CONFLICT(account_id, profile_id, entity_type, entity_id) DO UPDATE SET
                deleted_at_ms = MAX(deleted_at_ms, excluded.deleted_at_ms)
            `).bind(accountId, pid, del.itemId, delMs).run();
          }
        }
      }

      // 3b. Ma liste
      if (Array.isArray(data.myList)) {
        for (const ml of data.myList) {
          const pid = normalizeProfileId(ml.profileId);
          if (!pid || !isLive(pid)) continue;
          const itemJson = typeof ml.item === 'string' ? ml.item : JSON.stringify(ml.item);
          const addedAtMs = typeof ml.addedAtMs === 'number' ? ml.addedAtMs : Date.now();
          const tomb: any = await env.DB.prepare(
            "SELECT deleted_at_ms FROM sync_tombstones WHERE account_id = ? AND lower(profile_id) = ? AND entity_type = 'my_list' AND entity_id = ?"
          ).bind(accountId, pid, ml.itemId).first();

          if (tomb && tomb.deleted_at_ms >= addedAtMs) {
            continue;
          }
          if (tomb && addedAtMs > tomb.deleted_at_ms) {
            await env.DB.prepare(
              "DELETE FROM sync_tombstones WHERE account_id = ? AND lower(profile_id) = ? AND entity_type = 'my_list' AND entity_id = ?"
            ).bind(accountId, pid, ml.itemId).run();
          }

          await env.DB.prepare(
            'DELETE FROM my_list WHERE account_id = ? AND lower(profile_id) = ? AND profile_id != ? AND item_id = ?'
          ).bind(accountId, pid, pid, ml.itemId).run();

          await env.DB.prepare(`
            INSERT INTO my_list (account_id, profile_id, item_id, item_json, added_at, updated_at_ms)
            VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, ?)
            ON CONFLICT(account_id, profile_id, item_id) DO UPDATE SET
              item_json = CASE WHEN excluded.updated_at_ms >= COALESCE(updated_at_ms, 0) THEN excluded.item_json ELSE item_json END,
              updated_at_ms = MAX(COALESCE(updated_at_ms, 0), excluded.updated_at_ms)
          `).bind(accountId, pid, ml.itemId, itemJson, addedAtMs).run();
        }
      }

      // 4. Addons (canonical URLs only — plan cap is hard, no /manifest.json twins)
      if (Array.isArray(data.addons)) {
        const existingAddons = new Set(await canonicalizeAddons(env, accountId));
        let addonSlots = Math.max(0, pushLimits.maxAddons - existingAddons.size);
        for (const url of data.addons) {
          const clean = normalizeAddonUrl(url);
          if (!clean || existingAddons.has(clean)) continue;
          if (addonSlots <= 0) break;
          await env.DB.prepare(`
            INSERT INTO addons (account_id, manifest_url, installed_at)
            VALUES (?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(account_id, manifest_url) DO NOTHING
          `).bind(accountId, clean).run();
          existingAddons.add(clean);
          addonSlots -= 1;
        }
      }

      return json({
        success: true,
        timestamp: new Date().toISOString(),
        ...(upgraded ? { token: upgraded.token } : {}),
      });
    }

    // MARK: - POST /api/auth/logout (revokes this device's session)
    if (url.pathname === '/api/auth/logout' && request.method === 'POST') {
      const session = await authenticate(token, env);
      if (session?.sessionId) {
        await env.DB.prepare('UPDATE sessions SET revoked_at_ms = ? WHERE id = ? AND revoked_at_ms IS NULL')
          .bind(Date.now(), session.sessionId)
          .run();
      }
      return json({ success: true });
    }

    // MARK: - POST /api/auth/delete-account (hard-delete account + cascaded cloud data)
    if (url.pathname === '/api/auth/delete-account' && request.method === 'POST') {
      const session = await authenticate(token, env);
      if (!session) return json({ error: 'Non authentifié' }, 401);
      await env.DB.prepare('DELETE FROM accounts WHERE id = ?').bind(session.accountId).run();
      return json({ success: true });
    }

    // MARK: - POST /api/billing/apple (StoreKit 2 JWS → accounts.plan)
    if (url.pathname === '/api/billing/apple' && request.method === 'POST') {
      const session = await authenticate(token, env);
      if (!session) return json({ error: 'Non authentifié' }, 401);
      const { signedTransaction } = (await request.json().catch(() => ({}))) as any;
      if (typeof signedTransaction !== 'string' || !signedTransaction.includes('.')) {
        return json({ error: 'Transaction StoreKit manquante.' }, 400);
      }
      let payload: any;
      try {
        payload = decodeAppleTransactionJWS(signedTransaction);
      } catch {
        return json({ error: 'Transaction StoreKit illisible.' }, 400);
      }
      const productId = typeof payload.productId === 'string' ? payload.productId : '';
      const reportedPlan = planForProductId(productId);
      if (!reportedPlan) {
        return json({ error: `Produit inconnu: ${productId || '?'}` }, 400);
      }
      if (payload.revocationDate) {
        await env.DB.prepare(
          `UPDATE accounts SET plan = 'free', plan_expires_at_ms = NULL, plan_product_id = NULL, updated_at = CURRENT_TIMESTAMP WHERE id = ?`
        ).bind(session.accountId).run();
        return json({ success: true, plan: 'free', limits: limitsFor('free') });
      }
      const expiresAtMs = productId.endsWith('.lifetime')
        ? null
        : typeof payload.expiresDate === 'number'
          ? payload.expiresDate
          : typeof payload.expiresDate === 'string'
            ? Number(payload.expiresDate)
            : null;
      if (expiresAtMs != null && !Number.isNaN(expiresAtMs) && expiresAtMs < Date.now()) {
        // Expired sub report — only clear if this product is the one on the account.
        const row: any = await env.DB.prepare('SELECT plan_product_id FROM accounts WHERE id = ?')
          .bind(session.accountId).first();
        if (row?.plan_product_id === productId) {
          await env.DB.prepare(
            `UPDATE accounts SET plan = 'free', plan_expires_at_ms = NULL, plan_product_id = NULL, updated_at = CURRENT_TIMESTAMP WHERE id = ?`
          ).bind(session.accountId).run();
        }
        const after = await accountPlan(env, session.accountId);
        return json({ success: true, plan: after.plan, limits: after.limits, planExpiresAtMs: after.expiresAtMs });
      }
      const current = await accountPlan(env, session.accountId);
      if (rankPlan(reportedPlan) < rankPlan(current.plan)) {
        // Stale Pro restore must not overwrite active Ultra.
        return json({ success: true, plan: current.plan, limits: current.limits, planExpiresAtMs: current.expiresAtMs });
      }
      await env.DB.prepare(
        `UPDATE accounts SET plan = ?, plan_expires_at_ms = ?, plan_product_id = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?`
      ).bind(reportedPlan, expiresAtMs, productId, session.accountId).run();
      const updated = await accountPlan(env, session.accountId);
      return json({
        success: true,
        plan: updated.plan,
        limits: updated.limits,
        planExpiresAtMs: updated.expiresAtMs,
        productId,
      });
    }

    // MARK: - GET /api/devices (devices signed in to the account)
    if (url.pathname === '/api/devices' && request.method === 'GET') {
      const session = await authenticate(token, env);
      if (!session) return json({ error: 'Non authentifié' }, 401);
      const upgraded = await upgradeLegacySession(env, session, request);
      const currentSessionId = upgraded?.sessionId ?? session.sessionId;
      const { plan, limits } = await accountPlan(env, session.accountId);
      const rows = await env.DB.prepare(
        `SELECT id, device_name, device_model, device_kind, display_name, created_at_ms, last_seen_at_ms
         FROM sessions WHERE account_id = ? AND revoked_at_ms IS NULL ORDER BY last_seen_at_ms DESC`
      ).bind(session.accountId).all();
      return json({
        plan,
        limits,
        devices: rows.results.map((r: any) => ({
          id: r.id,
          name: r.display_name || r.device_name,
          rawName: r.device_name,
          displayName: r.display_name || null,
          model: r.device_model || null,
          kind: inferSessionKind(r.device_kind, r.display_name || r.device_name, r.device_model),
          createdAtMs: r.created_at_ms,
          lastSeenAtMs: r.last_seen_at_ms,
          isCurrent: !!currentSessionId && r.id === currentSessionId,
        })),
        ...(upgraded ? { token: upgraded.token } : {}),
      });
    }

    // MARK: - POST /api/devices/revoke (signs one device out)
    if (url.pathname === '/api/devices/revoke' && request.method === 'POST') {
      const session = await authenticate(token, env);
      if (!session) return json({ error: 'Non authentifié' }, 401);
      const { id } = (await request.json().catch(() => ({}))) as any;
      if (!id) return json({ error: 'Identifiant d\'appareil requis.' }, 400);
      const res = await env.DB.prepare(
        'UPDATE sessions SET revoked_at_ms = ? WHERE id = ? AND account_id = ? AND revoked_at_ms IS NULL'
      ).bind(Date.now(), id, session.accountId).run();
      if (res.meta.changes === 0) return json({ error: 'Appareil introuvable.' }, 404);
      return json({ success: true });
    }

    // MARK: - POST /api/devices/revoke-others (signs out every device but this one)
    if (url.pathname === '/api/devices/revoke-others' && request.method === 'POST') {
      const session = await authenticate(token, env);
      if (!session) return json({ error: 'Non authentifié' }, 401);
      const res = await env.DB.prepare(
        'UPDATE sessions SET revoked_at_ms = ? WHERE account_id = ? AND id != ? AND revoked_at_ms IS NULL'
      ).bind(Date.now(), session.accountId, session.sessionId || '').run();
      return json({ success: true, revoked: res.meta.changes });
    }

    // MARK: - POST /api/devices/rename (Pro+)
    if (url.pathname === '/api/devices/rename' && request.method === 'POST') {
      const session = await authenticate(token, env);
      if (!session) return json({ error: 'Non authentifié' }, 401);
      const { limits, plan } = await accountPlan(env, session.accountId);
      if (!limits.canRenameDevices) {
        return json({ error: 'Le renommage d\'appareils est réservé à Pro et Ultra.', code: 'plan_required', plan, limits }, 402);
      }
      const { id, displayName } = (await request.json().catch(() => ({}))) as any;
      if (!id) return json({ error: 'Identifiant d\'appareil requis.' }, 400);
      const clean = typeof displayName === 'string' ? displayName.trim().slice(0, 32) : '';
      if (!clean) return json({ error: 'Nom d\'appareil requis (32 caractères max).' }, 400);
      const res = await env.DB.prepare(
        'UPDATE sessions SET display_name = ? WHERE id = ? AND account_id = ? AND revoked_at_ms IS NULL'
      ).bind(clean, id, session.accountId).run();
      if (res.meta.changes === 0) return json({ error: 'Appareil introuvable.' }, 404);
      return json({ success: true, id, displayName: clean });
    }

    return json({ error: 'Route introuvable' }, 404);
  },
};
