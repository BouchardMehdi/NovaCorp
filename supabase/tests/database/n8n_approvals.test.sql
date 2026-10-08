begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,email) values
 ('14000000-0000-0000-0000-000000000001','approvals-test@novacorp.test'),
 ('14000000-0000-0000-0000-000000000002','approvals-manager@novacorp.test'),
 ('14000000-0000-0000-0000-000000000003','approvals-rh@novacorp.test'),
 ('14000000-0000-0000-0000-000000000004','approvals-drh@novacorp.test');
update profiles set role='manager' where id='14000000-0000-0000-0000-000000000002';
update profiles set role='hr' where id='14000000-0000-0000-0000-000000000003';
update profiles set role='director' where id='14000000-0000-0000-0000-000000000004';
update profiles set manager_id='14000000-0000-0000-0000-000000000002' where id='14000000-0000-0000-0000-000000000001';
insert into hr_routing_settings(hr_referent_id,director_referent_id)
 values('14000000-0000-0000-0000-000000000003','14000000-0000-0000-0000-000000000004')
 on conflict(singleton) do update set hr_referent_id=excluded.hr_referent_id,director_referent_id=excluded.director_referent_id;

insert into leave_balances(employee_id,year,allocated_days)
 values('14000000-0000-0000-0000-000000000001',2026,25);
create temporary table mail_state(data jsonb); grant all on mail_state to service_role;
set local role authenticated;
set local request.jwt.claims='{"sub":"14000000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($q$select advance_hr_approvals('forbidden')$q$,'42501',null,'avancement réservé backend');
select throws_ok($q$select claim_hr_notification_email()$q$,'42501',null,'emails réservés backend');
select throws_ok($q$select finish_hr_notification_email(gen_random_uuid(),gen_random_uuid(),true)$q$,'42501',null,'acquittement réservé backend');
insert into requests(id,request_type,title,amount,quantity) values
 ('24000000-0000-0000-0000-000000000001','equipment','Ordinateur',1501,1),
 ('24000000-0000-0000-0000-000000000004','equipment','Refus RH',1501,1),
 ('24000000-0000-0000-0000-000000000005','equipment','Refus DRH',1501,1),
 ('24000000-0000-0000-0000-000000000006','equipment','Annulation',80,1);
insert into requests(id,request_type,title,start_date,end_date) values
 ('24000000-0000-0000-0000-000000000002','leave','Congés acceptés','2026-11-02','2026-11-03'),
 ('24000000-0000-0000-0000-000000000003','leave','Congés refusés','2026-11-09','2026-11-10');
select submit_hr_request(id) from requests where requester_id='14000000-0000-0000-0000-000000000001';
reset role;
set local role service_role;
update requests set status='under_review' where requester_id='14000000-0000-0000-0000-000000000001';
select prepare_hr_approvals(id) from requests where requester_id='14000000-0000-0000-0000-000000000001';
insert into ai_reviews(request_id,provider,model,prompt_version,status,qualification,summary,finished_at)
select id,'test','fixture','test','succeeded','eligible','Contrôle fictif SQL',now() from requests
where requester_id='14000000-0000-0000-0000-000000000001';
update requests set status='pending_approval' where requester_id='14000000-0000-0000-0000-000000000001';
update approval_steps set status='pending' where request_id in
 (select id from requests where requester_id='14000000-0000-0000-0000-000000000001') and position=1;
