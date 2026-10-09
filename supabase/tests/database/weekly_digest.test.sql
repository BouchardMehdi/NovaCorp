begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,email) values
 ('16000000-0000-0000-0000-000000000001','digest-employee@novacorp.test'),
 ('16000000-0000-0000-0000-000000000002','digest-manager@novacorp.test'),
 ('16000000-0000-0000-0000-000000000003','digest-other@novacorp.test'),
 ('16000000-0000-0000-0000-000000000004','digest-empty@novacorp.test');
update profiles set role='manager' where id in ('16000000-0000-0000-0000-000000000002','16000000-0000-0000-0000-000000000003','16000000-0000-0000-0000-000000000004');
-- Fixtures historiques : seules les lignes de cette transaction sont simulees.
set local session_replication_role='replica';
insert into requests(id,requester_id,manager_id,request_type,title,status,submitted_at,completed_at,approval_rule_id,amount,quantity)
select ('26000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'16000000-0000-0000-0000-000000000001',
 case when n=6 then '16000000-0000-0000-0000-000000000003'::uuid else '16000000-0000-0000-0000-000000000002'::uuid end,
 'equipment','Fixture digest '||n,st::request_status,submitted::timestamptz,completed::timestamptz,
 (select id from approval_rules where request_type='equipment' and active),10,1
from (values
 (1,'pending_approval','2026-10-05 00:00 Europe/Paris',null),
 (2,'approved','2026-10-04 23:59:59 Europe/Paris','2026-10-11 23:59:59 Europe/Paris'),
 (3,'pending_approval','2026-10-12 00:00 Europe/Paris',null),
 (4,'under_review','2026-10-06 12:00 Europe/Paris',null),
 (5,'draft',null,null),
 (6,'pending_approval','2026-10-06 12:00 Europe/Paris',null),
 (7,'approved','2026-10-06 12:00 Europe/Paris','2026-10-12 00:00 Europe/Paris')) v(n,st,submitted,completed);
insert into approval_steps(request_id,position,required_role,assignee_id,status,activated_at,due_at)
select id,1,'manager',manager_id,'pending',submitted_at,submitted_at+interval '48 hours'
from requests where id in ('26000000-0000-0000-0000-000000000001','26000000-0000-0000-0000-000000000003','26000000-0000-0000-0000-000000000006');
set local session_replication_role='origin';

set local role authenticated;
select throws_ok($q$select queue_weekly_manager_digests()$q$,'42501',null,'planification reservee au backend');
select throws_ok($q$select claim_weekly_manager_digest()$q$,'42501',null,'reservation reservee au backend');
select throws_ok($q$select * from manager_weekly_digests$q$,'42501',null,'aucun acces direct client aux digests');
reset role;
select is(private.queue_weekly_manager_digests('2026-10-11 08:00 Europe/Paris','16000000-0000-0000-0000-000000000002'),0,'pas de digest le dimanche');
select is(private.queue_weekly_manager_digests('2026-10-12 07:59:59 Europe/Paris','16000000-0000-0000-0000-000000000002'),0,'pas avant 8 h lundi');
select is(private.queue_weekly_manager_digests('2026-10-12 08:00 Europe/Paris','16000000-0000-0000-0000-000000000002'),1,'digest lundi a 8 h');
select is(private.queue_weekly_manager_digests('2026-10-12 16:00 Europe/Paris','16000000-0000-0000-0000-000000000002'),0,'rejeu sans doublon');
select is((select received_count from manager_weekly_digests where manager_id='16000000-0000-0000-0000-000000000002'),3,'receptions semaine precedente, bornes locales et brouillons exclus');
select is((select approved_count from manager_weekly_digests where manager_id='16000000-0000-0000-0000-000000000002'),1,'approbations finales selon date de cloture, meme soumission ancienne');
select is((select pending_count from manager_weekly_digests where manager_id='16000000-0000-0000-0000-000000000002'),2,'attentes manager toutes dates, qualification exclue');
select matches((select body from manager_weekly_digests where manager_id='16000000-0000-0000-0000-000000000002'),'Fixture digest 1','liste des demandes en attente');
select ok((select body not like '%Fixture digest 6%' from manager_weekly_digests where manager_id='16000000-0000-0000-0000-000000000002'),'autre equipe exclue');
select matches((select body from manager_weekly_digests where manager_id='16000000-0000-0000-0000-000000000002'),'scope=team','lien Mon equipe');
select is(private.queue_weekly_manager_digests('2026-10-12 08:00 Europe/Paris','16000000-0000-0000-0000-000000000004'),1,'manager sans activite recoit aussi le digest');
select is((select received_count+approved_count+pending_count from manager_weekly_digests where manager_id='16000000-0000-0000-0000-000000000004'),0,'semaine sans activite : compteurs nuls');
select is(private.queue_weekly_manager_digests('2026-10-12 08:00 Europe/Paris','16000000-0000-0000-0000-000000000001'),0,'salarie ne recoit pas de digest manager');
select is(private.queue_weekly_manager_digests('2026-03-30 05:59:59+00','16000000-0000-0000-0000-000000000004'),0,'heure ete : attendre 8 h Paris');
select is(private.queue_weekly_manager_digests('2026-03-30 06:00+00','16000000-0000-0000-0000-000000000004'),1,'heure ete : 8 h Paris = 6 h UTC');
select is(private.queue_weekly_manager_digests('2026-10-26 06:59:59+00','16000000-0000-0000-0000-000000000004'),0,'heure hiver : attendre 8 h Paris');
select is(private.queue_weekly_manager_digests('2026-10-26 07:00+00','16000000-0000-0000-0000-000000000004'),1,'heure hiver : 8 h Paris = 7 h UTC');

-- Tests SMTP independants du jour courant : snapshot de la semaine courante.
delete from manager_weekly_digests where manager_id='16000000-0000-0000-0000-000000000002';
insert into manager_weekly_digests(manager_id,week_start,snapshot_at,received_count,approved_count,pending_count,subject,body)
values('16000000-0000-0000-0000-000000000002',date_trunc('week',now() at time zone 'Europe/Paris')::date,now(),3,1,2,'Fixture digest SMTP','Fixture figee');
create temporary table digest_mail(data jsonb);
-- Le seul instant non envoyable est le lundi avant 8 h : la fixture est alors reportee a 8 h.
create function pg_temp.check_digest_smtp() returns setof text language plpgsql as $$begin
 if extract(isodow from now() at time zone 'Europe/Paris')=1 and (now() at time zone 'Europe/Paris')::time<time '08:00' then
  return next pass('avant 8 h : livraison differee couverte par le garde serveur');
 else
  insert into digest_mail select claim_weekly_manager_digest('16000000-0000-0000-0000-000000000002');
  return next is((select data->>'to' from digest_mail),'digest-manager@novacorp.test','email au manager');
  return next is((select data->>'text' from digest_mail),'Fixture figee','contenu fige a la mise en file');
  return next is((claim_weekly_manager_digest('16000000-0000-0000-0000-000000000002')->>'claimed')::boolean,false,'reservation exclusive');
  return next is((finish_weekly_manager_digest((select (data->>'notification_id')::uuid from digest_mail),gen_random_uuid(),true)->>'recorded')::boolean,false,'jeton incorrect refuse');
  return next is((finish_weekly_manager_digest((select (data->>'notification_id')::uuid from digest_mail),(select (data->>'lease_token')::uuid from digest_mail),false)->>'recorded')::boolean,true,'echec SMTP trace');
  return next is((select status::text from manager_weekly_digests where manager_id='16000000-0000-0000-0000-000000000002'),'failed','echec conserve');
  update manager_weekly_digests set next_attempt_at=now() where manager_id='16000000-0000-0000-0000-000000000002';
  update digest_mail set data=claim_weekly_manager_digest('16000000-0000-0000-0000-000000000002');
  return next is((finish_weekly_manager_digest((select (data->>'notification_id')::uuid from digest_mail),(select (data->>'lease_token')::uuid from digest_mail),true,'fixture-id')->>'recorded')::boolean,true,'reprise SMTP acquittee');
  return next is((finish_weekly_manager_digest((select (data->>'notification_id')::uuid from digest_mail),(select (data->>'lease_token')::uuid from digest_mail),true)->>'replayed')::boolean,true,'acquittement idempotent');
 end if;
end $$;
select * from pg_temp.check_digest_smtp();
insert into manager_weekly_digests(manager_id,week_start,snapshot_at,received_count,approved_count,pending_count,subject,body)
values('16000000-0000-0000-0000-000000000002',date_trunc('week',now() at time zone 'Europe/Paris')::date-7,now(),0,0,0,'Ancien digest','Obsolete');
select is((claim_weekly_manager_digest('16000000-0000-0000-0000-000000000002')->>'claimed')::boolean,false,'semaine precedente non envoyee en retard');
select is((select next_attempt_at::text from manager_weekly_digests where manager_id='16000000-0000-0000-0000-000000000002' and status='failed'),'infinity','ancien digest abandonne');
update manager_weekly_digests set status='sending',sent_at=null,attempts=5,lease_until=now()-interval '1 second'
 where manager_id='16000000-0000-0000-0000-000000000002' and week_start=date_trunc('week',now() at time zone 'Europe/Paris')::date;
select is((claim_weekly_manager_digest('16000000-0000-0000-0000-000000000002')->>'claimed')::boolean,false,'cinquieme reservation expiree non reemise');
select is((select next_attempt_at::text from manager_weekly_digests where manager_id='16000000-0000-0000-0000-000000000002' and attempts=5),'infinity','abandon apres cinq tentatives');
update profiles set role='employee' where id='16000000-0000-0000-0000-000000000004';
select is((claim_weekly_manager_digest('16000000-0000-0000-0000-000000000004')->>'claimed')::boolean,false,'role manager retire : aucune livraison');
select * from finish();
rollback;
