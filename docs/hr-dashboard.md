# Supervision RH

La page **/tableau-de-bord/supervision**, accessible depuis le menu pour les RH et la DRH, suit toutes les demandes soumises, y compris leurs demandes personnelles. Les brouillons et les annulations sans soumission sont exclus. Le filtre de type s'applique à l'ensemble des compteurs, répartitions et listes.

La RPC `get_hr_dashboard(text)` utilise la session utilisateur, les permissions RLS existantes et un contrôle du rôle en base. Elle ne donne accès ni au manager, ni au salarié, ni au visiteur, ni à une clé service utilisée directement. Aucune clé d'administration n'est utilisée par la page.

## Indicateurs

- demandes soumises et demandes en cours ;
- validations actives et validations dont l'échéance est atteinte ;
- incidents d'automatisation et d'envoi, avec indication de reprise automatique ou de vérification manuelle ;
- répartition par statut et par type ;
- délai moyen et médian de la soumission à la décision finale pour les demandes approuvées ou refusées. Les annulations et les demandes encore en cours sont exclues de ces délais.

Les agrégats sont calculés en SQL sur toutes les lignes accessibles, indépendamment de la limite de chargement des listes Supabase. Ils correspondent à toute la période disponible, sans fenêtre implicite. Les validations, incidents et demandes en attente affichent chacun leurs 20 premiers éléments, avec les compteurs complets et un lien vers les fiches. Les validations et demandes les plus anciennes sont prioritaires. Les dates sont affichées à l'heure de Paris.

Pour chaque demande et automatisation, seule la dernière exécution est examinée : un échec suivi d'une réussite n'est plus un incident. Les traitements échoués des demandes clôturées ne sont pas comptés. Pour les emails, les notifications de statut restent pertinentes après clôture ; les notifications de validation, relance ou alerte devenues obsolètes sont exclues.

Les messages d'incident sont génériques : les détails techniques et les secrets ne sont pas affichés. Cette page ne relance pas un traitement et ne prend pas de décision. Les décisions et les traces n8n restent accessibles dans leurs écrans respectifs.

## Actualisation et vérification

La page se rafraîchit lors des changements Realtime de demande, validation et notification, au retour sur la fenêtre et toutes les dix secondes tant qu'elle est visible. Ce rafraîchissement de secours actualise aussi les incidents et le passage des échéances. Le bouton Actualiser permet une mise à jour manuelle. Une panne de chargement affiche un message d'erreur sans présenter de faux compteurs à zéro.

```powershell
npm run db:migrate
npm run db:types
npm run db:verify
```

Pour les tests navigateur, dépublier la qualification, les validations et les relances selon le README, puis lancer `npm test`. Les tests ajoutés vérifient les rôles, les compteurs, un retard et une erreur fictifs, les liens, le filtre et le rendu mobile. Ils nettoient uniquement leur utilisateur et leurs demandes. Réactiver ensuite les trois familles de workflows.
