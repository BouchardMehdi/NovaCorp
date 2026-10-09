# ngrok et webhook n8n, avec Supabase local

Supabase reste dans ses conteneurs locaux. Aucun projet cloud, migration distante ou changement des circuits RH n'est nécessaire pour ouvrir le tunnel.

## État de cette branche

- Tunnel ngrok optionnel vers n8n, avec commandes de démarrage et de retour au mode local.
- Workflow indépendant **NovaCorp - Reception webhook requests (TP)**, publié sur `POST /webhook/novacorp-requests`.
- Authentification par en-tête `X-NovaCorp-Webhook-Token`, généré localement et importé dans les identifiants chiffrés n8n.
- Test avec un identifiant synthétique qui ne correspond à aucune demande en base.
- Trigger `AFTER INSERT` et transport asynchrone `pg_net` dans Supabase local, avec URL et secret d'authentification conservés dans Vault.
- Envoi limité à l'événement, l'identifiant et le statut de la demande, après autorisation explicite de l'URL publique précise. Aucun titre, motif, date, montant ou coordonnée n'est exporté.

Le parcours est `INSERT requests → trigger PostgreSQL → URL conservée dans Vault → ngrok → webhook n8n`. Le récepteur accuse réception sans lancer de traitement métier. L'autorisation initiale a été donnée pour l'URL du compte utilisée lors de la configuration ; toute nouvelle adresse nécessite un nouvel accord.

## Préparer les fichiers locaux

Avec Docker et n8n déjà disponibles :

```powershell
npm run ngrok:env
npm run n8n:webhook:setup
npm run n8n:webhook:verify
npm run db:migrate
```

`ngrok:env` crée `.env.ngrok.local` sans écraser un fichier existant et génère le secret du webhook dans `.env.n8n.local`. Ces deux fichiers sont ignorés par Git. Ne pas publier leur contenu, ni afficher la configuration Compose complète lorsqu'elle contient des secrets.

`n8n:webhook:setup` importe uniquement le nouveau workflow et sa connexion, puis redémarre n8n avec les délais d'arrêt existants. Il peut être relancé avec le même secret. Les autres workflows restent publiés. Les modifications manuelles de ce nouveau workflow sont remplacées lors d'une réinstallation : le dupliquer pour les conserver.

## Renseigner l'authtoken ngrok

Dans le tableau de bord ngrok, ouvrir **Your Authtoken** : <https://dashboard.ngrok.com/get-started/your-authtoken>.

Copier le token uniquement dans `.env.ngrok.local` :

```dotenv
NGROK_AUTHTOKEN=remplacer_par_le_token_du_compte
N8N_PUBLIC_URL=
```

Ne pas coller le token dans le chat. La ligne `N8N_PUBLIC_URL` est remplie automatiquement à l'ouverture du tunnel.

## Ouvrir et vérifier le tunnel

```powershell
npm run ngrok:start
npm run n8n:webhook:verify:public
```

Le script démarre l'agent ngrok sur le réseau Docker existant, découvre l'URL HTTPS via son API locale, la conserve dans `.env.ngrok.local`, puis recrée uniquement n8n avec les paramètres de proxy et les cookies sécurisés. La clé de chiffrement et le volume n8n sont conservés. L'image ngrok Alpine est fixée par son digest et représente environ 41 Mo dans l'environnement vérifié.

Pendant le tunnel, utiliser l'adresse HTTPS affichée pour ouvrir n8n et son compte propriétaire existant. Ne pas utiliser les comptes salariés pour cette connexion. Le PC, Docker, n8n et l'agent doivent rester démarrés. L'inspection du contenu des requêtes par l'agent est désactivée ; son API de contrôle est publiée uniquement sur `127.0.0.1:4040`.

Le test public envoie uniquement un événement synthétique de forme :

```json
{
  "type": "INSERT",
  "schema": "public",
  "table": "requests",
  "record": {"id": "UUID-synthetique", "status": "draft"},
  "old_record": null
}
```

