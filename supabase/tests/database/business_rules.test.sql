begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select no_plan();
insert into auth.users(id,email) values
 ('11000000-0000-0000-0000-000000000001','regles-salarie@novacorp.test'),
 ('11000000-0000-0000-0000-000000000002','regles-manager@novacorp.test'),
 ('11000000-0000-0000-0000-000000000003','regles-rh@novacorp.test'),
 ('11000000-0000-0000-0000-000000000004','regles-drh@novacorp.test'),
 ('11000000-0000-0000-0000-000000000005','regles-rh-suppleant@novacorp.test'),
 ('11000000-0000-0000-0000-000000000006','regles-drh-suppleant@novacorp.test');
update profiles set role='manager' where id='11000000-0000-0000-0000-000000000002';
update profiles set role='hr' where id in ('11000000-0000-0000-0000-000000000003','11000000-0000-0000-0000-000000000005');
update profiles set role='director' where id in ('11000000-0000-0000-0000-000000000004','11000000-0000-0000-0000-000000000006');
update profiles set manager_id='11000000-0000-0000-0000-000000000002' where id in
 ('11000000-0000-0000-0000-000000000001','11000000-0000-0000-0000-000000000003','11000000-0000-0000-0000-000000000004');
insert into hr_routing_settings(singleton,hr_referent_id,director_referent_id,alternate_hr_id,alternate_director_id)
 values(true,'11000000-0000-0000-0000-000000000003','11000000-0000-0000-0000-000000000004',
 '11000000-0000-0000-0000-000000000005','11000000-0000-0000-0000-000000000006')
 on conflict(singleton) do update set hr_referent_id=excluded.hr_referent_id,director_referent_id=excluded.director_referent_id,
 alternate_hr_id=excluded.alternate_hr_id,alternate_director_id=excluded.alternate_director_id;
insert into leave_balances(employee_id,year,allocated_days) values
 ('11000000-0000-0000-0000-000000000001',2026,25),('11000000-0000-0000-0000-000000000001',2027,25);

select is((select director_days_above from approval_rules where request_type='leave' and active),10::numeric,'seuil congés validé : 10 jours');
select is((select director_amount_above from approval_rules where request_type='equipment' and active),1000::numeric,'seuil matériel validé : 1000 EUR');
select is((select director_amount_above from approval_rules where request_type='training' and active),1500::numeric,'seuil formation validé : 1500 EUR');
select ok(not exists(select 1 from approval_rules where active and (decision_hours<>48 or reminder_hours<>24)),'48 h de décision et 24 h de relance');
select ok((select director_days_above is null and director_amount_above is null from approval_rules where request_type='remote_work' and active),'télétravail sans DRH');
select is(calculate_leave_days('2026-10-09','2026-10-12'),2::numeric,'week-end exclu');
select is(calculate_leave_days('2027-01-01','2027-01-01'),1::numeric,'jour férié compté selon calendrier de démonstration');
select is(calculate_leave_days('2026-11-02','2026-11-02',false,true),0.5::numeric,'demi-journée du matin');
select is(calculate_leave_days('2026-11-02','2026-11-03',true,true),1::numeric,'deux demi-journées sur les bornes');
select throws_ok($$select calculate_leave_days('2026-11-07','2026-11-08')$$,'23514',null,'week-end seul interdit');
select throws_ok($$select calculate_leave_days('2026-11-02','2026-11-02',true,true)$$,'23514',null,'période vide interdite');
select throws_ok($$select calculate_leave_days('2026-11-07','2026-11-09',true,false)$$,'23514',null,'demi-journée de week-end interdite');
select throws_ok($$select calculate_leave_days('1999-01-01','2026-01-01')$$,'23514',null,'calcul borné aux années des soldes');
select throws_ok($$update hr_routing_settings set hr_referent_id='11000000-0000-0000-0000-000000000002'$$,'23514',null,'référent RH doit être RH');

