import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

async function seed() {
  if (!url || !key || !["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname)) {
    throw new Error("Ce script est réservé à Supabase local configuré dans .env.local.");
  }
  const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const accounts = [];
  for (let page = 1; ; page++) {
    const { data, error } = await client.auth.admin.listUsers({ page, perPage: 100 });
    if (error) throw error;
    accounts.push(...data.users);
    if (data.users.length < 100) break;
  }
  const emails = ["salarie@novacorp.test", "manager@novacorp.test", "rh@novacorp.test", "drh@novacorp.test"];
  const users = emails.map((email) => accounts.find((user) => user.email === email));
  if (users.some((user) => !user)) throw new Error("Créer d’abord les comptes fictifs avec npm run auth:seed.");
  const year = new Date().getFullYear();
  const balances = users.flatMap((user) => [year, year + 1].map((balanceYear) => ({
    employee_id: user.id, year: balanceYear, allocated_days: 25,
  })));
  const { error: balanceError } = await client.from("leave_balances")
    .upsert(balances, { onConflict: "employee_id,year", ignoreDuplicates: true });
  if (balanceError) throw balanceError;
  const { error: routingError } = await client.from("hr_routing_settings").upsert({
    singleton: true,
    hr_referent_id: users[2].id,
    director_referent_id: users[3].id,
  }, { onConflict: "singleton", ignoreDuplicates: true });
  if (routingError) throw routingError;
  // Affecter les profils RH/DRH sans écraser une affectation manuelle existante.
  const { error: managerError } = await client.from("profiles")
    .update({ manager_id: users[1].id }).in("id", [users[2].id, users[3].id]).is("manager_id", null);
  if (managerError) throw managerError;
  console.log("Soldes fictifs de 25 jours initialisés pour " + year + " et " + (year + 1) + ".");
  console.log("Référents de démonstration : Morgan Petit (RH), Lou Bernard (DRH).");
  console.log("Les soldes et la configuration déjà présents sont conservés.");
}

seed().catch((error) => { console.error(error.message); process.exitCode = 1; });
