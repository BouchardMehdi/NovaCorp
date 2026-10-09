import { randomUUID } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { docker } from "./n8n-tools.mjs";
import { config, value, publicUrl } from "./ngrok-tools.mjs";

export function sql(source) {
  return docker(["exec", "-i", "supabase_db_NovaCorp", "psql", "-U", "supabase_admin", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-Atq"], source).trim();
}
export async function approveEndpoint(endpoint) {
  const current = (await publicUrl()) + "/webhook/novacorp-requests";
  if (endpoint !== current) throw new Error("L'URL autorisée doit correspondre exactement au tunnel configuré.");
  const source = await config();
  const lines = source.split(/\r?\n/).filter(line => line.trim() && !line.startsWith("N8N_APPROVED_WEBHOOK_URL="));
  await writeFile(".env.ngrok.local", lines.join("\n") + "\nN8N_APPROVED_WEBHOOK_URL=" + endpoint + "\n", { mode: 0o600 });
}
export async function connectWebhook() {
  const endpoint = (await publicUrl()) + "/webhook/novacorp-requests";
  if (value(await config(), "N8N_APPROVED_WEBHOOK_URL") !== endpoint) {
    disableWebhook();
    throw new Error("Cette URL n'a pas été autorisée. Le webhook Supabase reste désactivé ; demander l'accord pour cette destination.");
  }
  const token = value(await readFile(".env.n8n.local", "utf8"), "NOVACORP_REQUESTS_WEBHOOK_TOKEN");
  if (!/^[a-f0-9]{64}$/.test(token)) throw new Error("Installer d'abord le webhook avec npm run n8n:webhook:setup.");
  if (sql("select count(*) from pg_trigger where tgname='requests_webhook_insert' and tgrelid='public.requests'::regclass;") !== "1")
    throw new Error("Appliquer d'abord npm run db:migrate en local.");
  const delimiter = "$config_" + randomUUID().replaceAll("-", "") + "$";
  const payload = JSON.stringify({ n8n_requests_webhook_url: endpoint, n8n_requests_webhook_token: token });
  sql(`begin; set local statement_timeout='10s';
    create temporary table webhook_config(payload jsonb) on commit drop;
    insert into webhook_config values (${delimiter}${payload}${delimiter}::jsonb);
    do $configure$ declare item record; secret_id uuid;
    begin
      for item in select j.key,j.value from webhook_config c,jsonb_each_text(c.payload) j loop
        select id into secret_id from vault.secrets where name=item.key;
        if secret_id is null then perform vault.create_secret(item.value,item.key);
        else perform vault.update_secret(secret_id,item.value); end if;
      end loop;
    end $configure$; commit;`);
  return endpoint;
}
export function disableWebhook() {
  sql("do $disable$ declare secret_id uuid; begin select id into secret_id from vault.secrets where name='n8n_requests_webhook_url'; if secret_id is not null then perform vault.update_secret(secret_id,''); end if; end $disable$;");
}
