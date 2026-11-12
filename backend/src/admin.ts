/**
 * Admin API (`/api/admin/*`): one operator, authenticated by the `ADMIN_PASSWORD` Worker secret.
 * The admin is not an account row: its token carries `role: 'admin'` and no session, and the
 * account API rejects any token that has a role.
 */

import { json, sha256, hashPassword, signToken, readToken, parsePlan, effectivePlan, limitsFor, MIN_PASSWORD_LENGTH } from './shared.ts';
import type { Env } from './shared.ts';

const ADMIN_TOKEN_TTL_S = 8 * 60 * 60;
const ACCOUNT_LIST_LIMIT = 200;

/** Compares digests so the response time does not reveal how much of the password matched. */
async function passwordMatches(candidate: string, expected: string): Promise<boolean> {
  const [a, b] = await Promise.all([sha256(candidate), sha256(expected)]);
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

async function isAdmin(request: Request, env: Env): Promise<boolean> {
  const token = (request.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  const payload = await readToken(token, env.JWT_SECRET);
  return payload?.role === 'admin';
}

/** One structured line per admin write, kept by Workers Logs. */
function audit(action: string, accountId: string, detail: Record<string, unknown> = {}): void {
  console.log(JSON.stringify({ audit: 'admin', action, accountId, ...detail, atMs: Date.now() }));
}

async function login(request: Request, env: Env): Promise<Response> {
  const { password } = (await request.json().catch(() => ({}))) as any;
  if (typeof password !== 'string' || !(await passwordMatches(password, env.ADMIN_PASSWORD!))) {
    console.log(JSON.stringify({ audit: 'admin', action: 'login_failed', atMs: Date.now() }));
    return json({ error: 'Mot de passe administrateur incorrect.' }, 401);
  }
  const now = Math.floor(Date.now() / 1000);
  const exp = now + ADMIN_TOKEN_TTL_S;
  audit('login', '-');
  return json({ token: await signToken({ sub: 'admin', role: 'admin', iat: now, exp }, env.JWT_SECRET), expiresAtMs: exp * 1000 });
}

async function listAccounts(env: Env, query: string): Promise<Response> {
  const now = Date.now();
  const q = query.trim().toLowerCase();
  const like = `%${q}%`;
  const rows = await env.DB.prepare(
    `SELECT a.id, a.email, a.nickname, a.plan, a.plan_expires_at_ms, a.created_at,
       (SELECT COUNT(DISTINCT lower(p.id)) FROM profiles p WHERE p.account_id = a.id) AS profiles,
       (SELECT COUNT(*) FROM sessions s WHERE s.account_id = a.id AND s.revoked_at_ms IS NULL) AS devices,
       (SELECT COUNT(*) FROM addons d WHERE d.account_id = a.id) AS addons,
       (SELECT MAX(s.last_seen_at_ms) FROM sessions s WHERE s.account_id = a.id) AS last_seen_at_ms
     FROM accounts a
     WHERE ? = '' OR a.email LIKE ? OR lower(IFNULL(a.nickname, '')) LIKE ?
     ORDER BY a.created_at DESC
     LIMIT ${ACCOUNT_LIST_LIMIT}`
  ).bind(q, like, like).all();

  const active = '(plan_expires_at_ms IS NULL OR plan_expires_at_ms <= 0 OR plan_expires_at_ms >= ?)';
  const totals: any = await env.DB.prepare(
    `SELECT COUNT(*) AS total,
       SUM(CASE WHEN plan = 'pro' AND ${active} THEN 1 ELSE 0 END) AS pro,
       SUM(CASE WHEN plan = 'ultra' AND ${active} THEN 1 ELSE 0 END) AS ultra,
       (SELECT COUNT(*) FROM sessions WHERE revoked_at_ms IS NULL) AS devices
     FROM accounts`
  ).bind(now, now).first();
  const total = Number(totals?.total ?? 0);
  const pro = Number(totals?.pro ?? 0);
  const ultra = Number(totals?.ultra ?? 0);

  return json({
    totals: { accounts: total, free: total - pro - ultra, pro, ultra, devices: Number(totals?.devices ?? 0) },
    accounts: (rows.results as any[]).map((r) => ({
      id: r.id,
      email: r.email,
      nickname: r.nickname || '',
      plan: effectivePlan(r.plan, r.plan_expires_at_ms, now),
      planExpiresAtMs: r.plan_expires_at_ms ?? null,
      createdAt: r.created_at,
      lastSeenAtMs: r.last_seen_at_ms ?? null,
      profiles: Number(r.profiles),
      devices: Number(r.devices),
      addons: Number(r.addons),
    })),
  });
}

async function findAccount(env: Env, id: unknown): Promise<any | null> {
  if (typeof id !== 'string' || !id) return null;
  return env.DB.prepare(
    'SELECT id, email, nickname, plan, plan_expires_at_ms, plan_product_id, created_at FROM accounts WHERE id = ?'
  ).bind(id).first();
}

async function accountDetail(env: Env, id: string | null): Promise<Response> {
  const account = await findAccount(env, id);
  if (!account) return json({ error: 'Compte introuvable.' }, 404);
  const [profiles, devices, addons] = await Promise.all([
    env.DB.prepare(
      'SELECT lower(id) AS id, MAX(name) AS name, MAX(avatar_json) AS avatar_json FROM profiles WHERE account_id = ? GROUP BY lower(id) ORDER BY MIN(sort_order)'
    ).bind(account.id).all(),
    env.DB.prepare(
      `SELECT id, device_name, display_name, device_model, device_kind, created_at_ms, last_seen_at_ms
       FROM sessions WHERE account_id = ? AND revoked_at_ms IS NULL ORDER BY last_seen_at_ms DESC`
    ).bind(account.id).all(),
    env.DB.prepare('SELECT manifest_url FROM addons WHERE account_id = ? ORDER BY installed_at ASC').bind(account.id).all(),
  ]);
  const plan = effectivePlan(account.plan, account.plan_expires_at_ms);
  return json({
    id: account.id,
    email: account.email,
    nickname: account.nickname || '',
    plan,
    planExpiresAtMs: account.plan_expires_at_ms ?? null,
    planSource: account.plan_product_id || null,
    limits: limitsFor(plan),
    createdAt: account.created_at,
    profiles: profiles.results,
    devices: (devices.results as any[]).map((d) => ({
      id: d.id,
      name: d.display_name || d.device_name,
      model: d.device_model || null,
      kind: d.device_kind === 'browser' ? 'browser' : 'tv',
      createdAtMs: d.created_at_ms,
      lastSeenAtMs: d.last_seen_at_ms,
    })),
    addons: (addons.results as any[]).map((a) => a.manifest_url),
  });
}

async function revokeSessions(env: Env, accountId: string): Promise<number> {
  const res = await env.DB.prepare(
    'UPDATE sessions SET revoked_at_ms = ? WHERE account_id = ? AND revoked_at_ms IS NULL'
  ).bind(Date.now(), accountId).run();
  return res.meta.changes;
}

async function setPlan(env: Env, body: any): Promise<Response> {
  const account = await findAccount(env, body.id);
  if (!account) return json({ error: 'Compte introuvable.' }, 404);
  const plan = parsePlan(body.plan);
  const expiresAtMs = plan !== 'free' && typeof body.expiresAtMs === 'number' && body.expiresAtMs > Date.now() ? body.expiresAtMs : null;
  // 'admin.grant' keeps an expired StoreKit report for another product from clearing a granted plan.
  await env.DB.prepare(
    'UPDATE accounts SET plan = ?, plan_expires_at_ms = ?, plan_product_id = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?'
  ).bind(plan, expiresAtMs, plan === 'free' ? null : 'admin.grant', account.id).run();
  audit('set_plan', account.id, { from: account.plan, to: plan, expiresAtMs });
  return json({ success: true, plan, planExpiresAtMs: expiresAtMs });
}

async function resetPassword(env: Env, body: any): Promise<Response> {
  const account = await findAccount(env, body.id);
  if (!account) return json({ error: 'Compte introuvable.' }, 404);
  if (typeof body.newPassword !== 'string' || body.newPassword.length < MIN_PASSWORD_LENGTH) {
    return json({ error: `Le mot de passe doit comporter au moins ${MIN_PASSWORD_LENGTH} caractères.` }, 400);
  }
  await env.DB.prepare('UPDATE accounts SET password_hash = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?')
    .bind(await hashPassword(body.newPassword), account.id).run();
  // Whoever knew the old password may still hold a session: a reset signs everyone out.
  const revoked = await revokeSessions(env, account.id);
  audit('reset_password', account.id, { revokedSessions: revoked });
  return json({ success: true, revoked });
}

async function signOutEverywhere(env: Env, body: any): Promise<Response> {
  const account = await findAccount(env, body.id);
  if (!account) return json({ error: 'Compte introuvable.' }, 404);
  const revoked = await revokeSessions(env, account.id);
  audit('sign_out_all', account.id, { revokedSessions: revoked });
  return json({ success: true, revoked });
}

async function revokeDevice(env: Env, body: any): Promise<Response> {
  const res = await env.DB.prepare(
    'UPDATE sessions SET revoked_at_ms = ? WHERE id = ? AND account_id = ? AND revoked_at_ms IS NULL'
  ).bind(Date.now(), String(body.deviceId || ''), String(body.id || '')).run();
  if (res.meta.changes === 0) return json({ error: 'Appareil introuvable.' }, 404);
  audit('revoke_device', String(body.id), { deviceId: body.deviceId });
  return json({ success: true });
}

async function deleteAccount(env: Env, body: any): Promise<Response> {
  const account = await findAccount(env, body.id);
  if (!account) return json({ error: 'Compte introuvable.' }, 404);
  await env.DB.prepare('DELETE FROM accounts WHERE id = ?').bind(account.id).run();
  audit('delete_account', account.id, { email: account.email });
  return json({ success: true });
}

export async function handleAdminApi(request: Request, env: Env, url: URL): Promise<Response> {
  if (!env.ADMIN_PASSWORD) return json({ error: 'Administration désactivée.' }, 503);
  const route = `${request.method} ${url.pathname}`;
  if (route === 'POST /api/admin/login') return login(request, env);
  if (!(await isAdmin(request, env))) return json({ error: 'Session administrateur expirée.' }, 401);

  if (route === 'GET /api/admin/accounts') return listAccounts(env, url.searchParams.get('q') || '');
  if (route === 'GET /api/admin/account') return accountDetail(env, url.searchParams.get('id'));

  const body = request.method === 'POST' ? ((await request.json().catch(() => ({}))) as any) : {};
  switch (route) {
    case 'POST /api/admin/account/plan': return setPlan(env, body);
    case 'POST /api/admin/account/password': return resetPassword(env, body);
    case 'POST /api/admin/account/sign-out': return signOutEverywhere(env, body);
    case 'POST /api/admin/account/device/revoke': return revokeDevice(env, body);
    case 'POST /api/admin/account/delete': return deleteAccount(env, body);
    default: return json({ error: 'Route introuvable' }, 404);
  }
}
