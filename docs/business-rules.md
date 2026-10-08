# Règles métier validées

Ces règles sont les choix de l'équipe pour NovaCorp. Le PDF impose les quatre types, le routage multi-niveaux, les contrôles, la traçabilité et les notifications ; il ne chiffre pas les seuils et délais. Les données locales sont fictives.

## Validation

| Demande | Circuit | Condition de passage au DRH |
|---|---|---|
| Congés | Manager → RH | Plus de 10 jours ouvrés calculés |
| Télétravail | Manager → RH | Aucun passage au DRH |
| Matériel | Manager → RH | Montant total strictement supérieur à 1 000 EUR |
| Formation | Manager → RH | Montant total strictement supérieur à 1 500 EUR |

Au seuil exact, le DRH n'intervient pas. Un refus motivé met fin au circuit. Un accord permet à n8n d'activer l'étape suivante. La qualification IA ne constitue pas une décision d'approbation.

La migration crée une nouvelle version active des quatre circuits, avec 48 heures de décision et 24 heures avant relance. Les versions antérieures sont désactivées, leurs paramètres conservés. Les demandes déjà soumises gardent leurs règles.

## Affectation des validateurs

Le manager vient du profil du demandeur. Les référents viennent de la ligne unique de `hr_routing_settings`. Les identifiants du manager, du RH et du DRH éventuellement requis sont capturés à la soumission.

En démonstration :

- Manager de Camille : **Alex Martin**, `manager@novacorp.test`.
- Référent RH : **Morgan Petit**, `rh@novacorp.test`.
- Référent DRH : **Lou Bernard**, `drh@novacorp.test`.

L'auto-approbation est interdite. Si le demandeur est le référent RH ou le référent DRH requis, un suppléant du même rôle doit être configuré (`alternate_hr_id` / `alternate_director_id`). Sinon la soumission échoue avec un message explicite. Aucun suppléant fictif supplémentaire n'est créé automatiquement.

Alex n'a pas de manager dans le jeu initial : pour qu'il soumette une demande personnelle, il faut lui affecter un autre manager. Les profils RH et DRH sont rattachés à Alex par l'initialisation locale si aucun manager n'est déjà renseigné.

`prepare_hr_approvals(p_request_id)`, réservé au backend, crée les étapes depuis les référents capturés. L'appel peut être répété sans dupliquer les étapes. Il n'active aucune étape et ne remplace pas l'orchestration n8n. Les validateurs affectés doivent toujours avoir le rôle attendu.

## Congés

Le calendrier de démonstration est **lundi à vendredi**, dates incluses. Les jours fériés ne sont pas exclus. Ce choix de simulation est explicite ; aucun calendrier légal ou conventionnel n'est supposé.

Les demi-journées portent sur les bornes :

| Champ | Signification |
|---|---|
| `start_half_day = false` | Début le matin |
| `start_half_day = true` | Début l'après-midi |
| `end_half_day = false` | Fin à la fin de la journée |
| `end_half_day = true` | Fin à midi |

Une demande sur un seul jour avec une seule de ces bornes activée vaut 0,5 jour. Activer les deux sur le même jour produit une période vide et est refusé. Les demi-journées sur un week-end et les périodes sans jour ouvré sont refusées.

`calculate_leave_days(p_start, p_end, p_start_half, p_end_half)` est disponible au client connecté pour prévisualiser le résultat. La base recalcule le total lors de la soumission : elle remplace une valeur de `requested_days` fournie par le client. Les années prises en charge vont de 2000 à 2200, comme les soldes.

### Soldes et mouvements

Les quatre comptes fictifs reçoivent **25 jours** pour l'année courante et la suivante lors de `npm run business:seed`. C'est une donnée de démonstration, pas un droit légal déduit du PDF. Les soldes existants ne sont pas réinitialisés.

`disponible = droits alloués − jours consommés − jours réservés`.

| Événement | Mouvement |
|---|---|
| Soumission | Réservation des jours, disponible diminué |
| Approbation finale | Réservation transformée en consommation |
| Refus final | Réservation libérée, aucune consommation |
| Annulation | Réservation libérée |
| Nouvelle tentative d'une opération déjà terminée | Aucun second mouvement |

Les mouvements sont réalisés par la base dans la même transaction que le statut. Une soumission sans solde suffisant est refusée. Une demande sur deux années est répartie entre les deux soldes, demi-journées comprises ; si un solde est absent ou insuffisant, toute la soumission est annulée.

