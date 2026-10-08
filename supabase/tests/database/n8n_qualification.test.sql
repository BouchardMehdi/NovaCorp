begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,email) values
 ('13000000-0000-0000-0000-000000000001','qualification-test@novacorp.test'),
 ('13000000-0000-0000-0000-000000000002','qualification-manager@novacorp.test'),
 ('13000000-0000-0000-0000-000000000003','qualification-rh@novacorp.test'),
 ('13000000-0000-0000-0000-000000000004','qualification-drh@novacorp.test');
update profiles set role='manager' where id='13000000-0000-0000-0000-000000000002';
update profiles set role='hr' where id='13000000-0000-0000-0000-000000000003';
update profiles set role='director' where id='13000000-0000-0000-0000-000000000004';
update profiles set manager_id='13000000-0000-0000-0000-000000000002' where id='13000000-0000-0000-0000-000000000001';
insert into hr_routing_settings(hr_referent_id,director_referent_id)
 values('13000000-0000-0000-0000-000000000003','13000000-0000-0000-0000-000000000004')
 on conflict(singleton) do update set hr_referent_id=excluded.hr_referent_id,director_referent_id=excluded.director_referent_id;
create temporary table qualification_test_state(key text primary key,data jsonb);
grant all on qualification_test_state to authenticated,service_role;
set local role authenticated;
set local request.jwt.claims='{"sub":"13000000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($$select claim_hr_qualification('auth','ollama','qwen3:1.7b')$$,'42501',null,'qualification interdite au salarié');
select throws_ok($$select claim_hr_manager_email()$$,'42501',null,'réservation email interdite au salarié');
insert into requests(id,request_type,title,amount,quantity) values
 ('23000000-0000-0000-0000-000000000001','equipment','Matériel identique',1501,1),
 ('23000000-0000-0000-0000-000000000002','equipment','Matériel identique',1501,1),
 ('23000000-0000-0000-0000-000000000003','equipment','À annuler',80,1),
 ('23000000-0000-0000-0000-000000000004','equipment','À reprendre',90,1);
select submit_hr_request(id) from requests where requester_id='13000000-0000-0000-0000-000000000001';
reset role;
set local role service_role;
select throws_ok($$select claim_hr_qualification(null,'ollama','qwen3:1.7b')$$,'23514',null,'identifiant exécution obligatoire');
insert into qualification_test_state values('first',claim_hr_qualification('first','ollama','qwen3:1.7b','23000000-0000-0000-0000-000000000001'));
select is((select (data->>'claimed')::boolean from qualification_test_state where key='first'),true,'demande réservée');
select is((select status::text from requests where id='23000000-0000-0000-0000-000000000001'),'under_review','passage en analyse atomique');
select is((claim_hr_qualification('other','ollama','qwen3:1.7b','23000000-0000-0000-0000-000000000001')->>'claimed')::boolean,false,'deuxième qualification exclue');
select ok(not (select data->'request' ? 'requester_id' from qualification_test_state where key='first'),'identité du salarié exclue du prompt');
select is((select count(*)::integer from ai_reviews where request_id='23000000-0000-0000-0000-000000000001'),1,'une seule revue créée');
select is((complete_hr_qualification((select (data->>'run_id')::uuid from qualification_test_state where key='first'),gen_random_uuid(),
 '{"qualification":"eligible","summary":"Synthèse","response_draft":"En attente"}')->>'completed')::boolean,false,'jeton inconnu refusé');
select throws_ok($$select complete_hr_qualification(
 (select (data->>'run_id')::uuid from qualification_test_state where key='first'),
 (select (data->>'lease_token')::uuid from qualification_test_state where key='first'),
 '{"qualification":"approved","summary":"Faux","response_draft":""}')$$,'23514',null,'décision du modèle non acceptée');
select lives_ok($$select complete_hr_qualification(
 (select (data->>'run_id')::uuid from qualification_test_state where key='first'),
 (select (data->>'lease_token')::uuid from qualification_test_state where key='first'),
 '{"qualification":"eligible","summary":"Synthèse","response_draft":"Attente décision"}',12,20)$$,'qualification terminée');
