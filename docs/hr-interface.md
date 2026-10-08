# Interface des demandes RH

## Parcours disponible

Depuis `/tableau-de-bord`, le salarié peut créer une demande de congés, télétravail, matériel ou formation, enregistrer un brouillon, le modifier, le soumettre et annuler une demande non terminée après confirmation.

La liste affiche les demandes personnelles avec des filtres de type et de statut, et une pagination de 20 demandes. Le solde affiché concerne l’année courante. Le manager dispose d’une vue de son équipe ; les RH et la DRH disposent d’une vue des demandes accessibles à leur rôle. Les brouillons des autres salariés restent privés.

La fiche présente les informations saisies, les étapes de validation et les 50 événements les plus récents. Elle se met à jour avec Supabase Realtime ; une actualisation de secours toutes les 10 secondes lorsque la page est visible et le retour au premier plan actualisent aussi les données.

Le validateur assigné à une étape active peut approuver ou refuser. Le refus exige un commentaire. Une synthèse IA réussie, lorsqu’elle existe, apparaît aux validateurs autorisés. Aucune décision n’est prise automatiquement par l’interface.

## Règles et sécurité

Chaque action serveur vérifie la session. Les accès utilisent la clé publique et la session du salarié, soumis aux politiques RLS. La clé d’administration n’est pas utilisée par les pages ou les actions de l’application.

Les fonctions SQL existantes restent responsables de la soumission, de l’annulation et des décisions. Les soldes, les chevauchements, les référents, les seuils DRH et les transitions restent vérifiés en base. Un échec de soumission conserve le brouillon enregistré et son identifiant : une nouvelle tentative modifie ce même brouillon.

Le titre est obligatoire même pour un brouillon. Les autres données propres au type peuvent être complétées plus tard ; les dates, le montant et la quantité nécessaires sont exigés à la soumission. Les dates vont de 2000 à 2200. Les montants sont en euros et acceptent une virgule ou un point, avec deux décimales maximum.

## Suite du projet

La soumission place la demande dans l’état « Soumise ». Le [workflow de qualification n8n](n8n-qualification.md) lance maintenant l’analyse IA, prépare le circuit et active le manager. L’avancement après les décisions reste à développer. Les boutons de validation apparaissent lorsque ces étapes existent et sont actives.

L’envoi au manager via MailHog est connecté dans n8n ; les notifications salarié et les relances restent à connecter. Cette étape ajoute les formulaires et le suivi ; le dépôt et l’analyse des pièces jointes ne sont pas encore exposés dans l’interface.

## Vérification

`npm test` couvre l’authentification et les parcours des quatre formulaires, les erreurs de solde et leurs reprises sans doublon, les filtres, la confidentialité d’un brouillon, l’affichage mobile et les décisions du manager avec actualisation du suivi salarié.

Les tests RH créent un utilisateur fictif distinct, doté d’un solde propre. Ils simulent la préparation n8n uniquement pour tester les boutons du validateur. Leur nettoyage supprime uniquement les données de cet utilisateur aléatoire, via le conteneur PostgreSQL local `supabase_db_NovaCorp`, sans réinitialiser la base.