`leave_allocations` conserve le nombre de jours par demande et par solde, avec l'état `reserved`, `consumed` ou `released`. Les clients, y compris le compte n8n, ne peuvent pas écrire directement ces allocations. Le journal des soldes est alimenté automatiquement.

Deux soumissions d'un même salarié sont sérialisées par un verrou sur son profil, puis les soldes sont verrouillés par année. Les tests de concurrence vérifient qu'un total supérieur au disponible et deux périodes identiques ne sont pas acceptés simultanément.

## Contrôles déterministes et IA

La base contrôle les dates et calcule les congés. Elle bloque la superposition de demandes actives de congés ou de télétravail d'un même salarié. Les brouillons, refus et annulations ne bloquent pas une nouvelle demande. Deux demi-journées disjointes sur le même jour sont permises ; une intersection limitée au week-end ne bloque pas.

`get_hr_request_checks(p_request_id)`, réservé au backend, retourne :

- le nombre de jours calculé ;
- la suffisance des soldes, sans déduire deux fois la réservation de cette demande ;
- les anomalies bloquantes et les demandes en conflit ;
- les demandes potentiellement identiques du salarié ;
- un indicateur de revue humaine nécessaire.

Un doublon potentiel compare le type, le titre normalisé, les dates/demi-journées, le montant et la quantité aux demandes actives ou approuvées. Il est signalé, sans refus automatique : deux commandes identiques peuvent être légitimes.

n8n pourra transmettre ce résultat au LLM pour produire la synthèse du validateur et un brouillon de réponse. Le LLM ne remplace pas le calcul du solde ni les contrôles d'autorisation. La [qualification locale avec Ollama](n8n-qualification.md) est maintenant implémentée dans n8n ; elle conserve la décision humaine.

## Délais et notifications

Le délai commence quand n8n active une étape en `pending`. La base produit `activated_at` et `due_at`.

- **24 heures calendaires** : une relance au validateur encore en attente.
- **48 heures calendaires** : une alerte au RH référent si l'étape reste en attente.
- Aucun accord, refus ou passage à l'étape suivante n'est automatique à l'expiration.
- Le week-end compte dans ces délais ; une nouvelle étape bénéficie de ses propres 48 heures.

Le backend appellera périodiquement `queue_hr_approval_reminders()`. Cette opération crée les notifications en file et évite les doublons. Le paramètre facultatif `p_now` permet des tests aux frontières ; en exploitation, utiliser l'heure réelle par défaut.

Si le premier passage du superviseur survient après l'échéance, il crée directement l'alerte RH, sans ajouter une relance déjà périmée. Une demande clôturée n'engendre plus de relances. Lors de la réservation d'un email, n8n vérifie en base que la demande et l'étape sont encore actives, y compris pour une notification déjà mise en file.

Ces opérations ne démarrent pas de planificateur et n'envoient pas d'email à elles seules. L'envoi MailHog et la planification périodique seront branchés dans n8n.

## Mise en place locale

```powershell
npm run db:migrate
npm run auth:seed
npm run business:seed
npm run db:types
```

L'initialisation métier est réservée aux URL locales. Les référents et les soldes déjà présents sont conservés. Après une réinitialisation volontaire de la base, relancer les deux scripts d'initialisation.

Vérifications :

```powershell
npm run db:lint
npm run db:test
npm run db:verify
npm run lint
npm run typecheck
npm test
npm run build
```

`db:test` annule les données de chaque test. `db:verify` crée une base temporaire, y reconstruit le schéma à partir des migrations, exécute les tests et deux scénarios de concurrence, puis supprime uniquement cette base temporaire. Il utilise le conteneur local `supabase_db_NovaCorp` et ne copie que la structure de la base, sans ses données.

Les formulaires et le suivi sont disponibles. Le workflow de qualification active le manager ; le [circuit n8n](n8n-approvals.md) active ensuite les RH/DRH et finalise après décisions humaines. Les emails des validateurs et les statuts salarié sont envoyés dans MailHog. Les [relances et alertes](n8n-reminders.md) sont planifiées dans n8n.

Les RPC backend `advance_hr_approvals(text,uuid)`, `claim_hr_notification_email(uuid)` et `finish_hr_notification_email(uuid,uuid,boolean,text)` assurent respectivement l’avancement atomique, la réservation SMTP et son acquittement. Les décisions humaines et les seuils restent vérifiés par les gardes SQL existants.

La supervision des délais est activée par `npm run n8n:reminders:start`. La dépublier également avec `npm run n8n:reminders:stop` avant les tests d’intégration ou navigateur, puis la réactiver après les vérifications.
