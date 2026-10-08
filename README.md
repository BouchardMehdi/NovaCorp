# NovaCorp

Plateforme interne de gestion des demandes RH, réalisée dans le cadre du fil rouge M1 DFS.

## Stack et périmètre de cette branche

- **Next.js + React + TypeScript** : interface.
- **Supabase local dans Docker** : Auth, PostgreSQL, RLS, Storage et Realtime.
- **MailHog dans Docker** : réception des emails de test.
- **n8n local dans Docker** : connexions Supabase et MailHog, workflow manuel de vérification.
- **Ollama + Qwen3 1.7B dans Docker** : LLM local gratuit appelé par n8n.

L’authentification et le schéma complet de la base RH sont en place : quatre types de demandes, règles de validation versionnées, étapes, historique, soldes de congés, pièces jointes privées, contrôles IA, exécutions n8n, notifications et mesures des délais. Les quatre formulaires et leur suivi sont disponibles : brouillons, soumission, annulation, filtres, vues par rôle et décisions des validateurs. La [qualification n8n avec Ollama](docs/n8n-qualification.md) prépare et active le manager, puis le notifie dans MailHog. L’avancement RH/DRH, les notifications salarié et les relances restent à développer. L’[installation locale n8n](docs/n8n-local.md) et ses connexions sont prêtes. Voir le [parcours de l’interface](docs/hr-interface.md).

Le [schéma relationnel et les permissions](docs/database-schema.md) décrivent les tables, les opérations et les permissions métier. Les [règles métier validées](docs/business-rules.md) sont actives : seuils DRH, délai de 48 h, relance à 24 h, calcul et réservation des congés. Les envois et la planification restent à brancher dans n8n.

## Prérequis

- Node.js **22.19 ou supérieur compatible avec Next.js** et npm.
- Docker Desktop démarré, avec les conteneurs Linux.
- Ports locaux disponibles : **3000**, **1025**, **8025**, **5678**, **11434**, **54320 à 54324**.
- Internet au premier démarrage pour télécharger les dépendances et les images.

Supabase est lancé par la CLI **2.120.0**, fixée dans les dépendances. Aucun compte Supabase cloud n’est nécessaire.

## Premier démarrage

Depuis la racine du dépôt :

```powershell
npm ci
npm run mail:start
npm run supabase:start
npm run local:env
npm run db:migrate
npm run auth:seed
npm run business:seed
npm run n8n:start
npm run n8n:setup
npm run n8n:verify
npm run llm:start
npm run llm:pull
npm run n8n:qualification:install
npm run n8n:qualification:start
npm run dev
```

Ouvrir **http://localhost:3000/connexion**. Pour n8n, ouvrir **http://localhost:5678** et créer le compte propriétaire au premier accès (indépendant des comptes salariés).

Le premier démarrage de Supabase télécharge plusieurs images et applique la migration des profils. MailHog crée le réseau Docker `novacorp_default`, partagé avec Supabase. Les ports MailHog sont liés à l'interface locale. La CLI Supabase peut publier ses ports sur toutes les interfaces : cet environnement reste réservé au développement local.

`npm run local:env` écrit l'URL, la clé publique et la clé d'administration locales dans **.env.local**, sans les afficher. Ce fichier est ignoré par Git. La clé d'administration sert uniquement aux scripts locaux d'initialisation, aux tests et au backend n8n ; elle n'est jamais utilisée par les clients Next.js.

La clé publique peut être une clé publishable ou la clé anon fournie par la CLI. Les accès aux données restent soumis à la session utilisateur et aux politiques RLS.

### Comptes fictifs de démonstration

| Email | Rôle |
|---|---|
| `salarie@novacorp.test` | Salarié : Camille Durand |
| `manager@novacorp.test` | Manager : Alex Martin |
| `rh@novacorp.test` | RH : Morgan Petit |
| `drh@novacorp.test` | DRH : Lou Bernard |

Mot de passe initial commun : **`NovaCorpDemo2026!`**.

Ces identifiants sont réservés aux données fictives locales. Le salarié est rattaché au manager. Le script peut être relancé : il réutilise les comptes existants et met à jour leurs profils, sans réinitialiser leurs mots de passe.

L'inscription publique est désactivée. Les comptes sont créés avec l'API d'administration Supabase et confirmés par le script.

## Services locaux

| Service | Adresse |
|---|---|
| Application | http://localhost:3000 |
| API Supabase | http://127.0.0.1:54321 |
| Supabase Studio | http://127.0.0.1:54323 |
| MailHog | http://localhost:8025 |
| n8n | http://localhost:5678 |
| Ollama | http://localhost:11434 |
| SMTP MailHog, depuis le réseau Docker partagé | `mailhog:1025` |

