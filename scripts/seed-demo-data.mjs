import { createClient } from "@supabase/supabase-js";
import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { demoEmail, demoPassword, demoScenarios } from "./demo-scenarios.mjs";

async function seed() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key || !["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname))
    throw new Error("Ce jeu de données est réservé à Supabase local (.env.local).");
  // Le SQL et l'API doivent désigner le même environnement local standard.
  if (Number(new URL(url).port) !== 54321)
    throw new Error("Le script attend l'API Supabase locale sur le port 54321.");
  const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const users = [];
  for (let page = 1; ; page++) {
    const { data, error } = await client.auth.admin.listUsers({ page, perPage: 100 });
    if (error) throw error;
    users.push(...data.users);
    if (data.users.length < 100) break;
  }
  const validators = [
    ["manager@novacorp.test", "manager"], ["rh@novacorp.test", "hr"], ["drh@novacorp.test", "director"],
  ];
  const ids = [];
  for (const [email, role] of validators) {
    const user = users.find((candidate) => candidate.email === email);
    if (!user) throw new Error("Exécuter d'abord npm run auth:seed et npm run business:seed.");
    const { data, error } = await client.from("profiles").select("role").eq("id", user.id).single();
    if (error) throw error;
    if (data.role !== role) throw new Error("Rôle inattendu pour " + email + " ; aucune modification effectuée.");
    ids.push(user.id);
  }
  const { data: routing, error: routingError } = await client.from("hr_routing_settings")
    .select("hr_referent_id,director_referent_id").eq("singleton", true).single();
  if (routingError) throw routingError;
  if (routing.hr_referent_id !== ids[1] || routing.director_referent_id !== ids[2])
    throw new Error("Les référents locaux ne correspondent pas aux comptes de démonstration.");
  const year = new Date().getFullYear();
  const scenarios = demoScenarios(year);
  // Vérifier le conteneur avant de créer le compte.
  execFileSync("docker", ["exec", "supabase_db_NovaCorp", "pg_isready", "-U", "supabase_admin"],
    { encoding: "utf8", timeout: 15000, stdio: ["pipe", "pipe", "pipe"] });
  let employee = users.find((candidate) => candidate.email === demoEmail);
  if (!employee) {
    const { data, error } = await client.auth.admin.createUser({
      email: demoEmail, password: demoPassword, email_confirm: true,
      user_metadata: { first_name: "Emma", last_name: "Laurent" },
    });
    if (error) throw error;
    employee = data.user;
  }
  if (!employee) throw new Error("Le compte de démonstration n'a pas été créé.");
  const { data: profile, error: profileError } = await client.from("profiles")
    .select("role,manager_id").eq("id", employee.id).single();
  if (profileError) throw profileError;
  if (profile.role !== "employee" || (profile.manager_id && profile.manager_id !== ids[0]))
    throw new Error("Le profil de démonstration a été personnalisé ; vérifier son rôle et son manager.");
  // Autorise la reprise après une interruption entre la création Auth et l'affectation.
  if (!profile.manager_id) {
    const { error } = await client.from("profiles").update({ manager_id: ids[0] }).eq("id", employee.id);
    if (error) throw error;
  }
  const { error: balanceError } = await client.from("leave_balances").upsert(
    [year, year + 1].map((balanceYear) => ({ employee_id: employee.id, year: balanceYear, allocated_days: 25 })),
    { onConflict: "employee_id,year", ignoreDuplicates: true },
  );
  if (balanceError) throw balanceError;
  const payload = JSON.stringify({ employee_id: employee.id, scenarios });
  const delimiter = "$demo_" + randomUUID().replaceAll("-", "") + "$";
  const sql = [
    "begin;", "set local statement_timeout = '60s';",
    "create temporary table demo_seed_context(payload jsonb) on commit drop;",
    "insert into demo_seed_context values (" + delimiter + payload + delimiter + "::jsonb);",
    await readFile(new URL("./demo-data.sql", import.meta.url), "utf8"), "commit;",
  ].join("\n");
  const output = execFileSync("docker", ["exec", "-i", "supabase_db_NovaCorp", "psql",
    "-U", "supabase_admin", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-q"], {
    input: sql, encoding: "utf8", timeout: 90000, maxBuffer: 2 * 1024 * 1024,
    stdio: ["pipe", "pipe", "pipe"],
  });
  if (output.trim()) console.log(output.trim());
  const { data: requests, error } = await client.from("requests")
    .select("id,status").eq("requester_id", employee.id).in("id", scenarios.map((scenario) => scenario.id));
  if (error) throw error;
  if (requests.length !== scenarios.length) throw new Error("Le jeu de démonstration est incomplet.");
  const counts = requests.reduce((result, request) => {
    result[request.status] = (result[request.status] ?? 0) + 1;
    return result;
  }, {});
  console.log("Démonstration prête : " + requests.length + " demandes pour " + demoEmail + ".");
  console.log("Statuts actuels : " + JSON.stringify(counts));
  console.log("Les demandes existantes sont conservées. n8n peut faire progresser les demandes soumises.");
}

seed().catch((error) => {
  console.error(error.stderr?.toString().trim() || error.message);
  process.exitCode = 1;
});
