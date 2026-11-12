/**
 * Account portal, served at `/` and `/pair` (the Apple TV QR lands on `/pair?code=LOGE-1234`).
 * Mobile-first: most visits start from a phone scanning the TV.
 */

import { renderPage, icon } from './ui-kit.ts';

/** Only a well-formed pairing code ever reaches the page script. */
export function sanitizePairCode(raw: string): string {
  const code = raw.trim().toUpperCase();
  return /^LOGE-\d{4}$/.test(code) ? code : '';
}

const NAV = [
  { id: 'apercu', label: 'Aperçu', icon: 'home' },
  { id: 'profils', label: 'Profils', icon: 'users' },
  { id: 'appareils', label: 'Appareils', icon: 'tv' },
  { id: 'extensions', label: 'Extensions', icon: 'blocks' },
  { id: 'compte', label: 'Compte', icon: 'user' },
];

const styles = String.raw`
.auth { min-height: 100dvh; display: grid; place-items: center; padding: 32px 16px; }
.auth-card { width: min(400px, 100%); display: grid; gap: 24px; }
.auth-card header { display: grid; gap: 16px; }
.pair-banner { display: flex; gap: 12px; align-items: center; padding: 14px 16px; border-radius: var(--r-md); background: rgb(229 9 20 / 0.1); color: #ffb4b0; font-size: 14px; }
.pair-banner strong { color: var(--text); }

.topbar {
  position: sticky; top: 0; z-index: 10; height: 60px; padding: 0 16px;
  display: flex; align-items: center; justify-content: space-between;
  background: rgb(20 20 20 / 0.8); backdrop-filter: blur(20px) saturate(160%); -webkit-backdrop-filter: blur(20px) saturate(160%);
}
.shell { max-width: 1040px; margin: 0 auto; padding: 16px 16px calc(96px + env(safe-area-inset-bottom)); }
.content { min-width: 0; max-width: 680px; }
.view-head { display: grid; gap: 6px; margin: 8px 0 24px; }

.nav {
  position: fixed; inset: auto 0 0 0; z-index: 10; display: flex; justify-content: space-around;
  padding: 6px 4px calc(6px + env(safe-area-inset-bottom));
  background: rgb(28 28 30 / 0.85); backdrop-filter: blur(20px) saturate(160%); -webkit-backdrop-filter: blur(20px) saturate(160%);
  box-shadow: 0 -1px 0 var(--line);
}
.nav a { flex: 1; display: grid; justify-items: center; gap: 2px; padding: 6px 0; border-radius: 10px; font-size: 11px; font-weight: 500; color: var(--text-3); text-decoration: none; transition: color 150ms ease, background-color 150ms ease; }
.nav a[aria-current="page"] { color: var(--text); }
.nav .icon { width: 22px; height: 22px; }
@media (max-width: 899px) { .toast { bottom: calc(84px + env(safe-area-inset-bottom)); } }
@media (min-width: 900px) {
  .topbar { padding: 0 32px; }
  .shell { display: grid; grid-template-columns: 200px minmax(0, 1fr); gap: 56px; padding: 32px; }
  .nav { position: sticky; inset: auto; top: 92px; align-self: start; flex-direction: column; gap: 2px; padding: 0; background: none; backdrop-filter: none; box-shadow: none; }
  .nav a { display: flex; align-items: center; gap: 12px; padding: 10px 12px; font-size: 15px; color: var(--text-2); }
  .nav a[aria-current="page"] { background: rgb(255 255 255 / 0.07); color: var(--text); }
  .nav .icon { width: 20px; height: 20px; }
}
@media (hover: hover) { .nav a:hover { color: var(--text); } }

.pair-card { display: grid; gap: 14px; }
.pair-card.is-highlighted { box-shadow: 0 0 0 1px rgb(229 9 20 / 0.5); }
.pair-card input { text-transform: uppercase; letter-spacing: 0.08em; font-variant-numeric: tabular-nums; }

.tiles { display: grid; grid-template-columns: repeat(auto-fill, minmax(132px, 1fr)); gap: 12px; }
.tile {
  display: grid; justify-items: center; gap: 12px; padding: 22px 12px 18px; border-radius: var(--r-lg);
  background: var(--panel); border: 0; cursor: pointer; text-align: center;
  transition: background-color 150ms ease, scale 150ms ease-out;
}
.tile:not(:disabled):active { scale: 0.96; }
.tile:disabled { opacity: 0.45; cursor: not-allowed; }
.tile-name { font-weight: 500; max-width: 100%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.tile-add { background: transparent; box-shadow: inset 0 0 0 1px var(--line-strong); color: var(--text-2); }
@media (hover: hover) { .tile:not(:disabled):hover { background: var(--panel-raised); } .tile-add:not(:disabled):hover { background: rgb(255 255 255 / 0.04); } }

.avatar { width: 72px; height: 72px; border-radius: 50%; display: grid; place-items: center; color: #fff; }
.avatar svg { width: 54%; height: 54%; }
.avatar-lg { width: 96px; height: 96px; margin: 0 auto; }
.swatches { display: flex; flex-wrap: wrap; gap: 10px; }
.swatch { position: relative; width: 36px; height: 36px; border-radius: 50%; cursor: pointer; display: grid; place-items: center; color: #fff; transition: scale 150ms ease-out; }
.swatch input { position: absolute; opacity: 0; pointer-events: none; }
.swatch:has(input:checked) { box-shadow: 0 0 0 2px var(--panel), 0 0 0 4px #fff; }
.swatch:active { scale: 0.92; }
.symbols { display: grid; grid-template-columns: repeat(5, 1fr); gap: 8px; }
.symbols .swatch { width: 100%; height: 48px; border-radius: var(--r-md); background: rgb(255 255 255 / 0.06); color: var(--text-2); }
.symbols .swatch svg { width: 24px; height: 24px; }
.symbols .swatch:has(input:checked) { background: rgb(255 255 255 / 0.14); color: var(--text); box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.5); }

.group-label { display: flex; justify-content: space-between; align-items: baseline; margin: 28px 4px 10px; }
.group-label:first-child { margin-top: 0; }
.tag { font-size: 12px; font-weight: 600; color: var(--ok); }

.plans { display: grid; gap: 10px; }
.plan-row { display: flex; align-items: center; gap: 14px; padding: 14px 16px; border-radius: var(--r-md); box-shadow: inset 0 0 0 1px var(--line); }
.plan-row.is-current { box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.4); }
.plan-row ul { list-style: none; font-size: 13px; color: var(--text-3); }
`;

