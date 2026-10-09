# Relances et alertes de délai

Le workflow **NovaCorp - Relances 24 h et alertes RH 48 h** (`novacorpReminders`) vérifie chaque minute les étapes de validation actives, avec l'heure du serveur Supabase :

- à partir de **24 heures calendaires** après activation, une relance au validateur affecté ;
- à partir de **48 heures calendaires**, une alerte au RH référent figé à la soumission ;
- aucune acceptation, aucun refus, aucune activation de l'étape suivante sans décision humaine.

Chaque étape manager, RH ou DRH a son propre délai. Les règles et les référents restent ceux de la demande. Une relance et une alerte au maximum sont créées par étape, grâce aux clés de déduplication. Plusieurs exécutions concurrentes ou un redémarrage ne créent pas d'autres messages.

Si la supervision reprend après 48 heures, elle crée directement l'alerte ; elle n'ajoute pas une relance de 24 heures périmée. Si une relance déjà créée n'est pas encore envoyée à l'échéance, le workflow de notifications l'abandonne au profit de l'alerte.

## Installation

Avec Supabase, n8n et le circuit de validation configurés :

```powershell
npm run db:migrate
npm run n8n:reminders:install
npm run n8n:reminders:start
```

Le workflow de notifications existant (`novacorpNotifications`) envoie aussi ces messages dans MailHog. Il doit être publié avec `npm run n8n:approvals:start`. Aucun nouveau conteneur ni appel LLM.

La RPC `queue_due_hr_reminders(uuid)` n'accepte pas d'heure fournie par n8n : elle utilise `now()`. Son paramètre facultatif de demande sert aux vérifications ciblées. L'ancienne RPC `queue_hr_approval_reminders(timestamptz)` conserve son contrat pour les tests et outils backend. Leur implémentation privée verrouille d'abord les demandes, puis leurs étapes, et crée les notifications dans une seule transaction. La nouvelle RPC est réservée à `service_role`.

Les emails reprennent la référence, le titre, l'étape et l'échéance à l'heure de Paris. Les alertes passent avant les relances, puis les autres emails. Le workflow d'envoi réserve au plus un email par minute : la réception peut donc être retardée par la file. Les décisions et le statut sont revérifiés lors de la réservation ; une étape décidée, une demande annulée ou finale ne reçoit plus de nouvelle relance ou alerte. Une décision pendant un envoi SMTP déjà commencé peut toutefois arriver après cette vérification.

Les réservations et reprises SMTP conservent les mêmes règles : cinq minutes de réservation, jetons, temporisation et cinq tentatives maximum. SMTP peut produire un doublon si le message est reçu avant une interruption de l'acquittement en base. Les notifications créées en base restent uniques.

## Vérifications

```powershell
npm run n8n:qualification:stop
npm run n8n:approvals:stop
npm run n8n:reminders:stop
npm run db:verify
npm run n8n:reminders:verify
```

Les tests SQL vérifient les instants avant/à 24 h et 48 h, les destinataires, la déduplication, la priorité, les reprises SMTP, l'indépendance des délais et l'annulation. La reconstruction vérifie aussi deux planifications concurrentes.

Le test n8n exécute réellement la supervision et les envois dans MailHog. Il utilise une demande fictive dédiée et simule ses horodatages dans une session PostgreSQL, sans désactiver les triggers des autres sessions ni modifier les demandes existantes. La qualification est une fixture SQL. Il vérifie les destinataires manager et RH, les messages, les rejeux, le délai RH distinct et une alerte annulée avant envoi. Ses comptes, demandes et workflows temporaires sont nettoyés.

Pour reprendre après les vérifications :

```powershell
npm run n8n:qualification:start
npm run n8n:approvals:start
npm run n8n:reminders:start
```

Un simple arrêt de Docker ou n8n conserve les publications et les volumes. Au redémarrage, la supervision reprend sur les étapes encore actives.
