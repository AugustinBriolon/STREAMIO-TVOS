/**
 * Shared design system for the web pages (account portal and admin console):
 * tokens, components, icons and the small client runtime both pages build on.
 * Tokens mirror `Sources/Design/Theme.swift` so the web reads as the same product as the TV app.
 *
 * Client code lives in `String.raw` blocks: no backticks and no `${` inside them.
 */

export const ICONS: Record<string, string> = {
  home: '<path d="M3.5 10.5 12 3.5l8.5 7"/><path d="M5.5 9v11h13V9"/>',
  users: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.6-3.6 3.3-5.5 6.5-5.5s5.9 1.9 6.5 5.5"/><path d="M16 4.6a3.5 3.5 0 0 1 0 6.8M18 14.8c2 .7 3.2 2.5 3.5 5.2"/>',
  tv: '<rect x="2.5" y="4.5" width="19" height="13" rx="2"/><path d="M8 21h8"/>',
  browser: '<rect x="4" y="5" width="16" height="11" rx="1.5"/><path d="M2 19h20"/>',
  blocks: '<rect x="3.5" y="3.5" width="7" height="7" rx="1.5"/><rect x="13.5" y="3.5" width="7" height="7" rx="1.5"/><rect x="3.5" y="13.5" width="7" height="7" rx="1.5"/><path d="M17 13.5v7M13.5 17h7"/>',
  user: '<circle cx="12" cy="8" r="4"/><path d="M4 20.5c.8-4 4-6 8-6s7.2 2 8 6"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  trash: '<path d="M4 7h16M9.5 7V4.5h5V7M6.5 7l1 13h9l1-13"/>',
  pencil: '<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="m13.5 6.5 4 4"/>',
  logout: '<path d="M14 4h4a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-4"/><path d="M10 16l-4-4 4-4M6 12h10"/>',
  check: '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
  link: '<path d="M10 14a4.5 4.5 0 0 0 6.4 0l3-3a4.5 4.5 0 0 0-6.4-6.4l-1 1"/><path d="M14 10a4.5 4.5 0 0 0-6.4 0l-3 3a4.5 4.5 0 0 0 6.4 6.4l1-1"/>',
  shield: '<path d="M12 3 4.5 6v5.5c0 4.6 3.2 8 7.5 9.5 4.3-1.5 7.5-4.9 7.5-9.5V6z"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/>',
  close: '<path d="M6 6l12 12M18 6 6 18"/>',
  chevron: '<path d="m9 6 6 6-6 6"/>',
  more: '<circle cx="12" cy="5" r="1.6" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.6" fill="currentColor" stroke="none"/><circle cx="12" cy="19" r="1.6" fill="currentColor" stroke="none"/>',
  spark: '<path d="M12 3.5l2 5.5 5.5 2-5.5 2-2 5.5-2-5.5-5.5-2 5.5-2z"/>',
  key: '<circle cx="8" cy="15" r="4"/><path d="m11 12 8-8M16 7l2.5 2.5"/>',
};

/** Server-side twin of the client `icon()` helper. */
export function icon(name: string): string {
  return `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">${ICONS[name] || ''}</svg>`;
}

