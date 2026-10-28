# Validation humaine des demandes RH

Document de démonstration NovaCorp, issu de docs/business-rules.md. Il décrit les choix du projet ; il ne constitue ni une convention collective ni un avis juridique.

## Circuit et responsabilités

Les demandes de congés, télétravail, matériel et formation suivent une validation manager puis ressources humaines. La direction RH intervient selon les seuils du type de demande. Une qualification par l'intelligence artificielle ne constitue jamais une approbation ou un refus. Les décisions appartiennent aux validateurs humains affectés. L'auto-approbation est interdite. Le manager et les référents sont figés à la soumission.

## Contrôles et demandes similaires

La base SQL contrôle les dates, les soldes, les chevauchements et les doublons potentiels. Ses résultats priment sur le texte de la demande et sur les documents. Un doublon potentiel nécessite une revue humaine ; il ne provoque pas un refus automatique. Un refus exige un motif. Aucun dépassement de délai ne provoque un accord automatique.