MailHog est prêt pour les futures notifications métier envoyées par n8n. La récupération du mot de passe et les emails Supabase Auth ne sont pas configurés à cette étape.

MailHog conserve ses messages en mémoire : ils ne sont pas conservés après un redémarrage du conteneur. Les emails de démonstration restent locaux. Les notifications métier seront implémentées dans n8n à une étape suivante.

## Authentification et accès

- `/connexion` : formulaire avec validation serveur, erreurs et état de chargement.
- `/tableau-de-bord` : espace privé ; un visiteur est redirigé vers la connexion.
- `/` : redirection vers l'espace privé.
- La session est renouvelée dans `src/proxy.ts`.
- Les pages privées vérifient l'identité auprès de Supabase Auth avec `getUser()`.
- Le serveur utilise la clé publique et la session du compte, sans contournement de la RLS.
- Une session absente ou invalide ne permet pas d'accéder aux pages privées.
- Un utilisateur connecté est redirigé depuis la page de connexion vers son espace.

La table `public.profiles` contient le nom, le rôle et le manager. Un salarié lit son profil ; un manager lit aussi ceux de son équipe ; les RH et le DRH lisent tous les profils. Aucun utilisateur ne peut modifier directement son rôle, son manager ou son profil. Les demandes et leurs fichiers sont protégés par RLS ; les brouillons restent privés. Voir la [matrice des accès](docs/database-schema.md#permissions-rls).

Si Supabase n'est pas configuré, la page de connexion présente un message d'indisponibilité et désactive le formulaire. Si le service ne répond pas pendant une tentative, un message d'erreur est affiché.

## Vérifications

Avec Supabase démarré et les comptes fictifs créés. Si les workflows métier sont publiés, les arrêter avec `npm run n8n:qualification:stop` avant les tests navigateur, puis les reprendre avec `npm run n8n:qualification:start` :

```powershell
npm run db:lint
npm run db:test
npm run db:verify
npm run n8n:verify
npm run lint
npm run typecheck
npm run build
npx playwright install chromium
npm test
```

Les tests SQL couvrent les permissions, les contraintes, les règles et le parcours de validation complet avec DRH. Leurs données fictives sont annulées à la fin de chaque test.

Les tests navigateur couvrent les champs invalides, l'accès anonyme, une session forgée, le mauvais mot de passe, la connexion, le maintien de session après actualisation, la déconnexion, l'isolation des profils par RLS et l'affichage mobile. Les tests RH couvrent également les quatre formulaires, les reprises après erreur sans doublon, les réservations de congés, les filtres, la confidentialité des brouillons et les décisions des validateurs avec actualisation du suivi. Ils créent puis nettoient leurs propres données fictives et nécessitent le conteneur PostgreSQL local. Playwright démarre automatiquement Next.js si aucun serveur ne tourne sur le port 3000.

## Arrêt et reprise

Arrêter Next.js avec **Ctrl+C**, puis :

```powershell
npm run n8n:stop
npm run llm:stop
npm run supabase:stop
npm run mail:stop
```

Les données Supabase sont conservées. Pour reprendre :

```powershell
npm run mail:start
npm run supabase:start
npm run db:migrate
npm run llm:start
npm run n8n:start
npm run dev
```

Après un changement de clés locales, relancer `npm run local:env` et redémarrer Next.js.

**Attention : `npx supabase db reset` efface les données de la base locale.** Si une réinitialisation est volontaire, recréer ensuite les comptes avec `npm run auth:seed`, puis les soldes et référents avec `npm run business:seed`.

## Structure

```text
src/app/connexion/             Formulaire et action serveur de connexion
src/app/tableau-de-bord/       Espace privé, formulaires, suivi et décisions
src/lib/auth/                  Validation et vérification de l'utilisateur
src/lib/supabase/              Clients navigateur et serveur
src/proxy.ts                   Renouvellement de session et protection des routes
supabase/config.toml           Configuration des services locaux
supabase/migrations/           Schéma RH, politiques RLS et opérations contrôlées
supabase/tests/database/       Tests SQL transactionnels
src/types/database.ts          Types publics générés (npm run db:types)
docs/database-schema.md        Schéma relationnel et contrat pour n8n
docs/business-rules.md         Règles métier validées et initialisation
docs/n8n-local.md              Installation et connexions n8n
docs/n8n-qualification.md      Qualification locale et notifications manager
n8n/workflows/                 Workflows exportés sans secrets
scripts/                       Configuration locale et comptes fictifs
tests/                         Tests de connexion, permissions et parcours RH
compose.yaml                   n8n, MailHog, volume et réseau Docker local
```

## Références

- [Supabase local et CLI](https://supabase.com/docs/guides/local-development)
- [Supabase Auth avec Next.js](https://supabase.com/docs/guides/auth/server-side/nextjs)
- [MailHog](https://github.com/mailhog/MailHog)