select is((select qualification::text from ai_reviews where request_id='23000000-0000-0000-0000-000000000001'),'needs_review','doublon impose revue humaine malgré le modèle');
select is((select status::text from requests where id='23000000-0000-0000-0000-000000000001'),'pending_approval','jamais approuvée par IA');
select is((select count(*)::integer from approval_steps where request_id='23000000-0000-0000-0000-000000000001'),3,'DRH créé au seuil dépassé');
select is((select count(*)::integer from approval_steps where request_id='23000000-0000-0000-0000-000000000001' and status='pending'),1,'seul le manager activé');
select is((select count(*)::integer from notifications where request_id='23000000-0000-0000-0000-000000000001' and kind='approval_needed'),1,'notification manager unique');
select is((complete_hr_qualification((select (data->>'run_id')::uuid from qualification_test_state where key='first'),
 (select (data->>'lease_token')::uuid from qualification_test_state where key='first'),
 '{"qualification":"eligible","summary":"Autre synthèse","response_draft":""}')->>'replayed')::boolean,true,'fin de qualification rejouable');
select is((select input_tokens from ai_reviews where request_id='23000000-0000-0000-0000-000000000001'),12,'rejeu ne modifie pas les tokens');
select is((claim_hr_qualification('again','ollama','qwen3:1.7b','23000000-0000-0000-0000-000000000001')->>'claimed')::boolean,false,'demande qualifiée non reprise');
insert into qualification_test_state values('mail',claim_hr_manager_email('23000000-0000-0000-0000-000000000001'));
select is((select data->>'to' from qualification_test_state where key='mail'),'qualification-manager@novacorp.test','email du manager affecté');
select is((claim_hr_manager_email('23000000-0000-0000-0000-000000000001')->>'claimed')::boolean,false,'envoi concurrent exclu');
select is((finish_hr_manager_email((select (data->>'notification_id')::uuid from qualification_test_state where key='mail'),
 gen_random_uuid(),true)->>'recorded')::boolean,false,'acquittement avec mauvais jeton refusé');
select lives_ok($$select finish_hr_manager_email(
 (select (data->>'notification_id')::uuid from qualification_test_state where key='mail'),
 (select (data->>'lease_token')::uuid from qualification_test_state where key='mail'),true,'test-message')$$,'envoi confirmé');
select is((select status::text from notifications where id=(select (data->>'notification_id')::uuid from qualification_test_state where key='mail')),'sent','envoi tracé');
select is((claim_hr_manager_email('23000000-0000-0000-0000-000000000001')->>'claimed')::boolean,false,'message envoyé non repris');
insert into qualification_test_state values('cancel',claim_hr_qualification('cancel','ollama','qwen3:1.7b','23000000-0000-0000-0000-000000000003'));
reset role;
set local role authenticated;
select cancel_hr_request('23000000-0000-0000-0000-000000000003');
reset role;
set local role service_role;
select is(complete_hr_qualification((select (data->>'run_id')::uuid from qualification_test_state where key='cancel'),
 (select (data->>'lease_token')::uuid from qualification_test_state where key='cancel'),
 '{"qualification":"eligible","summary":"Synthèse","response_draft":""}')->>'reason','request_inactive','annulation pendant IA respectée');
select is((select count(*)::integer from approval_steps where request_id='23000000-0000-0000-0000-000000000003'),0,'aucune étape après annulation');
insert into qualification_test_state values('retry',claim_hr_qualification('retry','ollama','qwen3:1.7b','23000000-0000-0000-0000-000000000004'));
select lives_ok($$select fail_hr_qualification(
 (select (data->>'run_id')::uuid from qualification_test_state where key='retry'),
 (select (data->>'lease_token')::uuid from qualification_test_state where key='retry'),'llm_http_error')$$,'erreur du modèle tracée');
select is((select status::text from requests where id='23000000-0000-0000-0000-000000000004'),'under_review','erreur sans décision automatique');
select is((claim_hr_qualification('too-soon','ollama','qwen3:1.7b','23000000-0000-0000-0000-000000000004')->>'claimed')::boolean,false,'temporisation respectée');
update workflow_runs set retry_after=now() where request_id='23000000-0000-0000-0000-000000000004';
insert into qualification_test_state values('retry2',claim_hr_qualification('retry2','ollama','qwen3:1.7b','23000000-0000-0000-0000-000000000004'));
select is((select (data->>'attempt')::integer from qualification_test_state where key='retry2'),2,'reprise numérotée');
update workflow_runs set lease_until=now()-interval '1 second' where id=(select (data->>'run_id')::uuid from qualification_test_state where key='retry2');
insert into qualification_test_state values('retry3',claim_hr_qualification('retry3','ollama','qwen3:1.7b','23000000-0000-0000-0000-000000000004'));
select is((select (data->>'attempt')::integer from qualification_test_state where key='retry3'),3,'reprise après processus interrompu');
select is((complete_hr_qualification((select (data->>'run_id')::uuid from qualification_test_state where key='retry2'),
 (select (data->>'lease_token')::uuid from qualification_test_state where key='retry2'),
 '{"qualification":"eligible","summary":"Ancienne réponse","response_draft":""}')->>'completed')::boolean,false,'ancienne réponse écartée après reprise');
