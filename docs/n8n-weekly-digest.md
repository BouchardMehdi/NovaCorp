# S4 — Digest hebdomadaire manager

Chaque lundi à **8 h, heure de Paris**, `novacorpWeeklyDigest` prépare un email par compte ayant le rôle manager, y compris sans activité. Le workflow utilise le cron `0 8 * * 1` et le fuseau `Europe/Paris`.

Le récapitulatif contient :

- **Reçues** : demandes soumises entre le lundi précédent à 0 h inclus et le lundi courant à 0 h exclu, selon le manager figé à la soumission. Les brouillons sont exclus.
- **Finalement approuvées** : demandes de cette équipe ayant atteint le statut final `approved` pendant cette même semaine, quelle que soit leur date de soumission. Une simple validation manager suivie d'une attente RH n'est pas une approbation finale.
- **En attente de votre validation** : toutes les étapes manager encore actives au passage du workflow, y compris celles des semaines antérieures. Les étapes RH/DRH et les demandes en qualification sont exclues de ce compteur.
- Les références et titres des 20 plus anciennes demandes à traiter, ainsi qu'un lien vers **Mon équipe**. Le compteur inclut toutes les demandes, même au-delà de 20.

La semaine est définie en dates locales de Paris : elle peut comporter 167 ou 169 heures lors des changements d'heure. Le contenu est figé à la mise en file, et l'email invite à consulter l'état actuel dans l'application. Les décisions humaines et les demandes restent inchangées.

## Installation et activation

```powershell
npm run db:migrate
npm run n8n:digest:install
npm run n8n:digest:start
```

Deux workflows sont importés et publiés :

| Identifiant | Fonctionnement |
| --- | --- |
| `novacorpWeeklyDigest` | Prépare les digests le lundi à 8 h |
| `novacorpDigestEmails` | Envoie au plus un digest par minute et reprend les échecs SMTP |

Les connexions Supabase et MailHog existantes sont réutilisées. Supabase reste local, la configuration ngrok est conservée et aucun appel LLM ou nouveau conteneur n'est nécessaire. Le lien vers le front reste local comme dans les autres emails.

Les commandes S4 conservent les paramètres publics du conteneur. Si d'autres commandes du README ont réappliqué la configuration locale de n8n, utiliser `npm run ngrok:start` pour retrouver la configuration publique autorisée.

**8 h est l'heure de préparation**, les emails peuvent arriver quelques minutes plus tard selon la file. Docker et n8n doivent tourner pour le déclenchement. Aucune reprise des semaines manquées n'est ajoutée. Un lancement manuel de la préparation est accepté uniquement le lundi à partir de 8 h ; il ne produit pas de doublon.

Pour arrêter uniquement S4 :

```powershell
npm run n8n:digest:stop
```

## Fiabilité et accès

La table `manager_weekly_digests` conserve les compteurs, le contenu et l'état SMTP. La contrainte unique `(manager_id, week_start)` garantit un seul digest par semaine, même sous concurrence. Elle est protégée par RLS et accessible uniquement au backend ; aucun accès direct depuis le navigateur.

Les RPC publiques `queue_weekly_manager_digests`, `claim_weekly_manager_digest` et `finish_weekly_manager_digest` sont réservées à `service_role`. La préparation utilise l'heure serveur ; seul le helper privé accepte une horloge pour les tests. Le paramètre facultatif `p_manager_id` cible un manager lors des vérifications.

La réservation SMTP dure cinq minutes, avec jeton et cinq tentatives maximum. Un mauvais jeton ne peut pas acquitter le message. Le retrait du rôle manager et une semaine devenue ancienne empêchent la livraison. Les digests expirés ou définitivement échoués restent consultables en base ; les erreurs d'envoi sont visibles dans les exécutions du workflow n8n. Ils ne sont pas rattachés à une demande individuelle dans la supervision RH.

Comme pour les autres emails, une interruption après réception SMTP mais avant acquittement peut provoquer une nouvelle livraison. La déduplication en base ne garantit pas une livraison SMTP exactement une fois.

## Vérifications

```powershell
npm run db:verify
npm run n8n:digest:stop
npm run n8n:digest:verify
npm run n8n:digest:start
```

Les tests SQL vérifient les bornes locales, les compteurs, l'isolation des équipes, les managers sans activité, les droits, les changements d'heure et les reprises SMTP. La reconstruction teste aussi deux préparations concurrentes.

La vérification n8n crée un manager fictif sans demandes RH, prépare sa photographie de la semaine courante, exécute les deux workflows et vérifie l'email dans MailHog ainsi que le rejeu sans doublon. Elle nettoie son compte, son digest et ses workflows temporaires. Le lundi avant 8 h, elle vérifie le report de la livraison ; les tests SQL couvrent les autres horaires. Si S5 est actif, arrêter aussi l'onboarding avec `npm run n8n:onboarding:stop` avant ce test, puis le reprendre avec `npm run n8n:onboarding:start`.
