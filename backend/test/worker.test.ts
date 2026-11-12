/**
 * Contract tests: the real Worker against the real `schema.sql`, on an in-memory SQLite
 * that mimics the D1 calls the Worker makes. Run with `npm test` (Node ≥ 23, no dependencies).
 */

import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { Script } from 'node:vm';
import worker from '../src/index.ts';
import { sanitizePairCode, renderWebPortal } from '../src/pages/web-portal.ts';
import { renderAdminPortal } from '../src/pages/admin-portal.ts';

const SCHEMA = readFileSync(new URL('../schema.sql', import.meta.url), 'utf8');
const ADMIN_PASSWORD = 'test-admin-password';

function createD1(): any {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys = ON;');
  db.exec(SCHEMA);
  const statement = (sql: string, params: any[] = []): any => ({
    bind: (...values: any[]) => statement(sql, values),
    first: async () => db.prepare(sql).get(...params) ?? null,
    all: async () => ({ results: db.prepare(sql).all(...params) }),
    run: async () => ({ meta: { changes: Number(db.prepare(sql).run(...params).changes) } }),
  });
  return { prepare: (sql: string) => statement(sql), batch: async (list: any[]) => Promise.all(list.map((s) => s.run())) };
}

let env: any;
beforeEach(() => {
  env = { DB: createD1(), JWT_SECRET: 'test-secret', ADMIN_PASSWORD };
});

async function call(path: string, options: { method?: string; token?: string; body?: unknown } = {}) {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (options.token) headers.Authorization = `Bearer ${options.token}`;
  const res = await worker.fetch(
    new Request(`https://loge.test${path}`, {
      method: options.method || (options.body ? 'POST' : 'GET'),
      headers,
      body: options.body ? JSON.stringify(options.body) : undefined,
    }),
    env
  );
  return { status: res.status, data: (await res.json().catch(() => null)) as any, res };
}

async function register(email = 'ana@example.com', password = 'secret123') {
  const { data } = await call('/api/auth/register', { body: { email, password, clientKind: 'browser' } });
  return { token: data.token as string, accountId: data.accountId as string };
}

async function adminToken() {
  const { data } = await call('/api/admin/login', { body: { password: ADMIN_PASSWORD } });
  return data.token as string;
}

test('admin login rejects a wrong password and accepts the configured one', async () => {
  assert.equal((await call('/api/admin/login', { body: { password: 'nope' } })).status, 401);
  const ok = await call('/api/admin/login', { body: { password: ADMIN_PASSWORD } });
  assert.equal(ok.status, 200);
  assert.ok(ok.data.token);
  assert.ok(ok.data.expiresAtMs > Date.now());
});

test('admin API is disabled when ADMIN_PASSWORD is not set', async () => {
  delete env.ADMIN_PASSWORD;
  assert.equal((await call('/api/admin/login', { body: { password: '' } })).status, 503);
});

test('tokens do not cross the account/admin boundary', async () => {
  const user = await register();
  const admin = await adminToken();
  assert.equal((await call('/api/admin/accounts', { token: user.token })).status, 401);
  assert.equal((await call('/api/account', { token: admin })).status, 401);
  assert.equal((await call('/api/account/profile', { token: admin, body: { name: 'x' } })).status, 401);
  assert.equal((await call('/api/admin/accounts')).status, 401);
});

test('admin lists accounts with counts, totals and search', async () => {
  const ana = await register('ana@example.com');
  await register('bob@example.com');
  await call('/api/account/profile', { token: ana.token, body: { name: 'Ana' } });
  const admin = await adminToken();

  const all = await call('/api/admin/accounts', { token: admin });
  assert.equal(all.status, 200);
  assert.deepEqual(all.data.totals, { accounts: 2, free: 2, pro: 0, ultra: 0, devices: 2 });
  const row = all.data.accounts.find((a: any) => a.email === 'ana@example.com');
  assert.equal(row.profiles, 1);
  assert.equal(row.devices, 1);

  const filtered = await call('/api/admin/accounts?q=BOB', { token: admin });
  assert.deepEqual(filtered.data.accounts.map((a: any) => a.email), ['bob@example.com']);
});

