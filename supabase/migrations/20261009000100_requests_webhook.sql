-- TP : transport auxiliaire, limité aux métadonnées autorisées.
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

-- La file contient l'en-tête d'authentification : accès réservé au backend.
revoke all on net.http_request_queue, net._http_response from public, anon, authenticated;
-- Le worker pg_net local s'exécute avec le rôle backend postgres.
grant all on net.http_request_queue, net._http_response to postgres;

create function private.notify_request_insert() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare endpoint text; token text;
begin
  select decrypted_secret into endpoint from vault.decrypted_secrets
    where name = 'n8n_requests_webhook_url';
  select decrypted_secret into token from vault.decrypted_secrets
    where name = 'n8n_requests_webhook_token';
  if nullif(btrim(endpoint), '') is null or nullif(token, '') is null then return new; end if;
  perform net.http_post(
    url := endpoint,
    headers := jsonb_build_object('Content-Type', 'application/json', 'X-NovaCorp-Webhook-Token', token),
    body := jsonb_build_object('type', 'INSERT', 'schema', 'public', 'table', 'requests',
      'record', jsonb_build_object('id', new.id, 'status', new.status), 'old_record', null),
    timeout_milliseconds := 10000
  );
  return new;
exception when others then
  -- Préserver la sauvegarde ; ne pas journaliser de données RH ou de secret.
  raise warning 'Webhook requests non mis en file (SQLSTATE %).', sqlstate;
  return new;
end;
$$;
revoke all on function private.notify_request_insert() from public, anon, authenticated, service_role;

create trigger requests_webhook_insert
after insert on public.requests
for each row execute function private.notify_request_insert();