set local role authenticated;
set local request.jwt.claims='{"sub":"11000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is(calculate_leave_days('2026-11-02','2026-11-02',true,false),0.5::numeric,'calcul accessible au salarié');
select throws_ok($$select prepare_hr_approvals('21000000-0000-0000-0000-000000000001')$$,'42501',null,'préparation réservée au backend');
select throws_ok($$select queue_hr_approval_reminders()$$,'42501',null,'supervision réservée au backend');
insert into requests(id,request_type,title,start_date,end_date,requested_days) values
 ('21000000-0000-0000-0000-000000000001','leave','Réservation de trois jours','2026-11-02','2026-11-04',99),
 ('21000000-0000-0000-0000-000000000002','leave','Chevauchement de congés','2026-11-03','2026-11-05',3),
 ('21000000-0000-0000-0000-000000000003','remote_work','Chevauchement télétravail','2026-11-03','2026-11-04',null),
 ('21000000-0000-0000-0000-000000000004','leave','Solde insuffisant','2026-06-01','2026-07-31',45),
 ('21000000-0000-0000-0000-000000000005','leave','Année sans solde','2027-12-30','2028-01-03',3);
select lives_ok($$select submit_hr_request('21000000-0000-0000-0000-000000000001')$$,'soumission réserve le solde');
select is((select requested_days from requests where id='21000000-0000-0000-0000-000000000001'),3::numeric,'nombre de jours fourni par client remplacé par calcul');
select is((select reserved_days from leave_balances where employee_id=auth.uid() and year=2026),3::numeric,'trois jours réservés');
select is((select available_days from leave_balances where employee_id=auth.uid() and year=2026),22::numeric,'disponible tient compte de la réservation');
select throws_ok($$select submit_hr_request('21000000-0000-0000-0000-000000000002')$$,'23514',null,'congés superposés bloqués');
select throws_ok($$select submit_hr_request('21000000-0000-0000-0000-000000000003')$$,'23514',null,'télétravail superposé aux congés bloqué');
select throws_ok($$select submit_hr_request('21000000-0000-0000-0000-000000000004')$$,'23514',null,'solde insuffisant bloqué');
select throws_ok($$select submit_hr_request('21000000-0000-0000-0000-000000000005')$$,'23514',null,'année manquante bloque toute la réservation');
select is((select reserved_days from leave_balances where employee_id=auth.uid() and year=2027),0::numeric,'réservation de la première année annulée si seconde échoue');
select is((select count(*)::integer from leave_allocations where request_id='21000000-0000-0000-0000-000000000005'),0,'aucune allocation partielle après échec');
select cancel_hr_request('21000000-0000-0000-0000-000000000001');
select is((select available_days from leave_balances where employee_id=auth.uid() and year=2026),25::numeric,'annulation libère les trois jours');
select is((select state from leave_allocations where request_id='21000000-0000-0000-0000-000000000001'),'released','allocation libérée et conservée pour traçabilité');
select throws_ok($$insert into leave_allocations(request_id,balance_id,days) select
 '21000000-0000-0000-0000-000000000001',id,20 from leave_balances limit 1$$,'42501',null,'salarié ne falsifie pas les réservations');

insert into requests(id,request_type,title,start_date,end_date,start_half_day,end_half_day) values
 ('21000000-0000-0000-0000-000000000006','leave','Matin','2026-11-09','2026-11-09',false,true),
 ('21000000-0000-0000-0000-000000000007','leave','Après-midi','2026-11-09','2026-11-09',true,false),
 ('21000000-0000-0000-0000-000000000008','leave','Journée complète','2026-11-09','2026-11-09',false,false),
 ('21000000-0000-0000-0000-000000000009','leave','Sur deux années','2026-12-31','2027-01-04',true,true);
