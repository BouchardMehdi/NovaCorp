begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,email) values
 ('16000000-0000-0000-0000-000000000001','dashboard-test@novacorp.test'),
 ('16000000-0000-0000-0000-000000000002','dashboard-manager@novacorp.test'),
 ('16000000-0000-0000-0000-000000000003','dashboard-rh@novacorp.test'),
 ('16000000-0000-0000-0000-000000000004','dashboard-drh@novacorp.test');
update profiles set role='manager' where id='16000000-0000-0000-0000-000000000002';
update profiles set role='hr' where id='16000000-0000-0000-0000-000000000003';
update profiles set role='director' where id='16000000-0000-0000-0000-000000000004';
update profiles set manager_id='16000000-0000-0000-0000-000000000002' where id='16000000-0000-0000-0000-000000000001';
insert into hr_routing_settings(hr_referent_id,director_referent_id)
 values('16000000-0000-0000-0000-000000000003','16000000-0000-0000-0000-000000000004')
 on conflict(singleton) do update set hr_referent_id=excluded.hr_referent_id,director_referent_id=excluded.director_referent_id;

create temporary table dashboard_state(data jsonb); grant all on dashboard_state to authenticated;
set local role authenticated;
set local request.jwt.claims='{"sub":"16000000-0000-0000-0000-000000000001","role":"authenticated","user_metadata":{"role":"hr"}}';
select throws_ok($q$select get_hr_dashboard()$q$,'42501',null,'salarié refusé malgré métadonnées RH');
insert into requests(id,request_type,title,amount,quantity) values
 ('26000000-0000-0000-0000-000000000001','equipment','Validation en retard',1501,1),
 ('26000000-0000-0000-0000-000000000002','equipment','Erreur résolue',80,1),
 ('26000000-0000-0000-0000-000000000003','equipment','Erreur actuelle',90,1),
 ('26000000-0000-0000-0000-000000000004','equipment','Demande clôturée',90,1),
 ('26000000-0000-0000-0000-000000000005','equipment','Brouillon privé',90,1);
select submit_hr_request(id) from requests where requester_id='16000000-0000-0000-0000-000000000001'
 and id<>'26000000-0000-0000-0000-000000000005';
reset role; set local role service_role;
update requests set status='under_review' where requester_id='16000000-0000-0000-0000-000000000001' and status='submitted';
select prepare_hr_approvals('26000000-0000-0000-0000-000000000001');
insert into ai_reviews(request_id,provider,model,prompt_version,status,qualification,summary,finished_at)
 values('26000000-0000-0000-0000-000000000001','test','fixture','test','succeeded','eligible','Fixture',now());
update requests set status='pending_approval' where id='26000000-0000-0000-0000-000000000001';
update approval_steps set status='pending' where request_id='26000000-0000-0000-0000-000000000001' and position=1;
insert into workflow_runs(request_id,workflow_key,execution_id,status,started_at,finished_at,error_code,retry_after) values
 ('26000000-0000-0000-0000-000000000002','hr_qualification_v1','dashboard-resolved-fail','failed',now()-interval '2 hours',now()-interval '1 hour','llm_http_error',now()),
 ('26000000-0000-0000-0000-000000000002','hr_qualification_v1','dashboard-resolved-ok','succeeded',now()-interval '30 minutes',now(),null,null),
 ('26000000-0000-0000-0000-000000000003','hr_qualification_v1','dashboard-current-fail','failed',now()-interval '30 minutes',now(),'llm_http_error','infinity');
update notifications set status='failed',next_attempt_at=now()+interval '1 minute',last_error='Échec SMTP'
 where request_id='26000000-0000-0000-0000-000000000001' and kind='approval_needed';
reset role; set local session_replication_role='replica';
update approval_steps set activated_at=now()-interval '49 hours',due_at=now()-interval '1 hour'
 where request_id='26000000-0000-0000-0000-000000000001' and position=1;
update requests set status='approved',submitted_at=now()-interval '10 hours',completed_at=now()
 where id='26000000-0000-0000-0000-000000000004';
set local session_replication_role='origin';
set local role authenticated;
set local request.jwt.claims='{"sub":"16000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($q$select get_hr_dashboard()$q$,'42501',null,'manager refusé');
reset role; set local role anon;
select throws_ok($q$select get_hr_dashboard()$q$,'42501',null,'visiteur refusé');
reset role; set local role service_role;
select throws_ok($q$select get_hr_dashboard()$q$,'42501',null,'RPC réservée aux sessions utilisateur');
reset role; set local role authenticated;
set local request.jwt.claims='{"sub":"16000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($q$select get_hr_dashboard('inconnu')$q$,'23514',null,'type invalide refusé');
insert into dashboard_state select get_hr_dashboard();
select is((select (data->>'total')::integer from dashboard_state),(select count(*)::integer from requests where submitted_at is not null and status<>'draft'),'total exact hors brouillons');
select is((select (data->>'active')::integer from dashboard_state),(select count(*)::integer from requests where submitted_at is not null and status in ('submitted','under_review','pending_approval')),'compteur demandes actives exact');
select is((select (data->'by_type'->>'equipment')::integer from dashboard_state),(select count(*)::integer from requests where submitted_at is not null and request_type='equipment'),'répartition par type exacte');
select is((select (data->>'average_hours')::numeric from dashboard_state),(select round(avg(extract(epoch from(completed_at-submitted_at))/3600)::numeric,2) from requests where submitted_at is not null and status in ('approved','rejected')),'moyenne sur les seules décisions finales');
select ok(exists(select 1 from dashboard_state,jsonb_array_elements(data->'pending') p where p->>'request_id'='26000000-0000-0000-0000-000000000001' and (p->>'overdue')::boolean),'validation en retard identifiée');
select ok(not exists(select 1 from dashboard_state,jsonb_array_elements(data->'waiting') w where w->>'id'='26000000-0000-0000-0000-000000000005'),'brouillon privé absent');
select ok(not exists(select 1 from dashboard_state,jsonb_array_elements(data->'issues') i where i->>'request_id'='26000000-0000-0000-0000-000000000002'),'échec résolu absent des incidents');
select ok(exists(select 1 from dashboard_state,jsonb_array_elements(data->'issues') i where i->>'request_id'='26000000-0000-0000-0000-000000000003' and not (i->>'automatic_retry')::boolean),'échec épuisé demande une vérification manuelle');
select ok(exists(select 1 from dashboard_state,jsonb_array_elements(data->'issues') i where i->>'request_id'='26000000-0000-0000-0000-000000000001' and i->>'source'='email' and (i->>'automatic_retry')::boolean),'échec SMTP actif visible et reprise prévue');
select is((get_hr_dashboard('training')->>'total')::integer,(select count(*)::integer from requests where submitted_at is not null and request_type='training'),'filtre appliqué aux compteurs');
select ok(jsonb_array_length(get_hr_dashboard()->'pending')<=20,'détail borné à 20 validations');
reset role; set local role authenticated;
set local request.jwt.claims='{"sub":"16000000-0000-0000-0000-000000000004","role":"authenticated"}';
select lives_ok($q$select get_hr_dashboard()$q$,'DRH autorisée');
select * from finish();
rollback;