const styles = String.raw`
:root {
  color-scheme: dark;
  --bg: #141414;
  --panel: #1c1c1e;
  --panel-raised: #252528;
  --line: rgb(255 255 255 / 0.08);
  --line-strong: rgb(255 255 255 / 0.16);
  --text: #f5f5f7;
  --text-2: rgb(255 255 255 / 0.68);
  --text-3: rgb(255 255 255 / 0.5);
  --accent: #e50914;
  --accent-press: #c40812;
  --ok: #46d369;
  --warn: #f5c518;
  --danger: #ff5a52;
  --r-sm: 8px;
  --r-md: 12px;
  --r-lg: 20px;
  --ease-out: cubic-bezier(0.23, 1, 0.32, 1);
  --ease-drawer: cubic-bezier(0.32, 0.72, 0, 1);
  --shadow-pop: 0 1px 0 rgb(255 255 255 / 0.04) inset, 0 24px 48px -12px rgb(0 0 0 / 0.6);
}
* { box-sizing: border-box; margin: 0; padding: 0; }
html { -webkit-text-size-adjust: 100%; }
body {
  background: var(--bg);
  color: var(--text);
  font: 15px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Inter", system-ui, sans-serif;
  -webkit-font-smoothing: antialiased;
  -webkit-tap-highlight-color: transparent;
  min-height: 100dvh;
}
body:has(dialog[open]) { overflow: hidden; }
button, input, select { font: inherit; color: inherit; }
a { color: inherit; }
[hidden] { display: none !important; }
.icon { width: 20px; height: 20px; flex: none; fill: none; stroke: currentColor; stroke-width: 1.75; stroke-linecap: round; stroke-linejoin: round; }
.num { font-variant-numeric: tabular-nums; }
.mono { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 13px; }
.muted { color: var(--text-2); }
.faint { color: var(--text-3); font-size: 13px; }
.sr-only { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; }

/* Type */
.eyebrow { font-size: 12px; font-weight: 600; letter-spacing: 0.06em; text-transform: uppercase; color: var(--text-3); }
.title-xl { font-size: clamp(26px, 4vw, 32px); line-height: 1.15; font-weight: 700; letter-spacing: -0.02em; text-wrap: balance; }
.title-md { font-size: 17px; line-height: 1.3; font-weight: 600; letter-spacing: -0.01em; }

/* Brand */
.brand { display: inline-flex; align-items: center; gap: 10px; font-weight: 700; font-size: 17px; letter-spacing: -0.01em; text-decoration: none; }
.brand-mark { width: 28px; height: 28px; border-radius: 8px; background: var(--accent); display: grid; place-items: center; font-size: 15px; font-weight: 800; color: #fff; }
.brand small { font-weight: 500; color: var(--text-3); font-size: 14px; }

/* Buttons */
.btn {
  display: inline-flex; align-items: center; justify-content: center; gap: 8px;
  min-height: 44px; padding: 0 18px; border-radius: var(--r-md);
  border: 1px solid transparent; cursor: pointer; font-weight: 600; font-size: 15px; white-space: nowrap; text-decoration: none;
  background: var(--panel-raised); color: var(--text);
  transition: background-color 150ms ease, opacity 150ms ease, scale 150ms ease-out;
}
.btn:not(:disabled):active { scale: 0.96; }
.btn:disabled { opacity: 0.45; cursor: not-allowed; }
/* Primary mirrors TV PillButtonStyle: solid white, not brand red (red = brand/danger). */
.btn-primary { background: #fff; color: #141414; }
.btn-quiet { background: transparent; color: var(--text-2); }
.btn-danger { background: rgb(255 90 82 / 0.12); color: var(--danger); }
.btn-sm { min-height: 36px; padding: 0 12px; font-size: 14px; border-radius: 10px; }
.btn-icon { width: 40px; min-height: 40px; padding: 0; border-radius: 10px; background: transparent; color: var(--text-2); }
.btn-block { width: 100%; }
@media (hover: hover) {
  .btn:not(:disabled):hover { background: #2e2e32; }
  .btn-primary:not(:disabled):hover { background: #e8e8ed; }
  .btn-quiet:not(:disabled):hover, .btn-icon:not(:disabled):hover { background: rgb(255 255 255 / 0.06); color: var(--text); }
  .btn-danger:not(:disabled):hover { background: rgb(255 90 82 / 0.2); }
}
.btn:focus-visible, .field input:focus-visible, .nav a:focus-visible, .tile:focus-visible, .row-button:focus-visible, .seg label:has(input:focus-visible), .swatch:has(input:focus-visible) {
  outline: 2px solid #fff; outline-offset: 2px;
}
.spinner { width: 16px; height: 16px; border-radius: 50%; border: 2px solid rgb(255 255 255 / 0.3); border-top-color: currentColor; animation: spin 600ms linear infinite; }
@keyframes spin { to { rotate: 360deg; } }

/* Fields */
.field { display: grid; gap: 6px; }
.field > span { font-size: 13px; font-weight: 500; color: var(--text-2); }
.field input, .field select {
  min-height: 44px; width: 100%; padding: 0 14px; border-radius: var(--r-md);
  background: rgb(255 255 255 / 0.05); border: 1px solid var(--line-strong);
  transition: border-color 150ms ease, background-color 150ms ease;
}
.field input::placeholder { color: var(--text-3); }
.field input:focus { border-color: rgb(255 255 255 / 0.4); background: rgb(255 255 255 / 0.07); outline: none; }
.inline-form { display: flex; gap: 8px; align-items: end; }
.inline-form .field { flex: 1; min-width: 0; }
.form-stack { display: grid; gap: 14px; }
.form-error { color: var(--danger); font-size: 14px; }

/* Row overflow menu: one quiet trigger, actions stay secondary/destructive. */
.menu { position: relative; }
.menu-pop {
  position: absolute; top: calc(100% + 4px); right: 0; z-index: 5; min-width: 180px;
  padding: 6px; border-radius: 12px; background: #2c2c30; box-shadow: var(--shadow-pop);
  display: grid; gap: 2px;
}
.menu-pop[hidden] { display: none !important; }
.menu-item {
  display: flex; align-items: center; gap: 10px; width: 100%; min-height: 40px; padding: 0 12px;
  border: 0; border-radius: 8px; background: transparent; color: var(--text); font: inherit; font-weight: 500;
  text-align: left; cursor: pointer;
}
.menu-item .icon { width: 18px; height: 18px; color: var(--text-2); }
.menu-item.is-danger { color: var(--danger); }
.menu-item.is-danger .icon { color: var(--danger); }
@media (hover: hover) {
  .menu-item:hover { background: rgb(255 255 255 / 0.08); }
  .menu-item.is-danger:hover { background: rgb(255 90 82 / 0.14); }
}
.menu-item:focus-visible { outline: 2px solid #fff; outline-offset: -2px; }

/* Surfaces */
.card { background: var(--panel); border-radius: var(--r-lg); padding: 20px; }
.card + .card, .stack > * + * { margin-top: 16px; }
.card-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 16px; }
.card-head p { margin-top: 2px; }
.list { background: var(--panel); border-radius: var(--r-lg); overflow: hidden; }
.row { display: flex; align-items: center; gap: 14px; padding: 14px 16px; min-height: 64px; }
.row + .row { box-shadow: 0 -1px 0 var(--line); }
.row-main { flex: 1; min-width: 0; }
.row-title { font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.row-sub { font-size: 13px; color: var(--text-3); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.row-actions { display: flex; gap: 4px; flex: none; }
.row-button { width: 100%; text-align: left; background: none; border: 0; cursor: pointer; transition: background-color 150ms ease; }
@media (hover: hover) { .row-button:hover { background: rgb(255 255 255 / 0.03); } }
.glyph { width: 40px; height: 40px; border-radius: 10px; background: rgb(255 255 255 / 0.06); display: grid; place-items: center; color: var(--text-2); flex: none; }
.danger-zone { box-shadow: inset 0 0 0 1px rgb(255 90 82 / 0.25); background: transparent; }
.empty { padding: 32px 20px; text-align: center; color: var(--text-3); font-size: 14px; }

/* Badges & meters */
.badge { display: inline-flex; align-items: center; height: 22px; padding: 0 8px; border-radius: 6px; font-size: 12px; font-weight: 600; background: rgb(255 255 255 / 0.08); color: var(--text-2); }
.badge-pro { background: rgb(229 9 20 / 0.16); color: #ff6b70; }
.badge-ultra { background: rgb(245 197 24 / 0.14); color: var(--warn); }
.badge-ok { background: rgb(70 211 105 / 0.14); color: var(--ok); }
.meters { display: grid; grid-template-columns: repeat(auto-fit, minmax(130px, 1fr)); gap: 16px 20px; }
.meter-label { display: flex; justify-content: space-between; font-size: 13px; color: var(--text-2); margin-bottom: 8px; }
.meter-track { height: 4px; border-radius: 2px; background: rgb(255 255 255 / 0.08); overflow: hidden; }
.meter-fill { height: 100%; border-radius: 2px; background: var(--text); transform-origin: left; transition: scale 400ms var(--ease-out); }

/* Segmented control */
.seg { display: flex; padding: 3px; gap: 2px; background: rgb(255 255 255 / 0.06); border-radius: 11px; }
.seg label { flex: 1; text-align: center; padding: 8px 10px; border-radius: 8px; font-size: 14px; font-weight: 500; color: var(--text-2); cursor: pointer; transition: background-color 150ms ease, color 150ms ease; }
.seg input { position: absolute; opacity: 0; pointer-events: none; }
.seg label:has(input:checked) { background: var(--panel-raised); color: var(--text); box-shadow: 0 1px 3px rgb(0 0 0 / 0.4); }

/* Dialogs: bottom sheet on phones, centered card on wide screens. Exit is faster than enter. */
dialog.sheet {
  margin: auto 0 0; width: 100%; max-width: 100%; max-height: 92dvh;
  background: var(--panel); color: var(--text); border: 0; border-radius: 20px 20px 0 0;
  padding: 0 0 env(safe-area-inset-bottom); box-shadow: var(--shadow-pop);
  overflow: auto; overscroll-behavior: contain;
  opacity: 0; transform: translateY(100%);
  transition: opacity 150ms ease-out, transform 200ms var(--ease-out), overlay 200ms allow-discrete, display 200ms allow-discrete;
}
dialog.sheet[open] { opacity: 1; transform: none; transition-duration: 200ms, 350ms, 350ms, 350ms; transition-timing-function: ease-out, var(--ease-drawer); }
@starting-style { dialog.sheet[open] { opacity: 0; transform: translateY(100%); } }
dialog.sheet::backdrop { background: rgb(0 0 0 / 0); transition: background-color 200ms ease, overlay 200ms allow-discrete, display 200ms allow-discrete; }
dialog.sheet[open]::backdrop { background: rgb(0 0 0 / 0.6); }
@starting-style { dialog.sheet[open]::backdrop { background: rgb(0 0 0 / 0); } }
.sheet-head { position: sticky; top: 0; z-index: 1; display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 18px 20px 12px; background: var(--panel); }
.sheet-body { padding: 4px 20px 20px; display: grid; gap: 16px; }
.sheet-foot { display: flex; gap: 8px; justify-content: flex-end; padding: 0 20px 20px; }
.sheet-foot .spacer { flex: 1; }
@media (min-width: 640px) {
  dialog.sheet { margin: auto; width: min(460px, calc(100% - 32px)); border-radius: var(--r-lg); padding: 0; transform: translateY(8px) scale(0.98); }
  @starting-style { dialog.sheet[open] { transform: translateY(8px) scale(0.98); } }
  dialog.sheet.drawer { margin: 0 0 0 auto; height: 100dvh; max-height: 100dvh; width: min(520px, 100%); border-radius: 0; transform: translateX(32px); }
  dialog.sheet.drawer[open] { transform: none; }
  @starting-style { dialog.sheet.drawer[open] { transform: translateX(32px); } }
}

/* Toast */
.toast {
  position: fixed; inset: auto auto calc(24px + env(safe-area-inset-bottom)) 50%; margin: 0; border: 0; color: var(--text);
  translate: -50% 0; max-width: calc(100% - 32px); overflow: visible;
  display: flex; align-items: center; gap: 10px; padding: 12px 16px; border-radius: 14px;
  background: #2c2c30; box-shadow: var(--shadow-pop); font-size: 14px; font-weight: 500;
  opacity: 0; transform: translateY(12px); pointer-events: none;
  transition: opacity 150ms ease-out, transform 150ms ease-out;
}
.toast.is-visible { opacity: 1; transform: none; transition-duration: 250ms; }
.toast[data-tone="error"] { color: #ffb4b0; }
.toast[data-tone="success"] .icon { color: var(--ok); }

/* View entrance: only on navigation, never on high-frequency actions. */
.view { animation: view-in 250ms var(--ease-out) both; }
@keyframes view-in { from { opacity: 0; transform: translateY(8px); } }

@media (prefers-reduced-motion: reduce) {
  dialog.sheet, dialog.sheet[open], .toast, .toast.is-visible { transform: none !important; }
  @starting-style { dialog.sheet[open] { transform: none; } }
  .view { animation-name: view-fade; }
  .meter-fill { transition: none; }
  .btn:not(:disabled):active { scale: 1; }
}
@keyframes view-fade { from { opacity: 0; } }
`;