select throws_ok($q$select advance_hr_approvals(null)$q$,'23514',null,'exécution obligatoire');
select is((advance_hr_approvals('early','24000000-0000-0000-0000-000000000001')->>'processed')::boolean,false,'attend décision humaine');
reset role;
set local role authenticated;
set local request.jwt.claims='{"sub":"14000000-0000-0000-0000-000000000002","role":"authenticated"}';
select decide_hr_approval(id,true) from approval_steps where request_id='24000000-0000-0000-0000-000000000001' and position=1;
reset role; set local role service_role;
select is(advance_hr_approvals('manager-ok','24000000-0000-0000-0000-000000000001')->>'action','activate_hr','activation RH après manager');
select is((advance_hr_approvals('manager-ok','24000000-0000-0000-0000-000000000001')->>'replayed')::boolean,true,'rejeu sans effet');
select is((select count(*)::integer from approval_steps where request_id='24000000-0000-0000-0000-000000000001' and status='pending'),1,'un seul validateur actif');
select is((select count(*)::integer from notifications where request_id='24000000-0000-0000-0000-000000000001' and kind='approval_needed'),2,'notification RH unique');
select ok((select due_at=activated_at+interval '48 hours' from approval_steps where request_id='24000000-0000-0000-0000-000000000001' and position=2),'48 heures dès activation RH');
-- Anciens événements de statut restent datés, les emails de validation obsolètes ne partent pas.
update notifications set status='sent',sent_at=now() where kind='status_change' and request_id='24000000-0000-0000-0000-000000000001';
insert into mail_state select claim_hr_notification_email('24000000-0000-0000-0000-000000000001');
select is((select data->>'to' from mail_state),'approvals-rh@novacorp.test','email au RH affecté');
select is((claim_hr_notification_email('24000000-0000-0000-0000-000000000001')->>'claimed')::boolean,false,'réservation email exclusive');
select is((finish_hr_notification_email((select (data->>'notification_id')::uuid from mail_state),gen_random_uuid(),true)->>'recorded')::boolean,false,'mauvais jeton refusé');
select is((finish_hr_notification_email((select (data->>'notification_id')::uuid from mail_state),(select (data->>'lease_token')::uuid from mail_state),false)->>'recorded')::boolean,true,'échec SMTP tracé');
select is((claim_hr_notification_email('24000000-0000-0000-0000-000000000001')->>'claimed')::boolean,false,'temporisation respectée');
update notifications set next_attempt_at=now() where id=(select (data->>'notification_id')::uuid from mail_state);
update mail_state set data=claim_hr_notification_email('24000000-0000-0000-0000-000000000001');
select is((finish_hr_notification_email((select (data->>'notification_id')::uuid from mail_state),(select (data->>'lease_token')::uuid from mail_state),true)->>'recorded')::boolean,true,'SMTP confirmé');
select is((finish_hr_notification_email((select (data->>'notification_id')::uuid from mail_state),(select (data->>'lease_token')::uuid from mail_state),true)->>'replayed')::boolean,true,'acquittement rejouable');
reset role; set local role authenticated;
set local request.jwt.claims='{"sub":"14000000-0000-0000-0000-000000000003","role":"authenticated"}';
select decide_hr_approval(id,true) from approval_steps where request_id='24000000-0000-0000-0000-000000000001' and position=2;
reset role; set local role service_role;
select is(advance_hr_approvals('rh-ok','24000000-0000-0000-0000-000000000001')->>'action','activate_director','DRH activé au-dessus du seuil');
select is((select status::text from requests where id='24000000-0000-0000-0000-000000000001'),'pending_approval','pas de décision avant DRH');
reset role; set local role authenticated;
set local request.jwt.claims='{"sub":"14000000-0000-0000-0000-000000000004","role":"authenticated"}';
select decide_hr_approval(id,true) from approval_steps where request_id='24000000-0000-0000-0000-000000000001' and position=3;
reset role; set local role service_role;
select is(advance_hr_approvals('drh-ok','24000000-0000-0000-0000-000000000001')->>'action','approved','demande finalisée après DRH');
select is((advance_hr_approvals('repeat-final','24000000-0000-0000-0000-000000000001')->>'processed')::boolean,false,'finalisation unique');
reset role; set local role authenticated;
set local request.jwt.claims='{"sub":"14000000-0000-0000-0000-000000000002","role":"authenticated"}';
select decide_hr_approval(id,true) from approval_steps where request_id='24000000-0000-0000-0000-000000000002' and position=1;
select decide_hr_approval(id,false,'Dates refusées') from approval_steps where request_id='24000000-0000-0000-0000-000000000003' and position=1;
reset role; set local role service_role;
select is(advance_hr_approvals('leave-mgr','24000000-0000-0000-0000-000000000002')->>'action','activate_hr','congés courts passent aux RH');
select is(advance_hr_approvals('leave-no','24000000-0000-0000-0000-000000000003')->>'action','rejected','refus humain finalisé');
select is((select reserved_days from leave_balances where employee_id='14000000-0000-0000-0000-000000000001'),2::numeric,'refus libère ses réservations');
select is((select status::text from approval_steps where request_id='24000000-0000-0000-0000-000000000003' and position=2),'waiting','RH non activé après refus');
reset role; set local role authenticated;
set local request.jwt.claims='{"sub":"14000000-0000-0000-0000-000000000003","role":"authenticated"}';
select decide_hr_approval(id,true) from approval_steps where request_id='24000000-0000-0000-0000-000000000002' and position=2;
reset role; set local role service_role;
select is(advance_hr_approvals('leave-rh','24000000-0000-0000-0000-000000000002')->>'action','approved','congés courts finalisés sans DRH');
select is((select consumed_days from leave_balances where employee_id='14000000-0000-0000-0000-000000000001'),2::numeric,'congés approuvés consommés');
select is((select reserved_days from leave_balances where employee_id='14000000-0000-0000-0000-000000000001'),0::numeric,'réservations soldées');
-- Événement final sélectionné pour tester le contenu réellement envoyé au salarié.
update notifications set status='sent',sent_at=now() where request_id='24000000-0000-0000-0000-000000000002'
 and (kind<>'status_change' or event_id not in (select id from request_events where request_id='24000000-0000-0000-0000-000000000002' and new_status='approved'));