select lives_ok($$select submit_hr_request('21000000-0000-0000-0000-000000000006')$$,'demi-journée matin réservée');
select lives_ok($$select submit_hr_request('21000000-0000-0000-0000-000000000007')$$,'après-midi distinct du matin accepté');
select is((select reserved_days from leave_balances where employee_id=auth.uid() and year=2026),1::numeric,'deux demi-journées valent un jour');
select throws_ok($$select submit_hr_request('21000000-0000-0000-0000-000000000008')$$,'23514',null,'journée pleine chevauche les demi-journées');
select cancel_hr_request('21000000-0000-0000-0000-000000000006');
select cancel_hr_request('21000000-0000-0000-0000-000000000007');
select lives_ok($$select submit_hr_request('21000000-0000-0000-0000-000000000009')$$,'demande multi-années soumise atomiquement');
select is((select reserved_days from leave_balances where employee_id=auth.uid() and year=2026),0.5::numeric,'réservation 2026 correcte');
select is((select reserved_days from leave_balances where employee_id=auth.uid() and year=2027),1.5::numeric,'réservation 2027 correcte');
select is((select hr_referent_id::text from requests where id='21000000-0000-0000-0000-000000000009'),
 '11000000-0000-0000-0000-000000000003','référent RH capturé');
reset role;
set local request.jwt.claims='{}';
set local role service_role;
select is((get_hr_request_checks('21000000-0000-0000-0000-000000000009')->>'sufficient_leave_balance')::boolean,true,'contrôle ne déduit pas deux fois sa propre réservation');
select is((get_hr_request_checks('21000000-0000-0000-0000-000000000004')->'blocking_issues') ? 'insufficient_leave_balance',true,'contrôle déterministe signale solde insuffisant');
select transition_hr_request('21000000-0000-0000-0000-000000000009','under_review');
select lives_ok($$select prepare_hr_approvals('21000000-0000-0000-0000-000000000009')$$,'préparation du circuit depuis référents capturés');
select lives_ok($$select prepare_hr_approvals('21000000-0000-0000-0000-000000000009')$$,'préparation rejouable');
select is((select count(*)::integer from approval_steps where request_id='21000000-0000-0000-0000-000000000009'),2,'préparation ne duplique pas les étapes');
insert into ai_reviews(request_id,provider,model,prompt_version,status,qualification,summary,finished_at)
 values('21000000-0000-0000-0000-000000000009','test','fictif','v1','succeeded','eligible','Synthèse de test',now());
select transition_hr_request('21000000-0000-0000-0000-000000000009','pending_approval');
update approval_steps set status='pending' where request_id='21000000-0000-0000-0000-000000000009' and position=1;
select is((select extract(epoch from due_at-activated_at)/3600 from approval_steps
 where request_id='21000000-0000-0000-0000-000000000009' and position=1),48::numeric,'échéance exactement 48 heures');
select queue_hr_approval_reminders((select activated_at+interval '23 hours' from approval_steps where request_id='21000000-0000-0000-0000-000000000009' and position=1));
select is((select count(*)::integer from notifications where request_id='21000000-0000-0000-0000-000000000009' and kind='reminder'),0,'pas de relance avant 24 heures');
select queue_hr_approval_reminders((select activated_at+interval '24 hours' from approval_steps where request_id='21000000-0000-0000-0000-000000000009' and position=1));
select queue_hr_approval_reminders((select activated_at+interval '24 hours' from approval_steps where request_id='21000000-0000-0000-0000-000000000009' and position=1));
select is((select count(*)::integer from notifications where request_id='21000000-0000-0000-0000-000000000009' and kind='reminder'),0,'ancienne relance a 24 heures supprimee');
select queue_hr_approval_reminders((select due_at from approval_steps where request_id='21000000-0000-0000-0000-000000000009' and position=1));
select queue_hr_approval_reminders((select due_at+interval '1 hour' from approval_steps where request_id='21000000-0000-0000-0000-000000000009' and position=1));
select is((select count(*)::integer from notifications where request_id='21000000-0000-0000-0000-000000000009' and kind='overdue_alert'),1,'alerte RH à 48 heures dédupliquée');
select is((select recipient_id::text from notifications where request_id='21000000-0000-0000-0000-000000000009' and kind='overdue_alert'),
 '11000000-0000-0000-0000-000000000003','alerte destinée au RH référent');
