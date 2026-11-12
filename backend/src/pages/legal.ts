/** Static legal HTML pages — same material language as the foyer portal. */

const shell = (title: string, body: string) => `<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <meta name="theme-color" content="#141414">
  <title>${title} — Loge</title>
  <style>
    :root {
      --canvas: #141414;
      --text: #fff;
      --secondary: rgba(255,255,255,.72);
      --tertiary: rgba(255,255,255,.44);
      --border: rgba(255,255,255,.10);
      --accent: #E50914;
      --ease: cubic-bezier(0.2, 0, 0, 1);
    }
    * { box-sizing: border-box; margin: 0; padding: 0; -webkit-font-smoothing: antialiased; }
    body {
      min-height: 100dvh;
      background:
        radial-gradient(ellipse 80% 50% at 50% -10%, rgba(229,9,20,.12), transparent 70%),
        var(--canvas);
      color: var(--text);
      font: 400 15px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
      padding: 28px 18px 48px;
    }
    .wrap { width: min(100%, 40rem); margin: 0 auto; }
    .top {
      display: flex; align-items: center; justify-content: space-between; gap: 12px;
      margin-bottom: 28px;
    }
    .brand {
      font-size: 18px; font-weight: 800; letter-spacing: -0.02em; color: var(--text);
      text-decoration: none;
    }
    .back {
      height: 36px; padding: 0 14px; border-radius: 999px;
      border: 1px solid var(--border); background: rgba(255,255,255,.08);
      color: var(--text); font: 600 12px/1 inherit; text-decoration: none;
      display: inline-flex; align-items: center;
      transition: transform 150ms ease-out, background-color 150ms ease;
    }
    .back:active { transform: scale(0.96); }
    @media (hover: hover) and (pointer: fine) {
      .back:hover { background: rgba(255,255,255,.14); }
    }
    h1 {
      font-size: clamp(1.6rem, 4vw, 2rem); font-weight: 800;
      letter-spacing: -0.025em; line-height: 1.15; margin-bottom: 8px;
    }
    .lede { color: var(--secondary); margin-bottom: 22px; }
    .card {
      background: rgba(255,255,255,.06); border: 1px solid var(--border);
      border-radius: 20px; padding: 20px 18px;
      box-shadow: 0 18px 40px -12px rgba(0,0,0,.55), inset 0 1px 0 rgba(255,255,255,.10);
    }
    .card p, .card li { color: var(--secondary); }
    .card p + p, .card ul { margin-top: 12px; }
    .card ul { padding-left: 1.15rem; }
    .card li + li { margin-top: 8px; }
    .card a { color: #fff; text-underline-offset: 2px; }
    .card h2 {
      font-size: 13px; font-weight: 700; letter-spacing: 0.04em;
      text-transform: uppercase; color: var(--tertiary); margin: 18px 0 8px;
    }
    .card h2:first-child { margin-top: 0; }
    pre {
      white-space: pre-wrap; font: inherit; color: var(--secondary);
    }
    @media (prefers-reduced-motion: reduce) {
      .back { transition: none; transform: none !important; }
    }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="top">
      <a class="brand" href="/">Loge</a>
      <a class="back" href="/">Espace compte</a>
    </div>
    ${body}
  </div>
</body>
</html>`;

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

Suppression du compte
• Dans l’app (Réglages → Compte) : « Supprimer le compte » efface immédiatement le compte et les données cloud associées (profils, Ma liste, progression, sessions, addons synchronisés).

Contact
• support : https://enloge.pages.dev/support/
• a.briolon92@gmail.com`;

export const privacyPolicyHTML = shell(
  'Confidentialité',
  `<h1>Confidentialité</h1>
   <p class="lede">Ce que Loge collecte, pourquoi, et comment le supprimer.</p>
   <div class="card"><pre>${privacyPolicyText.replace(/</g, '&lt;')}</pre></div>`
);

export const supportHTML = shell(
  'Support',
  `<h1>Support</h1>
   <p class="lede">Loge est un lecteur Apple TV : vous apportez vos propres addons et sources.</p>
   <div class="card">
     <h2>Compte &amp; appareils</h2>
     <p>Ouvrez <a href="/">l’espace compte</a> pour jumeler une Apple TV ou gérer les sessions.</p>
     <h2>Confidentialité</h2>
     <p><a href="/privacy">Politique de confidentialité</a>.</p>
     <h2>Contact</h2>
     <p><a href="mailto:a.briolon92@gmail.com">a.briolon92@gmail.com</a></p>
   </div>`
);
