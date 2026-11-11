/**
 * Cloudflare Worker Backend for Loge
 * Handles Authentication, Device Flow Pairing (QR Code), and Multi-Device Cloud Sync.
 */

export interface Env {
  DB: D1Database;
  JWT_SECRET: string;
}

// Helpers crypto natifs Web Crypto (compatibles Cloudflare Workers sans dépendance lourde)
async function hashPassword(password: string): Promise<string> {
  const enc = new TextEncoder();
  const digest = await crypto.subtle.digest('SHA-256', enc.encode(password + 'stremiotv_salt'));
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

async function generateToken(accountId: string, secret: string, sessionId: string): Promise<string> {
  const payload = {
    sub: accountId,
    sid: sessionId,
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 365, // 1 an
  };
  const str = btoa(JSON.stringify(payload));
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    enc.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const signature = await crypto.subtle.sign('HMAC', key, enc.encode(str));
  const sigStr = btoa(String.fromCharCode(...new Uint8Array(signature)));
  return `${str}.${sigStr}`;
}

interface TokenClaims {
  accountId: string;
  /** Null for tokens issued before device sessions existed (ADR 0022): they stay valid until they expire. */
  sessionId: string | null;
}

async function verifyToken(token: string, secret: string): Promise<TokenClaims | null> {
  try {
    const [payloadStr, sigStr] = token.split('.');
    if (!payloadStr || !sigStr) return null;
    const enc = new TextEncoder();
    const key = await crypto.subtle.importKey(
      'raw',
      enc.encode(secret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['verify']
    );
    const sigBytes = Uint8Array.from(atob(sigStr), (c) => c.charCodeAt(0));
    const valid = await crypto.subtle.verify('HMAC', key, sigBytes, enc.encode(payloadStr));
    if (!valid) return null;
    const payload = JSON.parse(atob(payloadStr));
    if (payload.exp < Math.floor(Date.now() / 1000)) return null;
    return { accountId: payload.sub, sessionId: payload.sid ?? null };
  } catch {
    return null;
  }
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

/** Opens a device session and returns a token bound to it. */
async function openSession(
  env: Env,
  accountId: string,
  deviceName: unknown,
  deviceModel: unknown
): Promise<{ token: string; sessionId: string }> {
  const sessionId = crypto.randomUUID();
  const now = Date.now();
  await env.DB.prepare(
    'INSERT INTO sessions (id, account_id, device_name, device_model, created_at_ms, last_seen_at_ms) VALUES (?, ?, ?, ?, ?, ?)'
  ).bind(sessionId, accountId, cleanLabel(deviceName, 'Navigateur web'), cleanLabel(deviceModel, ''), now, now).run();
  return { sessionId, token: await generateToken(accountId, env.JWT_SECRET, sessionId) };
}

async function issueToken(env: Env, accountId: string, deviceName: unknown, deviceModel: unknown): Promise<string> {
  return (await openSession(env, accountId, deviceName, deviceModel)).token;
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
  await env.DB.prepare(
    `UPDATE sessions SET
       device_name = ?,
       device_model = CASE WHEN ? != '' THEN ? ELSE device_model END,
       last_seen_at_ms = ?
     WHERE id = ?`
  ).bind(name, model, model, Date.now(), sessionId).run();
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
    await env.DB.prepare(
      `UPDATE sessions SET
         device_name = ?,
         device_model = CASE WHEN ? != '' THEN ? ELSE device_model END,
         last_seen_at_ms = ?
       WHERE id = ?`
    ).bind(deviceName, deviceModel, deviceModel, now, existing.id).run();
    return { sessionId: existing.id, token: await generateToken(session.accountId, env.JWT_SECRET, existing.id) };
  }
  return openSession(env, session.accountId, deviceName, deviceModel);
}

/** Profile ids deleted on any device or on the web: they must never be recreated by a later push. */
async function deletedProfileIds(env: Env, accountId: string): Promise<Set<string>> {
  const rows = await env.DB.prepare(
    "SELECT entity_id FROM sync_tombstones WHERE account_id = ? AND entity_type = 'profile'"
  ).bind(accountId).all();
  return new Set(rows.results.map((r: any) => r.entity_id));
}

async function deleteProfileEverywhere(env: Env, accountId: string, profileId: string, deletedAtMs: number) {
  await env.DB.batch([
    env.DB.prepare('DELETE FROM profiles WHERE account_id = ? AND id = ?').bind(accountId, profileId),
    env.DB.prepare('DELETE FROM my_list WHERE account_id = ? AND profile_id = ?').bind(accountId, profileId),
    env.DB.prepare('DELETE FROM playback_progress WHERE account_id = ? AND profile_id = ?').bind(accountId, profileId),
    env.DB.prepare(`
      INSERT INTO sync_tombstones (account_id, profile_id, entity_type, entity_id, deleted_at_ms)
      VALUES (?, ?, 'profile', ?, ?)
      ON CONFLICT(account_id, profile_id, entity_type, entity_id) DO UPDATE SET
        deleted_at_ms = MAX(deleted_at_ms, excluded.deleted_at_ms)
    `).bind(accountId, profileId, profileId, deletedAtMs),
  ]);
}

function json(data: any, status = 200): Response {
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

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Device-Name, X-Device-Model',
        },
      });
    }

    // MARK: - Web Companion Interface (HTML pour iPhone/Mac lors du scan QR)
    if (url.pathname === '/' || url.pathname === '/pair') {
      const codeParam = url.searchParams.get('code') || '';
      return new Response(renderWebPortal(codeParam), {
        headers: { 'Content-Type': 'text/html; charset=utf-8' },
      });
    }

    if (url.pathname === '/privacy') {
      return new Response(privacyPolicyHTML, {
        headers: { 'Content-Type': 'text/html; charset=utf-8' },
      });
    }

    if (url.pathname === '/support') {
      return new Response(supportHTML, {
        headers: { 'Content-Type': 'text/html; charset=utf-8' },
      });
    }

    // Helper auth header
    const authHeader = request.headers.get('Authorization') || '';
    const token = authHeader.replace(/^Bearer\s+/i, '');

    // MARK: - POST /api/auth/register
    if (url.pathname === '/api/auth/register' && request.method === 'POST') {
      const { email, password, deviceName, deviceModel } = (await request.json()) as any;
      if (!email || !password || password.length < 6) {
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

      const jwt = await issueToken(env, accountId, deviceName, deviceModel);
      return json({ token: jwt, accountId, email: email.toLowerCase() });
    }

    // MARK: - POST /api/auth/login
    if (url.pathname === '/api/auth/login' && request.method === 'POST') {
      const { email, password, deviceName, deviceModel } = (await request.json()) as any;
      if (!email || !password) return json({ error: 'Identifiants requis.' }, 400);
      const pwHash = await hashPassword(password);
      const account: any = await env.DB.prepare('SELECT id, email FROM accounts WHERE email = ? AND password_hash = ?')
        .bind(email.toLowerCase(), pwHash)
        .first();
      if (!account) {
        return json({ error: 'Email ou mot de passe incorrect.' }, 401);
      }
      const jwt = await issueToken(env, account.id, deviceName, deviceModel);
      return json({ token: jwt, accountId: account.id, email: account.email });
    }

    // MARK: - POST /api/device/code (Apple TV demande un code d'appairage)
    if (url.pathname === '/api/device/code' && request.method === 'POST') {
      const body = (await request.json().catch(() => ({}))) as any;
      const deviceName = body.deviceName || 'Apple TV';
      // Génère un code court convivial (ex: STREM-4821)
      const randomDigits = Math.floor(1000 + Math.random() * 9000);
      const code = `STREM-${randomDigits}`;
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
        const jwt = await issueToken(env, entry.account_id, deviceName || entry.device_name, deviceModel);
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

      const account: any = await env.DB.prepare('SELECT email, nickname FROM accounts WHERE id = ?')
        .bind(accountId)
        .first();

      const profiles = await env.DB.prepare('SELECT id, name, avatar_json, sort_order FROM profiles WHERE account_id = ? ORDER BY sort_order ASC')
        .bind(accountId)
        .all();

      const addons = await env.DB.prepare('SELECT manifest_url FROM addons WHERE account_id = ? ORDER BY installed_at ASC')
        .bind(accountId)
        .all();

      return json({
        email: account?.email || '',
        nickname: account?.nickname || '',
        profiles: profiles.results,
        addons: addons.results.map((r: any) => r.manifest_url),
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
      if (newPassword.length < 6) {
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

      const profileId = id || crypto.randomUUID();
      let avatarJson: string;
      if (avatar && typeof avatar === 'object') {
        avatarJson = JSON.stringify(avatar);
      } else if (id) {
        // Rename-only updates must keep the existing avatar (TV contract).
        const existing: any = await env.DB.prepare(
          'SELECT avatar_json FROM profiles WHERE account_id = ? AND id = ?'
        ).bind(accountId, id).first();
        avatarJson = existing?.avatar_json || JSON.stringify({ color: 'blue', symbol: 'face.smiling' });
      } else {
        avatarJson = JSON.stringify({ color: 'blue', symbol: 'face.smiling' });
      }

      if (!id) {
        const countRes: any = await env.DB.prepare('SELECT count(*) as c FROM profiles WHERE account_id = ?').bind(accountId).first();
        if (countRes && countRes.c >= 6) {
          return json({ error: 'Nombre maximum de profils atteint (6).' }, 400);
        }
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

      const countRes: any = await env.DB.prepare('SELECT count(*) as c FROM profiles WHERE account_id = ?').bind(accountId).first();
      if (countRes && countRes.c <= 1) {
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
      const clean = (manifestUrl || '').trim();
      if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
        return json({ error: 'URL d\'addon invalide (doit commencer par https://).' }, 400);
      }

      await env.DB.prepare('INSERT INTO addons (account_id, manifest_url, installed_at) VALUES (?, ?, CURRENT_TIMESTAMP) ON CONFLICT DO NOTHING')
        .bind(accountId, clean)
        .run();

      return json({ success: true, manifestUrl: clean });
    }

    // MARK: - DELETE /api/account/addons
    if (url.pathname === '/api/account/addons' && request.method === 'DELETE') {
      const session = await authenticate(token, env);
      const accountId = session?.accountId;
      if (!accountId) return json({ error: 'Non authentifié' }, 401);

      const { manifestUrl } = (await request.json().catch(() => ({}))) as any;
      if (!manifestUrl) return json({ error: 'URL d\'addon requise.' }, 400);

      await env.DB.prepare('DELETE FROM addons WHERE account_id = ? AND manifest_url = ?')
        .bind(accountId, manifestUrl)
        .run();

      return json({ success: true });
    }

    // MARK: - GET /api/sync/pull (Récupération des données du foyer)
    if (url.pathname === '/api/sync/pull' && request.method === 'GET') {
      const session = await authenticate(token, env);
      const accountId = session?.accountId;
      if (!accountId || !session) return json({ error: 'Non authentifié' }, 401);
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

      const addons = await env.DB.prepare('SELECT manifest_url FROM addons WHERE account_id = ?')
        .bind(accountId)
        .all();

      return json({
        profiles: profiles.results,
        deletedProfiles,
        progress: progress.results,
        myList: myList.results,
        deletedMyList,
        deletedProgress,
        addons: addons.results.map((r: any) => r.manifest_url),
        ...(upgraded ? { token: upgraded.token } : {}),
      });
    }

    // MARK: - POST /api/sync/push (Envoi des modifications locales de l'Apple TV)
    if (url.pathname === '/api/sync/push' && request.method === 'POST') {
      const session = await authenticate(token, env);
      const accountId = session?.accountId;
      if (!accountId || !session) return json({ error: 'Non authentifié' }, 401);
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
      const isLive = (profileId: string) => !deletedProfiles.has(profileId);

      // 1. Profils
      if (Array.isArray(data.profiles)) {
        for (const p of data.profiles.filter((p: any) => isLive(p.id))) {
          await env.DB.prepare(`
            INSERT INTO profiles (account_id, id, name, avatar_json, sort_order, updated_at)
            VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(account_id, id) DO UPDATE SET
              name = excluded.name,
              avatar_json = excluded.avatar_json,
              sort_order = excluded.sort_order,
              updated_at = CURRENT_TIMESTAMP
          `).bind(accountId, p.id, p.name, JSON.stringify(p.avatar), p.sortOrder || 0).run();
        }
      }

      // 2a. Suppressions de progression de lecture (tombstones)
      if (Array.isArray(data.deletedProgress)) {
        for (const del of data.deletedProgress.filter((d: any) => isLive(d.profileId))) {
          if (!del.profileId || !del.videoId) continue;
          const delMs = typeof del.deletedAtMs === 'number' ? del.deletedAtMs : Date.now();
          const existing: any = await env.DB.prepare(
            'SELECT updated_at_ms FROM playback_progress WHERE account_id = ? AND profile_id = ? AND video_id = ?'
          ).bind(accountId, del.profileId, del.videoId).first();

          if (!existing || existing.updated_at_ms == null || delMs >= existing.updated_at_ms) {
            await env.DB.prepare(
              'DELETE FROM playback_progress WHERE account_id = ? AND profile_id = ? AND video_id = ?'
            ).bind(accountId, del.profileId, del.videoId).run();

            await env.DB.prepare(`
              INSERT INTO sync_tombstones (account_id, profile_id, entity_type, entity_id, deleted_at_ms)
              VALUES (?, ?, 'progress', ?, ?)
              ON CONFLICT(account_id, profile_id, entity_type, entity_id) DO UPDATE SET
                deleted_at_ms = MAX(deleted_at_ms, excluded.deleted_at_ms)
            `).bind(accountId, del.profileId, del.videoId, delMs).run();
          }
        }
      }

      // 2b. Progression de lecture
      if (Array.isArray(data.progress)) {
        for (const pr of data.progress.filter((p: any) => isLive(p.profileId))) {
          const itemJson = typeof pr.item === 'string' ? pr.item : JSON.stringify(pr.item);
          const updatedAtMs = typeof pr.updatedAtMs === 'number' ? pr.updatedAtMs : Date.now();
          const tomb: any = await env.DB.prepare(
            "SELECT deleted_at_ms FROM sync_tombstones WHERE account_id = ? AND profile_id = ? AND entity_type = 'progress' AND entity_id = ?"
          ).bind(accountId, pr.profileId, pr.videoId).first();

          if (tomb && tomb.deleted_at_ms >= updatedAtMs) {
            continue;
          }
          if (tomb && updatedAtMs > tomb.deleted_at_ms) {
            await env.DB.prepare(
              "DELETE FROM sync_tombstones WHERE account_id = ? AND profile_id = ? AND entity_type = 'progress' AND entity_id = ?"
            ).bind(accountId, pr.profileId, pr.videoId).run();
          }

          await env.DB.prepare(`
            INSERT INTO playback_progress (account_id, profile_id, video_id, item_json, position, duration, updated_at, updated_at_ms)
            VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, ?)
            ON CONFLICT(account_id, profile_id, video_id) DO UPDATE SET
              position = CASE WHEN excluded.updated_at_ms >= COALESCE(updated_at_ms, 0) THEN excluded.position ELSE position END,
              duration = CASE WHEN excluded.updated_at_ms >= COALESCE(updated_at_ms, 0) THEN excluded.duration ELSE duration END,
              item_json = CASE WHEN excluded.updated_at_ms >= COALESCE(updated_at_ms, 0) THEN excluded.item_json ELSE item_json END,
              updated_at_ms = MAX(COALESCE(updated_at_ms, 0), excluded.updated_at_ms),
              updated_at = CURRENT_TIMESTAMP
          `).bind(accountId, pr.profileId, pr.videoId, itemJson, pr.position, pr.duration, updatedAtMs).run();
        }
      }

      // 3a. Suppressions de Ma liste (tombstones)
      if (Array.isArray(data.deletedMyList)) {
        for (const del of data.deletedMyList.filter((d: any) => isLive(d.profileId))) {
          if (!del.profileId || !del.itemId) continue;
          const delMs = typeof del.deletedAtMs === 'number' ? del.deletedAtMs : Date.now();
          const existing: any = await env.DB.prepare(
            'SELECT updated_at_ms FROM my_list WHERE account_id = ? AND profile_id = ? AND item_id = ?'
          ).bind(accountId, del.profileId, del.itemId).first();

          if (!existing || existing.updated_at_ms == null || delMs >= existing.updated_at_ms) {
            await env.DB.prepare(
              'DELETE FROM my_list WHERE account_id = ? AND profile_id = ? AND item_id = ?'
            ).bind(accountId, del.profileId, del.itemId).run();

            await env.DB.prepare(`
              INSERT INTO sync_tombstones (account_id, profile_id, entity_type, entity_id, deleted_at_ms)
              VALUES (?, ?, 'my_list', ?, ?)
              ON CONFLICT(account_id, profile_id, entity_type, entity_id) DO UPDATE SET
                deleted_at_ms = MAX(deleted_at_ms, excluded.deleted_at_ms)
            `).bind(accountId, del.profileId, del.itemId, delMs).run();
          }
        }
      }

      // 3b. Ma liste
      if (Array.isArray(data.myList)) {
        for (const ml of data.myList.filter((m: any) => isLive(m.profileId))) {
          const itemJson = typeof ml.item === 'string' ? ml.item : JSON.stringify(ml.item);
          const addedAtMs = typeof ml.addedAtMs === 'number' ? ml.addedAtMs : Date.now();
          const tomb: any = await env.DB.prepare(
            "SELECT deleted_at_ms FROM sync_tombstones WHERE account_id = ? AND profile_id = ? AND entity_type = 'my_list' AND entity_id = ?"
          ).bind(accountId, ml.profileId, ml.itemId).first();

          if (tomb && tomb.deleted_at_ms >= addedAtMs) {
            continue;
          }
          if (tomb && addedAtMs > tomb.deleted_at_ms) {
            await env.DB.prepare(
              "DELETE FROM sync_tombstones WHERE account_id = ? AND profile_id = ? AND entity_type = 'my_list' AND entity_id = ?"
            ).bind(accountId, ml.profileId, ml.itemId).run();
          }

          await env.DB.prepare(`
            INSERT INTO my_list (account_id, profile_id, item_id, item_json, added_at, updated_at_ms)
            VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, ?)
            ON CONFLICT(account_id, profile_id, item_id) DO UPDATE SET
              item_json = CASE WHEN excluded.updated_at_ms >= COALESCE(updated_at_ms, 0) THEN excluded.item_json ELSE item_json END,
              updated_at_ms = MAX(COALESCE(updated_at_ms, 0), excluded.updated_at_ms)
          `).bind(accountId, ml.profileId, ml.itemId, itemJson, addedAtMs).run();
        }
      }

      // 4. Addons
      if (Array.isArray(data.addons)) {
        for (const url of data.addons) {
          await env.DB.prepare(`
            INSERT INTO addons (account_id, manifest_url, installed_at)
            VALUES (?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(account_id, manifest_url) DO NOTHING
          `).bind(accountId, url).run();
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

    // MARK: - GET /api/devices (devices signed in to the account)
    if (url.pathname === '/api/devices' && request.method === 'GET') {
      const session = await authenticate(token, env);
      if (!session) return json({ error: 'Non authentifié' }, 401);
      const upgraded = await upgradeLegacySession(env, session, request);
      const currentSessionId = upgraded?.sessionId ?? session.sessionId;
      const rows = await env.DB.prepare(
        'SELECT id, device_name, device_model, created_at_ms, last_seen_at_ms FROM sessions WHERE account_id = ? AND revoked_at_ms IS NULL ORDER BY last_seen_at_ms DESC'
      ).bind(session.accountId).all();
      return json({
        devices: rows.results.map((r: any) => ({
          id: r.id,
          name: r.device_name,
          model: r.device_model || null,
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

    return json({ error: 'Route introuvable' }, 404);
  },
};

// MARK: - Template HTML Web Companion
function renderWebPortal(prefillCode: string): string {
  return `<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <meta name="theme-color" content="#141414">
  <title>Loge • Espace Compte & Jumelage</title>
  <style>
    /* Design Tokens calqués sur Theme.swift et tvOS */
    :root {
      --tv-canvas: #141414;
      --tv-surface: rgba(255, 255, 255, 0.08);
      --tv-surface-raised: rgba(255, 255, 255, 0.14);
      --tv-surface-subtle: rgba(255, 255, 255, 0.04);
      --tv-accent: #E50914; /* Rouge cinéma emblématique */
      --tv-accent-glow: rgba(229, 9, 20, 0.28);
      --tv-text-primary: #FFFFFF;
      --tv-text-secondary: rgba(255, 255, 255, 0.72);
      --tv-text-tertiary: rgba(255, 255, 255, 0.44);
      --tv-match: #46D369; /* Vert Debrid */
      --tv-border: rgba(255, 255, 255, 0.10);
      --tv-border-focus: rgba(255, 255, 255, 0.35);
      --tv-radius-card: 20px;
      --tv-radius-control: 12px;
      --tv-radius-pill: 9999px;
      --tv-ease-critique: cubic-bezier(0.2, 0, 0, 1);
    }

    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
      -webkit-font-smoothing: antialiased;
      -moz-osx-font-smoothing: grayscale;
      -webkit-tap-highlight-color: transparent;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "Helvetica Neue", sans-serif;
    }

    body {
      background-color: var(--tv-canvas);
      background-image: 
        radial-gradient(ellipse 80% 50% at 50% -10%, rgba(229, 9, 20, 0.12), transparent 70%),
        radial-gradient(ellipse 60% 40% at 50% 110%, rgba(255, 255, 255, 0.03), transparent 60%);
      color: var(--tv-text-primary);
      min-height: 100vh;
      min-height: 100dvh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: flex-start;
      padding: 24px 16px 40px;
      overflow-x: hidden;
    }

    .container {
      width: 100%;
      max-width: 460px;
      margin: 0 auto;
    }

    /* Carte principale */
    .tv-card {
      background: var(--tv-surface);
      border: 1px solid var(--tv-border);
      border-radius: var(--tv-radius-card);
      padding: 26px 22px;
      box-shadow: 
        0 26px 45px -10px rgba(0, 0, 0, 0.70),
        0 8px 16px -4px rgba(0, 0, 0, 0.40),
        inset 0 1px 0 0 rgba(255, 255, 255, 0.14);
      position: relative;
    }

    /* En-tête */
    .header {
      display: flex;
      flex-direction: column;
      align-items: center;
      text-align: center;
      margin-bottom: 22px;
    }

    .tv-brand-icon {
      width: 52px;
      height: 52px;
      border-radius: 13px;
      background: linear-gradient(135deg, #1f1f23 0%, #0d0d0f 100%);
      border: 1px solid rgba(255, 255, 255, 0.16);
      display: flex;
      align-items: center;
      justify-content: center;
      margin-bottom: 12px;
      box-shadow: 0 10px 24px -4px rgba(0, 0, 0, 0.65), inset 0 1px 0 0 rgba(255, 255, 255, 0.25);
    }

    .tv-brand-icon svg {
      width: 26px;
      height: 26px;
      fill: var(--tv-accent);
      filter: drop-shadow(0 2px 6px rgba(229, 9, 20, 0.45));
    }

    .brand-title {
      font-size: 24px;
      font-weight: 800;
      letter-spacing: -0.025em;
      color: var(--tv-text-primary);
      margin-bottom: 3px;
    }

    .brand-subtitle {
      font-size: 13.5px;
      font-weight: 400;
      color: var(--tv-text-secondary);
      line-height: 1.4;
    }

    /* Carte de Jumelage Apple TV */
    .pairing-card {
      display: flex;
      align-items: center;
      justify-content: space-between;
      background: rgba(0, 0, 0, 0.38);
      border: 1px solid rgba(255, 255, 255, 0.08);
      border-radius: var(--tv-radius-control);
      padding: 12px 14px;
      margin-bottom: 18px;
    }

    .pairing-device {
      display: flex;
      align-items: center;
      gap: 10px;
    }

    .pulse-dot {
      width: 8px;
      height: 8px;
      border-radius: var(--tv-radius-pill);
      background-color: var(--tv-match);
      box-shadow: 0 0 10px var(--tv-match);
    }

    .device-title {
      font-size: 13px;
      font-weight: 600;
      color: var(--tv-text-primary);
    }

    .device-sub {
      font-size: 11px;
      color: var(--tv-text-tertiary);
    }

    .pairing-code-badge {
      font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
      font-size: 14px;
      font-weight: 700;
      letter-spacing: 0.08em;
      color: var(--tv-text-primary);
      background: var(--tv-surface-raised);
      padding: 5px 9px;
      border-radius: 7px;
      border: 1px solid rgba(255, 255, 255, 0.15);
    }

    /* Segmented Picker tvOS */
    .tv-segmented {
      display: grid;
      background: rgba(0, 0, 0, 0.32);
      border: 1px solid rgba(255, 255, 255, 0.06);
      border-radius: 10px;
      padding: 3px;
      margin-bottom: 18px;
    }

    .tv-segmented-2 { grid-template-columns: 1fr 1fr; }
    .tv-segmented-4 { grid-template-columns: repeat(4, 1fr); gap: 2px; }
    .tv-segmented-5 { grid-template-columns: repeat(5, 1fr); gap: 2px; }
    .device-current { font-size: 11px; font-weight: 700; color: var(--tv-match); margin-left: 6px; }

    .tv-segment-item {
      padding: 8px 6px;
      border: none;
      background: transparent;
      color: var(--tv-text-secondary);
      font-size: 12.5px;
      font-weight: 600;
      border-radius: 7px;
      cursor: pointer;
      text-align: center;
      transition: background 0.14s var(--tv-ease-critique), color 0.14s var(--tv-ease-critique);
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .tv-segment-item.active {
      background: var(--tv-surface-raised);
      color: var(--tv-text-primary);
      box-shadow: 0 2px 8px rgba(0, 0, 0, 0.45);
    }

    /* Formulaire */
    .input-group {
      margin-bottom: 14px;
    }

    .input-label {
      display: block;
      font-size: 12px;
      font-weight: 600;
      color: var(--tv-text-secondary);
      margin-bottom: 5px;
    }

    .tv-input {
      width: 100%;
      height: 44px;
      padding: 0 13px;
      background: rgba(0, 0, 0, 0.38);
      border: 1px solid var(--tv-border);
      border-radius: var(--tv-radius-control);
      color: var(--tv-text-primary);
      font-size: 14px;
      outline: none;
      transition: border-color 0.14s ease-out, background 0.14s ease-out;
    }

    .tv-input::placeholder { color: var(--tv-text-tertiary); }
    .tv-input:focus {
      background: rgba(0, 0, 0, 0.55);
      border-color: var(--tv-border-focus);
      box-shadow: 0 0 0 3px rgba(255, 255, 255, 0.10);
    }

    /* Boutons */
    .tv-pill-primary {
      width: 100%;
      height: 44px;
      margin-top: 6px;
      background: #FFFFFF;
      color: #000000;
      border: none;
      border-radius: var(--tv-radius-pill);
      font-size: 14.5px;
      font-weight: 700;
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      position: relative;
      overflow: hidden;
      box-shadow: 0 10px 20px -5px rgba(0, 0, 0, 0.45);
      transition: transform 0.14s var(--tv-ease-critique), opacity 0.14s ease-out;
    }

    .tv-pill-primary::after {
      content: "";
      position: absolute;
      top: 0; left: 0; right: 0; height: 50%;
      background: linear-gradient(to bottom, rgba(255, 255, 255, 0.38) 0%, rgba(255, 255, 255, 0.05) 100%);
      pointer-events: none;
    }

    .tv-pill-primary:active { transform: scale(0.96); }
    .tv-pill-primary:disabled { opacity: 0.5; cursor: not-allowed; transform: none; }

    .tv-btn-secondary {
      height: 38px;
      padding: 0 14px;
      background: rgba(255, 255, 255, 0.10);
      border: 1px solid rgba(255, 255, 255, 0.12);
      border-radius: var(--tv-radius-pill);
      color: var(--tv-text-primary);
      font-size: 13px;
      font-weight: 600;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 6px;
      transition: background 0.14s ease, transform 0.14s var(--tv-ease-critique);
    }
    .tv-btn-secondary:hover { background: rgba(255, 255, 255, 0.16); }
    .tv-btn-secondary:active { transform: scale(0.96); }

    .tv-btn-danger {
      background: rgba(229, 9, 20, 0.15);
      border: 1px solid rgba(229, 9, 20, 0.30);
      color: #FF5A60;
      border-radius: var(--tv-radius-pill);
      padding: 6px 12px;
      font-size: 12px;
      font-weight: 600;
      cursor: pointer;
      transition: background 150ms ease-out, transform 150ms ease-out;
    }
    .tv-btn-danger:hover { background: rgba(229, 9, 20, 0.28); }
    .tv-btn-danger:active:not(:disabled) { transform: scale(0.96); }

    /* Profils — alignés ProfileEditorView / ProfileAvatarView */
    .profile-card {
      display: flex;
      align-items: center;
      gap: 12px;
      width: 100%;
      padding: 12px;
      background: rgba(0, 0, 0, 0.28);
      border: 1px solid transparent;
      border-radius: var(--tv-radius-control);
      box-shadow: 0 1px 0 rgba(255, 255, 255, 0.06), inset 0 0 0 1px var(--tv-border);
      margin-bottom: 10px;
      cursor: pointer;
      text-align: left;
      color: inherit;
      font: inherit;
      transition: transform 150ms ease-out, background-color 150ms ease-out, box-shadow 150ms ease-out;
    }
    .profile-card:active:not(:disabled) { transform: scale(0.96); }
    @media (hover: hover) {
      .profile-card:hover { background: rgba(255, 255, 255, 0.06); }
    }

    .profile-info {
      display: flex;
      align-items: center;
      gap: 12px;
      flex: 1;
      min-width: 0;
    }

    .profile-avatar {
      width: 44px;
      height: 44px;
      border-radius: 50%;
      --avatar-c: #4085F2;
      background: var(--avatar-c);
      display: flex;
      align-items: center;
      justify-content: center;
      color: #FFF;
      flex-shrink: 0;
      border: 1px solid transparent;
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.35);
    }
    .profile-avatar svg {
      width: 42%;
      height: 42%;
      display: block;
    }
    .profile-avatar-lg {
      width: 72px;
      height: 72px;
    }

    .profile-name-text {
      font-size: 14px;
      font-weight: 600;
      color: var(--tv-text-primary);
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .profile-subtext {
      font-size: 11px;
      color: var(--tv-text-tertiary);
    }

    .profile-edit-hint {
      font-size: 11px;
      font-weight: 600;
      color: var(--tv-text-tertiary);
      flex-shrink: 0;
    }

    .profile-editor {
      margin-top: 12px;
      padding: 14px;
      background: var(--tv-surface-subtle);
      border: 1px solid var(--tv-border);
      border-radius: calc(var(--tv-radius-control) + 14px);
      transition: opacity 200ms var(--tv-ease-critique);
    }
    .profile-editor[hidden] { display: none; }

    .profile-editor-head {
      display: flex;
      align-items: center;
      gap: 14px;
      margin-bottom: 14px;
    }

    .profile-editor-title {
      font-size: 15px;
      font-weight: 700;
      letter-spacing: -0.01em;
    }

    .profile-section-label {
      font-size: 11px;
      font-weight: 600;
      color: var(--tv-text-secondary);
      margin: 10px 0 8px;
      text-transform: none;
    }

    .swatch-row {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
    }

    .swatch {
      width: 36px;
      height: 36px;
      border-radius: 50%;
      border: 1px solid transparent;
      padding: 0;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      color: #fff;
      background: rgba(255, 255, 255, 0.10);
      box-shadow: none;
      appearance: none;
      -webkit-appearance: none;
      transition: transform 150ms ease-out, background-color 150ms ease-out, box-shadow 150ms ease-out, color 150ms ease-out;
      -webkit-tap-highlight-color: transparent;
    }
    .swatch:active:not(:disabled) { transform: scale(0.96); }
    .swatch[aria-checked="true"] {
      box-shadow: 0 0 0 2px #fff;
      border-color: transparent;
    }
    .swatch-color {
      background-color: var(--avatar-c);
      background-image: none;
    }
    .swatch-color[aria-checked="true"]::after {
      content: "";
      width: 10px;
      height: 6px;
      border-left: 2px solid #fff;
      border-bottom: 2px solid #fff;
      transform: rotate(-45deg) translateY(-1px);
    }
    .swatch-symbol[aria-checked="true"] {
      background: #fff;
      color: #111;
      box-shadow: none;
    }
    .swatch-symbol svg {
      width: 18px;
      height: 18px;
      display: block;
    }

    .profile-editor-actions {
      display: flex;
      flex-wrap: nowrap;
      align-items: stretch;
      gap: 8px;
      margin-top: 14px;
    }
    .profile-editor-actions .tv-pill-primary,
    .profile-editor-actions .tv-btn-secondary,
    .profile-editor-actions .tv-btn-danger {
      flex: 1 1 0;
      min-width: 0;
      height: 40px;
      margin: 0;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      padding: 0 12px;
      font-size: 13px;
    }
    .profile-editor-actions .tv-btn-danger {
      display: none;
    }
    .profile-editor-actions .tv-btn-danger.is-visible {
      display: inline-flex;
    }

    @media (prefers-reduced-motion: reduce) {
      .profile-card,
      .swatch,
      .profile-editor,
      .tv-btn-danger {
        transition: opacity 150ms ease, background-color 150ms ease !important;
      }
      .profile-card:active:not(:disabled),
      .swatch:active:not(:disabled),
      .tv-btn-danger:active:not(:disabled) {
        transform: none !important;
      }
    }

    /* Addons list */
    .addon-card {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 11px 12px;
      background: rgba(0, 0, 0, 0.28);
      border: 1px solid var(--tv-border);
      border-radius: var(--tv-radius-control);
      margin-bottom: 8px;
    }

    .addon-meta {
      flex: 1;
      margin-right: 10px;
      overflow: hidden;
    }

    .addon-name {
      font-size: 13px;
      font-weight: 600;
      color: var(--tv-text-primary);
      text-overflow: ellipsis;
      white-space: nowrap;
      overflow: hidden;
    }

    .addon-host {
      font-size: 11px;
      color: var(--tv-text-tertiary);
      text-overflow: ellipsis;
      white-space: nowrap;
      overflow: hidden;
    }

    /* User session bar */
    .user-bar {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 10px 14px;
      background: rgba(0, 0, 0, 0.35);
      border: 1px solid var(--tv-border);
      border-radius: var(--tv-radius-control);
      margin-bottom: 16px;
    }

    .user-badge {
      display: flex;
      flex-direction: column;
      overflow: hidden;
    }

    .user-email {
      font-size: 13px;
      font-weight: 600;
      color: var(--tv-text-primary);
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .user-foyer {
      font-size: 11px;
      color: var(--tv-match);
      font-weight: 500;
    }

    /* Toast */
    .tv-toast {
      position: fixed;
      bottom: 24px;
      left: 50%;
      transform: translateX(-50%) translateY(30px);
      background: rgba(20, 20, 20, 0.95);
      backdrop-filter: blur(20px);
      border: 1px solid var(--tv-border-focus);
      color: #FFF;
      padding: 10px 18px;
      border-radius: var(--tv-radius-pill);
      font-size: 13px;
      font-weight: 600;
      box-shadow: 0 12px 30px rgba(0, 0, 0, 0.7);
      opacity: 0;
      pointer-events: none;
      transition: transform 0.25s var(--tv-ease-critique), opacity 0.25s ease;
      z-index: 1000;
      display: flex;
      align-items: center;
      gap: 8px;
    }

    .tv-toast.visible {
      transform: translateX(-50%) translateY(0);
      opacity: 1;
    }

    .tv-toast.success { border-color: rgba(70, 211, 105, 0.45); }
    .tv-toast.error { border-color: rgba(229, 9, 20, 0.55); color: #FF5A60; }

    /* Alert */
    .error-alert {
      display: none;
      background: rgba(229, 9, 20, 0.14);
      border: 1px solid rgba(229, 9, 20, 0.35);
      border-radius: var(--tv-radius-control);
      padding: 10px 14px;
      margin-bottom: 14px;
      color: #FF5A60;
      font-size: 13px;
      font-weight: 500;
      text-align: center;
      line-height: 1.4;
    }

    .tv-spinner {
      width: 16px;
      height: 16px;
      border: 2px solid rgba(0, 0, 0, 0.20);
      border-top-color: #000000;
      border-radius: var(--tv-radius-pill);
      animation: spin 0.65s linear infinite;
    }
    @keyframes spin { to { transform: rotate(360deg); } }

    .footer-bar {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 6px;
      margin-top: 20px;
      font-size: 12px;
      color: var(--tv-text-tertiary);
    }
    .footer-dot {
      width: 4px;
      height: 4px;
      border-radius: var(--tv-radius-pill);
      background-color: var(--tv-text-tertiary);
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="tv-card">
      <!-- HEADER -->
      <div class="header">
        <div class="tv-brand-icon">
          <svg viewBox="0 0 24 24">
            <polygon points="6,3 20,12 6,21"/>
          </svg>
        </div>
        <h1 class="brand-title">Loge</h1>
        <p class="brand-subtitle" id="portal-sub">Synchronisation & Profils du Foyer</p>
      </div>

      <!-- VUE NON CONNECTÉ : AUTHENTIFICATION -->
      <div id="auth-panel">
        <div class="pairing-card" id="pairing-card-auth" style="display: ${prefillCode && prefillCode !== 'STREM-XXXX' ? 'flex' : 'none'};">
          <div class="pairing-device">
            <div class="pulse-dot"></div>
            <div>
              <div class="device-title">Apple TV à proximité</div>
              <div class="device-sub">Jumelage automatique</div>
            </div>
          </div>
          <div class="pairing-code-badge">${prefillCode || 'STREM-XXXX'}</div>
        </div>

        <div class="tv-segmented tv-segmented-2">
          <button type="button" class="tv-segment-item active" id="tab-login" onclick="setAuthMode('login')">Se connecter</button>
          <button type="button" class="tv-segment-item" id="tab-register" onclick="setAuthMode('register')">Créer un compte</button>
        </div>

        <div class="error-alert" id="auth-error"></div>

        <form onsubmit="handleAuthSubmit(event)">
          <div class="input-group">
            <label class="input-label" for="email">Adresse e-mail</label>
            <input type="email" id="email" class="tv-input" autocomplete="email" placeholder="nom@exemple.com" required>
          </div>

          <div class="input-group">
            <label class="input-label" for="password">Mot de passe</label>
            <input type="password" id="password" class="tv-input" autocomplete="current-password" placeholder="••••••••••••" required>
          </div>

          <button type="submit" class="tv-pill-primary" id="auth-submit-btn">
            <span id="auth-btn-text">Se connecter & Associer</span>
          </button>
        </form>
      </div>

      <!-- VUE CONNECTÉ : GESTION DU FOYER -->
      <div id="dash-panel" style="display: none;">
        <!-- Barre utilisateur & Déconnexion -->
        <div class="user-bar">
          <div class="user-badge">
            <span class="user-email" id="user-email-display">compte@stremio</span>
            <span class="user-foyer" id="user-foyer-display">Foyer Loge</span>
          </div>
          <button type="button" class="tv-btn-secondary" onclick="handleLogout()" style="padding: 0 10px; height: 32px; font-size: 11.5px;">Déconnexion</button>
        </div>

        <!-- Appel d'action Apple TV si un code d'appairage est présent -->
        <div id="dash-pair-banner" class="pairing-card" style="display: ${prefillCode && prefillCode !== 'STREM-XXXX' ? 'flex' : 'none'};">
          <div class="pairing-device">
            <div class="pulse-dot"></div>
            <div>
              <div class="device-title">Apple TV détectée</div>
              <div class="device-sub">${prefillCode}</div>
            </div>
          </div>
          <button type="button" class="tv-btn-secondary" id="dash-pair-btn" onclick="handleConfirmPairing()" style="background: var(--tv-match); color: #000; border: none; font-weight: 700;">Associer</button>
        </div>

        <!-- Segmented 4 onglets -->
        <div class="tv-segmented tv-segmented-5">
          <button type="button" class="tv-segment-item active" id="tab-btn-profiles" onclick="switchDashTab('profiles')">Profils</button>
          <button type="button" class="tv-segment-item" id="tab-btn-devices" onclick="switchDashTab('devices')">Appareils</button>
          <button type="button" class="tv-segment-item" id="tab-btn-addons" onclick="switchDashTab('addons')">Add-ons</button>
          <button type="button" class="tv-segment-item" id="tab-btn-foyer" onclick="switchDashTab('foyer')">Surnom</button>
          <button type="button" class="tv-segment-item" id="tab-btn-security" onclick="switchDashTab('security')">Sécurité</button>
        </div>

        <!-- TAB 1 : PROFILS -->
        <div id="tab-content-profiles">
          <div id="profiles-list" style="margin-bottom: 14px;"></div>
          <button type="button" class="tv-pill-primary" id="profile-create-btn" onclick="openProfileEditor()" style="height: 40px; font-size: 13px;">+ Ajouter un profil</button>

          <div id="profile-editor" class="profile-editor" hidden>
            <div class="profile-editor-head">
              <div id="profile-editor-preview" class="profile-avatar profile-avatar-lg" style="--avatar-c:#4085F2" aria-hidden="true"></div>
              <div>
                <div class="profile-editor-title" id="profile-editor-title">Ajouter un profil</div>
                <div class="profile-subtext" id="profile-editor-subtitle">Couleur et pictogramme synchronisés avec l’Apple TV</div>
              </div>
            </div>
            <div class="input-group" style="margin-bottom: 4px;">
              <label class="input-label" for="profile-editor-name">Nom du profil</label>
              <input type="text" id="profile-editor-name" class="tv-input" maxlength="16" placeholder="Ex: Salon" autocomplete="off" oninput="syncProfilePreview()">
            </div>
            <div class="profile-section-label">Couleur</div>
            <div id="profile-color-row" class="swatch-row" role="radiogroup" aria-label="Couleur"></div>
            <div class="profile-section-label">Pictogramme</div>
            <div id="profile-symbol-row" class="swatch-row" role="radiogroup" aria-label="Pictogramme"></div>
            <div class="profile-editor-actions">
              <button type="button" class="tv-pill-primary" id="profile-save-btn" onclick="saveProfileEditor()" style="height: 40px; flex: 1;">Enregistrer</button>
              <button type="button" class="tv-btn-secondary" onclick="closeProfileEditor()" style="height: 40px;">Annuler</button>
              <button type="button" class="tv-btn-danger" id="profile-delete-btn" onclick="handleDeleteProfileFromEditor()">Supprimer</button>
            </div>
          </div>
        </div>

        <!-- TAB : APPAREILS CONNECTÉS -->
        <div id="tab-content-devices" style="display: none;">
          <div style="font-size: 12px; color: var(--tv-text-secondary); margin-bottom: 10px; line-height: 1.45;">
            Appareils liés au compte. Une Apple TV n’apparaît qu’après jumelage ou sync avec une version récente. La déconnecter coupe la sync, pas les données locales.
          </div>
          <div id="devices-list" style="margin-bottom: 14px;"></div>
          <button type="button" class="tv-btn-secondary" id="revoke-others-btn" onclick="handleRevokeOthers()" style="width: 100%; height: 40px; margin-bottom: 8px;">Déconnecter tous les autres appareils</button>
          <button type="button" class="tv-btn-danger" onclick="handleLogout()" style="width: 100%; height: 40px; display: inline-flex; align-items: center; justify-content: center;">Déconnexion de ce navigateur</button>
        </div>

        <!-- TAB 2 : ADD-ONS -->
        <div id="tab-content-addons" style="display: none;">
          <div style="font-size: 12px; color: var(--tv-text-secondary); margin-bottom: 10px;">
            Extensions synchronisées avec toutes vos Apple TV du foyer.
          </div>
          <div id="addons-list" style="margin-bottom: 14px;"></div>

          <div style="background: var(--tv-surface-subtle); border: 1px dashed var(--tv-border); border-radius: var(--tv-radius-control); padding: 12px;">
            <div style="font-size: 12.5px; font-weight: 600; margin-bottom: 6px;">Installer une extension</div>
            <input type="url" id="new-addon-url" class="tv-input" placeholder="https://.../manifest.json" style="height: 38px; margin-bottom: 8px;">
            <button type="button" class="tv-pill-primary" onclick="handleAddAddon()" style="height: 38px; font-size: 13px;">+ Installer l'extension</button>
          </div>
        </div>

        <!-- TAB 3 : SURNOM DU FOYER -->
        <div id="tab-content-foyer" style="display: none;">
          <div style="font-size: 12.5px; color: var(--tv-text-secondary); margin-bottom: 12px; line-height: 1.45;">
            Donnez un surnom à votre compte pour reconnaître facilement ce foyer sur l'Apple TV (ex: « Maison Principale », « Salon », « Famille Briolon »).
          </div>
          <div class="input-group">
            <label class="input-label" for="foyer-nickname-input">Surnom du compte</label>
            <input type="text" id="foyer-nickname-input" class="tv-input" placeholder="Ex: Maison de vacances" maxlength="40">
          </div>
          <button type="button" class="tv-pill-primary" onclick="handleSaveNickname()">Enregistrer le surnom</button>
        </div>

        <!-- TAB 4 : SÉCURITÉ / MOT DE PASSE -->
        <div id="tab-content-security" style="display: none;">
          <div style="font-size: 12.5px; color: var(--tv-text-secondary); margin-bottom: 12px;">
            Modifiez le mot de passe de votre compte Loge.
          </div>
          <div class="input-group">
            <label class="input-label" for="cur-pwd">Mot de passe actuel</label>
            <input type="password" id="cur-pwd" class="tv-input" placeholder="••••••••••••" autocomplete="current-password">
          </div>
          <div class="input-group">
            <label class="input-label" for="new-pwd">Nouveau mot de passe (min. 6 car.)</label>
            <input type="password" id="new-pwd" class="tv-input" placeholder="••••••••••••" autocomplete="new-password">
          </div>
          <button type="button" class="tv-pill-primary" onclick="handleChangePassword()">Mettre à jour le mot de passe</button>
        </div>
      </div>
    </div>

    <!-- PIED DE PAGE -->
    <div class="footer-bar">
      <span>Loge 2.0</span>
      <span class="footer-dot"></span>
      <span>Cloudflare D1</span>
      <span class="footer-dot"></span>
      <span>Chiffré</span>
    </div>
  </div>

  <!-- TOAST FEEDBACK -->
  <div class="tv-toast" id="tv-toast">Notification</div>

  <script>
    let authMode = 'login';
    const pairCode = "${prefillCode}";
    let cachedProfiles = [];
    let editingProfileId = null;
    let draftAvatar = { color: 'blue', symbol: 'face.smiling' };

    // Source of truth: Sources/Models/Profile.swift + ProfileAvatarView.swift
    const AVATAR_COLORS = [
      { id: 'red', hex: '#E63338' },
      { id: 'orange', hex: '#FA8C26' },
      { id: 'yellow', hex: '#F7C733' },
      { id: 'green', hex: '#40C273' },
      { id: 'teal', hex: '#2EB2BD' },
      { id: 'blue', hex: '#4085F2' },
      { id: 'purple', hex: '#9461EB' },
      { id: 'pink', hex: '#F2619E' }
    ];
    const AVATAR_SYMBOLS = [
      'face.smiling', 'star.fill', 'gamecontroller.fill', 'popcorn.fill',
      'moon.stars.fill', 'bolt.fill', 'heart.fill', 'pawprint.fill',
      'flame.fill', 'leaf.fill'
    ];

    function avatarColorHex(id) {
      const hit = AVATAR_COLORS.find(function(c) { return c.id === id; });
      return hit ? hit.hex : '#4085F2';
    }

    function avatarSymbolSvg(symbol) {
      const paths = {
        'face.smiling': '<circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="1.8"/><circle cx="9" cy="10" r="1.15" fill="currentColor"/><circle cx="15" cy="10" r="1.15" fill="currentColor"/><path d="M8.2 14.2c1.3 1.7 2.9 2.4 3.8 2.4s2.5-.7 3.8-2.4" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>',
        'star.fill': '<path fill="currentColor" d="M12 3.1l2.35 4.76 5.25.76-3.8 3.7.9 5.24L12 15.1l-4.7 2.46.9-5.24-3.8-3.7 5.25-.76z"/>',
        'gamecontroller.fill': '<path fill="currentColor" d="M8.2 8.2h7.6c2.4 0 4.2 2.1 3.8 4.5l-.5 2.8c-.3 1.7-1.8 2.9-3.5 2.9h-7.2c-1.7 0-3.2-1.2-3.5-2.9l-.5-2.8c-.4-2.4 1.4-4.5 3.8-4.5zm1.3 2.2v1.4H8.1v1.6h1.4V15h1.6v-1.6h1.4v-1.6h-1.4v-1.4H9.5zm6.2 1.1a1.05 1.05 0 110 2.1 1.05 1.05 0 010-2.1zm1.9 1.9a1.05 1.05 0 110 2.1 1.05 1.05 0 010-2.1z"/>',
        'popcorn.fill': '<path fill="currentColor" d="M7.2 10.2h9.6l-.7 8.1c-.1.9-.9 1.6-1.8 1.6H9.7c-.9 0-1.7-.7-1.8-1.6l-.7-8.1zm1.6-5.2.6 1.8 1.2-.9.5 1.6 1.1-.7.6 1.5 1.1-.5.4 1.4h-7l.4-1.4 1.1.5.6-1.5 1.1.7.5-1.6 1.2.9z"/>',
        'moon.stars.fill': '<path fill="currentColor" d="M14.8 3.5a7.5 7.5 0 1 0 5.7 10.2 6.1 6.1 0 0 1-5.7-10.2zM18.1 5l.55 1.2 1.2.55-1.2.55L18.1 8.5l-.55-1.2-1.2-.55 1.2-.55z"/>',
        'bolt.fill': '<path fill="currentColor" d="M13.2 2.5L6.8 13.1h4.1l-.9 8.4 7.2-11.4h-4.3z"/>',
        'heart.fill': '<path fill="currentColor" d="M12 20.2s-7.2-4.4-9.1-8.3C1.4 9 2.6 6.2 5.3 5.5c1.7-.4 3.3.3 4.2 1.6.9-1.3 2.5-2 4.2-1.6 2.7.7 3.9 3.5 2.4 6.4-1.9 3.9-9.1 8.3-9.1 8.3z"/>',
        'pawprint.fill': '<path fill="currentColor" d="M8.1 9.1a1.7 1.7 0 112.3-2.5 1.7 1.7 0 01-2.3 2.5zm5.5 0a1.7 1.7 0 112.3-2.5 1.7 1.7 0 01-2.3 2.5zM6.2 12.4a1.55 1.55 0 112.1-2.2 1.55 1.55 0 01-2.1 2.2zm9.5 0a1.55 1.55 0 112.1-2.2 1.55 1.55 0 01-2.1 2.2zM12 13.2c-2.4 0-4.2 1.9-3.7 3.6.4 1.3 1.9 2.2 3.7 2.2s3.3-.9 3.7-2.2c.5-1.7-1.3-3.6-3.7-3.6z"/>',
        'flame.fill': '<path fill="currentColor" d="M12.2 2.8c.2 2.1 1.4 3.3 2.6 4.5 1.4 1.4 2.7 2.8 2.7 5.1 0 3.2-2.4 5.8-5.5 5.8S6.5 15.6 6.5 12.4c0-1.7.7-3.1 1.7-4.3.5 1.6 1.5 2.4 2.5 2.4-.2-1.8.4-3.5 1.5-5.7z"/>',
        'leaf.fill': '<path fill="currentColor" d="M19.2 4.8c-4.8-.4-9.3 1.2-11.6 5.1-1.5 2.5-1.6 5.4-.4 7.7l-2 2.1 1.3 1.2 2-2.1c2.3 1 5.1.7 7.4-.9 3.7-2.6 5.1-7.3 3.3-13.1z"/>'
      };
      return '<svg viewBox="0 0 24 24" aria-hidden="true">' + (paths[symbol] || paths['face.smiling']) + '</svg>';
    }

    function parseAvatar(p) {
      let avatar = { color: 'blue', symbol: 'face.smiling' };
      try {
        if (typeof p.avatar_json === 'string') avatar = JSON.parse(p.avatar_json);
        else if (p.avatar) avatar = p.avatar;
      } catch (_) {}
      if (!AVATAR_COLORS.some(function(c) { return c.id === avatar.color; })) avatar.color = 'blue';
      if (AVATAR_SYMBOLS.indexOf(avatar.symbol) < 0) avatar.symbol = 'face.smiling';
      return avatar;
    }

    function suggestedAvatar(profiles) {
      const usedColors = new Set(profiles.map(function(p) { return parseAvatar(p).color; }));
      const usedSymbols = new Set(profiles.map(function(p) { return parseAvatar(p).symbol; }));
      return {
        color: (AVATAR_COLORS.find(function(c) { return !usedColors.has(c.id); }) || AVATAR_COLORS[profiles.length % AVATAR_COLORS.length]).id,
        symbol: AVATAR_SYMBOLS.find(function(s) { return !usedSymbols.has(s); }) || AVATAR_SYMBOLS[profiles.length % AVATAR_SYMBOLS.length]
      };
    }
    let accountData = null;

    // Toast
    let toastTimeout = null;
    function showToast(msg, type = 'normal') {
      const t = document.getElementById('tv-toast');
      t.innerText = msg;
      t.className = 'tv-toast visible ' + type;
      clearTimeout(toastTimeout);
      toastTimeout = setTimeout(() => {
        t.className = 'tv-toast';
      }, 3000);
    }

    // Persist across visits (not sessionStorage): same origin as the QR keeps the foyer signed in.
    function readStoredAuth() {
      let token = localStorage.getItem('loge_token');
      let email = localStorage.getItem('loge_email');
      if (!token) {
        token = localStorage.getItem('stremiotv_token');
        if (token) {
          localStorage.setItem('loge_token', token);
          localStorage.removeItem('stremiotv_token');
          email = localStorage.getItem('stremiotv_email') || email;
          if (email) {
            localStorage.setItem('loge_email', email);
            localStorage.removeItem('stremiotv_email');
          }
        }
      }
      return { token: token || null, email: email || null };
    }

    function hasPairCode() {
      return !!(pairCode && pairCode !== 'STREM-XXXX');
    }

    // Gestion de l'état de démarrage
    document.addEventListener('DOMContentLoaded', async () => {
      const { token } = readStoredAuth();
      if (!token) return;
      await loadDashboard();
      // Already signed in on the phone: scanning the TV QR confirms without re-typing credentials.
      if (localStorage.getItem('loge_token') && hasPairCode()) {
        await handleConfirmPairing();
      }
    });

    function setAuthMode(mode) {
      authMode = mode;
      document.getElementById('tab-login').classList.toggle('active', mode === 'login');
      document.getElementById('tab-register').classList.toggle('active', mode === 'register');
      document.getElementById('auth-btn-text').innerText = mode === 'login' ? "Se connecter & Associer" : "Créer le compte & Associer";
      document.getElementById('auth-error').style.display = 'none';
    }

    async function handleAuthSubmit(e) {
      e.preventDefault();
      const email = document.getElementById('email').value.trim();
      const password = document.getElementById('password').value;
      const errorAlert = document.getElementById('auth-error');
      const submitBtn = document.getElementById('auth-submit-btn');
      const btnText = document.getElementById('auth-btn-text');

      errorAlert.style.display = 'none';
      submitBtn.disabled = true;
      btnText.innerHTML = '<div class="tv-spinner"></div>';

      try {
        const endpoint = authMode === 'register' ? '/api/auth/register' : '/api/auth/login';
        const res = await fetch(endpoint, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email, password, deviceName: 'Navigateur web', deviceModel: browserLabel() })
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Erreur d\\'authentification');

        localStorage.setItem('loge_token', data.token);
        localStorage.setItem('loge_email', email);

        if (hasPairCode()) {
          try {
            await fetch('/api/device/confirm', {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ' + data.token
              },
              body: JSON.stringify({ code: pairCode })
            });
            showToast('Apple TV jumelée avec succès !', 'success');
          } catch (_) {}
        }

        await loadDashboard();
      } catch (err) {
        errorAlert.innerText = err.message;
        errorAlert.style.display = 'block';
        submitBtn.disabled = false;
        btnText.innerText = authMode === 'login' ? "Se connecter & Associer" : "Créer le compte & Associer";
      }
    }

    async function loadDashboard() {
      const token = readStoredAuth().token;
      if (!token) return;

      try {
        const res = await fetch('/api/account', {
          headers: {
            'Authorization': 'Bearer ' + token,
            'X-Device-Name': 'Navigateur web',
            'X-Device-Model': browserLabel()
          }
        });
        if (res.status === 401) {
          handleLogout();
          return;
        }
        accountData = await res.json();

        // Remplir UI
        document.getElementById('auth-panel').style.display = 'none';
        document.getElementById('dash-panel').style.display = 'block';
        document.getElementById('portal-sub').innerText = 'Espace Gestion du Foyer';

        if (accountData.token) localStorage.setItem('loge_token', accountData.token);
        document.getElementById('user-email-display').innerText = accountData.email || localStorage.getItem('loge_email') || 'Compte actif';
        document.getElementById('user-foyer-display').innerText = accountData.nickname ? 'Foyer : ' + accountData.nickname : 'Foyer Loge';
        document.getElementById('foyer-nickname-input').value = accountData.nickname || '';

        renderProfiles(accountData.profiles || []);
        renderAddons(accountData.addons || []);
        await loadDevices();
      } catch (e) {
        showToast('Erreur lors du chargement des données', 'error');
      }
    }

    function renderProfiles(profiles) {
      cachedProfiles = profiles || [];
      const container = document.getElementById('profiles-list');
      const createBtn = document.getElementById('profile-create-btn');
      createBtn.style.display = cachedProfiles.length >= 6 || !document.getElementById('profile-editor').hidden ? 'none' : 'flex';

      if (!cachedProfiles.length) {
        container.innerHTML = '<div style="font-size: 13px; color: var(--tv-text-tertiary); text-align: center; padding: 12px;">Aucun profil trouvé.</div>';
        return;
      }

      container.innerHTML = cachedProfiles.map(function(p) {
        const avatar = parseAvatar(p);
        return '<button type="button" class="profile-card" onclick="openProfileEditor(\\'' + p.id + '\\')" aria-label="Modifier ' + escapeHtml(p.name) + '">' +
          '<div class="profile-info">' +
            '<div class="profile-avatar" style="--avatar-c:' + avatarColorHex(avatar.color) + '">' + avatarSymbolSvg(avatar.symbol) + '</div>' +
            '<div style="min-width:0">' +
              '<div class="profile-name-text">' + escapeHtml(p.name) + '</div>' +
              '<div class="profile-subtext">Modifier couleur et pictogramme</div>' +
            '</div>' +
          '</div>' +
          '<span class="profile-edit-hint">Modifier</span>' +
        '</button>';
      }).join('');
    }

    function syncProfilePreview() {
      const preview = document.getElementById('profile-editor-preview');
      const nameInput = document.getElementById('profile-editor-name');
      preview.style.setProperty('--avatar-c', avatarColorHex(draftAvatar.color));
      preview.innerHTML = avatarSymbolSvg(draftAvatar.symbol);
      const liveName = (nameInput.value || '').trim();
      document.getElementById('profile-editor-subtitle').textContent = liveName || (editingProfileId ? 'Modifier le profil' : 'Nouveau profil');
    }

    function renderAvatarPickers() {
      const colorRow = document.getElementById('profile-color-row');
      const symbolRow = document.getElementById('profile-symbol-row');
      colorRow.innerHTML = AVATAR_COLORS.map(function(c) {
        return '<button type="button" class="swatch swatch-color" role="radio" aria-checked="' + (draftAvatar.color === c.id) + '" aria-label="' + c.id + '" style="--avatar-c:' + c.hex + '" onclick="setDraftColor(\\'' + c.id + '\\')"></button>';
      }).join('');
      symbolRow.innerHTML = AVATAR_SYMBOLS.map(function(s) {
        return '<button type="button" class="swatch swatch-symbol" role="radio" aria-checked="' + (draftAvatar.symbol === s) + '" aria-label="' + s + '" onclick="setDraftSymbol(\\'' + s + '\\')">' + avatarSymbolSvg(s) + '</button>';
      }).join('');
    }

    function setDraftColor(color) {
      draftAvatar.color = color;
      renderAvatarPickers();
      syncProfilePreview();
    }

    function setDraftSymbol(symbol) {
      draftAvatar.symbol = symbol;
      renderAvatarPickers();
      syncProfilePreview();
    }

    function openProfileEditor(id) {
      editingProfileId = id || null;
      const editor = document.getElementById('profile-editor');
      const deleteBtn = document.getElementById('profile-delete-btn');
      const nameInput = document.getElementById('profile-editor-name');
      document.getElementById('profile-create-btn').style.display = 'none';

      if (editingProfileId) {
        const profile = cachedProfiles.find(function(p) { return p.id === editingProfileId; });
        if (!profile) return;
        const avatar = parseAvatar(profile);
        draftAvatar = { color: avatar.color, symbol: avatar.symbol };
        nameInput.value = profile.name || '';
        document.getElementById('profile-editor-title').textContent = 'Modifier le profil';
        deleteBtn.classList.toggle('is-visible', cachedProfiles.length > 1);
      } else {
        draftAvatar = suggestedAvatar(cachedProfiles);
        nameInput.value = 'Profil ' + (cachedProfiles.length + 1);
        document.getElementById('profile-editor-title').textContent = 'Ajouter un profil';
        deleteBtn.classList.remove('is-visible');
      }

      editor.hidden = false;
      renderAvatarPickers();
      syncProfilePreview();
      nameInput.focus();
      nameInput.select();
    }

    function closeProfileEditor() {
      editingProfileId = null;
      document.getElementById('profile-editor').hidden = true;
      document.getElementById('profile-create-btn').style.display = cachedProfiles.length >= 6 ? 'none' : 'flex';
    }

    async function saveProfileEditor() {
      const token = localStorage.getItem('loge_token');
      const name = document.getElementById('profile-editor-name').value.trim();
      if (!name) {
        showToast('Donnez un nom au profil.', 'error');
        return;
      }
      if (name.length > 16) {
        showToast('Le nom est trop long (16 caractères maximum).', 'error');
        return;
      }

      const body = {
        name: name,
        avatar: { color: draftAvatar.color, symbol: draftAvatar.symbol }
      };
      if (editingProfileId) body.id = editingProfileId;

      try {
        const res = await fetch('/api/account/profile', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + token
          },
          body: JSON.stringify(body)
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Erreur');
        showToast(editingProfileId ? 'Profil mis à jour.' : 'Profil « ' + name + ' » ajouté !', 'success');
        closeProfileEditor();
        await loadDashboard();
      } catch (err) {
        showToast(err.message, 'error');
      }
    }

    async function handleDeleteProfileFromEditor() {
      if (!editingProfileId) return;
      await handleDeleteProfile(editingProfileId);
    }

    function renderAddons(addons) {
      const container = document.getElementById('addons-list');
      if (!addons.length) {
        container.innerHTML = '<div style="font-size: 13px; color: var(--tv-text-tertiary); text-align: center; padding: 12px;">Aucune extension personnalisée installée.</div>';
        return;
      }

      container.innerHTML = addons.map(function(url) {
        let host = url;
        try { host = new URL(url).hostname; } catch (_) {}
        return '<div class="addon-card">' +
          '<div class="addon-meta">' +
            '<div class="addon-name">' + escapeHtml(host) + '</div>' +
            '<div class="addon-host">' + escapeHtml(url) + '</div>' +
          '</div>' +
          '<button type="button" class="tv-btn-danger" onclick="handleDeleteAddon(\\'' + encodeURIComponent(url) + '\\')">Retirer</button>' +
        '</div>';
      }).join('');
    }

    function browserLabel() {
      const ua = navigator.userAgent;
      if (/iPhone/.test(ua)) return 'iPhone';
      if (/iPad/.test(ua)) return 'iPad';
      if (/Android/.test(ua)) return 'Android';
      if (/Macintosh/.test(ua)) return 'Mac';
      if (/Windows/.test(ua)) return 'PC Windows';
      return '';
    }

    function formatLastSeen(ms) {
      if (!ms) return '';
      const minutes = Math.round((Date.now() - ms) / 60000);
      if (minutes < 10) return 'Actif récemment';
      if (minutes < 60) return 'Vu il y a ' + minutes + ' min';
      const hours = Math.round(minutes / 60);
      if (hours < 24) return 'Vu il y a ' + hours + ' h';
      return 'Vu le ' + new Date(ms).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long' });
    }

    async function loadDevices() {
      const token = localStorage.getItem('loge_token');
      try {
        const res = await fetch('/api/devices', {
          headers: {
            'Authorization': 'Bearer ' + token,
            'X-Device-Name': 'Navigateur web',
            'X-Device-Model': browserLabel()
          }
        });
        if (res.status === 401) { handleLogout(); return; }
        const data = await res.json();
        if (data.token) localStorage.setItem('loge_token', data.token);
        renderDevices(data.devices || []);
      } catch (_) {
        document.getElementById('devices-list').innerHTML = '';
      }
    }

    function renderDevices(devices) {
      const container = document.getElementById('devices-list');
      const others = devices.filter(function(d) { return !d.isCurrent; });
      document.getElementById('revoke-others-btn').style.display = others.length ? 'flex' : 'none';
      if (!devices.length) {
        container.innerHTML = '<div style="font-size: 13px; color: var(--tv-text-tertiary); text-align: center; padding: 12px;">Aucun appareil connecté. Les appareils connectés avant cette version n\\'apparaissent pas ici.</div>';
        return;
      }
      container.innerHTML = devices.map(function(d) {
        const subtitle = [d.model, formatLastSeen(d.lastSeenAtMs)].filter(Boolean).join(' · ');
        const action = d.isCurrent
          ? '<span class="device-current">Cet appareil</span>'
          : '<button type="button" class="tv-btn-danger" data-id="' + escapeHtml(d.id) + '" onclick="handleRevokeDevice(this.dataset.id)">Déconnecter</button>';
        return '<div class="addon-card">' +
          '<div class="addon-meta">' +
            '<div class="addon-name">' + escapeHtml(d.name) + '</div>' +
            '<div class="addon-host">' + escapeHtml(subtitle) + '</div>' +
          '</div>' + action +
        '</div>';
      }).join('');
    }

    async function handleRevokeDevice(id) {
      const token = localStorage.getItem('loge_token');
      try {
        const res = await fetch('/api/devices/revoke', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token },
          body: JSON.stringify({ id: id })
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Erreur');
        showToast('Appareil déconnecté.', 'success');
        await loadDevices();
      } catch (err) {
        showToast(err.message, 'error');
      }
    }

    async function handleRevokeOthers() {
      if (!confirm('Déconnecter tous les autres appareils ? Ils devront se reconnecter pour se synchroniser.')) return;
      const token = localStorage.getItem('loge_token');
      try {
        const res = await fetch('/api/devices/revoke-others', {
          method: 'POST',
          headers: { 'Authorization': 'Bearer ' + token }
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Erreur');
        showToast('Autres appareils déconnectés.', 'success');
        await loadDevices();
      } catch (err) {
        showToast(err.message, 'error');
      }
    }

    function switchDashTab(tab) {
      ['profiles', 'devices', 'addons', 'foyer', 'security'].forEach(t => {
        document.getElementById('tab-btn-' + t).classList.toggle('active', t === tab);
        document.getElementById('tab-content-' + t).style.display = t === tab ? 'block' : 'none';
      });
    }

    async function handleConfirmPairing() {
      const token = readStoredAuth().token;
      if (!token || !hasPairCode()) return;
      const btn = document.getElementById('dash-pair-btn');
      if (btn) {
        btn.disabled = true;
        btn.innerText = 'Liaison...';
      }

      try {
        const res = await fetch('/api/device/confirm', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + token
          },
          body: JSON.stringify({ code: pairCode })
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Erreur lors du jumelage');

        showToast('Apple TV jumelée avec succès !', 'success');
        const banner = document.getElementById('dash-pair-banner');
        if (banner) banner.style.display = 'none';
      } catch (err) {
        showToast(err.message, 'error');
        if (btn) {
          btn.disabled = false;
          btn.innerText = 'Associer';
        }
      }
    }

    async function handleSaveNickname() {
      const token = localStorage.getItem('loge_token');
      const nickname = document.getElementById('foyer-nickname-input').value.trim();

      try {
        const res = await fetch('/api/account/nickname', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + token
          },
          body: JSON.stringify({ nickname })
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Erreur');

        showToast('Surnom du foyer enregistré !', 'success');
        document.getElementById('user-foyer-display').innerText = nickname ? 'Foyer : ' + nickname : 'Foyer Loge';
      } catch (err) {
        showToast(err.message, 'error');
      }
    }

    async function handleChangePassword() {
      const token = localStorage.getItem('loge_token');
      const currentPassword = document.getElementById('cur-pwd').value;
      const newPassword = document.getElementById('new-pwd').value;

      if (!currentPassword || !newPassword) {
        showToast('Veuillez renseigner tous les champs.', 'error');
        return;
      }

      try {
        const res = await fetch('/api/account/password', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + token
          },
          body: JSON.stringify({ currentPassword, newPassword })
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Erreur');

        showToast('Mot de passe modifié avec succès !', 'success');
        document.getElementById('cur-pwd').value = '';
        document.getElementById('new-pwd').value = '';
      } catch (err) {
        showToast(err.message, 'error');
      }
    }

    async function handleDeleteProfile(id) {
      const profile = cachedProfiles.find(function(p) { return p.id === id; });
      const label = profile ? '« ' + profile.name + ' »' : 'ce profil';
      if (!confirm('Supprimer le profil ' + label + ' ? Sa liste et sa progression de lecture seront perdues.')) return;
      const token = localStorage.getItem('loge_token');

      try {
        const res = await fetch('/api/account/profile', {
          method: 'DELETE',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + token
          },
          body: JSON.stringify({ id })
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Erreur');

        showToast('Profil supprimé.', 'success');
        closeProfileEditor();
        await loadDashboard();
      } catch (err) {
        showToast(err.message, 'error');
      }
    }

    async function handleAddAddon() {
      const token = localStorage.getItem('loge_token');
      const input = document.getElementById('new-addon-url');
      const manifestUrl = input.value.trim();

      if (!manifestUrl) {
        showToast('Veuillez renseigner une URL manifest.json', 'error');
        return;
      }

      try {
        const res = await fetch('/api/account/addons', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + token
          },
          body: JSON.stringify({ manifestUrl })
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Erreur');

        showToast('Extension installée avec succès !', 'success');
        input.value = '';
        await loadDashboard();
      } catch (err) {
        showToast(err.message, 'error');
      }
    }

    async function handleDeleteAddon(encodedUrl) {
      const manifestUrl = decodeURIComponent(encodedUrl);
      if (!confirm('Retirer cette extension ?')) return;
      const token = localStorage.getItem('loge_token');

      try {
        const res = await fetch('/api/account/addons', {
          method: 'DELETE',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + token
          },
          body: JSON.stringify({ manifestUrl })
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Erreur');

        showToast('Extension retirée.', 'success');
        await loadDashboard();
      } catch (err) {
        showToast(err.message, 'error');
      }
    }

    function handleLogout() {
      const token = readStoredAuth().token;
      // Best effort: the session is revoked server-side so it leaves the device list.
      if (token) fetch('/api/auth/logout', { method: 'POST', headers: { 'Authorization': 'Bearer ' + token } }).catch(function() {});
      localStorage.removeItem('loge_token');
      localStorage.removeItem('loge_email');
      localStorage.removeItem('stremiotv_token');
      localStorage.removeItem('stremiotv_email');
      document.getElementById('dash-panel').style.display = 'none';
      document.getElementById('auth-panel').style.display = 'block';
      document.getElementById('portal-sub').innerText = 'Synchronisation multi-écrans pour le foyer';
      showToast('Déconnecté.');
    }

    function escapeHtml(str) {
      if (!str) return '';
      return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }
  </script>
</body>
</html>`;
}

const privacyPolicyText = `Politique de confidentialité — Loge

Dernière mise à jour : 11 novembre 2026

Loge est une application Apple TV qui vous permet de parcourir des catalogues et de lire des flux que vous configurez vous-même (addons / sources). Loge n’héberge aucun contenu vidéo.

Données collectées si vous créez un compte
• Adresse e-mail et mot de passe (hashé) pour l’authentification
• Nom et modèle de l’appareil pour la liste des sessions
• Profils, « Ma liste » et progression de lecture synchronisés entre vos appareils

Finalité
• Fournir le compte foyer, l’appairage et la synchronisation multi-appareils
• Permettre la révocation d’une session (déconnexion d’un appareil)

Conservation et sécurité
• Les données sont stockées sur Cloudflare (Worker + base D1)
• Les jetons d’accès sont liés à une session révocable
• Pas de publicité, pas de tracking publicitaire, pas de revente de données

Vos droits
• Vous pouvez supprimer des profils, vous déconnecter, ou demander la suppression du compte via le support

Contact
• support : https://loge-api.stremiotv-home.workers.dev/support`;

const privacyPolicyHTML = `<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Confidentialité — Loge</title></head>
<body style="font-family:system-ui,sans-serif;max-width:40rem;margin:2rem auto;padding:0 1rem;line-height:1.5"><pre style="white-space:pre-wrap;font-family:inherit">${privacyPolicyText.replace(/</g, '&lt;')}</pre></body></html>`;

const supportHTML = `<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Support — Loge</title>
<style>body{font-family:system-ui,sans-serif;max-width:40rem;margin:2rem auto;padding:0 1rem;line-height:1.5;color:#111;background:#fafafa}a{color:#c00}</style></head>
<body>
<h1>Support Loge</h1>
<p>Loge est un lecteur Apple TV : vous apportez vos propres addons et sources. L’app ne fournit aucun flux.</p>
<ul>
<li>Compte &amp; appareils : ouvrez <a href="/">l’espace compte</a> pour jumeler une Apple TV ou gérer les sessions.</li>
<li>Confidentialité : <a href="/privacy">politique de confidentialité</a>.</li>
<li>Contact : écrivez à <a href="mailto:a.briolon92@gmail.com">a.briolon92@gmail.com</a>.</li>
</ul>
</body></html>`;