select is((select status::text from approval_steps where request_id='21000000-0000-0000-0000-000000000009' and position=1),'pending','retard sans décision automatique');
select throws_ok($$insert into notifications(request_id,recipient_id,approval_step_id,kind,deduplication_key) select
 request_id,assignee_id,id,'overdue_alert','destinataire-invalide' from approval_steps
 where request_id='21000000-0000-0000-0000-000000000009' and position=1$$,'23514',null,'alerte de retard avec mauvais destinataire refusée');
reset role;
set local role authenticated;
set local request.jwt.claims='{"sub":"11000000-0000-0000-0000-000000000002","role":"authenticated"}';
select decide_hr_approval((select id from approval_steps where request_id='21000000-0000-0000-0000-000000000009' and position=1),true,null);
reset role;
set local request.jwt.claims='{}';
set local role service_role;
update approval_steps set status='pending' where request_id='21000000-0000-0000-0000-000000000009' and position=2;
reset role;
set local role authenticated;
set local request.jwt.claims='{"sub":"11000000-0000-0000-0000-000000000003","role":"authenticated"}';
select decide_hr_approval((select id from approval_steps where request_id='21000000-0000-0000-0000-000000000009' and position=2),true,null);
reset role;
set local request.jwt.claims='{}';
set local role service_role;
select lives_ok($$select transition_hr_request('21000000-0000-0000-0000-000000000009','approved')$$,'approbation consomme les jours');
select lives_ok($$select transition_hr_request('21000000-0000-0000-0000-000000000009','approved')$$,'répétition de finalisation sans double consommation');
select is((select consumed_days from leave_balances where employee_id='11000000-0000-0000-0000-000000000001' and year=2026),0.5::numeric,'2026 consommé une seule fois');
select is((select consumed_days from leave_balances where employee_id='11000000-0000-0000-0000-000000000001' and year=2027),1.5::numeric,'2027 consommé une seule fois');
select ok(not exists(select 1 from leave_allocations where request_id='21000000-0000-0000-0000-000000000009' and state<>'consumed'),'allocations marquées consommées');
select queue_hr_approval_reminders(now()+interval '10 days');
select is((select count(*)::integer from notifications where request_id='21000000-0000-0000-0000-000000000009' and kind in ('reminder','overdue_alert')),1,'pas de relance supplémentaire après clôture');
reset role;

set local role authenticated;
set local request.jwt.claims='{"sub":"11000000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into requests(id,request_type,title,start_date,end_date) values
 ('21000000-0000-0000-0000-000000000010','leave','Refus avec libération','2026-11-16','2026-11-17');
select submit_hr_request('21000000-0000-0000-0000-000000000010');
reset role;
set local request.jwt.claims='{}';
set local role service_role;
select transition_hr_request('21000000-0000-0000-0000-000000000010','under_review');
select prepare_hr_approvals('21000000-0000-0000-0000-000000000010');
insert into ai_reviews(request_id,provider,model,prompt_version,status,qualification,summary,finished_at)
 values('21000000-0000-0000-0000-000000000010','test','fictif','v1','succeeded','needs_review','Synthèse de test',now());
select transition_hr_request('21000000-0000-0000-0000-000000000010','pending_approval');
update approval_steps set status='pending' where request_id='21000000-0000-0000-0000-000000000010' and position=1;
reset role;
set local role authenticated;
set local request.jwt.claims='{"sub":"11000000-0000-0000-0000-000000000002","role":"authenticated"}';
select decide_hr_approval((select id from approval_steps where request_id='21000000-0000-0000-0000-000000000010' and position=1),false,'Refus fictif');
reset role;
set local request.jwt.claims='{}';
set local role service_role;
select transition_hr_request('21000000-0000-0000-0000-000000000010','rejected');
select is((select reserved_days from leave_balances where employee_id='11000000-0000-0000-0000-000000000001' and year=2026),0::numeric,'refus libère la réservation');
select is((select consumed_days from leave_balances where employee_id='11000000-0000-0000-0000-000000000001' and year=2026),0.5::numeric,'refus ne consomme aucun jour');
reset role;

set local role authenticated;
set local request.jwt.claims='{"sub":"11000000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into requests(id,request_type,title,amount,quantity) values
 ('21000000-0000-0000-0000-000000000011','equipment','Matériel identique',1000,1),
 ('21000000-0000-0000-0000-000000000012','equipment','Matériel identique',1000,1),
 ('21000000-0000-0000-0000-000000000013','equipment','Matériel au-dessus du seuil',1000.01,1);
