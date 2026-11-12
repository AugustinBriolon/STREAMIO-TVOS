/**
 * Admin console, served at `/admin`. Talks only to `/api/admin/*` (see `admin.ts`).
 * The admin token lives in sessionStorage: closing the tab ends the admin session.
 */

import { renderPage, icon } from './ui-kit.ts';

const styles = String.raw`
.auth { min-height: 100dvh; display: grid; place-items: center; padding: 32px 16px; }
.auth-card { width: min(380px, 100%); display: grid; gap: 24px; }
.topbar { position: sticky; top: 0; z-index: 10; height: 60px; padding: 0 16px; display: flex; align-items: center; justify-content: space-between; background: rgb(20 20 20 / 0.8); backdrop-filter: blur(20px) saturate(160%); -webkit-backdrop-filter: blur(20px) saturate(160%); }
.wrap { max-width: 1120px; margin: 0 auto; padding: 16px 16px 48px; }
.stats { display: grid; grid-template-columns: repeat(2, 1fr); gap: 12px; margin: 8px 0 24px; }
.stat { background: var(--panel); border-radius: var(--r-lg); padding: 16px 18px; }
.stat strong { display: block; font-size: 26px; font-weight: 700; letter-spacing: -0.02em; font-variant-numeric: tabular-nums; }
.search { position: relative; margin-bottom: 12px; }
.search .icon { position: absolute; left: 14px; top: 12px; color: var(--text-3); }
.search input { padding-left: 42px; }
.acc-cols { display: none; }
.acc-row { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 4px 12px; align-items: center; padding: 14px 16px; }
.acc-row + .acc-row { box-shadow: 0 -1px 0 var(--line); }
.acc-meta { grid-column: 1 / -1; display: flex; gap: 12px; font-size: 13px; color: var(--text-3); }
@media (min-width: 760px) {
  .topbar { padding: 0 32px; }
  .wrap { padding: 32px; }
  .stats { grid-template-columns: repeat(5, 1fr); }
  .acc-cols, .acc-row { display: grid; grid-template-columns: minmax(0, 2.4fr) 80px 70px 80px 70px minmax(0, 1fr) 20px; gap: 12px; align-items: center; }
  .acc-cols { padding: 10px 16px; font-size: 12px; font-weight: 600; color: var(--text-3); text-transform: uppercase; letter-spacing: 0.06em; }
  .acc-meta { display: contents; }
  .acc-meta > span { font-size: 14px; color: var(--text-2); }
  .acc-meta .unit { display: none; }
}
.kv { display: grid; grid-template-columns: auto 1fr; gap: 6px 16px; font-size: 14px; }
.kv dt { color: var(--text-3); }
.kv dd { min-width: 0; overflow-wrap: anywhere; }
.section-title { display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; }
.chips { display: flex; flex-wrap: wrap; gap: 6px; }
.chip { padding: 4px 10px; border-radius: 999px; background: rgb(255 255 255 / 0.07); font-size: 13px; }
.drawer .list { background: rgb(255 255 255 / 0.03); }
.drawer .card { background: rgb(255 255 255 / 0.03); padding: 16px; }
`;

const body = `
<main id="login-screen" class="auth" hidden>
  <div class="auth-card">
    <span class="brand"><span class="brand-mark">L</span>Loge <small>Admin</small></span>
    <div><h1 class="title-xl">Administration</h1><p class="muted">Accès réservé à l’opérateur du service.</p></div>
    <form id="login-form" class="form-stack">
      <input type="text" autocomplete="username" value="admin" hidden>
      <label class="field"><span>Mot de passe administrateur</span><input id="admin-password" type="password" autocomplete="current-password" required></label>
      <p id="login-error" class="form-error" role="alert" hidden></p>
      <button id="login-submit" class="btn btn-primary btn-block" type="submit">${icon('shield')}Ouvrir la console</button>
    </form>
  </div>
</main>

<div id="console-screen" hidden>
  <header class="topbar">
    <span class="brand"><span class="brand-mark">L</span>Loge <small>Admin</small></span>
    <button class="btn btn-sm btn-quiet" id="admin-logout">${icon('logout')}Quitter</button>
  </header>
  <main class="wrap">
    <h1 class="title-xl">Comptes</h1>
    <div class="stats" id="stats"></div>
    <label class="field search"><span class="sr-only">Rechercher</span>${icon('search')}<input id="search" type="search" placeholder="Rechercher par e-mail ou nom de foyer" autocomplete="off"></label>
    <div class="list">
      <div class="acc-cols"><span>Compte</span><span>Formule</span><span>Profils</span><span>Appareils</span><span>Ext.</span><span>Dernière activité</span><span></span></div>
      <div id="accounts"></div>
    </div>
    <p class="faint" id="list-caption" style="margin-top:12px"></p>
  </main>
</div>

<dialog id="account-drawer" class="sheet drawer" aria-labelledby="drawer-title">
  <div class="sheet-head"><h2 id="drawer-title" class="title-md">Compte</h2><button class="btn btn-icon" data-close aria-label="Fermer">${icon('close')}</button></div>
  <div class="sheet-body" id="drawer-body"></div>
</dialog>
`;

