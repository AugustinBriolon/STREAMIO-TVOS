/**
 * Cloudflare Worker Backend for StremioTV
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

async function generateToken(accountId: string, secret: string): Promise<string> {
  const payload = {
    sub: accountId,
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

async function verifyToken(token: string, secret: string): Promise<string | null> {
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
    return payload.sub;
  } catch {
    return null;
  }
}

function json(data: any, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
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
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
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

    // Helper auth header
    const authHeader = request.headers.get('Authorization') || '';
    const token = authHeader.replace(/^Bearer\s+/i, '');

    // MARK: - POST /api/auth/register
    if (url.pathname === '/api/auth/register' && request.method === 'POST') {
      const { email, password } = (await request.json()) as any;
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

      const jwt = await generateToken(accountId, env.JWT_SECRET);
      return json({ token: jwt, accountId, email: email.toLowerCase() });
    }

    // MARK: - POST /api/auth/login
    if (url.pathname === '/api/auth/login' && request.method === 'POST') {
      const { email, password } = (await request.json()) as any;
      if (!email || !password) return json({ error: 'Identifiants requis.' }, 400);
      const pwHash = await hashPassword(password);
      const account: any = await env.DB.prepare('SELECT id, email FROM accounts WHERE email = ? AND password_hash = ?')
        .bind(email.toLowerCase(), pwHash)
        .first();
      if (!account) {
        return json({ error: 'Email ou mot de passe incorrect.' }, 401);
      }
      const jwt = await generateToken(account.id, env.JWT_SECRET);
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
      const { code } = (await request.json()) as any;
      if (!code) return json({ error: 'Code requis' }, 400);

      const entry: any = await env.DB.prepare(
        'SELECT account_id, status, expires_at FROM pairing_codes WHERE code = ?'
      )
        .bind(code)
        .first();

      if (!entry) return json({ error: 'Code inconnu ou expiré' }, 404);

      if (new Date(entry.expires_at) < new Date()) {
        return json({ status: 'expired' });
      }

      if (entry.status === 'authorized' && entry.account_id) {
        const account: any = await env.DB.prepare('SELECT email FROM accounts WHERE id = ?')
          .bind(entry.account_id)
          .first();
        const jwt = await generateToken(entry.account_id, env.JWT_SECRET);
        return json({ status: 'authorized', token: jwt, email: account?.email });
      }

      return json({ status: 'pending' });
    }

    // MARK: - POST /api/device/confirm (Le navigateur du smartphone confirme l'appairage)
    if (url.pathname === '/api/device/confirm' && request.method === 'POST') {
      const accountId = await verifyToken(token, env.JWT_SECRET);
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
      const accountId = await verifyToken(token, env.JWT_SECRET);
      if (!accountId) return json({ error: 'Non authentifié' }, 401);

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
      });
    }

    // MARK: - POST /api/account/nickname
    if (url.pathname === '/api/account/nickname' && request.method === 'POST') {
      const accountId = await verifyToken(token, env.JWT_SECRET);
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
      const accountId = await verifyToken(token, env.JWT_SECRET);
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
      const accountId = await verifyToken(token, env.JWT_SECRET);
      if (!accountId) return json({ error: 'Non authentifié' }, 401);

      const { id, name, avatar } = (await request.json().catch(() => ({}))) as any;
      const cleanName = (name || '').trim();
      if (!cleanName) return json({ error: 'Le nom du profil ne peut pas être vide.' }, 400);

      const profileId = id || crypto.randomUUID();
      const avatarJson = avatar ? JSON.stringify(avatar) : JSON.stringify({ color: 'blue', symbol: 'face.smiling' });

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
      const accountId = await verifyToken(token, env.JWT_SECRET);
      if (!accountId) return json({ error: 'Non authentifié' }, 401);

      const { id } = (await request.json().catch(() => ({}))) as any;
      if (!id) return json({ error: 'Identifiant de profil requis.' }, 400);

      const countRes: any = await env.DB.prepare('SELECT count(*) as c FROM profiles WHERE account_id = ?').bind(accountId).first();
      if (countRes && countRes.c <= 1) {
        return json({ error: 'Impossible de supprimer le dernier profil restant.' }, 400);
      }

      await env.DB.prepare('DELETE FROM profiles WHERE account_id = ? AND id = ?')
        .bind(accountId, id)
        .run();

      return json({ success: true });
    }

    // MARK: - POST /api/account/addons
    if (url.pathname === '/api/account/addons' && request.method === 'POST') {
      const accountId = await verifyToken(token, env.JWT_SECRET);
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
      const accountId = await verifyToken(token, env.JWT_SECRET);
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
      const accountId = await verifyToken(token, env.JWT_SECRET);
      if (!accountId) return json({ error: 'Non authentifié' }, 401);

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

      const addons = await env.DB.prepare('SELECT manifest_url FROM addons WHERE account_id = ?')
        .bind(accountId)
        .all();

      return json({
        profiles: profiles.results,
        progress: progress.results,
        myList: myList.results,
        deletedMyList,
        deletedProgress,
        addons: addons.results.map((r: any) => r.manifest_url),
      });
    }

    // MARK: - POST /api/sync/push (Envoi des modifications locales de l'Apple TV)
    if (url.pathname === '/api/sync/push' && request.method === 'POST') {
      const accountId = await verifyToken(token, env.JWT_SECRET);
      if (!accountId) return json({ error: 'Non authentifié' }, 401);

      const data = (await request.json()) as any;

      // 1. Profils
      if (Array.isArray(data.profiles)) {
        for (const p of data.profiles) {
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
        for (const del of data.deletedProgress) {
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
        for (const pr of data.progress) {
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
        for (const del of data.deletedMyList) {
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
        for (const ml of data.myList) {
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

      return json({ success: true, timestamp: new Date().toISOString() });
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
  <title>StremioTV • Espace Compte & Jumelage</title>
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
      padding: 24px 16px;
      overflow-x: hidden;
    }

    .container {
      width: 100%;
      max-width: 460px;
      margin: auto;
      animation: cardEnter 0.28s var(--tv-ease-critique) both;
    }

    @keyframes cardEnter {
      from { opacity: 0; transform: scale(0.98) translateY(8px); }
      to { opacity: 1; transform: scale(1) translateY(0); }
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
      animation: pulse 2.2s infinite ease-in-out;
    }

    @keyframes pulse {
      0%, 100% { opacity: 1; transform: scale(1); }
      50% { opacity: 0.45; transform: scale(0.85); }
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
      transition: background 0.14s ease;
    }
    .tv-btn-danger:hover { background: rgba(229, 9, 20, 0.28); }
    .tv-btn-danger:active { transform: scale(0.95); }

    /* Profils items */
    .profile-card {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 12px;
      background: rgba(0, 0, 0, 0.28);
      border: 1px solid var(--tv-border);
      border-radius: var(--tv-radius-control);
      margin-bottom: 10px;
    }

    .profile-info {
      display: flex;
      align-items: center;
      gap: 12px;
      flex: 1;
    }

    .profile-avatar {
      width: 40px;
      height: 40px;
      border-radius: 50%;
      background: linear-gradient(135deg, #0A84FF, #0056B3);
      display: flex;
      align-items: center;
      justify-content: center;
      font-weight: 700;
      font-size: 15px;
      color: #FFF;
      box-shadow: 0 4px 10px rgba(0, 0, 0, 0.4);
      flex-shrink: 0;
    }

    .profile-avatar.purple { background: linear-gradient(135deg, #BF5AF2, #8E24AA); }
    .profile-avatar.red { background: linear-gradient(135deg, #FF453A, #C62828); }
    .profile-avatar.green { background: linear-gradient(135deg, #30D158, #2E7D32); }
    .profile-avatar.orange { background: linear-gradient(135deg, #FF9F0A, #EF6C00); }
    .profile-avatar.yellow { background: linear-gradient(135deg, #FFD60A, #F57F17); }

    .profile-name-text {
      font-size: 14px;
      font-weight: 600;
      color: var(--tv-text-primary);
    }

    .profile-subtext {
      font-size: 11px;
      color: var(--tv-text-tertiary);
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
        <h1 class="brand-title">StremioTV</h1>
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
            <span class="user-foyer" id="user-foyer-display">Foyer StremioTV</span>
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
        <div class="tv-segmented tv-segmented-4">
          <button type="button" class="tv-segment-item active" id="tab-btn-profiles" onclick="switchDashTab('profiles')">Profils</button>
          <button type="button" class="tv-segment-item" id="tab-btn-addons" onclick="switchDashTab('addons')">Add-ons</button>
          <button type="button" class="tv-segment-item" id="tab-btn-foyer" onclick="switchDashTab('foyer')">Surnom</button>
          <button type="button" class="tv-segment-item" id="tab-btn-security" onclick="switchDashTab('security')">Sécurité</button>
        </div>

        <!-- TAB 1 : PROFILS -->
        <div id="tab-content-profiles">
          <div id="profiles-list" style="margin-bottom: 14px;"></div>
          
          <!-- Ajouter un profil (si < 6) -->
          <div id="add-profile-box" style="background: var(--tv-surface-subtle); border: 1px dashed var(--tv-border); border-radius: var(--tv-radius-control); padding: 12px; margin-top: 10px;">
            <div style="font-size: 12.5px; font-weight: 600; margin-bottom: 8px;">Ajouter un nouveau profil</div>
            <div style="display: flex; gap: 8px; margin-bottom: 8px;">
              <input type="text" id="new-profile-name" class="tv-input" placeholder="Ex: Salon, Maman..." maxlength="24" style="height: 38px;">
              <select id="new-profile-color" class="tv-input" style="height: 38px; width: 100px; padding: 0 8px;">
                <option value="blue">Bleu</option>
                <option value="purple">Violet</option>
                <option value="red">Rouge</option>
                <option value="green">Vert</option>
                <option value="orange">Orange</option>
                <option value="yellow">Jaune</option>
              </select>
            </div>
            <button type="button" class="tv-pill-primary" onclick="handleAddProfile()" style="height: 38px; font-size: 13px;">+ Créer le profil</button>
          </div>
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
            Modifiez le mot de passe de votre compte StremioTV.
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
      <span>StremioTV 2.0</span>
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

    // Gestion de l'état de démarrage
    document.addEventListener('DOMContentLoaded', async () => {
      const token = localStorage.getItem('stremiotv_token');
      if (token) {
        await loadDashboard();
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
          body: JSON.stringify({ email, password })
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Erreur d\\'authentification');

        localStorage.setItem('stremiotv_token', data.token);
        localStorage.setItem('stremiotv_email', email);

        if (pairCode && pairCode !== 'STREM-XXXX') {
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
      const token = localStorage.getItem('stremiotv_token');
      if (!token) return;

      try {
        const res = await fetch('/api/account', {
          headers: { 'Authorization': 'Bearer ' + token }
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

        document.getElementById('user-email-display').innerText = accountData.email || localStorage.getItem('stremiotv_email') || 'Compte actif';
        document.getElementById('user-foyer-display').innerText = accountData.nickname ? 'Foyer : ' + accountData.nickname : 'Foyer StremioTV';
        document.getElementById('foyer-nickname-input').value = accountData.nickname || '';

        renderProfiles(accountData.profiles || []);
        renderAddons(accountData.addons || []);
      } catch (e) {
        showToast('Erreur lors du chargement des données', 'error');
      }
    }

    function renderProfiles(profiles) {
      const container = document.getElementById('profiles-list');
      if (!profiles.length) {
        container.innerHTML = '<div style="font-size: 13px; color: var(--tv-text-tertiary); text-align: center; padding: 12px;">Aucun profil trouvé.</div>';
        return;
      }

      container.innerHTML = profiles.map(function(p) {
        let avatarObj = { color: 'blue', symbol: 'face.smiling' };
        try {
          if (typeof p.avatar_json === 'string') avatarObj = JSON.parse(p.avatar_json);
        } catch (_) {}

        const colorClass = avatarObj.color || 'blue';
        const initial = (p.name || 'P').charAt(0).toUpperCase();

        return '<div class="profile-card">' +
          '<div class="profile-info">' +
            '<div class="profile-avatar ' + colorClass + '">' + initial + '</div>' +
            '<div style="flex: 1; overflow: hidden;">' +
              '<input type="text" class="tv-input" value="' + escapeHtml(p.name) + '" ' +
                'id="prof-name-' + p.id + '" ' +
                'style="height: 34px; font-size: 13.5px; font-weight: 600; padding: 0 8px;" ' +
                'onchange="handleRenameProfile(\\'' + p.id + '\\')">' +
            '</div>' +
          '</div>' +
          '<div style="margin-left: 8px;">' +
            '<button type="button" class="tv-btn-danger" onclick="handleDeleteProfile(\\'' + p.id + '\\')" title="Supprimer">Supprimer</button>' +
          '</div>' +
        '</div>';
      }).join('');

      document.getElementById('add-profile-box').style.display = profiles.length >= 6 ? 'none' : 'block';
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

    function switchDashTab(tab) {
      ['profiles', 'addons', 'foyer', 'security'].forEach(t => {
        document.getElementById('tab-btn-' + t).classList.toggle('active', t === tab);
        document.getElementById('tab-content-' + t).style.display = t === tab ? 'block' : 'none';
      });
    }

    async function handleConfirmPairing() {
      const token = localStorage.getItem('stremiotv_token');
      const btn = document.getElementById('dash-pair-btn');
      btn.disabled = true;
      btn.innerText = 'Liaison...';

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
        document.getElementById('dash-pair-banner').style.display = 'none';
      } catch (err) {
        showToast(err.message, 'error');
        btn.disabled = false;
        btn.innerText = 'Associer';
      }
    }

    async function handleSaveNickname() {
      const token = localStorage.getItem('stremiotv_token');
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
        document.getElementById('user-foyer-display').innerText = nickname ? 'Foyer : ' + nickname : 'Foyer StremioTV';
      } catch (err) {
        showToast(err.message, 'error');
      }
    }

    async function handleChangePassword() {
      const token = localStorage.getItem('stremiotv_token');
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

    async function handleRenameProfile(id) {
      const token = localStorage.getItem('stremiotv_token');
      const input = document.getElementById('prof-name-' + id);
      const name = input ? input.value.trim() : '';
      if (!name) return;

      try {
        const res = await fetch('/api/account/profile', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + token
          },
          body: JSON.stringify({ id, name })
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Erreur');
        showToast('Profil renommé en « ' + name + ' »', 'success');
      } catch (err) {
        showToast(err.message, 'error');
      }
    }

    async function handleAddProfile() {
      const token = localStorage.getItem('stremiotv_token');
      const nameInput = document.getElementById('new-profile-name');
      const colorSelect = document.getElementById('new-profile-color');
      const name = nameInput.value.trim();
      const color = colorSelect.value;

      if (!name) {
        showToast('Veuillez saisir un nom de profil', 'error');
        return;
      }

      try {
        const res = await fetch('/api/account/profile', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + token
          },
          body: JSON.stringify({
            name,
            avatar: { color, symbol: 'person.crop.circle' }
          })
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Erreur');

        showToast('Profil « ' + name + ' » ajouté !', 'success');
        nameInput.value = '';
        await loadDashboard();
      } catch (err) {
        showToast(err.message, 'error');
      }
    }

    async function handleDeleteProfile(id) {
      if (!confirm('Voulez-vous vraiment supprimer ce profil ?')) return;
      const token = localStorage.getItem('stremiotv_token');

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
        await loadDashboard();
      } catch (err) {
        showToast(err.message, 'error');
      }
    }

    async function handleAddAddon() {
      const token = localStorage.getItem('stremiotv_token');
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
      const token = localStorage.getItem('stremiotv_token');

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
