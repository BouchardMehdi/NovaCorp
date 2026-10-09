begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,email) values
 ('15000000-0000-0000-0000-000000000001','reminders-test@novacorp.test'),
 ('15000000-0000-0000-0000-000000000002','reminders-manager@novacorp.test'),
 ('15000000-0000-0000-0000-000000000003','reminders-rh@novacorp.test'),
 ('15000000-0000-0000-0000-000000000004','reminders-drh@novacorp.test');
update profiles set role='manager' where id='15000000-0000-0000-0000-000000000002';
update profiles set role='hr' where id='15000000-0000-0000-0000-000000000003';
update profiles set role='director' where id='15000000-0000-0000-0000-000000000004';
update profiles set manager_id='15000000-0000-0000-0000-000000000002' where id='15000000-0000-0000-0000-000000000001';
insert into hr_routing_settings(hr_referent_id,director_referent_id)
 values('15000000-0000-0000-0000-000000000003','15000000-0000-0000-0000-000000000004')
 on conflict(singleton) do update set hr_referent_id=excluded.hr_referent_id,director_referent_id=excluded.director_referent_id;

create temporary table reminder_mail(data jsonb); grant all on reminder_mail to service_role;
set local role authenticated;
set local request.jwt.claims='{"sub":"15000000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($q$select queue_due_hr_reminders()$q$,'42501',null,'supervision réservée au backend');
insert into requests(id,request_type,title,amount,quantity) values
 ('25000000-0000-0000-0000-000000000001','equipment','Échéances matériel',1501,1),
 ('25000000-0000-0000-0000-000000000002','equipment','Autre demande à isoler',1501,1);
select submit_hr_request(id) from requests where requester_id='15000000-0000-0000-0000-000000000001';
reset role; set local role service_role;
update requests set status='under_review' where requester_id='15000000-0000-0000-0000-000000000001';
select prepare_hr_approvals(id) from requests where requester_id='15000000-0000-0000-0000-000000000001';
insert into ai_reviews(request_id,provider,model,prompt_version,status,qualification,summary,finished_at)
select id,'test','fixture','test','succeeded','eligible','Fixture SQL échéances',now()
from requests where requester_id='15000000-0000-0000-0000-000000000001';
update requests set status='pending_approval' where requester_id='15000000-0000-0000-0000-000000000001';
update approval_steps set status='pending' where request_id in
 (select id from requests where requester_id='15000000-0000-0000-0000-000000000001') and position=1;
update notifications set status='sent',sent_at=now() where request_id in
 (select id from requests where requester_id='15000000-0000-0000-0000-000000000001');
-- Fixture : horodatages simulés dans cette seule session, restauration avant les RPC.
reset role; set local session_replication_role='replica';
update approval_steps set activated_at=now()-interval '23 hours 59 minutes 59 seconds',
 due_at=now()+interval '24 hours 1 second'
 where request_id='25000000-0000-0000-0000-000000000001' and position=1;
set local session_replication_role='origin'; set local role service_role;
select is(queue_due_hr_reminders('25000000-0000-0000-0000-000000000001'),0,'pas de relance avant 24 heures');
reset role; set local session_replication_role='replica';
update approval_steps set activated_at=now()-interval '24 hours',due_at=now()+interval '24 hours'
 where request_id='25000000-0000-0000-0000-000000000001' and position=1;
update approval_steps set activated_at=now()-interval '49 hours',due_at=now()-interval '1 hour'
 where request_id='25000000-0000-0000-0000-000000000002' and position=1;
set local session_replication_role='origin'; set local role service_role;
select is(queue_due_hr_reminders('25000000-0000-0000-0000-000000000001'),1,'relance à 24 heures exactement');
select is(queue_due_hr_reminders('25000000-0000-0000-0000-000000000001'),0,'relance dédupliquée');
select is((select count(*)::integer from notifications where request_id='25000000-0000-0000-0000-000000000002' and kind='overdue_alert'),0,'supervision ciblée ne touche pas une autre demande');
select is((select count(*)::integer from notifications where request_id='25000000-0000-0000-0000-000000000001' and kind='overdue_alert'),0,'pas d’alerte à 24 heures');
insert into reminder_mail select claim_hr_notification_email('25000000-0000-0000-0000-000000000001');
select is((select data->>'to' from reminder_mail),'reminders-manager@novacorp.test','relance au manager affecté');
select matches((select data->>'subject' from reminder_mail),'24 h','objet de relance');
select matches((select data->>'text' from reminder_mail),'décision humaine','relance sans décision automatique');
select is((claim_hr_notification_email('25000000-0000-0000-0000-000000000001')->>'claimed')::boolean,false,'relance réservée exclusivement');
select is((finish_hr_notification_email((select (data->>'notification_id')::uuid from reminder_mail),
 (select (data->>'lease_token')::uuid from reminder_mail),false)->>'recorded')::boolean,true,'échec SMTP relance tracé');
reset role; set local session_replication_role='replica';
update approval_steps set activated_at=now()-interval '47 hours 59 minutes 59 seconds',due_at=now()+interval '1 second'
 where request_id='25000000-0000-0000-0000-000000000001' and position=1;
set local session_replication_role='origin'; set local role service_role;
select is(queue_due_hr_reminders('25000000-0000-0000-0000-000000000001'),0,'pas d’alerte avant 48 heures');
reset role; set local session_replication_role='replica';
update approval_steps set activated_at=now()-interval '48 hours',due_at=now()
 where request_id='25000000-0000-0000-0000-000000000001' and position=1;
