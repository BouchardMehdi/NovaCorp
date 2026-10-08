import { execFileSync } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const cli = path.resolve("node_modules/supabase/dist/supabase.js");
try {
  const status = JSON.parse(execFileSync(process.execPath, [cli, "status", "-o", "json"], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }));
  const url = status.API_URL;
  const key = status.PUBLISHABLE_KEY || status.ANON_KEY;
  const adminKey = status.SERVICE_ROLE_KEY;
  if (!url || !key || !adminKey) throw new Error("Informations de connexion locales incomplètes.");
  if (!["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname)) {
    throw new Error("Ce script est réservé à Supabase local.");
  }
  let existing = "";
  try { existing = await readFile(".env.local", "utf8"); } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  const values = {
    NEXT_PUBLIC_SUPABASE_URL: url,
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: key,
    SUPABASE_SERVICE_ROLE_KEY: adminKey,
  };
  let lines = existing.split(/\r?\n/).filter((line) => !Object.keys(values).some((name) => line.startsWith(name + "=")));
  lines = lines.filter((line) => line.trim() !== "");
  lines.push(...Object.entries(values).map(([name, value]) => name + "=" + value));
  await writeFile(".env.local", lines.join("\n") + "\n");
  console.log(".env.local configuré pour Supabase local. Les clés ne sont pas affichées.");
} catch (error) {
  console.error("Impossible de configurer .env.local. Vérifiez que npm run supabase:start a réussi.");
  console.error(error.message?.split("\n")[0]);
  process.exitCode = 1;
}