const script = String.raw`
var TOKEN_KEY = 'loge_admin_token';
var state = { token: null, detail: null, query: '' };

function readToken() { try { return sessionStorage.getItem(TOKEN_KEY); } catch (_) { return null; } }
function storeToken(token) {
  state.token = token;
  try { token ? sessionStorage.setItem(TOKEN_KEY, token) : sessionStorage.removeItem(TOKEN_KEY); } catch (_) {}
}

function admin(path, options) {
  options = options || {};
  options.token = state.token;
  return api(path, options).then(function (res) {
    if (res.status === 401 || res.status === 503) { showLogin(res.data.error); }
    return res;
  });
}

function showLogin(message) {
  storeToken(null);
  closeDialog($('#account-drawer'));
  $('#console-screen').hidden = true;
  $('#login-screen').hidden = false;
  $('#login-error').hidden = !message;
  $('#login-error').textContent = message || '';
  $('#admin-password').focus();
}
function showConsole() {
  $('#login-screen').hidden = true;
  $('#console-screen').hidden = false;
  loadAccounts();
}

$('#login-form').addEventListener('submit', function (e) {
  e.preventDefault();
  withBusy($('#login-submit'), function () {
    return api('/api/admin/login', { body: { password: $('#admin-password').value } }).then(function (res) {
      if (!res.ok) { $('#login-error').textContent = res.data.error || 'Connexion impossible.'; $('#login-error').hidden = false; return; }
      $('#admin-password').value = '';
      storeToken(res.data.token);
      showConsole();
    });
  });
});
$('#admin-logout').addEventListener('click', function () { showLogin(); });

/* ---------- List ---------- */
function stat(label, value) { return '<div class="stat"><span class="faint">' + label + '</span><strong>' + value + '</strong></div>'; }

function loadAccounts() {
  return admin('/api/admin/accounts?q=' + encodeURIComponent(state.query)).then(function (res) {
    if (!res.ok) return;
    var t = res.data.totals;
    $('#stats').innerHTML = stat('Comptes', t.accounts) + stat('Free', t.free) + stat('Pro', t.pro) + stat('Ultra', t.ultra) + stat('Appareils actifs', t.devices);
    var accounts = res.data.accounts;
    $('#accounts').innerHTML = accounts.length ? accounts.map(function (a) {
      return '<button class="row-button acc-row" data-account="' + esc(a.id) + '">' +
        '<span class="row-main"><span class="row-title" style="display:block">' + esc(a.email) + '</span><span class="row-sub" style="display:block">' + esc(a.nickname || 'Sans nom de foyer') + '</span></span>' +
        '<span>' + planBadge(a.plan) + '</span>' +
        '<span class="acc-meta"><span class="num">' + a.profiles + '<span class="unit"> profil(s)</span></span><span class="num">' + a.devices + '<span class="unit"> appareil(s)</span></span><span class="num">' + a.addons + '<span class="unit"> ext.</span></span><span>' + relativeTime(a.lastSeenAtMs) + '</span></span>' +
        '<span class="faint" aria-hidden="true">' + icon('chevron') + '</span></button>';
    }).join('') : '<p class="empty">' + (state.query ? 'Aucun compte ne correspond.' : 'Aucun compte pour le moment.') + '</p>';
    $('#list-caption').textContent = accounts.length >= 200 ? 'Les 200 comptes les plus récents sont affichés. Affinez la recherche.' : '';
  });
}

var searchTimer = null;
$('#search').addEventListener('input', function (e) {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(function () { state.query = e.target.value.trim(); loadAccounts(); }, 200);
});
$('#accounts').addEventListener('click', function (e) {
  var row = e.target.closest('[data-account]');
  if (row) openAccount(row.dataset.account);
});

/* ---------- Detail ---------- */
function openAccount(id) {
  return admin('/api/admin/account?id=' + encodeURIComponent(id)).then(function (res) {
    if (!res.ok) { toast(res.data.error || 'Compte introuvable.', 'error'); return; }
    state.detail = res.data;
    renderDetail();
    var drawer = $('#account-drawer');
    if (!drawer.open) drawer.showModal();
  });
}

function dateInputValue(ms) { return ms ? new Date(ms).toISOString().slice(0, 10) : ''; }

function renderDetail() {
  var d = state.detail;
  $('#drawer-title').textContent = d.email;
  var planOptions = ['free', 'pro', 'ultra'].map(function (p) {
    return '<label><input type="radio" name="plan" value="' + p + '"' + (d.plan === p ? ' checked' : '') + '>' + { free: 'Free', pro: 'Pro', ultra: 'Ultra' }[p] + '</label>';
  }).join('');
  var devices = d.devices.length ? d.devices.map(function (dev) {
    return '<div class="row"><span class="glyph">' + icon(dev.kind === 'browser' ? 'browser' : 'tv') + '</span><div class="row-main"><div class="row-title">' + esc(dev.name) + '</div>' +
      '<div class="row-sub">' + esc([dev.model, 'actif ' + relativeTime(dev.lastSeenAtMs)].filter(Boolean).join(' · ')) + '</div></div>' +
      '<button class="btn btn-sm btn-quiet" data-revoke="' + esc(dev.id) + '">Déconnecter</button></div>';
  }).join('') : '<p class="empty">Aucun appareil connecté.</p>';
  var profiles = d.profiles.length ? d.profiles.map(function (p) { return '<span class="chip">' + esc(p.name) + '</span>'; }).join('') : '<span class="faint">Aucun profil</span>';
  var addons = d.addons.length ? d.addons.map(function (u) { return '<div class="row-sub mono" style="white-space:normal;overflow-wrap:anywhere">' + esc(u) + '</div>'; }).join('') : '<span class="faint">Aucune extension</span>';

  $('#drawer-body').innerHTML =
    '<dl class="kv"><dt>Foyer</dt><dd>' + esc(d.nickname || '—') + '</dd><dt>Créé le</dt><dd>' + esc(d.createdAt || '—') + '</dd>' +
    '<dt>Identifiant</dt><dd class="mono">' + esc(d.id) + '</dd></dl>' +

    '<form class="card form-stack" id="plan-form"><div class="section-title"><h3 class="title-md">Formule</h3>' +
    (d.planSource ? '<span class="faint">' + esc(d.planSource === 'admin.grant' ? 'Attribuée par l’admin' : d.planSource) + '</span>' : '') + '</div>' +
    '<div class="seg" role="radiogroup" aria-label="Formule">' + planOptions + '</div>' +
    '<label class="field"><span>Expiration (facultatif)</span><input type="date" id="plan-expiry" value="' + dateInputValue(d.planExpiresAtMs) + '"></label>' +
    '<div><button class="btn btn-primary" type="submit">Appliquer la formule</button></div></form>' +

    '<div><div class="section-title"><h3 class="title-md">Appareils</h3>' + (d.devices.length ? '<button class="btn btn-sm btn-quiet" id="sign-out-all">' + icon('logout') + 'Tout déconnecter</button>' : '') + '</div>' +
    '<div class="list">' + devices + '</div></div>' +

    '<div><h3 class="title-md section-title">Profils</h3><div class="chips">' + profiles + '</div></div>' +
    '<div><h3 class="title-md section-title">Extensions</h3>' + addons + '</div>' +

    '<form class="card form-stack" id="password-form"><h3 class="title-md">Réinitialiser le mot de passe</h3>' +
    '<p class="faint">Tous les appareils du compte seront déconnectés.</p>' +
    '<div class="inline-form"><label class="field"><span class="sr-only">Nouveau mot de passe</span><input id="reset-password" autocomplete="off" spellcheck="false" minlength="6" required placeholder="Nouveau mot de passe" class="mono"></label>' +
    '<button class="btn" type="button" id="generate-password">' + icon('key') + 'Générer</button></div>' +
    '<div><button class="btn btn-primary" type="submit">Réinitialiser</button></div></form>' +

    '<div class="card danger-zone"><div class="card-head" style="margin:0"><div><h3 class="title-md">Supprimer le compte</h3><p class="faint">Efface le compte et toutes ses données.</p></div>' +
    '<button class="btn btn-danger" id="delete-account">Supprimer</button></div></div>';
}

function refreshAfter(message) {
  toast(message, 'success');
  loadAccounts();
  return openAccount(state.detail.id);
}

function generatePassword() {
  var alphabet = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789';
  var bytes = crypto.getRandomValues(new Uint8Array(14));
  return Array.prototype.map.call(bytes, function (b) { return alphabet[b % alphabet.length]; }).join('');
}

$('#drawer-body').addEventListener('click', function (e) {
  var d = state.detail;
  if (e.target.closest('#generate-password')) { $('#reset-password').value = generatePassword(); $('#reset-password').select(); return; }
  var revoke = e.target.closest('[data-revoke]');
  if (revoke) {
    withBusy(revoke, function () {
      return admin('/api/admin/account/device/revoke', { body: { id: d.id, deviceId: revoke.dataset.revoke } }).then(function (res) {
        if (!res.ok) { toast(res.data.error || 'Action impossible.', 'error'); return; }
        return refreshAfter('Appareil déconnecté');
      });
    });
    return;
  }
  if (e.target.closest('#sign-out-all')) {
    confirmAction({ title: 'Déconnecter tous les appareils ?', body: d.email + ' devra se reconnecter partout.', confirmLabel: 'Tout déconnecter', danger: true }).then(function (ok) {
      if (!ok) return;
      return admin('/api/admin/account/sign-out', { body: { id: d.id } }).then(function (res) {
        if (!res.ok) { toast(res.data.error || 'Action impossible.', 'error'); return; }
        return refreshAfter(res.data.revoked + ' appareil(s) déconnecté(s)');
      });
    });
    return;
  }
  if (e.target.closest('#delete-account')) {
    confirmAction({ title: 'Supprimer ce compte ?', body: 'Profils, listes, extensions et appareils seront effacés. Action irréversible.', confirmLabel: 'Supprimer définitivement', danger: true, requireText: d.email }).then(function (ok) {
      if (!ok) return;
      return admin('/api/admin/account/delete', { body: { id: d.id } }).then(function (res) {
        if (!res.ok) { toast(res.data.error || 'Suppression impossible.', 'error'); return; }
        closeDialog($('#account-drawer'));
        toast('Compte supprimé', 'success');
        loadAccounts();
      });
    });
  }
});

$('#drawer-body').addEventListener('submit', function (e) {
  e.preventDefault();
  var d = state.detail;
  if (e.target.id === 'plan-form') {
    var plan = $('input[name=plan]:checked', e.target).value;
    var expiry = $('#plan-expiry').value;
    // The plan ends at the end of the chosen day, local time.
    var expiresAtMs = expiry ? new Date(expiry + 'T23:59:59').getTime() : null;
    withBusy(e.submitter, function () {
      return admin('/api/admin/account/plan', { body: { id: d.id, plan: plan, expiresAtMs: expiresAtMs } }).then(function (res) {
        if (!res.ok) { toast(res.data.error || 'Action impossible.', 'error'); return; }
        return refreshAfter('Formule mise à jour');
      });
    });
  }
  if (e.target.id === 'password-form') {
    var password = $('#reset-password').value;
    if (password.length < 6) { toast('6 caractères minimum.', 'error'); return; }
    confirmAction({ title: 'Réinitialiser le mot de passe ?', body: 'Communiquez le nouveau mot de passe à ' + d.email + '. Ses appareils seront déconnectés.', confirmLabel: 'Réinitialiser' }).then(function (ok) {
      if (!ok) return;
      return admin('/api/admin/account/password', { body: { id: d.id, newPassword: password } }).then(function (res) {
        if (!res.ok) { toast(res.data.error || 'Action impossible.', 'error'); return; }
        return refreshAfter('Mot de passe réinitialisé');
      });
    });
  }
});

state.token = readToken();
if (state.token) showConsole(); else showLogin();
`;

export function renderAdminPortal(): string {
  return renderPage({ title: 'Loge — Administration', styles, body, script });
}
