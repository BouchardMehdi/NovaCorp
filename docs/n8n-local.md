# n8n local

## Installation et connexions

n8n 2.42.5 utilise Docker Compose, le réseau `novacorp_default` et un volume persistant `novacorp_n8n_data` pour sa base SQLite, ses workflows et ses identifiants chiffrés. Sa base interne est distincte de la base RH Supabase.

Avec Docker Desktop et Supabase local démarrés :

```powershell
npm run n8n:start
npm run n8n:setup
npm run n8n:verify
```

Ouvrir http://localhost:5678 et créer le compte propriétaire n8n au premier accès. Ce compte est indépendant des comptes salariés de NovaCorp. Les connexions et le workflow importés appartiennent au projet personnel du propriétaire.

`n8n:start` génère d’abord `.env.n8n.local`, puis lance le service et attend son contrôle de santé. Le fichier est ignoré par Git ; sa clé de chiffrement est conservée lors des relances. Garder ce fichier avec le volume pour conserver l’accès aux identifiants. Les ports n8n et MailHog sont liés à l’interface locale.

`n8n:setup` importe deux connexions, avec des identifiants fixes :
- **NovaCorp - Supabase local** : hôte `http://supabase_kong_NovaCorp:8000` et clé locale `service_role`.
- **NovaCorp - MailHog local** : serveur SMTP `mailhog`, port `1025`, sans authentification, SSL ou STARTTLS.

La clé Supabase est lue dans le conteneur lors de l’import ; aucun secret ne figure dans le JSON versionné. Les fichiers temporaires d’import sont supprimés après l’opération. Cette clé donne les permissions du backend : elle reste dans l’environnement n8n et ses identifiants chiffrés, jamais dans le front.

Depuis un conteneur, `localhost` désigne ce conteneur. Utiliser les noms Docker ci-dessus pour Supabase et SMTP, et les adresses `localhost` uniquement depuis le navigateur de l’hôte.

## Workflow de vérification

[n8n/workflows/setup-smoke.json](../n8n/workflows/setup-smoke.json) contient un workflow manuel, non publié :

1. Lire le catalogue des types RH dans Supabase.
2. Vérifier les codes `leave`, `remote_work`, `equipment` et `training`.
3. Envoyer un seul email fictif à `verification@novacorp.test` dans MailHog.

Aucune demande RH ni solde n’est modifié. L’email de sujet **NovaCorp - verification n8n** est visible sur http://localhost:8025. `n8n:verify` vérifie la disponibilité de n8n, exécute le workflow, puis vérifie l’arrivée d’un nouveau message correspondant.

Relancer `n8n:setup` remplace uniquement les deux connexions et le workflow de vérification portant ces identifiants. Pour conserver une version modifiée du workflow, le dupliquer sous un autre identifiant. Après un changement des clés Supabase locales, relancer `n8n:start` puis `n8n:setup`.

## Arrêt et reprise

```powershell
npm run n8n:stop
npm run n8n:start
```

L’arrêt conserve le volume et les workflows. Les emails MailHog restent en mémoire et sont perdus si MailHog redémarre. Ne pas utiliser `docker compose down -v` pour un simple arrêt : cette commande supprime les volumes.

## Prochaine étape

Le setup connecte les services. La [qualification avec Ollama](n8n-qualification.md) collecte désormais les demandes, exécute les contrôles, produit la synthèse et active le manager. Le [circuit de validation](n8n-approvals.md) assure maintenant l’avancement et les notifications salarié. Les [relances et alertes](n8n-reminders.md) sont désormais planifiées dans n8n.

Pour les RPC Supabase, utiliser un nœud HTTP Request avec l’authentification prédéfinie **Supabase API**, la connexion importée et une URL `http://supabase_kong_NovaCorp:8000/rest/v1/rpc/<fonction>`. Les paramètres sont transmis en JSON par POST. Le contrat des fonctions figure dans [les règles métier](business-rules.md) et [le schéma](database-schema.md).

Le LLM utilise maintenant Ollama et Qwen3 1.7B en local, sans clé API payante. Voir la [configuration du modèle](n8n-qualification.md).

Références officielles : [Docker Compose n8n](https://docs.n8n.io/deploy/host-n8n/install-options/install-using-docker-compose.md), [commandes serveur](https://docs.n8n.io/hosting/cli-commands/), [connexion Supabase](https://docs.n8n.io/integrations/builtin/credentials/supabase/).

Depuis l’installation du circuit de validation, `n8n:qualification:start` publie uniquement la qualification. Les emails de tous les validateurs et du salarié sont activés par `npm run n8n:approvals:start`. Dépublier aussi ces workflows avec `npm run n8n:approvals:stop` avant les tests d’intégration et navigateur.

La supervision des délais est activée par `npm run n8n:reminders:start`. La dépublier également avec `npm run n8n:reminders:stop` avant les tests d’intégration ou navigateur, puis la réactiver après les vérifications.
