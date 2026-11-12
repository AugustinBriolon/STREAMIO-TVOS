/** Static legal HTML pages. */

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

export const privacyPolicyHTML = `<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Confidentialité — Loge</title></head>
<body style="font-family:system-ui,sans-serif;max-width:40rem;margin:2rem auto;padding:0 1rem;line-height:1.5"><pre style="white-space:pre-wrap;font-family:inherit">${privacyPolicyText.replace(/</g, '&lt;')}</pre></body></html>`;

export const supportHTML = `<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Support — Loge</title>
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
