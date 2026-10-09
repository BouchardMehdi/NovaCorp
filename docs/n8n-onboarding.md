# S5 — Bienvenue et checklist du premier jour

L'ajout d'un nouveau profil dans `profiles` crée automatiquement une ligne dans `employee_onboardings`, dans la même transaction. Le workflow **NovaCorp - Bienvenue et checklist premier jour** (`novacorpOnboarding`) réserve et envoie l'email dans MailHog, au plus un message par minute.

Tout nouveau collègue reçoit cet accueil, y compris les managers, RH et DRH : les comptes Auth créent d'abord un profil salarié, puis l'administration affecte leur rôle. Une mise à jour du nom, du rôle ou du manager ne crée pas un nouvel accueil. La migration ne produit aucun envoi rétroactif pour les profils déjà existants.

L'email contient un message de bienvenue personnalisé avec le prénom disponible au moment de l'envoi, un lien vers la connexion à l'espace RH et la checklist suivante :

1. Confirmer avec les RH les horaires et le lieu de l'accueil.
2. Rencontrer le manager et l'équipe.
3. Vérifier l'accès à l'espace RH et aux outils de travail.
4. Récupérer le matériel et vérifier son fonctionnement.
5. Prendre connaissance des consignes internes et de sécurité.
6. Faire le point avec le manager sur les premières missions.

Les cases `[ ]` figurent dans le texte de l'email. Il s'agit d'une checklist de préparation, sans suivi interactif des cases dans le front. Les éléments sont conservés dans la ligne d'accueil. Aucun mot de passe ni clé n'est envoyé : les RH communiquent séparément les modalités de connexion. Les horaires, lieux et missions réels restent à préciser avec l'équipe.

## Installation

```powershell
npm run db:migrate
npm run n8n:onboarding:install
npm run n8n:onboarding:start
```

Les connexions Supabase et MailHog existantes sont réutilisées. Aucun nouveau conteneur ni appel LLM. Supabase reste local et le redémarrage conserve la configuration ngrok du conteneur n8n. Le lien vers le front reste local comme dans les autres emails.

Pour arrêter uniquement l'envoi des accueils :

```powershell
npm run n8n:onboarding:stop
```

La file continue à être alimentée lors des créations de profils, même avec n8n arrêté. Elle est traitée lors de la reprise ; aucune date de premier jour n'est inventée et l'email n'est pas programmé selon une date d'embauche.

## Fiabilité et accès

La contrainte unique sur `employee_id` garantit un accueil maximum par profil. La file est protégée par RLS, sans accès direct depuis le navigateur. Seul le backend peut appeler `claim_employee_onboarding(uuid)` et `finish_employee_onboarding(uuid,uuid,boolean,text)`. Le paramètre facultatif d'employé sert aux tests ciblés ; le workflow publié traite toute la file.

Les réservations SMTP durent cinq minutes, avec jeton et cinq tentatives maximum. Les échecs sont conservés et repris avec temporisation ; une adresse absente ou une cinquième réservation expirée requiert une vérification manuelle. Un ancien jeton ne peut pas acquitter une réservation reprise. La suppression du compte nettoie son accueil par cascade.

La déduplication en base n'assure pas une livraison SMTP exactement une fois : une interruption après réception du mail mais avant acquittement peut provoquer un nouvel envoi. Les erreurs figurent dans les exécutions n8n et dans la file d'accueil ; elles ne sont pas rattachées à une demande RH individuelle dans la supervision.

## Vérifications

```powershell
npm run db:verify
npm run n8n:onboarding:stop
npm run n8n:onboarding:verify
npm run n8n:onboarding:start
```

Le test n8n crée un nouveau compte fictif avec un prénom, vérifie la mise en file automatique puis l'email réel dans MailHog, les six cases, le lien et le rejeu sans doublon après modification du profil. Le compte, son accueil et le workflow temporaire sont nettoyés.

Les tests SQL vérifient les droits, les champs du message, les destinataires, les reprises, les jetons, l'adresse absente, la limite d'essais et la suppression du compte. La reconstruction vérifie aussi deux réservations simultanées.

Avant les autres tests d'intégration ou navigateur qui créent des utilisateurs, arrêter également ce workflow avec `npm run n8n:onboarding:stop`, puis le réactiver après les tests. Cela évite que leurs comptes temporaires reçoivent des emails d'accueil pendant la mesure des autres notifications.
