import { randomBytes } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import path from "node:path";
try {
  const status = JSON.parse(execFileSync(process.execPath, [path.resolve("node_modules/supabase/dist/supabase.js"), "status", "-o", "json"], { encoding: "utf8", stdio: ["ignore","pipe","pipe"] }));
  if (!["localhost","127.0.0.1","[::1]"].includes(new URL(status.API_URL).hostname) || !status.SERVICE_ROLE_KEY) throw new Error("Supabase local requis.");
  let existing = "";
  try { existing = await readFile(".env.n8n.local","utf8"); } catch(error) { if(error.code !== "ENOENT") throw error; }
  const key = existing.match(/^N8N_ENCRYPTION_KEY=(.+)$/m)?.[1]?.trim() || randomBytes(32).toString("hex");
  const values = { N8N_ENCRYPTION_KEY:key, NOVACORP_SUPABASE_URL:"http://supabase_kong_NovaCorp:8000", NOVACORP_SUPABASE_SERVICE_ROLE_KEY:status.SERVICE_ROLE_KEY };
  const lines = existing.split(/\r?\n/).filter(line => line.trim() && !Object.keys(values).some(name => line.startsWith(name+"=")));
  lines.push(...Object.entries(values).map(([name,value])=>name+"="+value));
  await writeFile(".env.n8n.local",lines.join("\n")+"\n",{mode:0o600});
  console.log(".env.n8n.local configuré. Clé de chiffrement conservée, aucun secret affiché.");
} catch {
  console.error("Configuration n8n impossible. Démarrez Supabase local avec npm run supabase:start.");
  process.exitCode = 1;
}