const body = `
<main id="auth-screen" class="auth" hidden>
  <div class="auth-card">
    <header>
      <span class="brand"><span class="brand-mark">L</span>Loge</span>
      <div>
        <h1 id="auth-title" class="title-xl">Connexion</h1>
        <p class="muted">Gérez votre foyer, vos profils et vos Apple TV.</p>
      </div>
    </header>
    <div id="auth-pair-banner" class="pair-banner" hidden>${icon('tv')}<span>Connectez-vous pour associer l’Apple TV <strong id="auth-pair-code"></strong>.</span></div>
    <div class="seg" role="radiogroup" aria-label="Mode">
      <label><input type="radio" name="auth-mode" value="login" checked>Se connecter</label>
      <label><input type="radio" name="auth-mode" value="register">Créer un compte</label>
    </div>
    <form id="auth-form" class="form-stack" novalidate>
      <label class="field"><span>Adresse e-mail</span><input id="auth-email" type="email" autocomplete="email" inputmode="email" required></label>
      <label class="field"><span>Mot de passe</span><input id="auth-password" type="password" autocomplete="current-password" minlength="6" required></label>
      <p id="auth-error" class="form-error" role="alert" hidden></p>
      <button id="auth-submit" class="btn btn-primary btn-block" type="submit">Se connecter</button>
    </form>
    <p class="faint"><a href="/privacy">Confidentialité</a> · <a href="/support">Assistance</a></p>
  </div>
</main>

<div id="app-screen" hidden>
  <header class="topbar">
    <span class="brand"><span class="brand-mark">L</span><span id="household-name">Loge</span></span>
    <span id="plan-badge"></span>
  </header>
  <div class="shell">
    <nav class="nav" aria-label="Sections">
      ${NAV.map((item) => `<a href="#${item.id}" data-nav="${item.id}">${icon(item.icon)}<span>${item.label}</span></a>`).join('')}
    </nav>
    <main class="content">
      <section data-view="apercu" hidden>
        <div class="view-head"><p class="eyebrow" id="overview-email"></p><h1 class="title-xl" id="overview-title">Votre foyer</h1></div>
        <div class="card pair-card" id="pair-card">
          <div><h2 class="title-md">Associer une Apple TV</h2><p class="muted">Saisissez le code affiché sur votre téléviseur.</p></div>
          <form id="pair-form" class="inline-form">
            <label class="field"><span class="sr-only">Code d’appairage</span><input id="pair-code" placeholder="LOGE-0000" autocomplete="off" spellcheck="false" maxlength="9" required></label>
            <button class="btn btn-primary" type="submit">Associer</button>
          </form>
        </div>
        <div class="card">
          <div class="card-head"><div><h2 class="title-md">Utilisation</h2><p class="faint" id="plan-caption"></p></div><a class="btn btn-sm btn-quiet" href="#compte">Abonnement</a></div>
          <div class="meters" id="usage-meters"></div>
        </div>
      </section>

      <section data-view="profils" hidden>
        <div class="view-head"><h1 class="title-xl">Profils</h1><p class="muted">Chaque profil a sa liste et sa reprise de lecture.</p></div>
        <div class="tiles" id="profile-tiles"></div>
      </section>

      <section data-view="appareils" hidden>
        <div class="view-head"><h1 class="title-xl">Appareils</h1><p class="muted">Les appareils connectés à votre compte.</p></div>
        <div id="device-groups"></div>
        <div class="card-head" style="margin-top:20px"><span class="faint" id="device-caption"></span><button class="btn btn-sm btn-quiet" id="revoke-others">${icon('logout')}Déconnecter les autres</button></div>
      </section>

      <section data-view="extensions" hidden>
        <div class="view-head"><h1 class="title-xl">Extensions</h1><p class="muted">Les addons Stremio installés sur toutes vos Apple TV.</p></div>
        <form id="addon-form" class="card form-stack">
          <label class="field"><span>URL du manifeste</span><input id="addon-url" type="url" inputmode="url" placeholder="https://…/manifest.json" autocomplete="off" spellcheck="false" required></label>
          <div class="card-head" style="margin:0"><span class="faint num" id="addon-caption"></span><button class="btn btn-primary" type="submit">${icon('plus')}Ajouter</button></div>
        </form>
        <div class="list" id="addon-list" style="margin-top:16px"></div>
      </section>

      <section data-view="compte" hidden>
        <div class="view-head"><h1 class="title-xl">Compte</h1><p class="muted" id="account-email"></p></div>
        <form id="nickname-form" class="card form-stack">
          <h2 class="title-md">Nom du foyer</h2>
          <div class="inline-form"><label class="field"><span class="sr-only">Nom du foyer</span><input id="nickname" maxlength="40" placeholder="Foyer Loge"></label><button class="btn" type="submit">Enregistrer</button></div>
        </form>
        <div class="card">
          <div class="card-head"><div><h2 class="title-md">Abonnement</h2><p class="faint">L’abonnement s’achète et se gère depuis l’app Loge sur Apple TV.</p></div></div>
          <div class="plans" id="plan-list"></div>
        </div>
        <form id="password-form" class="card form-stack">
          <h2 class="title-md">Mot de passe</h2>
          <input type="email" autocomplete="username" id="password-username" hidden>
          <label class="field"><span>Mot de passe actuel</span><input id="current-password" type="password" autocomplete="current-password" required></label>
          <label class="field"><span>Nouveau mot de passe</span><input id="new-password" type="password" autocomplete="new-password" minlength="6" required></label>
          <div><button class="btn" type="submit">Modifier le mot de passe</button></div>
        </form>
        <div class="card"><div class="card-head" style="margin:0"><div><h2 class="title-md">Session</h2><p class="faint">Déconnecte ce navigateur uniquement.</p></div><button class="btn" id="logout">${icon('logout')}Se déconnecter</button></div></div>
        <div class="card danger-zone"><div class="card-head" style="margin:0"><div><h2 class="title-md">Supprimer le compte</h2><p class="faint">Profils, listes, extensions et appareils sont effacés définitivement.</p></div><button class="btn btn-danger" id="delete-account">Supprimer</button></div></div>
      </section>
    </main>
  </div>
</div>

<dialog id="profile-dialog" class="sheet" aria-labelledby="profile-dialog-title">
  <div class="sheet-head"><h2 id="profile-dialog-title" class="title-md">Profil</h2><button class="btn btn-icon" data-close aria-label="Fermer">${icon('close')}</button></div>
  <form id="profile-form" class="sheet-body">
    <div class="avatar avatar-lg" id="profile-preview"></div>
    <label class="field"><span>Nom</span><input id="profile-name" maxlength="16" required autocomplete="off"></label>
    <fieldset class="field" style="border:0"><legend class="faint" style="margin-bottom:8px">Couleur</legend><div class="swatches" id="color-swatches"></div></fieldset>
    <fieldset class="field" style="border:0"><legend class="faint" style="margin-bottom:8px">Icône</legend><div class="symbols" id="symbol-swatches"></div></fieldset>
  </form>
  <div class="sheet-foot"><button class="btn btn-danger" id="profile-delete" type="button">Supprimer</button><span class="spacer"></span><button class="btn btn-quiet" data-close>Annuler</button><button class="btn btn-primary" id="profile-save" form="profile-form" type="submit">Enregistrer</button></div>
</dialog>

<dialog id="rename-dialog" class="sheet" aria-labelledby="rename-title">
  <div class="sheet-head"><h2 id="rename-title" class="title-md">Renommer l’appareil</h2></div>
  <form id="rename-form" class="sheet-body"><label class="field"><span>Nom</span><input id="rename-input" maxlength="32" required autocomplete="off"></label></form>
  <div class="sheet-foot"><button class="btn btn-quiet" data-close>Annuler</button><button class="btn btn-primary" form="rename-form" type="submit">Renommer</button></div>
</dialog>
`;