const runtime = String.raw`
function $(sel, root) { return (root || document).querySelector(sel); }
function $all(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }

function esc(value) {
  return String(value == null ? '' : value)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function icon(name) {
  return '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">' + (ICONS[name] || '') + '</svg>';
}

var toastTimer = null;
function toast(message, tone) {
  var el = $('#toast');
  el.dataset.tone = tone || 'normal';
  el.innerHTML = (tone === 'success' ? icon('check') : '') + '<span>' + esc(message) + '</span>';
  // Re-showing the popover lifts it into the top layer, above any open modal dialog.
  if (el.showPopover) { if (el.matches(':popover-open')) el.hidePopover(); el.showPopover(); }
  el.classList.add('is-visible');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(function () { el.classList.remove('is-visible'); }, 3200);
}

/** JSON fetch that never throws: resolves { ok, status, data }. */
function api(path, options) {
  options = options || {};
  var headers = Object.assign({ 'Content-Type': 'application/json' }, options.headers || {});
  if (options.token) headers.Authorization = 'Bearer ' + options.token;
  return fetch(path, {
    method: options.method || (options.body ? 'POST' : 'GET'),
    headers: headers,
    body: options.body ? JSON.stringify(options.body) : undefined
  }).then(function (res) {
    return res.json().catch(function () { return {}; }).then(function (data) {
      return { ok: res.ok, status: res.status, data: data };
    });
  }).catch(function () {
    return { ok: false, status: 0, data: { error: 'Connexion impossible. Vérifiez votre réseau.' } };
  });
}

/** Swaps a button's label for a spinner while work runs, and restores it after. */
function withBusy(button, work) {
  if (!button) return work();
  var label = button.innerHTML;
  button.disabled = true;
  button.innerHTML = '<span class="spinner" aria-hidden="true"></span><span class="sr-only">Chargement</span>';
  return Promise.resolve().then(work).finally(function () {
    button.disabled = false;
    button.innerHTML = label;
  });
}

function closeDialog(dialog) { if (dialog && dialog.open) dialog.close(); }

document.addEventListener('click', function (event) {
  var closer = event.target.closest('[data-close]');
  if (closer) closeDialog(closer.closest('dialog'));
  // A click on the backdrop lands on the dialog element itself.
  if (event.target.tagName === 'DIALOG') closeDialog(event.target);

  var toggle = event.target.closest('[data-menu-toggle]');
  if (toggle) {
    var menu = toggle.closest('.menu');
    var open = menu && menu.classList.contains('is-open');
    closeMenus();
    if (menu && !open) openMenu(menu);
    return;
  }
  if (!event.target.closest('.menu')) closeMenus();
});

document.addEventListener('keydown', function (event) {
  if (event.key === 'Escape') closeMenus();
});

function openMenu(menu) {
  var pop = menu.querySelector('.menu-pop');
  var toggle = menu.querySelector('[data-menu-toggle]');
  if (!pop || !toggle) return;
  menu.classList.add('is-open');
  pop.hidden = false;
  toggle.setAttribute('aria-expanded', 'true');
  // Fixed so overflow:hidden on .list does not clip the popover.
  var rect = toggle.getBoundingClientRect();
  pop.style.position = 'fixed';
  pop.style.top = Math.round(rect.bottom + 4) + 'px';
  pop.style.right = Math.round(window.innerWidth - rect.right) + 'px';
  pop.style.left = 'auto';
}

function closeMenus() {
  $all('.menu.is-open').forEach(function (menu) {
    menu.classList.remove('is-open');
    var pop = menu.querySelector('.menu-pop');
    var toggle = menu.querySelector('[data-menu-toggle]');
    if (pop) {
      pop.hidden = true;
      pop.style.top = '';
      pop.style.right = '';
      pop.style.position = '';
    }
    if (toggle) toggle.setAttribute('aria-expanded', 'false');
  });
}

/**
 * Asks before a destructive action. With requireText, the confirm button stays
 * disabled until that exact text is typed.
 */
function confirmAction(options) {
  var dialog = $('#confirm-dialog');
  $('#confirm-title').textContent = options.title;
  $('#confirm-body').textContent = options.body || '';
  var input = $('#confirm-input');
  var field = $('#confirm-field');
  var ok = $('#confirm-ok');
  ok.textContent = options.confirmLabel || 'Confirmer';
  ok.className = 'btn ' + (options.danger ? 'btn-danger' : 'btn-primary');
  field.hidden = !options.requireText;
  input.value = '';
  $('#confirm-hint').textContent = options.requireText ? 'Saisissez « ' + options.requireText + ' » pour confirmer' : '';
  ok.disabled = !!options.requireText;
  input.oninput = function () { ok.disabled = input.value.trim() !== options.requireText; };
  return new Promise(function (resolve) {
    var confirmed = false;
    ok.onclick = function () { confirmed = true; dialog.close(); };
    dialog.addEventListener('close', function () { resolve(confirmed); }, { once: true });
    dialog.showModal();
    (options.requireText ? input : ok).focus();
  });
}

function relativeTime(ms) {
  if (!ms) return 'jamais';
  var minutes = Math.round((Date.now() - ms) / 60000);
  if (minutes < 2) return "à l'instant";
  if (minutes < 60) return 'il y a ' + minutes + ' min';
  var hours = Math.round(minutes / 60);
  if (hours < 24) return 'il y a ' + hours + ' h';
  var days = Math.round(hours / 24);
  if (days < 30) return 'il y a ' + days + ' j';
  return new Date(ms).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short', year: 'numeric' });
}

function planBadge(plan) {
  var label = { free: 'Free', pro: 'Pro', ultra: 'Ultra' }[plan] || 'Free';
  return '<span class="badge badge-' + esc(plan || 'free') + '">' + label + '</span>';
}

function meter(label, used, max) {
  var ratio = max > 0 ? Math.min(1, used / max) : 0;
  return '<div><div class="meter-label"><span>' + esc(label) + '</span><span class="num">' + used + ' / ' + max + '</span></div>' +
    '<div class="meter-track" role="progressbar" aria-label="' + esc(label) + '" aria-valuemin="0" aria-valuemax="' + max + '" aria-valuenow="' + used + '">' +
    '<div class="meter-fill" style="scale: ' + ratio + ' 1"></div></div></div>';
}
`;

const sharedMarkup = `
<div id="toast" class="toast" role="status" aria-live="polite" popover="manual"></div>
<dialog id="confirm-dialog" class="sheet" aria-labelledby="confirm-title">
  <div class="sheet-head"><h2 id="confirm-title" class="title-md"></h2></div>
  <div class="sheet-body">
    <p id="confirm-body" class="muted"></p>
    <label id="confirm-field" class="field" hidden><span id="confirm-hint"></span><input id="confirm-input" autocomplete="off" spellcheck="false"></label>
  </div>
  <div class="sheet-foot"><button class="btn btn-quiet" data-close>Annuler</button><button id="confirm-ok" class="btn"></button></div>
</dialog>`;

/** Wraps a page body in the shared document, tokens and runtime. */
export function renderPage(options: { title: string; styles?: string; body: string; script: string }): string {
  return `<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#141414">
<meta name="robots" content="noindex">
<title>${options.title}</title>
<style>${styles}${options.styles || ''}</style>
</head>
<body>
${options.body}
${sharedMarkup}
<script>
var ICONS = ${JSON.stringify(ICONS)};
${runtime}
${options.script}
</script>
</body>
</html>`;
}
