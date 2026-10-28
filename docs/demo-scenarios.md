# Démonstration et recette S1–S5

Pour prouver le RAG, importer un nouveau document RH, soumettre une nouvelle demande puis consulter ses sources avec le validateur. Voir le [parcours documentaire](rag.md). Les exécutions sans demande réservée et les anciennes revues ne prouvent pas une recherche documentaire.


Ce guide sert à répéter la soutenance et à rejouer les contrôles sur des données fictives locales. Les scénarios manuels montrent les décisions des personnes ; les vérifications automatiques constituent des preuves techniques complémentaires.

## Préparer la session

1. Démarrer les services selon le README, charger `qwen3:1.7b`, appliquer les migrations et installer les workflows.
2. Ouvrir quatre sessions de navigateur distinctes pour Camille, Alex, Morgan et Lou. Un changement de compte dans le même contexte remplace la session.
3. Ouvrir MailHog et n8n, filtrer leurs listes sur les nouvelles exécutions et les nouveaux messages. Utiliser un titre unique, par exemple `DEMO-<date>-S1`, pour suivre une demande.
4. Préparer un scénario simple puis un scénario avec DRH. Ne pas présenter les historiques simulés d'Emma comme une exécution réelle avec Ollama.
5. Conserver des captures des statuts, de la synthèse, des décisions et des emails. Ne jamais capturer les clés ou les écrans de configuration contenant un secret.

## Parcours à montrer

| Scénario | Données / action | Résultat vérifiable |
| --- | --- | --- |
| S1 — Notification manager | Camille soumet une demande de matériel de 100 EUR | Qualification par le vrai modèle, synthèse visible par Alex, manager seul actif et email dans MailHog |
| S2 — Deux niveaux et seuil DRH | Matériel de 1 501 EUR ; accord Alex, puis Morgan, puis Lou | Une étape active à la fois, aucune décision automatique, statut final approuvé et email salarié |
| S2 — Refus | Nouvelle demande de matériel ; Alex refuse avec un motif | Refus final, pas d'activation RH/DRH, motif historisé et notification salarié |
| S3 — Relance | Étape manager en attente depuis plus de 48 h à 8 h Paris | Un rappel quotidien par étape et par date ; alerte RH unique à l'échéance ; aucune validation automatique |
| S4 — Digest | Lundi à 8 h Paris | Compteurs de la semaine précédente et attentes manager ; un email par manager et par semaine |
| S5 — Onboarding | Créer un nouveau compte fictif via l'administration Supabase avec prénom/nom | Un email de bienvenue avec six cases ; une modification du profil ne renvoie pas l'accueil |

Pour S1, continuer jusqu'à la décision RH pour montrer un cycle complet sans DRH. La demande de 100 EUR ne nécessite pas la DRH. Pour les congés, choisir une période sans conflit et un solde suffisant ; la DRH intervient strictement au-delà de 10 jours ouvrés.

L'accueil S5 ne se déclenche pas sur les comptes déjà créés. Utiliser un nouvel email fictif `@novacorp.test`, sans ajouter de données personnelles réelles. Supprimer uniquement le compte de démonstration dédié après la répétition.

## Rejouer sans attendre plusieurs jours

```powershell
npm run demo:verify -- S1
npm run demo:verify -- S2
npm run demo:verify -- S3
npm run demo:verify -- S4
npm run demo:verify -- S5
npm run demo:verify -- IA
# Ou toute la recette (plusieurs minutes, surtout avec Ollama sur CPU)
npm run demo:verify
```

Exécuter une commande à la fois. Le lanceur arrête temporairement le service n8n et lance un conteneur de test éphémère sur son volume, sans serveur, planificateur ni port publié. La CLI exécute uniquement les copies dédiées aux tests. Les publications de production restent inchangées ; les copies IA nécessaires sont publiées puis nettoyées. Le service initial reprend avec ses variables et sa configuration ngrok. L'accès public n8n est indisponible pendant ces essais. `IA` seul appelle Ollama sans arrêter n8n. Les vérifications sont réservées à Supabase local ; ne pas les lancer sur un VPS de production.

Le rapport `test-results/demo-report.json` indique les scénarios réellement exécutés, leur résultat, leur durée et la reprise du service. Il est ignoré par Git et ne contient ni clé ni contenu de demande. Un rapport avec `passed: false` ou `restored: false` ne constitue pas une recette réussie. En cas d'interruption brutale, vérifier l'arrêt du conteneur de test dédié avant de redémarrer le service principal ; ne pas démarrer deux serveurs sur le même volume.

### Ce qui est réel et ce qui est simulé

- **S1** : quatre types de demandes, vrai Ollama appelé par le sous-workflow n8n, email SMTP réel dans MailHog, rejeux et modèle inexistant. Le matériel inclut une tentative d'injection de consigne ; la demande doit rester en attente humaine.
- **S2 via `demo:verify`** : vraie qualification Ollama puis circuit n8n, emails et finalisation. Les décisions humaines sont simulées dans des sessions SQL authentifiées de fixture, sous les permissions du validateur. La démonstration manuelle et les tests Playwright montrent les vrais boutons. La commande historique `n8n:approvals:verify` conserve une qualification SQL de fixture pour isoler le circuit.
- **S3** : seuls les horodatages de la demande fictive sont simulés. Les workflows et SMTP sont réels. Les frontières 8 h / 48 h, les changements d'heure et le renouvellement au lendemain sont vérifiés par les tests SQL. Le test SMTP du rappel quotidien est exécuté après 8 h ; avant 8 h, il vérifie l'absence d'envoi.
- **S4** : le workflow de préparation respecte le jour courant. Un helper privé prépare ensuite le digest du seul manager fictif à l'heure du lundi, pour tester l'envoi sans attendre lundi. Le lundi avant 8 h, la livraison est différée. Les compteurs métier et bornes de semaine sont vérifiés en SQL.
- **S5** : vraie création Auth, déclencheur de profil et email ; compte et accueil fictifs nettoyés après vérification.

Aucun planning publié n'est accéléré pour la soutenance. Les demandes existantes, mots de passe et soldes des comptes de démonstration ne sont pas réinitialisés par les vérifications.

## Preuves et plan de secours

Conserver une capture de la demande créée, de la revue IA avec modèle et version du prompt, de la transition manager → RH → DRH, des emails et des exécutions n8n. Montrer un rejeu sans nouvelle revue ni notification. Pour les échecs, montrer le code d'erreur et la reprise, sans exposer une requête ou une clé.

Préparer une courte vidéo ou une série de captures d'un cycle réellement exécuté, ainsi qu'un rapport de recette daté. Ces pièces sont un secours de présentation ; elles ne remplacent pas la démonstration du système qui tourne.