Le récepteur accuse réception avec `business_processing: false`. Il ne crée, ne soumet, ne qualifie et ne valide aucune demande. Il n'envoie aucun email. Les appels sans secret sont refusés. Les exécutions sont visibles dans n8n, accessibles au propriétaire authentifié.

ngrok expose n8n, pas le front Next.js, Supabase Studio ou MailHog. Les liens des emails vers `localhost:3000` restent locaux. Les automatisations RH continuent d'utiliser le réseau Docker et la base locale.

## Raccorder Supabase local après autorisation de l'URL

Une fois l'adresse HTTPS obtenue et son utilisation autorisée, remplacer le domaine ci-dessous par l'adresse exacte autorisée :

```powershell
npm run n8n:webhook:connect -- --approve-url=https://DOMAINE_AUTORISE/webhook/novacorp-requests
npm run n8n:webhook:verify:chain
```

La commande conserve l'adresse autorisée dans `.env.ngrok.local` et met à jour les secrets `n8n_requests_webhook_url` et `n8n_requests_webhook_token` dans Vault, sans doublons ni affichage du token. L'URL n'est jamais écrite en dur dans une migration. Les commandes SQL ciblent exclusivement le conteneur PostgreSQL local.

`verify:chain` crée un seul brouillon synthétique sur le compte de démonstration Camille, attend le résultat HTTP enregistré par `pg_net`, vérifie la réponse du webhook public et l'absence de qualification, validation ou email, puis nettoie ce seul brouillon. L'identifiant et le statut du test passent effectivement par ngrok ; ses titre, motif et montant restent dans la base locale.

Le trigger s'exécute seulement sur les insertions, jamais lors d'une modification ou d'une soumission d'un brouillon existant. Les appels HTTP partent après validation de la transaction. Une transaction annulée n'envoie rien. Une URL vide ou un token absent désactive l'envoi. Une erreur de mise en file ne bloque pas la sauvegarde ; les erreurs HTTP ultérieures sont visibles dans `net._http_response`, sans reprise automatique de ce transport auxiliaire.

Pour désactiver seulement l'envoi PostgreSQL, tout en gardant le tunnel :

```powershell
npm run n8n:webhook:disconnect
```

## Arrêter et revenir au fonctionnement local

```powershell
npm run ngrok:stop
```

Cette commande désactive d'abord l'URL dans Vault, arrête le tunnel puis recrée n8n avec la configuration locale et son volume existant. Aucun volume ni donnée RH n'est supprimé. Les requêtes déjà mises en file peuvent encore se terminer ou échouer ; l'arrêt ne les rejoue pas.

`ngrok:start` désactive aussi l'envoi avant de démarrer. Si l'adresse obtenue correspond exactement à l'adresse déjà autorisée, il remet les secrets à jour et réactive l'envoi. Sinon, le tunnel s'ouvre mais l'envoi reste désactivé : obtenir un nouvel accord avant de lancer la commande de raccordement pour la nouvelle destination.

Pendant le mode public, utiliser `ngrok:start` pour relancer ou réappliquer la configuration publique. `n8n:start` utilise la configuration locale et annule les paramètres publics de n8n ; il n'arrête pas l'agent à lui seul.

## Préservation des règles métier

Les insertions correspondent aujourd'hui aux brouillons. Le webhook restera donc une réception technique, sans déclencher la qualification ou les emails. Les workflows métier existants continueront à traiter uniquement les demandes soumises, avec leurs protections contre les doublons. Les pannes du tunnel ne devront pas bloquer l'enregistrement des demandes.

Les tests SQL couvrent la confidentialité du payload, les permissions, les secrets absents, les insertions, l'absence d'appel sur modification, la désactivation et l'absence d'effets métier. Ils s'annulent intégralement et n'envoient aucun appel HTTP. La vérification réelle `verify:chain` complète ces tests avec le tunnel du compte.

Références : [ngrok Docker](https://ngrok.com/docs/using-ngrok-with/docker/), [configuration de l'agent](https://ngrok.com/docs/agent/config/v3/), [proxy et URL n8n](https://docs.n8n.io/hosting/configuration/configuration-examples/webhook-url/).
