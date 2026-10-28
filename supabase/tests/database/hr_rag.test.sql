begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
-- Transaction-local fixtures; other sessions never see this corpus replacement.
update hr_knowledge_documents set active=false;
insert into auth.users(id,email) values
 ('18000000-0000-0000-0000-000000000001','rag-employee@novacorp.test'),
 ('18000000-0000-0000-0000-000000000002','rag-manager@novacorp.test'),
 ('18000000-0000-0000-0000-000000000003','rag-hr@novacorp.test'),
 ('18000000-0000-0000-0000-000000000004','rag-director@novacorp.test');
update profiles set role='manager' where id='18000000-0000-0000-0000-000000000002';
update profiles set role='hr' where id='18000000-0000-0000-0000-000000000003';
update profiles set role='director' where id='18000000-0000-0000-0000-000000000004';
update profiles set manager_id='18000000-0000-0000-0000-000000000002' where id='18000000-0000-0000-0000-000000000001';
insert into hr_routing_settings(hr_referent_id,director_referent_id)
 values('18000000-0000-0000-0000-000000000003','18000000-0000-0000-0000-000000000004')
 on conflict(singleton) do update set hr_referent_id=excluded.hr_referent_id,director_referent_id=excluded.director_referent_id;
create temporary table rag_state(key text primary key,data jsonb);
grant all on rag_state to authenticated,service_role;
set local role service_role;
insert into rag_state values('import',import_hr_knowledge('rag-test','Matériel test','1',array['equipment'],'test.md',repeat('a',64),'[{"section":"Ecran","content":"Un écran professionnel nécessite une validation humaine du matériel."}]'));
select is((select (data->>'chunks')::integer from rag_state where key='import'),1,'document indexed');
select is((import_hr_knowledge('rag-test','Matériel test','1',array['equipment'],'test.md',repeat('a',64),'[{"section":"Ecran","content":"Un écran professionnel nécessite une validation humaine du matériel."}]')->>'replayed')::boolean,true,'same version idempotent');
select throws_ok($q$select import_hr_knowledge('rag-test','Matériel test','1',array['equipment'],'test.md',repeat('b',64),'[{"section":"Ecran","content":"Texte modifié"}]')$q$,'23514',null,'version immutable');
select is(jsonb_array_length(search_hr_knowledge('equipment','écrans professionnels')),1,'French search handles inflections and accents');
select is(jsonb_array_length(search_hr_knowledge('leave','écrans professionnels')),0,'type restriction prevents cross-category retrieval');
select throws_ok($q$select search_hr_knowledge('payroll','test')$q$,'23514',null,'unknown type denied');
select throws_ok($q$select import_hr_knowledge('invalid','Invalid','1',array['equipment'],'../../private',repeat('a',64),'[{"section":"X","content":"Y"}]')$q$,'23514',null,'absolute and relative file paths denied');
reset role;set local role anon;
select throws_ok($q$select search_hr_knowledge('equipment','écran')$q$,'42501',null,'anonymous search denied');
reset role;set local role authenticated;
set local request.jwt.claims='{"sub":"18000000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($q$select search_hr_knowledge('equipment','écran')$q$,'42501',null,'employee cannot query corpus');
select throws_ok($q$select * from hr_knowledge_chunks$q$,'42501',null,'raw corpus not exposed to clients');
select throws_ok($q$select import_hr_knowledge('fake','Fake','1',array['equipment'],'fake.md',repeat('f',64),'[{"section":"X","content":"Y"}]')$q$,'42501',null,'employee cannot poison corpus');
insert into requests(id,request_type,title,amount,quantity) values
 ('28000000-0000-0000-0000-000000000001','equipment','Ecran professionnel',100,1),
 ('28000000-0000-0000-0000-000000000002','equipment','Second écran',100,1);
