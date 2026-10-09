import { readFile, writeFile } from "node:fs/promises";
import { randomBytes } from "node:crypto";
import { docker } from "./n8n-tools.mjs";

export const overlay = ["compose", "--env-file", ".env.ngrok.local", "-f", "compose.yaml", "-f", "compose.ngrok.yaml", "--profile", "automation", "--profile", "tunnel"];
export async function config() {
  try { return await readFile(".env.ngrok.local", "utf8"); }
  catch (error) { if (error.code !== "ENOENT") throw error; return ""; }
}
export function value(source, name) {
  const raw = source.split(/\r?\n/).find(line => line.startsWith(name + "="))?.slice(name.length + 1).trim() ?? "";
  return raw.replace(/^(["'])(.*)\1$/, "$2");
}
export async function prepare() {
  if (!(await config())) await writeFile(".env.ngrok.local", "# Renseigner le token uniquement ici, jamais dans Git ou le chat.\nNGROK_AUTHTOKEN=\nN8N_PUBLIC_URL=\n", { mode: 0o600 });
  const path = ".env.n8n.local";
  const source = await readFile(path, "utf8");
  let token = value(source, "NOVACORP_REQUESTS_WEBHOOK_TOKEN");
  if (!token) {
    token = randomBytes(32).toString("hex");
    await writeFile(path, source.trimEnd() + "\nNOVACORP_REQUESTS_WEBHOOK_TOKEN=" + token + "\n", { mode: 0o600 });
  }
  return token;
}
export async function publicUrl() {
  const url = value(await config(), "N8N_PUBLIC_URL");
  if (!url || new URL(url).protocol !== "https:") throw new Error("Lancer npm run ngrok:start pour obtenir l'URL publique.");
  return url.replace(/\/$/, "");
}
export async function ready() {
  for (let attempt = 0; attempt < 60; attempt++) {
    try {
      const response = await timedFetch("http://127.0.0.1:5678/healthz/readiness");
      if (response.ok) return;
    } catch { /* démarrage en cours */ }
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
  throw new Error("n8n n'est pas prêt après le redémarrage.");
}
export async function timedFetch(url) {
  const controller = new AbortController();
  // Timer référencé : garder Node actif même pendant un redémarrage du serveur.
  const timer = setTimeout(() => controller.abort(), 1500);
  try { return await fetch(url, { signal: controller.signal }); }
  finally { clearTimeout(timer); }
}
export async function stopTunnel() {
  docker([...overlay, "stop", "ngrok"]);
  docker(["compose", "--profile", "automation", "up", "-d", "--wait", "n8n"]);
  await ready();
}
