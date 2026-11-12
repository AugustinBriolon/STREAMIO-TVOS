/**
 * Web companion portal (QR pair / foyer admin).
 * Served at `/` and `/pair` — keep HTML/CSS/JS here, not in the API worker.
 */

export function renderWebPortal(prefillCode: string): string {
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

    /* Offre foyer — statut compact ; catalogue dans la modal */
    .plan-status {
      background: var(--tv-surface-subtle);
      border: 1px solid var(--tv-border);
      border-radius: 18px;
      padding: 14px;
      margin-bottom: 14px;
      box-shadow: 0 1px 0 rgba(255, 255, 255, 0.06);
    }
    .plan-status-head {
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      gap: 12px;
      margin-bottom: 12px;
    }
    .plan-status-kicker {
      font-size: 11px;
      font-weight: 600;
      letter-spacing: 0.04em;
      text-transform: uppercase;
      color: var(--tv-text-tertiary);
      margin-bottom: 4px;
    }
    .plan-status-title {
      font-size: 18px;
      font-weight: 700;
      letter-spacing: -0.02em;
      line-height: 1.15;
      color: var(--tv-text-primary);
    }
    .plan-status-sync {
      margin-top: 4px;
      font-size: 12px;
      color: var(--tv-text-secondary);
      line-height: 1.35;
    }
    .plan-status-chip {
      flex-shrink: 0;
      font-size: 10px;
      font-weight: 700;
      letter-spacing: 0.04em;
      text-transform: uppercase;
      color: #0b0b0b;
      background: var(--tv-match);
      border-radius: 999px;
      padding: 4px 9px;
    }
    .plan-status-chip.is-free {
      color: var(--tv-text-secondary);
      background: var(--tv-surface-raised);
    }
    .plan-usage {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 8px;
      margin-bottom: 12px;
    }
    .plan-meter {
      background: rgba(0, 0, 0, 0.28);
      border: 1px solid transparent;
      border-radius: 12px;
      padding: 10px 10px 9px;
      box-shadow: 0 0 0 1px var(--tv-border);
    }
    .plan-meter-label {
      font-size: 11px;
      color: var(--tv-text-tertiary);
      margin-bottom: 4px;
    }
    .plan-meter-value {
      font-size: 14px;
      font-weight: 700;
      font-variant-numeric: tabular-nums;
      letter-spacing: -0.01em;
      color: var(--tv-text-primary);
    }
    .plan-meter-track {
      margin-top: 8px;
      height: 3px;
      border-radius: 999px;
      background: rgba(255, 255, 255, 0.08);
      overflow: hidden;
    }
    .plan-meter-fill {
      height: 100%;
      width: var(--meter, 0%);
      border-radius: inherit;
      background: var(--tv-match);
      transition: width 250ms var(--tv-ease-critique);
    }
    .plan-status-cta {
      width: 100%;
      height: 40px;
      border: 1px solid var(--tv-border);
      border-radius: var(--tv-radius-control);
      background: var(--tv-surface-raised);
      color: var(--tv-text-primary);
      font-size: 13px;
      font-weight: 600;
      cursor: pointer;
      transition: transform 150ms ease-out, background-color 150ms ease, border-color 150ms ease;
    }
    .plan-status-cta:not(:disabled):active { transform: scale(0.96); }
    @media (hover: hover) and (pointer: fine) {
      .plan-status-cta:hover {
        background: rgba(255, 255, 255, 0.18);
        border-color: var(--tv-border-focus);
      }
    }

    .plans-modal {
      position: fixed;
      inset: 0;
      z-index: 1100;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 16px;
      visibility: hidden;
      pointer-events: none;
    }
    .plans-modal.is-open {
      visibility: visible;
      pointer-events: auto;
    }
    .plans-modal-backdrop {
      position: absolute;
      inset: 0;
      border: 0;
      padding: 0;
      margin: 0;
      background: rgba(0, 0, 0, 0.58);
      cursor: pointer;
      opacity: 0;
      transition: opacity 250ms var(--tv-ease-critique);
    }
    .plans-modal.is-open .plans-modal-backdrop { opacity: 1; }
    .plans-modal.is-closing .plans-modal-backdrop { transition-duration: 150ms; }
    .plans-modal-panel {
      position: relative;
      width: min(100%, 420px);
      max-height: min(86dvh, 640px);
      overflow: auto;
      overscroll-behavior: contain;
      background: #1a1a1a;
      border: 1px solid transparent;
      border-radius: 32px;
      padding: 18px;
      box-shadow:
        0 0 0 1px rgba(255, 255, 255, 0.10),
        0 28px 60px -16px rgba(0, 0, 0, 0.78),
        inset 0 1px 0 rgba(255, 255, 255, 0.12);
      opacity: 0;
      transform: scale(0.96) translateY(12px);
      filter: blur(4px);
      transform-origin: center;
      transition:
        opacity 250ms var(--tv-ease-critique),
        transform 250ms var(--tv-ease-critique),
        filter 250ms var(--tv-ease-critique);
    }
    .plans-modal.is-open .plans-modal-panel {
      opacity: 1;
      transform: scale(1) translateY(0);
      filter: blur(0);
    }
    .plans-modal.is-closing .plans-modal-panel { transition-duration: 150ms; }
    .plans-modal-head {
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      gap: 12px;
      margin-bottom: 14px;
    }
    .plans-modal-title {
      font-size: 18px;
      font-weight: 700;
      letter-spacing: -0.02em;
      line-height: 1.15;
    }
    .plans-modal-sub {
      margin-top: 4px;
      font-size: 12px;
      color: var(--tv-text-secondary);
      line-height: 1.4;
    }
    .plans-modal-close {
      width: 36px;
      height: 36px;
      border-radius: 999px;
      border: 1px solid var(--tv-border);
      background: var(--tv-surface-raised);
      color: var(--tv-text-primary);
      font-size: 18px;
      line-height: 1;
      cursor: pointer;
      flex-shrink: 0;
      transition: transform 150ms ease-out, background-color 150ms ease;
    }
    .plans-modal-close:not(:disabled):active { transform: scale(0.96); }
    .plan-offer {
      background: var(--tv-surface-subtle);
      border: 1px solid var(--tv-border);
      border-radius: 14px;
      padding: 14px;
      margin-bottom: 8px;
      transition: border-color 150ms var(--tv-ease-critique), background-color 150ms var(--tv-ease-critique);
    }
    .plan-offer:last-of-type { margin-bottom: 0; }
    .plan-offer.is-current {
      border-color: rgba(70, 211, 105, 0.55);
      background: rgba(70, 211, 105, 0.08);
    }
    .plan-offer.is-emphasis:not(.is-current) {
      border-color: rgba(255, 255, 255, 0.22);
    }
    .plan-offer-top {
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      gap: 10px;
      margin-bottom: 8px;
    }
    .plan-offer-name {
      font-size: 15px;
      font-weight: 700;
      letter-spacing: -0.01em;
    }
    .plan-offer-price {
      font-size: 13px;
      font-weight: 600;
      color: var(--tv-text-secondary);
      font-variant-numeric: tabular-nums;
      white-space: nowrap;
    }
    .plan-offer-features {
      list-style: none;
      display: grid;
      gap: 5px;
      margin: 0;
      padding: 0;
    }
    .plan-offer-features li {
      font-size: 12px;
      color: var(--tv-text-secondary);
      line-height: 1.35;
      padding-left: 14px;
      position: relative;
    }
    .plan-offer-features li::before {
      content: "";
      position: absolute;
      left: 0;
      top: 0.55em;
      width: 5px;
      height: 5px;
      border-radius: 999px;
      background: var(--tv-text-tertiary);
    }
    .plan-offer.is-current .plan-offer-features li::before { background: var(--tv-match); }
    .plan-offer-badge {
      display: inline-block;
      margin-top: 10px;
      font-size: 10px;
      font-weight: 700;
      letter-spacing: 0.04em;
      text-transform: uppercase;
      color: #0b0b0b;
      background: var(--tv-match);
      border-radius: 999px;
      padding: 3px 8px;
    }
    .plans-modal-note {
      margin-top: 12px;
      font-size: 12px;
      color: var(--tv-text-tertiary);
      line-height: 1.45;
      text-align: center;
    }
    body.plans-modal-open { overflow: hidden; }
    @media (prefers-reduced-motion: reduce) {
      .plan-meter-fill { transition: none; }
      .plan-status-cta, .plans-modal-close { transition: none; transform: none !important; }
      .plans-modal-backdrop,
      .plans-modal-panel {
        transition: opacity 200ms ease;
        transform: none !important;
        filter: none !important;
      }
    }

    .device-row-icon {
      width: 28px;
      height: 28px;
      border-radius: 8px;
      background: var(--tv-surface-raised);
      display: inline-flex;
      align-items: center;
      justify-content: center;
      font-size: 14px;
      flex-shrink: 0;
    }

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
    .user-plan {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      margin-top: 4px;
      font-size: 11px;
      font-weight: 700;
      letter-spacing: 0.02em;
      color: #0b0b0b;
      background: var(--tv-match);
      border: 0;
      border-radius: 999px;
      padding: 3px 9px;
      width: fit-content;
      cursor: pointer;
      font-family: inherit;
      transition: transform 150ms ease-out, filter 150ms ease;
    }
    .user-plan:not(:disabled):active { transform: scale(0.96); }
    .user-plan.is-free {
      color: var(--tv-text-secondary);
      background: var(--tv-surface-raised);
    }
    @media (hover: hover) and (pointer: fine) {
      .user-plan:hover { filter: brightness(1.08); }
    }
    @media (prefers-reduced-motion: reduce) {
      .user-plan { transition: none; transform: none !important; }
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
        <div class="pairing-card" id="pairing-card-auth" style="display: ${prefillCode && prefillCode !== 'LOGE-XXXX' ? 'flex' : 'none'};">
          <div class="pairing-device">
            <div class="pulse-dot"></div>
            <div>
              <div class="device-title">Apple TV à proximité</div>
              <div class="device-sub">Jumelage automatique</div>
            </div>
          </div>
          <div class="pairing-code-badge">${prefillCode || 'LOGE-XXXX'}</div>
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
          <div style="display:flex;flex-direction:column;align-items:flex-end;gap:8px;flex-shrink:0;">
            <button type="button" class="user-plan is-free" id="user-plan-display" onclick="openPlansModal()" aria-haspopup="dialog" aria-controls="plans-modal">Offre Free</button>
            <button type="button" class="tv-btn-secondary" onclick="handleLogout()" style="padding: 0 10px; height: 32px; font-size: 11.5px;">Déconnexion</button>
          </div>
        </div>

        <div id="plan-summary" aria-live="polite"></div>

        <!-- Appel d'action Apple TV si un code d'appairage est présent -->
        <div id="dash-pair-banner" class="pairing-card" style="display: ${prefillCode && prefillCode !== 'LOGE-XXXX' ? 'flex' : 'none'};">
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

          <div id="addon-limit-hint" style="display:none;font-size:12px;color:var(--tv-text-tertiary);margin-bottom:10px;text-align:center;line-height:1.45;"></div>
          <div id="addon-install-box" style="background: var(--tv-surface-subtle); border: 1px dashed var(--tv-border); border-radius: var(--tv-radius-control); padding: 12px;">
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
      <span>Loge 2.0 · offre</span>
      <span class="footer-dot"></span>
      <span>Cloudflare D1</span>
      <span class="footer-dot"></span>
      <span>Chiffré</span>
    </div>
  </div>

  <!-- OFFRES — modal catalogue (achats sur Apple TV) -->
  <div class="plans-modal" id="plans-modal" aria-hidden="true">
    <button type="button" class="plans-modal-backdrop" onclick="closePlansModal()" aria-label="Fermer"></button>
    <div class="plans-modal-panel" role="dialog" aria-modal="true" aria-labelledby="plans-modal-title" tabindex="-1">
      <div class="plans-modal-head">
        <div>
          <div class="plans-modal-title" id="plans-modal-title">Offres Loge</div>
          <div class="plans-modal-sub">Une offre pour tout le foyer. Comparaison informative — l’achat se fait sur l’Apple TV.</div>
        </div>
        <button type="button" class="plans-modal-close" onclick="closePlansModal()" aria-label="Fermer">×</button>
      </div>
      <div id="plans-modal-list"></div>
      <p class="plans-modal-note">Pour passer à Pro ou Ultra, ouvrez Réglages → Abonnement sur votre Apple TV.</p>
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
      return !!(pairCode && pairCode !== 'LOGE-XXXX');
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
          body: JSON.stringify({
            email,
            password,
            deviceName: 'Navigateur web',
            deviceModel: browserLabel(),
            clientKind: 'browser'
          })
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
            'X-Device-Model': browserLabel(),
            'X-Client-Kind': 'browser'
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
        window.accountPlan = accountData.plan || 'free';
        window.accountLimits = accountData.limits || { maxProfiles: 1, maxAddons: 1, maxTVSessions: 1, maxBrowserSessions: 1, cloudSync: false, canRenameDevices: false };

        renderPlanBadge();
        renderPlanSummary();
        renderProfiles(accountData.profiles || []);
        renderAddons(accountData.addons || []);
        await loadDevices();
      } catch (e) {
        showToast('Erreur lors du chargement des données', 'error');
      }
    }

    const PLAN_CATALOG = [
      {
        id: 'free', name: 'Free', price: 'Gratuit', emphasis: false,
        features: ['1 profil', '1 addon', '1 Apple TV · 1 navigateur', 'Données locales uniquement', 'Noms appareils fixes']
      },
      {
        id: 'pro', name: 'Pro', price: '3,99 € / mois', emphasis: true,
        features: ['3 profils', '5 addons', '2 Apple TV · 1 navigateur', 'Sync cloud foyer', 'Renommer les appareils']
      },
      {
        id: 'ultra', name: 'Ultra', price: '7,99 € / mois', emphasis: true,
        features: ['6 profils', '20 addons', '4 Apple TV · 2 navigateurs', 'Sync cloud foyer', 'Renommer les appareils']
      }
    ];

    let plansModalLastFocus = null;
    let plansModalClosing = false;

    function renderPlanBadge() {
      const plan = window.accountPlan || 'free';
      const el = document.getElementById('user-plan-display');
      if (!el) return;
      el.textContent = 'Offre ' + planLabel(plan);
      el.classList.toggle('is-free', plan === 'free');
    }

    function planUsageCounts() {
      const profiles = (accountData && Array.isArray(accountData.profiles))
        ? accountData.profiles.length
        : cachedProfiles.length;
      const addons = (accountData && Array.isArray(accountData.addons))
        ? accountData.addons.length
        : (Array.isArray(window.accountAddons) ? window.accountAddons.length : 0);
      return { profiles: profiles, addons: addons };
    }

    function meterPct(used, max) {
      const m = Math.max(1, Number(max) || 1);
      const u = Math.max(0, Number(used) || 0);
      return Math.max(4, Math.min(100, Math.round((u / m) * 100)));
    }

    function renderPlanSummary() {
      const plan = window.accountPlan || 'free';
      const limits = window.accountLimits || {};
      const usage = planUsageCounts();
      const sync = limits.cloudSync ? 'Sync cloud active' : 'Données locales uniquement';
      const maxProfiles = Number(limits.maxProfiles || 1);
      const maxAddons = Number(limits.maxAddons || 1);
      const html =
        '<section class="plan-status" aria-label="Offre actuelle">' +
          '<div class="plan-status-head">' +
            '<div>' +
              '<div class="plan-status-kicker">Offre du foyer</div>' +
              '<div class="plan-status-title">' + escapeHtml(planLabel(plan)) + '</div>' +
              '<div class="plan-status-sync">' + escapeHtml(sync) + '</div>' +
            '</div>' +
            '<span class="plan-status-chip' + (plan === 'free' ? ' is-free' : '') + '">Actuel</span>' +
          '</div>' +
          '<div class="plan-usage">' +
            '<div class="plan-meter">' +
              '<div class="plan-meter-label">Profils</div>' +
              '<div class="plan-meter-value">' + usage.profiles + '<span style="color:var(--tv-text-tertiary);font-weight:600"> / ' + maxProfiles + '</span></div>' +
              '<div class="plan-meter-track"><div class="plan-meter-fill" style="--meter:' + meterPct(usage.profiles, maxProfiles) + '%"></div></div>' +
            '</div>' +
            '<div class="plan-meter">' +
              '<div class="plan-meter-label">Add-ons</div>' +
              '<div class="plan-meter-value">' + usage.addons + '<span style="color:var(--tv-text-tertiary);font-weight:600"> / ' + maxAddons + '</span></div>' +
              '<div class="plan-meter-track"><div class="plan-meter-fill" style="--meter:' + meterPct(usage.addons, maxAddons) + '%"></div></div>' +
            '</div>' +
          '</div>' +
          '<button type="button" class="plan-status-cta" onclick="openPlansModal()">Comparer les offres</button>' +
        '</section>';
      document.getElementById('plan-summary').innerHTML = html;
    }

    function renderPlansModalList() {
      const plan = window.accountPlan || 'free';
      const list = document.getElementById('plans-modal-list');
      if (!list) return;
      list.innerHTML = PLAN_CATALOG.map(function(c) {
        const current = c.id === plan;
        return '<article class="plan-offer' + (current ? ' is-current' : '') + (c.emphasis && !current ? ' is-emphasis' : '') + '">' +
          '<div class="plan-offer-top">' +
            '<div class="plan-offer-name">' + c.name + '</div>' +
            '<div class="plan-offer-price">' + c.price + '</div>' +
          '</div>' +
          '<ul class="plan-offer-features">' + c.features.map(function(f) {
            return '<li>' + escapeHtml(f) + '</li>';
          }).join('') + '</ul>' +
          (current ? '<span class="plan-offer-badge">Actuel</span>' : '') +
        '</article>';
      }).join('');
    }

    function openPlansModal() {
      const modal = document.getElementById('plans-modal');
      if (!modal || modal.classList.contains('is-open')) return;
      plansModalClosing = false;
      modal.classList.remove('is-closing');
      renderPlansModalList();
      plansModalLastFocus = document.activeElement;
      document.body.classList.add('plans-modal-open');
      modal.setAttribute('aria-hidden', 'false');
      // Force style flush so the enter transition runs from the closed presentation values.
      void modal.offsetWidth;
      modal.classList.add('is-open');
      const panel = modal.querySelector('.plans-modal-panel');
      if (panel) panel.focus({ preventScroll: true });
    }

    function closePlansModal() {
      const modal = document.getElementById('plans-modal');
      if (!modal || !modal.classList.contains('is-open') || plansModalClosing) return;
      plansModalClosing = true;
      modal.classList.add('is-closing');
      modal.classList.remove('is-open');
      modal.setAttribute('aria-hidden', 'true');
      document.body.classList.remove('plans-modal-open');
      const panel = modal.querySelector('.plans-modal-panel');
      let finished = false;
      const finish = function() {
        if (finished) return;
        finished = true;
        modal.classList.remove('is-closing');
        plansModalClosing = false;
        if (plansModalLastFocus && typeof plansModalLastFocus.focus === 'function') {
          plansModalLastFocus.focus({ preventScroll: true });
        }
        plansModalLastFocus = null;
      };
      if (!panel) { finish(); return; }
      const onEnd = function(e) {
        if (e.target !== panel) return;
        panel.removeEventListener('transitionend', onEnd);
        finish();
      };
      panel.addEventListener('transitionend', onEnd);
      setTimeout(finish, 220);
    }

    document.addEventListener('keydown', function(e) {
      if (e.key === 'Escape') closePlansModal();
    });

    function planLabel(plan) {
      if (plan === 'pro') return 'Pro';
      if (plan === 'ultra') return 'Ultra';
      return 'Free';
    }

    function deviceGlyph(d) {
      const kind = d.kind === 'browser' ? 'browser' : 'tv';
      if (kind !== 'browser') return '📺';
      const model = (d.model || '').toLowerCase();
      if (model.indexOf('mac') !== -1) return '💻';
      if (model.indexOf('ipad') !== -1) return '📱';
      if (model.indexOf('iphone') !== -1 || model.indexOf('ios') !== -1) return '📱';
      if (model.indexOf('windows') !== -1 || model.indexOf('pc') !== -1) return '🖥️';
      return '🌐';
    }

    function renderProfiles(profiles) {
      cachedProfiles = profiles || [];
      if (accountData) accountData.profiles = cachedProfiles;
      const container = document.getElementById('profiles-list');
      syncCreateProfileButton();
      if (document.getElementById('plan-summary')) renderPlanSummary();

      if (!cachedProfiles.length) {
        container.innerHTML = '<div style="font-size: 13px; color: var(--tv-text-tertiary); text-align: center; padding: 12px;">Aucun profil trouvé.</div>';
        return;
      }

      const capNote = cachedProfiles.length >= maxProfiles()
        ? '<div style="font-size:12px;color:var(--tv-text-tertiary);margin-bottom:8px;text-align:center">Limite atteinte : ' + maxProfiles() + ' profil' + (maxProfiles() > 1 ? 's' : '') + ' sur votre offre.</div>'
        : '';

      container.innerHTML = capNote + cachedProfiles.map(function(p) {
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
      if (!editingProfileId && cachedProfiles.length >= maxProfiles()) {
        showToast('Nombre maximum de profils atteint (' + maxProfiles() + ').', 'error');
        return;
      }
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

    function maxProfiles() {
      return Number((window.accountLimits && window.accountLimits.maxProfiles) || 1);
    }

    function maxAddons() {
      return Number((window.accountLimits && window.accountLimits.maxAddons) || 1);
    }

    function syncCreateProfileButton() {
      const editorOpen = !document.getElementById('profile-editor').hidden;
      document.getElementById('profile-create-btn').style.display =
        cachedProfiles.length >= maxProfiles() || editorOpen ? 'none' : 'flex';
    }

    function syncAddonInstaller() {
      const box = document.getElementById('addon-install-box');
      if (!box) return;
      const list = (window.accountAddons || []);
      const atCap = list.length >= maxAddons();
      box.style.display = atCap ? 'none' : 'block';
      const hint = document.getElementById('addon-limit-hint');
      if (hint) {
        hint.style.display = atCap ? 'block' : 'none';
        hint.textContent = 'Limite atteinte : ' + maxAddons() + ' addon' + (maxAddons() > 1 ? 's' : '') + ' sur votre offre. Gérez l\\'abonnement sur l\\'Apple TV.';
      }
    }

    function closeProfileEditor() {
      editingProfileId = null;
      document.getElementById('profile-editor').hidden = true;
      syncCreateProfileButton();
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
      if (!editingProfileId && cachedProfiles.length >= maxProfiles()) {
        showToast('Nombre maximum de profils atteint (' + maxProfiles() + ').', 'error');
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
      const list = addons || [];
      window.accountAddons = list;
      if (accountData) accountData.addons = list;
      const container = document.getElementById('addons-list');
      syncAddonInstaller();
      if (document.getElementById('plan-summary')) renderPlanSummary();
      if (!list.length) {
        container.innerHTML = '<div style="font-size: 13px; color: var(--tv-text-tertiary); text-align: center; padding: 12px;">Aucune extension personnalisée installée.</div>';
        return;
      }

      container.innerHTML = list.map(function(url) {
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
            'X-Device-Model': browserLabel(),
            'X-Client-Kind': 'browser'
          }
        });
        if (res.status === 401) { handleLogout(); return; }
        const data = await res.json();
        if (data.token) localStorage.setItem('loge_token', data.token);
        if (data.plan) window.accountPlan = data.plan;
        if (data.limits) window.accountLimits = data.limits;
        renderPlanBadge();
        renderPlanSummary();
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
      const canRename = !!(window.accountLimits && window.accountLimits.canRenameDevices);
      container.innerHTML = devices.map(function(d) {
        const kindLabel = d.kind === 'browser' ? 'Navigateur' : 'Apple TV';
        const subtitle = [kindLabel, d.model, formatLastSeen(d.lastSeenAtMs)].filter(Boolean).join(' · ');
        const rename = canRename
          ? '<button type="button" class="tv-btn-secondary" style="height:36px;padding:0 12px;margin-right:8px" data-id="' + escapeHtml(d.id) + '" data-name="' + escapeHtml(d.name) + '" onclick="handleRenameDevice(this.dataset.id, this.dataset.name)">Renommer</button>'
          : '';
        const action = d.isCurrent
          ? '<span class="device-current">Cet appareil</span>'
          : '<button type="button" class="tv-btn-danger" data-id="' + escapeHtml(d.id) + '" onclick="handleRevokeDevice(this.dataset.id)">Déconnecter</button>';
        return '<div class="addon-card">' +
          '<div style="display:flex;align-items:center;gap:10px;min-width:0;flex:1">' +
            '<div class="device-row-icon" aria-hidden="true">' + deviceGlyph(d) + '</div>' +
            '<div class="addon-meta" style="min-width:0">' +
              '<div class="addon-name">' + escapeHtml(d.name) + '</div>' +
              '<div class="addon-host">' + escapeHtml(subtitle) + '</div>' +
            '</div>' +
          '</div>' +
          '<div style="display:flex;align-items:center;gap:8px;flex-shrink:0">' + rename + action + '</div>' +
        '</div>';
      }).join('');
      if (!canRename) {
        container.innerHTML += '<div style="font-size:12px;color:var(--tv-text-tertiary);margin-top:8px;text-align:center">Renommer les appareils : offre Pro ou Ultra (gérer l\\'abonnement sur l\\'Apple TV).</div>';
      }
    }

    async function handleRenameDevice(id, currentName) {
      const next = prompt('Nouveau nom de l\\'appareil', currentName || '');
      if (next == null) return;
      const clean = next.trim().slice(0, 32);
      if (!clean) { showToast('Nom invalide.', 'error'); return; }
      const token = localStorage.getItem('loge_token');
      try {
        const res = await fetch('/api/devices/rename', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token },
          body: JSON.stringify({ id: id, displayName: clean })
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Erreur');
        showToast('Appareil renommé.', 'success');
        await loadDevices();
      } catch (err) {
        showToast(err.message, 'error');
      }
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
      const current = window.accountAddons || [];

      if (!manifestUrl) {
        showToast('Veuillez renseigner une URL manifest.json', 'error');
        return;
      }
      if (current.indexOf(manifestUrl) === -1 && current.length >= maxAddons()) {
        showToast('Nombre maximum d\\'addons atteint (' + maxAddons() + ').', 'error');
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