select submit_hr_request(id) from requests where requester_id='18000000-0000-0000-0000-000000000001';
reset role;set local role service_role;
insert into rag_state values('claim',claim_hr_qualification('rag-first','test','fixture','28000000-0000-0000-0000-000000000001'));
select throws_ok($q$select retrieve_hr_knowledge((select (data->>'run_id')::uuid from rag_state where key='claim'),gen_random_uuid(),'écran')$q$,'23514',null,'retrieval requires current lease');
insert into rag_state values('retrieval',retrieve_hr_knowledge((select (data->>'run_id')::uuid from rag_state where key='claim'),(select (data->>'lease_token')::uuid from rag_state where key='claim'),'écran professionnel'));
select is((select prompt_version from ai_reviews where request_id='28000000-0000-0000-0000-000000000001'),'hr-qualification-v3-rag','real retrieval stamps prompt version');
select is((select data->'passages'->0->>'source_id' from rag_state where key='retrieval'),'rag-test@1#1','source reference stable');
select import_hr_knowledge('rag-test','Matériel test','2',array['equipment'],'test.md',repeat('b',64),'[{"section":"Nouvelle version","content":"Un écran professionnel : nouvelle politique de matériel, toujours humaine."}]');
select is(search_hr_knowledge('equipment','écran')->0->>'version','2','new document version replaces old search results');
select is((select count(*)::integer from hr_knowledge_documents where slug='rag-test' and active),1,'one active version per slug');
select is(retrieve_hr_knowledge((select (data->>'run_id')::uuid from rag_state where key='claim'),(select (data->>'lease_token')::uuid from rag_state where key='claim'),'different query'),(select data from rag_state where key='retrieval'),'execution keeps its original snapshot across imports');
select throws_ok($q$select complete_hr_qualification((select (data->>'run_id')::uuid from rag_state where key='claim'),(select (data->>'lease_token')::uuid from rag_state where key='claim'),'{"qualification":"eligible","summary":"Fixture","response_draft":"Attente"}')$q$,'23514',null,'RAG completion requires citations field');
select throws_ok($q$select complete_hr_qualification((select (data->>'run_id')::uuid from rag_state where key='claim'),(select (data->>'lease_token')::uuid from rag_state where key='claim'),'{"qualification":"eligible","summary":"Fixture","response_draft":"Attente","citations":["invented@1#1"]}')$q$,'23514',null,'invented citation rejected in database');
select complete_hr_qualification((select (data->>'run_id')::uuid from rag_state where key='claim'),(select (data->>'lease_token')::uuid from rag_state where key='claim'),'{"qualification":"eligible","summary":"Fixture sourcée","response_draft":"Attente humaine","citations":["rag-test@1#1"]}');
select is((select rag_context->'citations'->>0 from ai_reviews where request_id='28000000-0000-0000-0000-000000000001'),'rag-test@1#1','validated citations persisted');
select is((select rag_context->'passages'->0->>'version' from ai_reviews where request_id='28000000-0000-0000-0000-000000000001'),'1','original source version retained after update');
select is((select status::text from requests where id='28000000-0000-0000-0000-000000000001'),'pending_approval','RAG cannot approve request');
reset role;update hr_knowledge_documents set active=false;
set local role service_role;
insert into rag_state values('empty-claim',claim_hr_qualification('rag-empty','test','fixture','28000000-0000-0000-0000-000000000002'));
select retrieve_hr_knowledge((select (data->>'run_id')::uuid from rag_state where key='empty-claim'),(select (data->>'lease_token')::uuid from rag_state where key='empty-claim'),'écran');
select complete_hr_qualification((select (data->>'run_id')::uuid from rag_state where key='empty-claim'),(select (data->>'lease_token')::uuid from rag_state where key='empty-claim'),'{"qualification":"eligible","summary":"Sans source","response_draft":"Attente","citations":[]}');
select is((select qualification::text from ai_reviews where request_id='28000000-0000-0000-0000-000000000002'),'needs_review','empty corpus cannot produce eligible');
reset role;set local role authenticated;
set local request.jwt.claims='{"sub":"18000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select rag_context->'passages'->0->>'source_id' from ai_reviews where request_id='28000000-0000-0000-0000-000000000001'),'rag-test@1#1','assigned manager sees snapshot through existing review RLS');
set local request.jwt.claims='{"sub":"18000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is((select count(*)::integer from ai_reviews where request_id='28000000-0000-0000-0000-000000000001'),0,'requester cannot read protected AI review');
reset role;
select * from finish();
rollback;
