import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
const password = "NovaCorpDemo2026!";
const accounts = [
  { email: "manager@novacorp.test", first_name: "Alex", last_name: "Martin", role: "manager" },
  { email: "salarie@novacorp.test", first_name: "Camille", last_name: "Durand", role: "employee" },
  { email: "rh@novacorp.test", first_name: "Morgan", last_name: "Petit", role: "hr" },
  { email: "drh@novacorp.test", first_name: "Lou", last_name: "Bernard", role: "director" },
];

async function seed() {
  if (!url || !key) throw new Error("Exécutez npm run local:env avant de créer les comptes.");
  if (!["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname)) {
    throw new Error("La création de ces comptes fictifs est réservée à Supabase local.");
  }
  const supabase = createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });
  const existing = [];
  for (let page = 1; ; page++) {
    const { data, error } = await supabase.auth.admin.listUsers({ page, perPage: 100 });
    if (error) throw error;
    existing.push(...data.users);
    if (data.users.length < 100) break;
  }
  const ids = new Map();
  for (const account of accounts) {
    let user = existing.find((candidate) => candidate.email === account.email);
    if (!user) {
      const { data, error } = await supabase.auth.admin.createUser({
        email: account.email, password, email_confirm: true,
        user_metadata: { first_name: account.first_name, last_name: account.last_name },
      });
      if (error) throw error;
      user = data.user;
    }
    if (!user) throw new Error("Compte non créé : " + account.email);
    const { error } = await supabase.from("profiles").upsert({
      id: user.id, first_name: account.first_name, last_name: account.last_name, role: account.role,
    });
    if (error) throw error;
    ids.set(account.email, user.id);
    console.log("Compte fictif prêt : " + account.email);
  }
  const { error } = await supabase.from("profiles")
    .update({ manager_id: ids.get("manager@novacorp.test") })
    .eq("id", ids.get("salarie@novacorp.test"));
  if (error) throw error;
  console.log("Comptes locaux prêts. Mot de passe de démonstration indiqué dans le README.");
}

seed().catch((error) => { console.error(error.message); process.exitCode = 1; });
