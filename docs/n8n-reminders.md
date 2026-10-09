# Rappel quotidien manager et alertes RH

S3 suit la photo : chaque matin à **8 h (Europe/Paris)**, rappeler au manager chaque demande dont sa validation attend depuis **strictement plus de 48 heures**. Le délai commence à l’activation de l’étape manager, après qualification.

- `novacorpManagerReminders` : rappel quotidien, cron `0 8 * * *`, fuseau `Europe/Paris`.
- `novacorpReminders` : alertes RH à 48 h, surveillance chaque minute, une alerte par étape manager/RH/DRH.
- Les relances à 24 h sont supprimées pour tous les validateurs. Les anciens messages restent dans l’historique ; ceux encore en attente sont abandonnés à la réservation SMTP.

Un rappel maximum par étape et par date de Paris, renouvelable chaque jour jusqu’à décision, grâce à la clé `step:<id>:manager-daily:YYYY-MM-DD:email`. Aucune décision ni transition automatique à l’échéance.

Le seuil est calculé à 8 h : exactement 48 h ne suffit pas. Un lancement manuel plus tard conserve ce seuil. Aucun rappel avant 8 h. Les changements d’heure sont pris en compte ; 48 h signifie 48 heures écoulées.

## Installation

```powershell
npm run db:migrate
npm run n8n:reminders:install
npm run n8n:reminders:start
```

Ces commandes gèrent les deux workflows. Le redémarrage conserve la configuration du conteneur n8n, notamment ngrok. Supabase reste local. Aucun conteneur ni appel LLM supplémentaire.

Les RPC `queue_daily_manager_reminders(uuid)` et `queue_due_hr_reminders(uuid)` sont réservées à `service_role`, utilisent l’heure Supabase et acceptent un identifiant facultatif pour les tests ciblés. L’ancienne RPC backend `queue_hr_approval_reminders(timestamptz)` ne crée plus que les alertes RH ; le champ historique `approval_rules.reminder_hours` ne pilote plus les rappels.

Le workflow existant `novacorpNotifications` envoie dans MailHog au plus un email par minute, avec priorité aux alertes : **8 h est l’heure de mise en file**, la livraison peut être retardée. Docker et n8n doivent tourner à 8 h ; aucune reprise automatique des journées manquées n’est ajoutée.

Lors de la réservation SMTP, la base revérifie la demande, l’étape, le destinataire, le seuil et la date. Les rappels d’un jour précédent et les étapes décidées/demandes clôturées ne sont plus envoyés. Une décision pendant un envoi SMTP déjà commencé peut arriver après cette vérification.

Les reprises SMTP restent limitées à cinq tentatives, avec réservation de cinq minutes et jeton. Une interruption après réception SMTP mais avant acquittement en base peut provoquer une nouvelle livraison ; la notification en base reste unique. La supervision RH inclut les incidents des rappels du jour.

## Vérifications

Dépublier les workflows métier avant les tests d’intégration puis les republier, comme indiqué dans le README.

```powershell
npm run db:verify
npm run n8n:reminders:verify
```

Les tests SQL couvrent 8 h, le seuil strict, les changements d’heure, le rejeu quotidien, le destinataire, l’arrêt après décision et l’exclusion des étapes RH, ainsi que les alertes RH.

Le test n8n utilise uniquement un compte et une demande fictifs dédiés, simule leurs horodatages, vérifie les emails manager/RH dans MailHog, les rejeux et l’annulation, puis nettoie ses fixtures. Avant 8 h, il vérifie l’absence de rappel ; l’envoi SMTP du rappel quotidien est testé à partir de 8 h. Les tests SQL déterministes restent indépendants de l’heure d’exécution.