const script = String.raw`
// Source of truth: Sources/Models/Profile.swift + ProfileAvatarView.swift
var AVATAR_COLORS = [
  { id: 'red', hex: '#E63338' }, { id: 'orange', hex: '#FA8C26' }, { id: 'yellow', hex: '#F7C733' },
  { id: 'green', hex: '#40C273' }, { id: 'teal', hex: '#2EB2BD' }, { id: 'blue', hex: '#4085F2' },
  { id: 'purple', hex: '#9461EB' }, { id: 'pink', hex: '#F2619E' }
];
var AVATAR_SYMBOLS = {
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
var SYMBOL_IDS = Object.keys(AVATAR_SYMBOLS);
var PLANS = [
  { id: 'free', name: 'Free', price: 'Gratuit', features: '1 profil · 1 extension · 1 Apple TV' },
  { id: 'pro', name: 'Pro', price: '3,99 € / mois', features: '3 profils · 5 extensions · 2 Apple TV · sync cloud' },
  { id: 'ultra', name: 'Ultra', price: '7,99 € / mois', features: '6 profils · 20 extensions · 4 Apple TV · sync cloud' }
];
var DEFAULT_LIMITS = { maxProfiles: 1, maxAddons: 1, maxTVSessions: 1, maxBrowserSessions: 1, cloudSync: false, canRenameDevices: false };
var CLIENT_HEADERS = { 'X-Device-Name': 'Navigateur web', 'X-Device-Model': browserLabel(), 'X-Client-Kind': 'browser' };

var state = { token: null, account: null, devices: [], editingProfileId: null, renamingDeviceId: null, draft: null };

// Persist across visits: the same origin as the QR keeps the household signed in.
function readStoredToken() {
  try {
    var token = localStorage.getItem('loge_token');
    var legacy = localStorage.getItem('stremiotv_token');
    if (!token && legacy) {
      token = legacy;
      localStorage.setItem('loge_token', legacy);
      localStorage.removeItem('stremiotv_token');
      localStorage.removeItem('stremiotv_email');
    }
    return token;
  } catch (_) { return null; }
}
function storeToken(token) {
  state.token = token;
  try { token ? localStorage.setItem('loge_token', token) : localStorage.removeItem('loge_token'); } catch (_) {}
}

function browserLabel() {
  var ua = navigator.userAgent;
  var os = /iPhone/.test(ua) ? 'iPhone' : /iPad/.test(ua) ? 'iPad' : /Android/.test(ua) ? 'Android' : /Mac/.test(ua) ? 'Mac' : /Windows/.test(ua) ? 'Windows' : 'Web';
  var browser = /Edg\//.test(ua) ? 'Edge' : /Firefox\//.test(ua) ? 'Firefox' : /Chrome\//.test(ua) ? 'Chrome' : /Safari\//.test(ua) ? 'Safari' : 'Navigateur';
  // Sent in an HTTP header, which only carries ASCII safely.
  return browser + ' sur ' + os;
}

/** Authenticated call; a 401 means the session was revoked elsewhere. */
function authed(path, options) {
  options = options || {};
  options.token = state.token;
  options.headers = CLIENT_HEADERS;
  return api(path, options).then(function (res) {
    if (res.status === 401) { signOutLocally(); toast('Session expirée. Reconnectez-vous.', 'error'); }
    if (res.data && res.data.token) storeToken(res.data.token);
    return res;
  });
}

function limits() { return (state.account && state.account.limits) || DEFAULT_LIMITS; }

/* ---------- Avatars ---------- */
function colorHex(id) { var hit = AVATAR_COLORS.find(function (c) { return c.id === id; }); return hit ? hit.hex : '#4085F2'; }
function parseAvatar(profile) {
  var avatar = {};
  try { avatar = typeof profile.avatar_json === 'string' ? JSON.parse(profile.avatar_json) : (profile.avatar || {}); } catch (_) {}
  return {
    color: AVATAR_COLORS.some(function (c) { return c.id === avatar.color; }) ? avatar.color : 'blue',
    symbol: AVATAR_SYMBOLS[avatar.symbol] ? avatar.symbol : 'face.smiling'
  };
}
function avatarHtml(avatar, extraClass) {
  return '<span class="avatar ' + (extraClass || '') + '" style="background:' + colorHex(avatar.color) + '"><svg viewBox="0 0 24 24" aria-hidden="true">' + AVATAR_SYMBOLS[avatar.symbol] + '</svg></span>';
}
function suggestedAvatar(profiles) {
  var used = profiles.map(parseAvatar);
  var color = AVATAR_COLORS.find(function (c) { return !used.some(function (a) { return a.color === c.id; }); });
  var symbol = SYMBOL_IDS.find(function (s) { return !used.some(function (a) { return a.symbol === s; }); });
  return { color: (color || AVATAR_COLORS[0]).id, symbol: symbol || SYMBOL_IDS[0] };
}

/* ---------- Routing ---------- */
var VIEWS = ['apercu', 'profils', 'appareils', 'extensions', 'compte'];
function showView() {
  var id = location.hash.slice(1);
  if (VIEWS.indexOf(id) < 0) id = 'apercu';
  $all('[data-view]').forEach(function (section) {
    var active = section.dataset.view === id;
    if (active && section.hidden) { section.classList.remove('view'); void section.offsetWidth; section.classList.add('view'); }
    section.hidden = !active;
  });
  $all('[data-nav]').forEach(function (link) {
    if (link.dataset.nav === id) link.setAttribute('aria-current', 'page'); else link.removeAttribute('aria-current');
  });
  if (id === 'appareils') loadDevices();
}
window.addEventListener('hashchange', function () { showView(); window.scrollTo(0, 0); });

/* ---------- Rendering ---------- */
function renderAll() {
  var a = state.account;
  var lim = limits();
  $('#household-name').textContent = a.nickname || 'Loge';
  $('#plan-badge').innerHTML = planBadge(a.plan);
  $('#overview-email').textContent = a.email;
  $('#overview-title').textContent = a.nickname ? 'Foyer ' + a.nickname : 'Votre foyer';
  $('#account-email').textContent = a.email;
  $('#password-username').value = a.email;
  $('#nickname').value = a.nickname || '';
  $('#plan-caption').textContent = 'Formule ' + ({ free: 'Free', pro: 'Pro', ultra: 'Ultra' }[a.plan] || 'Free') +
    (a.planExpiresAtMs ? ' · jusqu’au ' + new Date(a.planExpiresAtMs).toLocaleDateString('fr-FR') : '');
  renderMeters();
  renderProfiles();
  renderAddons();
  $('#plan-list').innerHTML = PLANS.map(function (p) {
    var current = p.id === a.plan;
    return '<div class="plan-row' + (current ? ' is-current' : '') + '"><div class="row-main"><div class="row-title">' + p.name + ' <span class="faint">· ' + p.price + '</span></div>' +
      '<ul><li>' + p.features + '</li></ul></div>' + (current ? '<span class="badge badge-ok">Actuelle</span>' : '') + '</div>';
  }).join('');
}

function deviceCount(kind) { return state.devices.filter(function (d) { return d.kind === kind; }).length; }

function renderMeters() {
  var a = state.account, lim = limits();
  $('#usage-meters').innerHTML =
    meter('Profils', (a.profiles || []).length, lim.maxProfiles) +
    meter('Extensions', (a.addons || []).length, lim.maxAddons) +
    meter('Apple TV', deviceCount('tv'), lim.maxTVSessions) +
    meter('Navigateurs', deviceCount('browser'), lim.maxBrowserSessions);
}

function renderProfiles() {
  var profiles = state.account.profiles || [];
  var atLimit = profiles.length >= limits().maxProfiles;
  $('#profile-tiles').innerHTML = profiles.map(function (p) {
    return '<button class="tile" data-profile="' + esc(p.id) + '">' + avatarHtml(parseAvatar(p)) + '<span class="tile-name">' + esc(p.name) + '</span></button>';
  }).join('') +
    '<button class="tile tile-add" data-profile=""' + (atLimit ? ' disabled' : '') + '><span class="avatar" style="background:rgb(255 255 255 / 0.06)">' + icon('plus') + '</span>' +
    '<span class="tile-name">' + (atLimit ? 'Limite atteinte' : 'Ajouter') + '</span></button>';
}

function addonHost(url) { try { return new URL(url).host; } catch (_) { return url; } }
function renderAddons() {
  var addons = state.account.addons || [];
  var max = limits().maxAddons;
  $('#addon-caption').textContent = addons.length + ' / ' + max + ' extensions';
  $('#addon-form button[type=submit]').disabled = addons.length >= max;
  $('#addon-list').innerHTML = addons.length ? addons.map(function (url) {
    return '<div class="row"><span class="glyph">' + icon('blocks') + '</span><div class="row-main"><div class="row-title">' + esc(addonHost(url)) + '</div><div class="row-sub">' + esc(url) + '</div></div>' +
      '<div class="row-actions"><button class="btn btn-icon" data-remove-addon="' + esc(url) + '" aria-label="Retirer ' + esc(addonHost(url)) + '">' + icon('trash') + '</button></div></div>';
  }).join('') : '<p class="empty">Aucune extension. Ajoutez l’URL d’un addon Stremio.</p>';
}

function renderDevices() {
  var lim = limits();
  var groups = [
    { kind: 'tv', label: 'Apple TV', max: lim.maxTVSessions, glyph: 'tv' },
    { kind: 'browser', label: 'Navigateurs', max: lim.maxBrowserSessions, glyph: 'browser' }
  ];
  $('#device-groups').innerHTML = groups.map(function (g) {
    var list = state.devices.filter(function (d) { return d.kind === g.kind; });
    var rows = list.map(function (d) {
      var sub = [d.model, d.isCurrent ? null : 'actif ' + relativeTime(d.lastSeenAtMs)].filter(Boolean).join(' · ');
      return '<div class="row"><span class="glyph">' + icon(g.glyph) + '</span><div class="row-main"><div class="row-title">' + esc(d.name) +
        (d.isCurrent ? ' <span class="tag">Cet appareil</span>' : '') + '</div><div class="row-sub">' + esc(sub) + '</div></div><div class="row-actions">' +
        (lim.canRenameDevices ? '<button class="btn btn-icon" data-rename-device="' + esc(d.id) + '" aria-label="Renommer ' + esc(d.name) + '">' + icon('pencil') + '</button>' : '') +
        (d.isCurrent ? '' : '<button class="btn btn-sm btn-quiet" data-revoke-device="' + esc(d.id) + '">Déconnecter</button>') + '</div></div>';
    }).join('');
    return '<div class="group-label"><span class="eyebrow">' + g.label + '</span><span class="faint num">' + list.length + ' / ' + g.max + '</span></div>' +
      '<div class="list">' + (rows || '<p class="empty">Aucun appareil.</p>') + '</div>';
  }).join('');
  $('#device-caption').textContent = lim.canRenameDevices ? '' : 'Renommer les appareils : formule Pro ou Ultra.';
  $('#revoke-others').disabled = state.devices.filter(function (d) { return !d.isCurrent; }).length === 0;
}

/* ---------- Data ---------- */
function loadAccount() {
  return authed('/api/account').then(function (res) {
    if (!res.ok) return false;
    state.account = res.data;
    renderAll();
    return true;
  });
}
function loadDevices() {
  return authed('/api/devices').then(function (res) {
    if (!res.ok) return;
    state.devices = res.data.devices || [];
    renderDevices();
    renderMeters();
  });
}

function enterApp() {
  $('#auth-screen').hidden = true;
  $('#app-screen').hidden = false;
  showView();
}
function signOutLocally() {
  storeToken(null);
  state.account = null;
  $('#app-screen').hidden = true;
  $('#auth-screen').hidden = false;
}

/* ---------- Pairing ---------- */
function confirmPairing(code, button) {
  return withBusy(button, function () {
    return authed('/api/device/confirm', { body: { code: code } }).then(function (res) {
      if (!res.ok) { toast(res.data.error || 'Code invalide ou expiré.', 'error'); return; }
      toast('Apple TV associée. Elle se connecte…', 'success');
      $('#pair-code').value = '';
      $('#pair-card').classList.remove('is-highlighted');
      if (history.replaceState) history.replaceState(null, '', '/' + location.hash);
      setTimeout(loadDevices, 4000);
    });
  });
}
$('#pair-form').addEventListener('submit', function (e) {
  e.preventDefault();
  var code = $('#pair-code').value.trim().toUpperCase();
  if (!/^LOGE-[0-9]{4}$/.test(code)) { toast('Le code ressemble à LOGE-1234.', 'error'); return; }
  confirmPairing(code, e.submitter);
});

/* ---------- Auth ---------- */
function authMode() { return $('input[name=auth-mode]:checked').value; }
$all('input[name=auth-mode]').forEach(function (radio) {
  radio.addEventListener('change', function () {
    var register = authMode() === 'register';
    $('#auth-title').textContent = register ? 'Créer un compte' : 'Connexion';
    $('#auth-submit').textContent = register ? 'Créer le compte' : 'Se connecter';
    $('#auth-password').autocomplete = register ? 'new-password' : 'current-password';
    $('#auth-error').hidden = true;
  });
});
$('#auth-form').addEventListener('submit', function (e) {
  e.preventDefault();
  var error = $('#auth-error');
  var email = $('#auth-email').value.trim();
  var password = $('#auth-password').value;
  error.hidden = true;
  if (!email || password.length < 6) {
    error.textContent = 'Saisissez un e-mail et un mot de passe de 6 caractères minimum.';
    error.hidden = false;
    return;
  }
  withBusy($('#auth-submit'), function () {
    var path = authMode() === 'register' ? '/api/auth/register' : '/api/auth/login';
    return api(path, { body: { email: email, password: password, deviceName: 'Navigateur web', deviceModel: browserLabel(), clientKind: 'browser' } })
      .then(function (res) {
        if (!res.ok) { error.textContent = res.data.error || 'Connexion impossible.'; error.hidden = false; return; }
        storeToken(res.data.token);
        $('#auth-password').value = '';
        return start();
      });
  });
});

/* ---------- Profiles ---------- */
function renderAvatarPickers() {
  $('#color-swatches').innerHTML = AVATAR_COLORS.map(function (c) {
    return '<label class="swatch" style="background:' + c.hex + '"><input type="radio" name="avatar-color" value="' + c.id + '"' + (state.draft.color === c.id ? ' checked' : '') + '><span class="sr-only">' + c.id + '</span></label>';
  }).join('');
  $('#symbol-swatches').innerHTML = SYMBOL_IDS.map(function (s) {
    return '<label class="swatch"><input type="radio" name="avatar-symbol" value="' + s + '"' + (state.draft.symbol === s ? ' checked' : '') + '><svg viewBox="0 0 24 24" aria-hidden="true">' + AVATAR_SYMBOLS[s] + '</svg><span class="sr-only">' + s + '</span></label>';
  }).join('');
  $('#profile-preview').outerHTML = avatarHtml(state.draft, 'avatar-lg').replace('<span class="avatar', '<span id="profile-preview" class="avatar');
}
$('#profile-form').addEventListener('change', function (e) {
  if (e.target.name === 'avatar-color') state.draft.color = e.target.value;
  if (e.target.name === 'avatar-symbol') state.draft.symbol = e.target.value;
  $('#profile-preview').outerHTML = avatarHtml(state.draft, 'avatar-lg').replace('<span class="avatar', '<span id="profile-preview" class="avatar');
});
$('#profile-tiles').addEventListener('click', function (e) {
  var tile = e.target.closest('[data-profile]');
  if (!tile || tile.disabled) return;
  var profiles = state.account.profiles || [];
  var profile = profiles.find(function (p) { return p.id === tile.dataset.profile; });
  state.editingProfileId = profile ? profile.id : null;
  state.draft = profile ? parseAvatar(profile) : suggestedAvatar(profiles);
  $('#profile-dialog-title').textContent = profile ? 'Modifier le profil' : 'Nouveau profil';
  $('#profile-name').value = profile ? profile.name : '';
  $('#profile-delete').hidden = !profile || profiles.length <= 1;
  renderAvatarPickers();
  $('#profile-dialog').showModal();
});
$('#profile-form').addEventListener('submit', function (e) {
  e.preventDefault();
  var name = $('#profile-name').value.trim();
  if (!name) { $('#profile-name').focus(); return; }
  withBusy($('#profile-save'), function () {
    return authed('/api/account/profile', { body: { id: state.editingProfileId || undefined, name: name, avatar: state.draft } }).then(function (res) {
      if (!res.ok) { toast(res.data.error || 'Enregistrement impossible.', 'error'); return; }
      closeDialog($('#profile-dialog'));
      toast(state.editingProfileId ? 'Profil mis à jour' : 'Profil créé', 'success');
      return loadAccount();
    });
  });
});
$('#profile-delete').addEventListener('click', function () {
  var id = state.editingProfileId;
  var name = $('#profile-name').value;
  closeDialog($('#profile-dialog'));
  confirmAction({ title: 'Supprimer « ' + name + ' » ?', body: 'Sa liste et sa reprise de lecture seront effacées sur tous les appareils.', confirmLabel: 'Supprimer', danger: true })
    .then(function (ok) {
      if (!ok) return;
      return authed('/api/account/profile', { method: 'DELETE', body: { id: id } }).then(function (res) {
        if (!res.ok) { toast(res.data.error || 'Suppression impossible.', 'error'); return; }
        toast('Profil supprimé', 'success');
        return loadAccount();
      });
    });
});

/* ---------- Devices ---------- */
$('#device-groups').addEventListener('click', function (e) {
  var revoke = e.target.closest('[data-revoke-device]');
  var rename = e.target.closest('[data-rename-device]');
  if (revoke) {
    var device = state.devices.find(function (d) { return d.id === revoke.dataset.revokeDevice; });
    confirmAction({ title: 'Déconnecter « ' + device.name + ' » ?', body: 'Il faudra l’associer à nouveau pour l’utiliser.', confirmLabel: 'Déconnecter', danger: true })
      .then(function (ok) {
        if (!ok) return;
        return authed('/api/devices/revoke', { body: { id: device.id } }).then(function (res) {
          if (!res.ok) { toast(res.data.error || 'Action impossible.', 'error'); return; }
          toast('Appareil déconnecté', 'success');
          return loadDevices();
        });
      });
  }
  if (rename) {
    var target = state.devices.find(function (d) { return d.id === rename.dataset.renameDevice; });
    state.renamingDeviceId = target.id;
    $('#rename-input').value = target.name;
    $('#rename-dialog').showModal();
    $('#rename-input').select();
  }
});
$('#rename-form').addEventListener('submit', function (e) {
  e.preventDefault();
  withBusy(e.submitter, function () {
    return authed('/api/devices/rename', { body: { id: state.renamingDeviceId, displayName: $('#rename-input').value } }).then(function (res) {
      if (!res.ok) { toast(res.data.error || 'Renommage impossible.', 'error'); return; }
      closeDialog($('#rename-dialog'));
      return loadDevices();
    });
  });
});
$('#revoke-others').addEventListener('click', function () {
  confirmAction({ title: 'Déconnecter les autres appareils ?', body: 'Toutes les Apple TV et les autres navigateurs devront se reconnecter.', confirmLabel: 'Tout déconnecter', danger: true })
    .then(function (ok) {
      if (!ok) return;
      return authed('/api/devices/revoke-others', { body: {} }).then(function (res) {
        if (!res.ok) { toast(res.data.error || 'Action impossible.', 'error'); return; }
        toast(res.data.revoked + ' appareil(s) déconnecté(s)', 'success');
        return loadDevices();
      });
    });
});

/* ---------- Extensions ---------- */
$('#addon-form').addEventListener('submit', function (e) {
  e.preventDefault();
  var url = $('#addon-url').value.trim();
  if (!url) return;
  withBusy(e.submitter, function () {
    return authed('/api/account/addons', { body: { manifestUrl: url } }).then(function (res) {
      if (!res.ok) { toast(res.data.error || 'Ajout impossible.', 'error'); return; }
      $('#addon-url').value = '';
      toast('Extension ajoutée', 'success');
      return loadAccount();
    });
  });
});
$('#addon-list').addEventListener('click', function (e) {
  var button = e.target.closest('[data-remove-addon]');
  if (!button) return;
  var url = button.dataset.removeAddon;
  confirmAction({ title: 'Retirer ' + addonHost(url) + ' ?', body: 'L’extension disparaîtra de toutes vos Apple TV.', confirmLabel: 'Retirer', danger: true })
    .then(function (ok) {
      if (!ok) return;
      return authed('/api/account/addons', { method: 'DELETE', body: { manifestUrl: url } }).then(function (res) {
        if (!res.ok) { toast(res.data.error || 'Action impossible.', 'error'); return; }
        toast('Extension retirée', 'success');
        return loadAccount();
      });
    });
});

/* ---------- Account ---------- */
$('#nickname-form').addEventListener('submit', function (e) {
  e.preventDefault();
  withBusy(e.submitter, function () {
    return authed('/api/account/nickname', { body: { nickname: $('#nickname').value } }).then(function (res) {
      if (!res.ok) { toast(res.data.error || 'Enregistrement impossible.', 'error'); return; }
      toast('Nom du foyer enregistré', 'success');
      return loadAccount();
    });
  });
});
$('#password-form').addEventListener('submit', function (e) {
  e.preventDefault();
  withBusy(e.submitter, function () {
    return authed('/api/account/password', { body: { currentPassword: $('#current-password').value, newPassword: $('#new-password').value } }).then(function (res) {
      if (!res.ok) { toast(res.data.error || 'Modification impossible.', 'error'); return; }
      $('#password-form').reset();
      toast('Mot de passe modifié', 'success');
    });
  });
});
$('#logout').addEventListener('click', function () {
  if (state.token) api('/api/auth/logout', { token: state.token, body: {} });
  signOutLocally();
});
$('#delete-account').addEventListener('click', function () {
  var email = state.account.email;
  confirmAction({ title: 'Supprimer définitivement le compte ?', body: 'Cette action est irréversible. Vos Apple TV seront déconnectées.', confirmLabel: 'Supprimer le compte', danger: true, requireText: email })
    .then(function (ok) {
      if (!ok) return;
      return authed('/api/auth/delete-account', { body: {} }).then(function (res) {
        if (!res.ok) { toast(res.data.error || 'Suppression impossible.', 'error'); return; }
        signOutLocally();
        toast('Compte supprimé', 'success');
      });
    });
});

/* ---------- Start ---------- */
function start() {
  return loadAccount().then(function (ok) {
    if (!ok) return;
    enterApp();
    loadDevices();
    // Signed in on this phone already: scanning the TV QR pairs without retyping anything.
    if (PAIR_CODE) {
      location.hash = '#apercu';
      $('#pair-card').classList.add('is-highlighted');
      $('#pair-code').value = PAIR_CODE;
      confirmPairing(PAIR_CODE);
      PAIR_CODE = '';
    }
  });
}

if (PAIR_CODE) {
  $('#auth-pair-banner').hidden = false;
  $('#auth-pair-code').textContent = PAIR_CODE;
}
state.token = readStoredToken();
if (state.token) {
  start().then(function () { if (!state.account) $('#auth-screen').hidden = false; });
} else {
  $('#auth-screen').hidden = false;
}
`;

export function renderWebPortal(prefillCode: string): string {
  const code = sanitizePairCode(prefillCode);
  return renderPage({
    title: 'Loge — Mon compte',
    styles,
    body,
    script: `var PAIR_CODE = ${JSON.stringify(code)};\n${script}`,
  });
}
