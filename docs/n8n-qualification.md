# Qualification RH avec n8n et Ollama

## Modèle gratuit et local

Le workflow appelle l’API locale Ollama (`http://ollama:11434/api/chat`) avec **Qwen3 1.7B**. Il n’utilise ni abonnement cloud, ni clé API payante. Les demandes ne sont pas envoyées à un fournisseur externe. Le modèle et les données Ollama sont conservés dans le volume Docker `novacorp_ollama_data`.

Le modèle compact est choisi pour les 8 Go disponibles dans Docker sur la machine de démonstration. L’exécution fonctionne sur CPU ; une réponse peut prendre du temps au premier chargement. Le modèle produit une aide au validateur, pas une décision fiable à lui seul.

Références : [modèle Qwen3 1.7B](https://ollama.com/library/qwen3:1.7b), [Ollama Docker](https://docs.ollama.com/docker), [sorties JSON structurées](https://docs.ollama.com/capabilities/structured-outputs).

## Installation et activation

Avec Supabase, n8n et leurs connexions locales configurés :

```powershell
npm run db:migrate
npm run db:types
npm run llm:start
npm run llm:pull
npm run n8n:qualification:install
npm run n8n:qualification:start
```

Le premier téléchargement du modèle représente environ 1,4 Go, en plus de l’image Ollama. La commande d’activation vérifie la présence du modèle avant de publier la qualification et de redémarrer n8n pour charger sa planification. Les emails sont activés avec le circuit de validation.

Les workflows restent non publiés après le simple import. La qualification est planifiée chaque minute ; le workflow de notifications général est activé séparément avec `n8n:approvals:start`. Chaque passage traite au plus une demande ou un message ; plusieurs passages peuvent tourner sans réserver deux fois la même demande.

Ouvrir n8n sur http://localhost:5678. Les workflows sont :
- **NovaCorp - Qualification des demandes** (`novacorpQualification`).
- L’ancien **NovaCorp - Notifications manager** (`novacorpManagerEmails`) est remplacé par **NovaCorp - Notifications RH et salarié** lors de l’installation du circuit de validation.

Ils réutilisent les connexions Supabase et MailHog existantes. Ollama est appelé directement sur le réseau Docker, sans identifiant supplémentaire. Le port hôte 11434 est lié uniquement à l’interface locale.

## Parcours

1. Réserver une demande soumise, passer son statut à « En analyse » et créer les traces du traitement.
2. Obtenir les contrôles déterministes Supabase : dates, jours, solde, conflits et doublons.
3. Appeler Ollama avec les faits de la demande et les contrôles. Les champs d’identité du salarié et des validateurs ne sont pas inclus ; les identifiants des demandes en conflit sont remplacés par des comptes.
4. Valider la réponse JSON (qualification, synthèse, brouillon de réponse) et les compteurs de tokens.
5. Enregistrer la revue et préparer le circuit manager → RH → DRH selon les seuils déjà définis.
6. Passer en validation et activer uniquement l’étape du manager. La base crée sa notification.
7. Le second workflow réserve cette notification, revérifie l’état de la demande et de l’étape, l’envoie dans MailHog puis marque l’envoi effectué.

La synthèse apparaît sur la fiche pour les validateurs autorisés. Le brouillon de réponse est conservé, sans être envoyé automatiquement au salarié. Les pièces jointes ne sont pas analysées à cette étape.

Les anomalies SQL imposent `invalid`, et les doublons imposent `needs_review`, même si le LLM répond `eligible`. Aucune de ces qualifications ne refuse ni n’approuve la demande : le manager décide.

## Concurrence, interruptions et erreurs

La migration `20261008000600_n8n_qualification.sql` ajoute cinq RPC réservées à `service_role` :

| Fonction | Usage |
|---|---|
| `claim_hr_qualification` | Réserver une demande, produire les contrôles et ouvrir les traces |
| `complete_hr_qualification` | Enregistrer la revue, préparer le circuit et activer le manager dans une transaction |
| `fail_hr_qualification` | Tracer une erreur et programmer une reprise limitée |
| `claim_hr_manager_email` | Réserver un email manager encore pertinent |
| `finish_hr_manager_email` | Enregistrer le résultat SMTP |

Les réservations durent cinq minutes et possèdent un jeton. Les demandes sont verrouillées avant les traces, étapes ou notifications. Deux qualifications concurrentes ne peuvent pas réserver la même demande. La fin de qualification est rejouable ; une ancienne réponse n’altère pas une nouvelle tentative.

Une erreur HTTP, une réponse invalide ou une interruption ne produit aucune décision. La demande reste en analyse, avec au maximum trois tentatives (temporisation d’une puis deux minutes). Une annulation pendant l’appel est respectée à la fin ; aucun circuit n’est alors activé. Après épuisement des tentatives, une vérification manuelle des traces est nécessaire.

Les emails sont réservés séparément, avec cinq tentatives maximum. Une notification obsolète ou sans adresse est mise en échec sans nouvelle tentative. Un échec SMTP est tracé, sans relancer l’analyse IA. La dernière réservation expirée est signalée pour vérification manuelle.

SMTP ne garantit pas un envoi exactement une fois : une interruption après la réception du mail et avant son acquittement en base peut provoquer un second message lors d’une reprise. La qualification et la création des étapes/notifications restent dédupliquées en base.

Les traces stockent le fournisseur, le modèle, la version du prompt, les contrôles, les tokens et les erreurs. Les erreurs techniques enregistrées restent génériques et ne recopient pas des secrets ou des requêtes HTTP. Le coût API local est nul ; la consommation des ressources de la machine n’est pas mesurée.

## Vérifications

```powershell
npm run n8n:qualification:test
npm run db:lint
npm run db:test
npm run db:verify
npm run n8n:qualification:verify
```

La vérification réelle exécute les workflows n8n avec le vrai modèle local sur les quatre types, vérifie les étapes, l’email reçu, les rejeux et le cas d’un modèle inexistant. Elle crée un utilisateur fictif dédié et des workflows de test non publiés, puis nettoie uniquement ces données. À exécuter avant la publication, ou après `npm run n8n:qualification:stop`, pour que le planificateur ne réserve pas les demandes fictives du test. Le script refuse de démarrer si les workflows métier sont publiés. Les tests navigateur doivent aussi être exécutés avec ces workflows dépubliés, car ils vérifient notamment l’état « Soumise » avant traitement n8n.

Les tests SQL sont transactionnels. La vérification de reconstruction ajoute une course entre deux réservations de qualification dans une base temporaire. Les tests JavaScript vérifient les réponses malformées et l’isolation des instructions du motif.

## Arrêt, reprise et suite

```powershell
npm run n8n:qualification:stop
npm run llm:stop
```

Pour reprendre, démarrer Ollama, puis republier les workflows avec `n8n:qualification:start`. Les poids du modèle sont conservés ; pas besoin de les télécharger à nouveau.

Le [circuit de validation](n8n-approvals.md) assure désormais l’avancement manager → RH → DRH et la finalisation après leurs décisions. Les [relances à 24 h et alertes à 48 h](n8n-reminders.md) sont planifiées dans n8n.

Depuis l’installation du circuit de validation, `n8n:qualification:start` publie uniquement la qualification. Les emails de tous les validateurs et du salarié sont activés par `npm run n8n:approvals:start`. Dépublier aussi ces workflows avec `npm run n8n:approvals:stop` avant les tests d’intégration et navigateur.

La supervision des délais est activée par `npm run n8n:reminders:start`. La dépublier également avec `npm run n8n:reminders:stop` avant les tests d’intégration ou navigateur, puis la réactiver après les vérifications.
