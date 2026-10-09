import { approveEndpoint, connectWebhook, disableWebhook } from "./requests-webhook-tools.mjs";

try {
  if (process.argv.includes("--disable")) {
    disableWebhook();
    console.log("Envoi automatique Supabase désactivé. Les demandes restent utilisables.");
  } else {
    const approved = process.argv.find(arg => arg.startsWith("--approve-url="))?.slice("--approve-url=".length);
    if (approved) await approveEndpoint(approved);
    const endpoint = await connectWebhook();
    console.log("Supabase local raccordé à " + endpoint);
    console.log("Métadonnées uniquement : événement, identifiant et statut. Aucun traitement RH déclenché.");
  }
} catch (error) {
  // Une erreur SQL peut contenir le secret interpolé : ne pas afficher stderr.
  console.error(error.status !== undefined ? "Configuration Vault impossible. Vérifier Supabase local et la migration." : error.message);
  process.exitCode = 1;
}
