begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();

select has_trigger('public','requests','requests_webhook_insert','Trigger présent sur requests');
select ok(not has_function_privilege('authenticated','private.notify_request_insert()','EXECUTE'),
  'La fonction du trigger est inaccessible au salarié');
select ok(not has_function_privilege('anon','private.notify_request_insert()','EXECUTE'),
  'La fonction du trigger est inaccessible anonymement');
select ok(not has_schema_privilege('authenticated','vault','USAGE'),'Vault reste privé');
select ok(not has_table_privilege('authenticated','net.http_request_queue','SELECT'),'La file et son token restent privés');
select ok(not has_table_privilege('anon','net.http_request_queue','SELECT'),'La file est inaccessible anonymement');
select ok(not has_table_privilege('authenticated','net._http_response','SELECT'),'Les réponses HTTP restent privées');
select ok(has_table_privilege('postgres','net.http_request_queue','DELETE'),'Le worker backend peut vider la file');
select ok(has_table_privilege('postgres','net._http_response','INSERT'),'Le worker backend peut enregistrer les réponses');

-- Transaction annulée : aucun envoi HTTP de test ne quitte PostgreSQL.
delete from vault.secrets where name in ('n8n_requests_webhook_url','n8n_requests_webhook_token');
insert into auth.users(id,email) values
 ('17000000-0000-4000-8000-000000000001','webhook-sql@novacorp.test');
insert into requests(id,requester_id,request_type,title,description,amount,quantity) values
 ('27000000-0000-4000-8000-000000000001','17000000-0000-4000-8000-000000000001',
  'equipment','Information privée','Motif à ne jamais exporter',120,1);
select is((select count(*) from net.http_request_queue where convert_from(body,'UTF8')::jsonb#>>'{record,id}'='27000000-0000-4000-8000-000000000001'),0::bigint,
  'Sans configuration, la sauvegarde fonctionne sans requête HTTP');

select vault.create_secret('https://example.invalid/webhook/novacorp-requests','n8n_requests_webhook_url');
insert into requests(id,requester_id,request_type,title) values
 ('27000000-0000-4000-8000-000000000002','17000000-0000-4000-8000-000000000001','equipment','Token absent');
select is((select count(*) from net.http_request_queue where convert_from(body,'UTF8')::jsonb#>>'{record,id}'='27000000-0000-4000-8000-000000000002'),0::bigint,
  'Sans token, aucun envoi');
select vault.create_secret('token-fictif-sql','n8n_requests_webhook_token');

set local role authenticated;
set local request.jwt.claims='{"sub":"17000000-0000-4000-8000-000000000001","role":"authenticated"}';
insert into requests(id,request_type,title,description,amount,quantity) values
 ('27000000-0000-4000-8000-000000000003','equipment','Titre privé','Motif privé',330,2);
reset role;

create temporary table webhook_test_payload as
select url,headers,convert_from(body,'UTF8')::jsonb as payload from net.http_request_queue
where convert_from(body,'UTF8')::jsonb#>>'{record,id}'='27000000-0000-4000-8000-000000000003';
select is((select count(*) from webhook_test_payload),1::bigint,'Une insertion produit une seule requête HTTP');
select is((select url from webhook_test_payload),'https://example.invalid/webhook/novacorp-requests','URL lue dans Vault');
select is((select headers->>'X-NovaCorp-Webhook-Token' from webhook_test_payload),'token-fictif-sql','Authentification lue dans Vault');
select is((select payload from webhook_test_payload),
 '{"type":"INSERT","schema":"public","table":"requests","record":{"id":"27000000-0000-4000-8000-000000000003","status":"draft"},"old_record":null}'::jsonb,
 'Payload strictement limité à événement, identifiant et statut');
select is((select status::text from requests where id='27000000-0000-4000-8000-000000000003'),'draft','Le webhook ne soumet pas le brouillon');
select is((select count(*) from approval_steps where request_id='27000000-0000-4000-8000-000000000003'),0::bigint,'Aucune validation créée');
select is((select count(*) from notifications where request_id='27000000-0000-4000-8000-000000000003'),0::bigint,'Aucun email créé');
select is((select count(*) from workflow_runs where request_id='27000000-0000-4000-8000-000000000003'),0::bigint,'Aucune qualification créée');

update requests set title='Brouillon modifié' where id='27000000-0000-4000-8000-000000000003';
select is((select count(*) from net.http_request_queue where convert_from(body,'UTF8')::jsonb#>>'{record,id}'='27000000-0000-4000-8000-000000000003'),1::bigint,
  'Une modification ne déclenche pas un second appel');
select vault.update_secret(id,'') from vault.secrets where name='n8n_requests_webhook_url';
insert into requests(id,requester_id,request_type,title) values
 ('27000000-0000-4000-8000-000000000004','17000000-0000-4000-8000-000000000001','equipment','Tunnel désactivé');
select is((select count(*) from net.http_request_queue where convert_from(body,'UTF8')::jsonb#>>'{record,id}'='27000000-0000-4000-8000-000000000004'),0::bigint,
  'URL désactivée : sauvegarde possible, aucun appel');
select * from finish();
rollback;
