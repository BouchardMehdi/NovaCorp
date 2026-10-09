# Données fictives pour les essais manuels

Branche : `feat/demo-data`. Ce jeu prépare les écrans existants sans modifier les règles métier.

## Installation

Avec Docker, Supabase local, les migrations, les comptes et les référents déjà configurés :

```powershell
npm run demo:seed
```

Sur une installation vierge, exécuter auparavant les étapes du README, notamment `npm run auth:seed` et `npm run business:seed`. Le script exige les référents Alex Martin, Morgan Petit et Lou Bernard ; il refuse de remplacer une configuration différente.

Le compte dédié **Emma Laurent**, `demo.salarie@novacorp.test`, utilise le mot de passe initial **NovaCorpDemo2026!**. Son manager est `manager@novacorp.test`. Les comptes RH et DRH existants permettent de suivre les étapes suivantes et la supervision.

Le compte habituel `salarie@novacorp.test` conserve ses propres demandes. Les quatre brouillons d'Emma restent privés ; les validateurs voient les demandes soumises selon leurs permissions habituelles.

## Scénarios initiaux

Les 23 demandes portent le préfixe **[Démo]**.

| Situation | Nombre | Contenu |
|---|---:|---|
| Brouillons | 4 | Un par type |
| Soumises, à qualifier | 4 | Un par type |
| Validation manager | 2 | Congés et télétravail |
| Validation RH | 2 | Équipement et formation |
| Validation DRH | 3 | Congés de 11 jours, équipement à 1 800 €, formation à 2 200 € |
| Approuvées | 2 | Congés et équipement |
| Refusée | 1 | Formation |
| Annulée | 1 | Télétravail |
| Qualification en échec | 1 | Équipement, trois tentatives fictives épuisées |
| Validation RH en retard | 1 | Équipement, délai de 48 h dépassé, échec SMTP fictif |
| Relances à 24 h | 2 | Manager et DRH |

Les périodes commencent l'année suivante, à partir de son premier lundi, et ne se chevauchent pas. À la première création en 2026, elles se situent donc en 2027. Le compte reçoit un solde initial de 25 jours pour l'année courante et la suivante, sans écraser un solde existant. Les scénarios réservent initialement 15 jours et consomment 2 jours.

## Historique et automatisations

La soumission, la réservation des congés, la qualification et les décisions passent par les fonctions métier existantes, dans une transaction. Les qualifications préparées utilisent les marqueurs `provider=demo` et `model=fixture` : elles sont simulées, sans appel LLM. Les commentaires de décision indiquent leur caractère fictif.

Pour afficher immédiatement des délais, les horodatages des nouvelles demandes sont ensuite simulés dans la session PostgreSQL du script. Ce traitement administratif est réservé aux identifiants du jeu, et ne désactive aucun trigger globalement. Les décisions préparées sont attribuées aux validateurs fictifs.

Les anciens emails de changement de statut sont marqués comme envoyés avec `provider_message_id=demo-fixture-no-smtp` : **aucun envoi SMTP n'a réellement eu lieu pour ces historiques fictifs**. Les invitations déjà dépassées sont rendues obsolètes. Une invitation active RH est volontairement en échec définitif pour alimenter la supervision.

Avec les workflows n8n actifs, les quatre demandes soumises sont réellement qualifiées et les invitations encore utiles, relances et alertes partent dans MailHog. Le jeu évolue donc après sa création, et les décisions suivantes restent humaines. Les demandes en échec définitif restent visibles pour un traitement manuel.

## Relancer le script

Les identifiants sont stables. Une demande déjà présente est ignorée : les modifications, décisions et annulations faites pendant les essais sont conservées. Les mots de passe existants ne sont pas réinitialisés. Les autres comptes et demandes ne sont pas modifiés.

La création des demandes et de leurs historiques est transactionnelle. La création Auth et l'initialisation du compte précèdent cette transaction ; après une interruption, relancer la même commande. Le script ne réinitialise ni la base, ni le jeu existant, même si l'année change. Il ne crée pas de pièces jointes.

Ce jeu sert aux essais manuels et à la démonstration ; les tests automatisés continuent de créer et nettoyer leurs propres données.
