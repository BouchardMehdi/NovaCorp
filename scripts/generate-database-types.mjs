import { execFileSync } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

try {
  const cli = path.resolve("node_modules/supabase/dist/supabase.js");
  const types = execFileSync(process.execPath, [cli, "gen", "types", "typescript", "--local", "--schema", "public"], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 8 * 1024 * 1024 });
  if (!types.includes("export type Database =")) throw new Error("La CLI n’a pas renvoyé les types attendus.");
  await mkdir("src/types", { recursive: true });
  await writeFile("src/types/database.ts", "// Généré depuis Supabase local : npm run db:types\n" + types.replace(/[ \t]+$/gm, ""));
  console.log("Types publics générés dans src/types/database.ts.");
} catch (error) {
  console.error("Génération impossible. Vérifiez que Supabase local est démarré et les migrations appliquées.");
  console.error(error.message?.split("\n")[0]);
  process.exitCode = 1;
}
