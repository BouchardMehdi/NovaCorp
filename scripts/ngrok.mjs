import { docker, container } from "./n8n-tools.mjs";
import { config, value, prepare, overlay, stopTunnel, timedFetch } from "./ngrok-tools.mjs";
import { writeFile } from "node:fs/promises";
import { connectWebhook, disableWebhook } from "./requests-webhook-tools.mjs";

try {
  const action = process.argv[2];
  if (action === "env") {
    await prepare();
    console.log("Fichier .env.ngrok.local prêt. Renseigner NGROK_AUTHTOKEN directement dans ce fichier.");
  } else if (action === "stop") {
    try { disableWebhook(); } finally { await stopTunnel(); }
    console.log("Tunnel arrêté. n8n utilise à nouveau http://localhost:5678 ; Supabase reste local.");
  } else if (action === "start") {
    await prepare();
    const source = await config();
    if (!value(source, "NGROK_AUTHTOKEN")) throw new Error("Renseigner NGROK_AUTHTOKEN dans .env.ngrok.local, puis relancer cette commande.");
    container();
    disableWebhook();
    docker([...overlay, "up", "-d", "--no-deps", "ngrok"]);
    let url;
    for (let attempt = 0; attempt < 30; attempt++) {
      try {
        const response = await timedFetch("http://127.0.0.1:4040/api/tunnels");
        if (response.ok) url = (await response.json()).tunnels?.find(tunnel => tunnel.public_url?.startsWith("https://"))?.public_url;
        if (url) break;
      } catch { /* démarrage en cours */ }
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
    if (!url) {
      docker([...overlay, "stop", "ngrok"]);
      throw new Error("Aucun tunnel HTTPS obtenu. Vérifier le token et le compte ngrok. Aucun changement Supabase effectué.");
    }
    const lines = source.split(/\r?\n/).filter(line => line.trim() && !line.startsWith("N8N_PUBLIC_URL="));
    await writeFile(".env.ngrok.local", lines.join("\n") + "\nN8N_PUBLIC_URL=" + url + "\n", { mode: 0o600 });
    docker([...overlay, "up", "-d", "--wait", "n8n"]);
    console.log("n8n public : " + url);
    console.log("Webhook : " + url + "/webhook/novacorp-requests");
    if (value(source, "N8N_APPROVED_WEBHOOK_URL") === url + "/webhook/novacorp-requests") {
      await connectWebhook();
      console.log("Supabase local : envoi des identifiants et statuts réactivé vers l'URL autorisée.");
    } else {
      console.log("Supabase reste local. Envoi automatique désactivé : autoriser d'abord cette URL précise.");
    }
  } else throw new Error("Action attendue : env, start ou stop.");
} catch (error) {
  // Ne pas afficher le stderr Docker : il peut contenir la configuration ngrok.
  console.error(error.status !== undefined ? "Commande Docker échouée. Vérifier Docker Desktop et la configuration locale." : error.message);
  process.exitCode = 1;
}