select submit_hr_request('21000000-0000-0000-0000-000000000011');
select submit_hr_request('21000000-0000-0000-0000-000000000012');
select submit_hr_request('21000000-0000-0000-0000-000000000013');
select ok((select director_referent_id is null from requests where id='21000000-0000-0000-0000-000000000011'),'1000 EUR exact : pas de DRH');
select ok((select director_referent_id is not null from requests where id='21000000-0000-0000-0000-000000000013'),'1000.01 EUR : DRH requis');
insert into requests(id,request_type,title,start_date,end_date,amount) values
 ('21000000-0000-0000-0000-000000000014','training','Formation au seuil','2026-11-02','2026-11-03',1500),
 ('21000000-0000-0000-0000-000000000015','training','Formation au-dessus du seuil','2026-11-02','2026-11-03',1500.01);
select submit_hr_request('21000000-0000-0000-0000-000000000014');
select submit_hr_request('21000000-0000-0000-0000-000000000015');
select ok((select director_referent_id is null from requests where id='21000000-0000-0000-0000-000000000014'),'1500 EUR exact : pas de DRH');
select ok((select director_referent_id is not null from requests where id='21000000-0000-0000-0000-000000000015'),'1500.01 EUR : DRH requis');
insert into requests(id,request_type,title,start_date,end_date) values
 ('21000000-0000-0000-0000-000000000016','leave','Plus de dix jours','2026-11-16','2026-11-30'),
 ('21000000-0000-0000-0000-000000000017','leave','Dix jours exacts','2026-12-01','2026-12-14');
select submit_hr_request('21000000-0000-0000-0000-000000000016');
select submit_hr_request('21000000-0000-0000-0000-000000000017');
select ok((select director_referent_id is not null and requested_days=11 from requests where id='21000000-0000-0000-0000-000000000016'),'onze jours : DRH requis');
select ok((select director_referent_id is null and requested_days=10 from requests where id='21000000-0000-0000-0000-000000000017'),'dix jours exacts : pas de DRH');
reset role;
set local request.jwt.claims='{}';
set local role service_role;
select is(jsonb_array_length(get_hr_request_checks('21000000-0000-0000-0000-000000000012')->'possible_duplicate_ids'),1,'doublon potentiel signalé');
select is((get_hr_request_checks('21000000-0000-0000-0000-000000000012')->>'requires_human_review')::boolean,true,'doublon à examiner par un humain');
select transition_hr_request('21000000-0000-0000-0000-000000000016','under_review');
select prepare_hr_approvals('21000000-0000-0000-0000-000000000016');
select is((select count(*)::integer from approval_steps where request_id='21000000-0000-0000-0000-000000000016'),3,'préparation ajoute réellement le DRH');
reset role;

set local role authenticated;
set local request.jwt.claims='{"sub":"11000000-0000-0000-0000-000000000003","role":"authenticated"}';
insert into requests(id,request_type,title,amount,quantity) values
 ('21000000-0000-0000-0000-000000000018','equipment','Demande personnelle du RH',100,1);
select submit_hr_request('21000000-0000-0000-0000-000000000018');
select is((select hr_referent_id::text from requests where id='21000000-0000-0000-0000-000000000018'),
 '11000000-0000-0000-0000-000000000005','suppléant RH affecté pour éviter auto-approbation');
reset role;
update hr_routing_settings set alternate_hr_id=null;
set local role authenticated;
set local request.jwt.claims='{"sub":"11000000-0000-0000-0000-000000000003","role":"authenticated"}';
insert into requests(id,request_type,title,amount,quantity) values
 ('21000000-0000-0000-0000-000000000019','equipment','RH sans suppléant',100,1);
select throws_ok($$select submit_hr_request('21000000-0000-0000-0000-000000000019')$$,'23514',null,'sans suppléant : pas d’auto-approbation implicite');
reset role;

select * from finish();
rollback;