update mail_state set data=claim_hr_notification_email('24000000-0000-0000-0000-000000000002');
select is((select data->>'to' from mail_state),'approvals-test@novacorp.test','statut envoyé au salarié');
select matches((select data->>'subject' from mail_state),'Acceptée','objet du statut final');
select matches((select data->>'text' from mail_state),'heure de Paris','événement horodaté');
select matches((select data->>'text' from mail_state),'état actuel','historique distingué du statut actuel');

reset role; set local role authenticated;
set local request.jwt.claims='{"sub":"14000000-0000-0000-0000-000000000001","role":"authenticated"}';
select cancel_hr_request('24000000-0000-0000-0000-000000000006');
reset role; set local role service_role;
select is((advance_hr_approvals('cancel','24000000-0000-0000-0000-000000000006')->>'processed')::boolean,false,'annulation respectée');
update notifications set status='sent',sent_at=now() where request_id='24000000-0000-0000-0000-000000000006' and kind='status_change';
select is((claim_hr_notification_email('24000000-0000-0000-0000-000000000006')->>'claimed')::boolean,false,'validation annulée non envoyée');
reset role; set local role authenticated;
set local request.jwt.claims='{"sub":"14000000-0000-0000-0000-000000000002","role":"authenticated"}';
select decide_hr_approval(id,true) from approval_steps where request_id in
 ('24000000-0000-0000-0000-000000000004','24000000-0000-0000-0000-000000000005') and position=1;
reset role; set local role service_role;
select advance_hr_approvals('refusal-hr','24000000-0000-0000-0000-000000000004');
select advance_hr_approvals('refusal-director','24000000-0000-0000-0000-000000000005');
reset role; set local role authenticated;
set local request.jwt.claims='{"sub":"14000000-0000-0000-0000-000000000003","role":"authenticated"}';
select decide_hr_approval(id,false,'Refus RH') from approval_steps where request_id='24000000-0000-0000-0000-000000000004' and position=2;
select decide_hr_approval(id,true) from approval_steps where request_id='24000000-0000-0000-0000-000000000005' and position=2;
reset role; set local role service_role;
select is(advance_hr_approvals('rh-no','24000000-0000-0000-0000-000000000004')->>'action','rejected','refus RH finalisé');
select is((select status::text from approval_steps where request_id='24000000-0000-0000-0000-000000000004' and position=3),'waiting','DRH non activé après refus RH');
select advance_hr_approvals('director-pending','24000000-0000-0000-0000-000000000005');
reset role; set local role authenticated;
set local request.jwt.claims='{"sub":"14000000-0000-0000-0000-000000000004","role":"authenticated"}';
select decide_hr_approval(id,false,'Refus DRH') from approval_steps where request_id='24000000-0000-0000-0000-000000000005' and position=3;
reset role; set local role service_role;
select is(advance_hr_approvals('director-no','24000000-0000-0000-0000-000000000005')->>'action','rejected','refus DRH finalisé');
select is((select count(*)::integer from workflow_runs where workflow_key='hr_approvals_v1' and request_id='24000000-0000-0000-0000-000000000004'),2,'trace activation puis refus RH');
select * from finish();
rollback;