test('admin grants a plan that the account then sees, and refuses a past expiry', async () => {
  const user = await register();
  const admin = await adminToken();

  await call('/api/admin/account/plan', { token: admin, body: { id: user.accountId, plan: 'ultra' } });
  const account = await call('/api/account', { token: user.token });
  assert.equal(account.data.plan, 'ultra');
  assert.equal(account.data.limits.maxProfiles, 6);

  const detail = await call(`/api/admin/account?id=${user.accountId}`, { token: admin });
  assert.equal(detail.data.planSource, 'admin.grant');

  // A past expiry is refused: the grant is stored without one.
  const past = await call('/api/admin/account/plan', { token: admin, body: { id: user.accountId, plan: 'pro', expiresAtMs: Date.now() - 1000 } });
  assert.equal(past.data.planExpiresAtMs, null);
});

test('admin password reset changes the password and signs every device out', async () => {
  const user = await register('ana@example.com', 'old-password');
  const admin = await adminToken();

  const tooShort = await call('/api/admin/account/password', { token: admin, body: { id: user.accountId, newPassword: '123' } });
  assert.equal(tooShort.status, 400);

  const reset = await call('/api/admin/account/password', { token: admin, body: { id: user.accountId, newPassword: 'new-password' } });
  assert.equal(reset.data.revoked, 1);
  assert.equal((await call('/api/account', { token: user.token })).status, 401);
  assert.equal((await call('/api/auth/login', { body: { email: 'ana@example.com', password: 'old-password' } })).status, 401);
  assert.equal((await call('/api/auth/login', { body: { email: 'ana@example.com', password: 'new-password' } })).status, 200);
});

test('admin signs out one device or all of them', async () => {
  const user = await register();
  const second = await call('/api/auth/login', { body: { email: 'ana@example.com', password: 'secret123', clientKind: 'tv' } });
  const admin = await adminToken();

  const detail = await call(`/api/admin/account?id=${user.accountId}`, { token: admin });
  assert.equal(detail.data.devices.length, 2);
  const tv = detail.data.devices.find((d: any) => d.kind === 'tv');
  await call('/api/admin/account/device/revoke', { token: admin, body: { id: user.accountId, deviceId: tv.id } });
  assert.equal((await call('/api/account', { token: second.data.token })).status, 401);
  assert.equal((await call('/api/account', { token: user.token })).status, 200);

  const all = await call('/api/admin/account/sign-out', { token: admin, body: { id: user.accountId } });
  assert.equal(all.data.revoked, 1);
  assert.equal((await call('/api/account', { token: user.token })).status, 401);
});

test('admin deletes an account and its data', async () => {
  const user = await register();
  await call('/api/account/profile', { token: user.token, body: { name: 'Ana' } });
  const admin = await adminToken();

  assert.equal((await call('/api/admin/account/delete', { token: admin, body: { id: user.accountId } })).status, 200);
  assert.equal((await call(`/api/admin/account?id=${user.accountId}`, { token: admin })).status, 404);
  assert.equal((await env.DB.prepare('SELECT COUNT(*) AS c FROM profiles').first()).c, 0);
  assert.equal((await call('/api/admin/account/delete', { token: admin, body: { id: user.accountId } })).status, 404);
});

test('admin actions write an audit line', async (t) => {
  const user = await register();
  const admin = await adminToken();
  const log = t.mock.method(console, 'log', () => {});
  await call('/api/admin/account/sign-out', { token: admin, body: { id: user.accountId } });
  const line = JSON.parse(log.mock.calls.at(-1)!.arguments[0]);
  assert.equal(line.audit, 'admin');
  assert.equal(line.action, 'sign_out_all');
  assert.equal(line.accountId, user.accountId);
});

test('the pairing code from the URL cannot inject script', () => {
  assert.equal(sanitizePairCode(' loge-1234 '), 'LOGE-1234');
  assert.equal(sanitizePairCode('";alert(1)//'), '');
  const html = renderWebPortal('</script><script>alert(1)</script>');
  assert.ok(!html.includes('alert(1)'));
  assert.ok(renderWebPortal('LOGE-4821').includes('var PAIR_CODE = "LOGE-4821";'));
});

test('portal and admin pages are served without caching', async () => {
  for (const path of ['/', '/pair?code=LOGE-1234', '/admin']) {
    const res = await worker.fetch(new Request(`https://loge.test${path}`), env);
    assert.equal(res.status, 200);
    assert.match(res.headers.get('Content-Type') || '', /text\/html/);
    assert.match(res.headers.get('Cache-Control') || '', /no-store/);
    assert.equal(res.headers.get('X-Frame-Options'), 'DENY');
  }
});

test('page scripts are valid JavaScript', () => {
  for (const html of [renderWebPortal('LOGE-1234'), renderAdminPortal()]) {
    const source = html.slice(html.indexOf('<script>') + 8, html.lastIndexOf('</script>'));
    assert.doesNotThrow(() => new Script(source));
  }
});