set local session_replication_role='origin'; set local role service_role;
update notifications set next_attempt_at=now() where request_id='25000000-0000-0000-0000-000000000001' and kind='reminder';
select is(queue_due_hr_reminders('25000000-0000-0000-0000-000000000001'),1,'alerte à 48 heures exactement');
select is(queue_due_hr_reminders('25000000-0000-0000-0000-000000000001'),0,'alerte dédupliquée');
update reminder_mail set data=claim_hr_notification_email('25000000-0000-0000-0000-000000000001');
select is((select data->>'to' from reminder_mail),'reminders-rh@novacorp.test','alerte au RH référent figé');
select matches((select data->>'subject' from reminder_mail),'48 h','alerte prioritaire sur une relance');
select matches((select data->>'text' from reminder_mail),'Aucune décision automatique','alerte sans décision');
select is((select status::text from requests where id='25000000-0000-0000-0000-000000000001'),'pending_approval','échéance ne finalise pas la demande');
select is((select status::text from approval_steps where request_id='25000000-0000-0000-0000-000000000001' and position=1),'pending','échéance ne décide pas pour le manager');
select is((finish_hr_notification_email((select (data->>'notification_id')::uuid from reminder_mail),
 (select (data->>'lease_token')::uuid from reminder_mail),true)->>'recorded')::boolean,true,'alerte acquittée');
select is((finish_hr_notification_email((select (data->>'notification_id')::uuid from reminder_mail),
 (select (data->>'lease_token')::uuid from reminder_mail),true)->>'replayed')::boolean,true,'alerte acquittée une seule fois');
select is((claim_hr_notification_email('25000000-0000-0000-0000-000000000001')->>'claimed')::boolean,false,'ancienne relance non envoyée après 48 heures');
select is((select next_attempt_at::text from notifications where request_id='25000000-0000-0000-0000-000000000001' and kind='reminder'),'infinity','relance dépassée abandonnée');
reset role; set local role authenticated;
set local request.jwt.claims='{"sub":"15000000-0000-0000-0000-000000000002","role":"authenticated"}';
select decide_hr_approval(id,true) from approval_steps where request_id='25000000-0000-0000-0000-000000000001' and position=1;
reset role; set local role service_role;
select advance_hr_approvals('reminders-manager','25000000-0000-0000-0000-000000000001');
update notifications set status='sent',sent_at=now() where request_id='25000000-0000-0000-0000-000000000001' and status='queued';
select is(queue_due_hr_reminders('25000000-0000-0000-0000-000000000001'),0,'délai repart de l’activation RH');
reset role; set local session_replication_role='replica';
update approval_steps set activated_at=now()-interval '24 hours',due_at=now()+interval '24 hours'
 where request_id='25000000-0000-0000-0000-000000000001' and position=2;
set local session_replication_role='origin'; set local role service_role;
select is(queue_due_hr_reminders('25000000-0000-0000-0000-000000000001'),1,'nouvelle relance pour étape RH');
update reminder_mail set data=claim_hr_notification_email('25000000-0000-0000-0000-000000000001');
select is((select data->>'to' from reminder_mail),'reminders-rh@novacorp.test','relance au RH validateur');
select finish_hr_notification_email((select (data->>'notification_id')::uuid from reminder_mail),
 (select (data->>'lease_token')::uuid from reminder_mail),true);
reset role; set local role authenticated;
set local request.jwt.claims='{"sub":"15000000-0000-0000-0000-000000000003","role":"authenticated"}';
select decide_hr_approval(id,true) from approval_steps where request_id='25000000-0000-0000-0000-000000000001' and position=2;
reset role; set local role service_role;
select advance_hr_approvals('reminders-rh','25000000-0000-0000-0000-000000000001');
update notifications set status='sent',sent_at=now() where request_id='25000000-0000-0000-0000-000000000001' and status='queued';
reset role; set local session_replication_role='replica';
update approval_steps set activated_at=now()-interval '49 hours',due_at=now()-interval '1 hour'
 where request_id='25000000-0000-0000-0000-000000000001' and position=3;
set local session_replication_role='origin'; set local role service_role;
select is(queue_due_hr_reminders('25000000-0000-0000-0000-000000000001'),1,'alerte directe si reprise après 48 heures');
select is((select count(*)::integer from notifications where request_id='25000000-0000-0000-0000-000000000001' and kind='reminder'),2,'pas de relance DRH périmée créée à 49 heures');
update reminder_mail set data=claim_hr_notification_email('25000000-0000-0000-0000-000000000001');
select is((select data->>'to' from reminder_mail),'reminders-rh@novacorp.test','retard DRH signalé aux RH');
select matches((select data->>'text' from reminder_mail),'DRH','étape en retard identifiée');
select finish_hr_notification_email((select (data->>'notification_id')::uuid from reminder_mail),
 (select (data->>'lease_token')::uuid from reminder_mail),false);
reset role; set local role authenticated;
set local request.jwt.claims='{"sub":"15000000-0000-0000-0000-000000000001","role":"authenticated"}';
select cancel_hr_request('25000000-0000-0000-0000-000000000001');
reset role; set local role service_role;
update notifications set next_attempt_at=now() where request_id='25000000-0000-0000-0000-000000000001' and kind='overdue_alert' and status='failed';
update notifications set status='sent',sent_at=now() where request_id='25000000-0000-0000-0000-000000000001' and kind='status_change' and status='queued';
select is(queue_due_hr_reminders('25000000-0000-0000-0000-000000000001'),0,'annulation exclue de supervision');
select is((claim_hr_notification_email('25000000-0000-0000-0000-000000000001')->>'claimed')::boolean,false,'alerte annulée non envoyée');
select * from finish();
rollback;
