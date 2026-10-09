# Circuit de validation n8n

Après qualification, le manager décide dans l'application. Chaque minute, le workflow **NovaCorp - Avancement des validations** traite au plus une demande :
- accord manager : activation RH ;
- accord RH : activation DRH uniquement si le circuit préparé l'exige, sinon acceptation finale ;
- accord DRH : acceptation finale ;
- refus à une étape : refus final, sans activation des étapes suivantes.

Les seuils restent strictement > 10 jours de congés, > 1 000 EUR de matériel et > 1 500 EUR de formation. Aucun DRH pour le télétravail. Les affectations et la version des règles sont celles figées à la soumission. Les décisions restent exclusivement celles des validateurs affectés. Le délai de 48 heures commence à l'activation de chaque étape. Les étapes restantes restent en attente après refus ou annulation ; elles ne sont plus actionnables.

## Installation

Avec Supabase et n8n démarrés et leurs connexions configurées :

```powershell
npm run db:migrate
npm run n8n:approvals:install
npm run n8n:qualification:start
npm run n8n:approvals:start
```

La publication des validations désactive l'ancien workflow `novacorpManagerEmails`. **NovaCorp - Notifications RH et salarié** le remplace pour tous les validateurs et les changements de statut salarié. Ne pas republier manuellement l'ancien workflow. La qualification reste un workflow séparé.

Le workflow de notifications réserve au plus un email par minute, l'envoie dans MailHog puis acquitte le résultat en base. Il traite aussi les notifications déjà en attente, y compris les événements antérieurs à cette installation. Les notifications de statut sont datées et décrivent un événement historique ; le lien vers la fiche donne le statut actuel. Les demandes de validation devenues obsolètes sont abandonnées. Une file importante peut retarder les emails.

Les messages utilisent des textes déterministes, jamais le brouillon produit par le LLM. Ils sont visibles sur http://localhost:8025. L'interface reste disponible sans attendre leur réception.

## Intégrité et reprises

La RPC backend `advance_hr_approvals` verrouille la demande, vérifie les décisions, active une étape ou finalise la demande, puis écrit une trace `hr_approvals_v1`, dans une seule transaction. Les triggers existants appliquent les permissions, les seuils, l'historique et les soldes : acceptation consomme les congés réservés, refus ou annulation les libère. Une demande finale n'est pas retraitée. Le rejeu d'un identifiant d'exécution déjà traité ne produit aucun effet. Aucun appel LLM supplémentaire.

Les RPC `claim_hr_notification_email` et `finish_hr_notification_email` sont réservées à `service_role`, comme l'avancement. Réservation SMTP de cinq minutes, jeton distinct à chaque tentative, cinq tentatives maximum et temporisation progressive. Une interruption après réception SMTP mais avant acquittement peut provoquer un doublon ; SMTP ne garantit pas exactement un envoi. Une dernière réservation expirée nécessite une vérification manuelle.

## Tests

```powershell
npm run n8n:qualification:stop
npm run n8n:approvals:stop
npm run db:verify
npm run n8n:approvals:verify
```

Le test réel exécute les workflows n8n et le SMTP MailHog sur trois parcours fictifs : validation avec DRH, congés acceptés sans DRH et congés refusés. Il teste les destinataires, les statuts finaux, les soldes et les rejeux. La qualification y est une fixture SQL, le modèle Ollama étant vérifié séparément par `n8n:qualification:verify`. Les autres messages de ces seules fixtures sont marqués envoyés pour isoler le mail testé. Les données et workflows créés sont nettoyés.

Dépublier les deux familles de workflows avant les tests navigateur ou d'intégration. Pour reprendre :

```powershell
npm run n8n:qualification:start
npm run n8n:approvals:start
```

Les [relances à 24 h et alertes RH à 48 h](n8n-reminders.md) sont désormais planifiées ; aucune échéance ne produit une décision automatique.

La supervision des délais est activée par `npm run n8n:reminders:start`. La dépublier également avec `npm run n8n:reminders:stop` avant les tests d’intégration ou navigateur, puis la réactiver après les vérifications.