select fail_hr_qualification((select (data->>'run_id')::uuid from qualification_test_state where key='retry3'),
 (select (data->>'lease_token')::uuid from qualification_test_state where key='retry3'),'llm_invalid_response');
select is((claim_hr_qualification('retry4','ollama','qwen3:1.7b','23000000-0000-0000-0000-000000000004')->>'claimed')::boolean,false,'limite de trois tentatives');
select is((select count(*)::integer from approval_steps where request_id='23000000-0000-0000-0000-000000000004'),0,'erreurs ne créent pas de validation');
insert into qualification_test_state values('second',claim_hr_qualification('second','ollama','qwen3:1.7b','23000000-0000-0000-0000-000000000002'));
select complete_hr_qualification((select (data->>'run_id')::uuid from qualification_test_state where key='second'),
 (select (data->>'lease_token')::uuid from qualification_test_state where key='second'),
 '{"qualification":"eligible","summary":"Synthèse seconde demande","response_draft":""}');
insert into qualification_test_state values('mail-failure',claim_hr_manager_email('23000000-0000-0000-0000-000000000002'));
select finish_hr_manager_email((select (data->>'notification_id')::uuid from qualification_test_state where key='mail-failure'),
 (select (data->>'lease_token')::uuid from qualification_test_state where key='mail-failure'),false);
select is((select status::text from notifications where id=(select (data->>'notification_id')::uuid from qualification_test_state where key='mail-failure')),'failed','échec SMTP tracé');
select is((claim_hr_manager_email('23000000-0000-0000-0000-000000000002')->>'claimed')::boolean,false,'pas de reprise SMTP immédiate');
update notifications set next_attempt_at=now() where id=(select (data->>'notification_id')::uuid from qualification_test_state where key='mail-failure');
insert into qualification_test_state values('mail-retry',claim_hr_manager_email('23000000-0000-0000-0000-000000000002'));
select is((select attempts from notifications where id=(select (data->>'notification_id')::uuid from qualification_test_state where key='mail-retry')),2,'tentative SMTP numérotée');
select is((finish_hr_manager_email((select (data->>'notification_id')::uuid from qualification_test_state where key='mail-failure'),
 (select (data->>'lease_token')::uuid from qualification_test_state where key='mail-failure'),true)->>'recorded')::boolean,false,'ancien acquittement SMTP écarté');
update notifications set attempts=5,lease_until=now()-interval '1 second'
 where id=(select (data->>'notification_id')::uuid from qualification_test_state where key='mail-retry');
select is((claim_hr_manager_email('23000000-0000-0000-0000-000000000002')->>'claimed')::boolean,false,'pas de sixième tentative SMTP');
select is((select status::text from notifications where id=(select (data->>'notification_id')::uuid from qualification_test_state where key='mail-retry')),'failed','dernière réservation expirée signalée');
select ok((select next_attempt_at='infinity'::timestamptz from notifications where id=(select (data->>'notification_id')::uuid from qualification_test_state where key='mail-retry')),'intervention manuelle après cinq tentatives');
reset role;
set local role authenticated;
insert into requests(id,request_type,title,amount,quantity) values('23000000-0000-0000-0000-000000000005','equipment','Message à ignorer',10,1);
select submit_hr_request('23000000-0000-0000-0000-000000000005');
reset role;
set local role service_role;
insert into qualification_test_state values('obsolete',claim_hr_qualification('obsolete','ollama','qwen3:1.7b','23000000-0000-0000-0000-000000000005'));
select complete_hr_qualification((select (data->>'run_id')::uuid from qualification_test_state where key='obsolete'),
 (select (data->>'lease_token')::uuid from qualification_test_state where key='obsolete'),
 '{"qualification":"eligible","summary":"Synthèse","response_draft":""}');
reset role;
set local role authenticated;
select cancel_hr_request('23000000-0000-0000-0000-000000000005');
reset role;
set local role service_role;
select is((claim_hr_manager_email('23000000-0000-0000-0000-000000000005')->>'claimed')::boolean,false,'demande annulée ne déclenche pas un email manager');
select is((select status::text from notifications where request_id='23000000-0000-0000-0000-000000000005' and kind='approval_needed'),'failed','notification obsolète tracée');
select * from finish();
rollback;
