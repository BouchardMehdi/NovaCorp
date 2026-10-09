begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select no_plan();

-- Toutes les données et valeurs métier de ce fichier sont fictives et annulées à la fin.
insert into auth.users (id, email) values
 ('10000000-0000-0000-0000-000000000001', 'bdd-salarie1@novacorp.test'),
 ('10000000-0000-0000-0000-000000000002', 'bdd-manager1@novacorp.test'),
 ('10000000-0000-0000-0000-000000000003', 'bdd-rh@novacorp.test'),
 ('10000000-0000-0000-0000-000000000004', 'bdd-drh@novacorp.test'),
 ('10000000-0000-0000-0000-000000000005', 'bdd-salarie2@novacorp.test'),
 ('10000000-0000-0000-0000-000000000006', 'bdd-manager2@novacorp.test'),
 ('10000000-0000-0000-0000-000000000007', 'bdd-rh-suppleant@novacorp.test');
update profiles set role = 'manager' where id in
 ('10000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000006');
update profiles set role = 'hr' where id in ('10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000007');
update profiles set role = 'director' where id = '10000000-0000-0000-0000-000000000004';
update profiles set manager_id = '10000000-0000-0000-0000-000000000002' where id = '10000000-0000-0000-0000-000000000001';
update profiles set manager_id = '10000000-0000-0000-0000-000000000006' where id = '10000000-0000-0000-0000-000000000005';
insert into leave_balances (employee_id, year, allocated_days) values
 ('10000000-0000-0000-0000-000000000001', 2026, 25),
 ('10000000-0000-0000-0000-000000000005', 2026, 20);


update approval_rules set active=false where active;
insert into hr_routing_settings(singleton,hr_referent_id,director_referent_id,alternate_hr_id) values
 (true,'10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000007')
 on conflict(singleton) do update set hr_referent_id=excluded.hr_referent_id, director_referent_id=excluded.director_referent_id, alternate_hr_id=excluded.alternate_hr_id, alternate_director_id=null;

select is((select count(*)::integer from request_types), 4, 'exactement quatre types du cahier des charges');
select ok(not exists(select 1 from pg_tables where schemaname = 'public' and tablename in
 ('profiles','requests','approval_steps','request_events','leave_balances','leave_balance_history',
 'request_attachments','workflow_runs','ai_reviews','notifications','request_types','approval_rules','process_measurements')
 and not rowsecurity), 'RLS activée sur toutes les tables métier');
select is((select public from storage.buckets where id = 'hr-attachments'), false, 'bucket privé');
select throws_ok($$update profiles set manager_id='10000000-0000-0000-0000-000000000001'
 where id='10000000-0000-0000-0000-000000000002'$$, '23514', null, 'manager doit avoir le bon rôle');
select throws_ok($$update leave_balances set reserved_days=30 where employee_id='10000000-0000-0000-0000-000000000001'$$,
 '23514', null, 'solde ne peut pas être négatif');

set local role anon;
select throws_ok($$select * from requests$$, '42501', null, 'visiteur sans accès aux demandes');
select throws_ok($$select submit_hr_request('20000000-0000-0000-0000-000000000001')$$,
 '42501', null, 'RPC inaccessible au visiteur');
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok($$insert into requests(id,request_type,title,amount,quantity) values
 ('20000000-0000-0000-0000-000000000001','equipment','Ordinateur de test',1500,1) returning id$$, 'salarié crée son brouillon');
select lives_ok($$insert into requests(id,request_type,title,start_date,end_date,requested_days) values
 ('20000000-0000-0000-0000-000000000002','leave','Congés de test','2026-11-02','2026-11-06',5)$$, 'brouillon congés');
select lives_ok($$insert into requests(id,request_type,title,start_date,end_date) values
 ('20000000-0000-0000-0000-000000000003','remote_work','Télétravail de test','2026-11-09','2026-11-10')$$, 'brouillon télétravail');
select lives_ok($$insert into requests(id,request_type,title,start_date,end_date,amount,training_provider) values
 ('20000000-0000-0000-0000-000000000004','training','Formation de test','2026-12-01','2026-12-02',500,'Organisme fictif')$$, 'brouillon formation');
select throws_ok($$insert into requests(requester_id,request_type,title) values
 ('10000000-0000-0000-0000-000000000005','equipment','Usurpation')$$, '42501', null, 'pas de demande au nom d’un autre');
select throws_ok($$update requests set status='approved' where id='20000000-0000-0000-0000-000000000001'$$,
 '42501', null, 'pas de modification directe du statut');
select throws_ok($$update profiles set role='director' where id=auth.uid()$$, '42501', null, 'pas d’élévation de rôle');
select throws_ok($$update requests set start_date='2026-12-01',end_date='2026-11-01'
 where id='20000000-0000-0000-0000-000000000002'$$, '23514', null, 'dates incohérentes rejetées');
select throws_ok($$select submit_hr_request('20000000-0000-0000-0000-000000000001')$$,
 '23514', null, 'règles non configurées bloquent la soumission');
select is((select count(*)::integer from leave_balances), 1, 'salarié voit uniquement son solde');
select throws_ok($$update leave_balances set allocated_days=99$$, '42501', null, 'salarié ne modifie pas son solde');
select throws_ok($$insert into request_events(request_id,event_type) values
 ('20000000-0000-0000-0000-000000000001','created')$$, '42501', null, 'historique non falsifiable');
select is((select count(*)::integer from request_events where event_type='created'), 4, 'créations historisées automatiquement');
select throws_ok($$select transition_hr_request('20000000-0000-0000-0000-000000000001','approved')$$,
 '42501', null, 'RPC backend interdite au salarié');
select throws_ok($$insert into request_attachments(request_id,filename,mime_type,size_bytes,storage_path) values
 ('20000000-0000-0000-0000-000000000001','test.pdf','application/pdf',100,'invalide')$$,
 '23514', null, 'une fiche de fichier exige un objet Storage');

set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}';
select is((select count(*)::integer from requests), 0, 'autre salarié ne voit aucun brouillon');
select throws_ok($$select cancel_hr_request('20000000-0000-0000-0000-000000000001')$$,
 '42501', null, 'autre salarié ne peut pas annuler');
select is(private.can_edit_request('20000000-0000-0000-0000-000000000001'), false, 'autre salarié ne peut pas téléverser');
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select count(*)::integer from requests), 0, 'manager ne voit pas les brouillons de son équipe');
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select count(*)::integer from requests where requester_id in ('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000005')), 0, 'RH ne voit pas les brouillons privés');
reset role;
set local request.jwt.claims = '{}';

-- Configuration exclusivement de test, non sauvegardée : aucune valeur métier n’est imposée.
update approval_rules set active=false where request_type='equipment';
insert into approval_rules(id,request_type,version,name,active,director_amount_above,decision_hours,reminder_hours)
 values('30000000-0000-0000-0000-000000000001','equipment',999999,'Circuit fictif de test',true,1000,48,24);
set local role authenticated;
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok($$select submit_hr_request('20000000-0000-0000-0000-000000000001')$$, 'soumission valide atomique');
select is((select status::text from requests where id='20000000-0000-0000-0000-000000000001'), 'submitted', 'statut soumis');
select is((select manager_id::text from requests where id='20000000-0000-0000-0000-000000000001'),
 '10000000-0000-0000-0000-000000000002', 'manager capturé depuis le profil');
select is((select count(*)::integer from notifications), 1, 'notification salarié mise en file');
select lives_ok($$update requests set title='Altération' where id='20000000-0000-0000-0000-000000000001'$$,
 'UPDATE sur demande soumise n’affecte aucune ligne');
select is((select title from requests where id='20000000-0000-0000-0000-000000000001'), 'Ordinateur de test', 'contenu soumis inchangé');
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select count(*)::integer from requests), 1, 'manager voit sa demande soumise');
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000006","role":"authenticated"}';
select is((select count(*)::integer from requests), 0, 'manager hors équipe ne voit rien');
reset role;
set local request.jwt.claims = '{}';

select throws_ok($$update approval_rules set director_amount_above=9999 where id='30000000-0000-0000-0000-000000000001'$$,
 '23514', null, 'règle utilisée immuable');
set local role service_role;
select lives_ok($$select transition_hr_request('20000000-0000-0000-0000-000000000001','under_review')$$, 'backend lance le contrôle IA');
select throws_ok($$select transition_hr_request('20000000-0000-0000-0000-000000000001','pending_approval')$$,
 '23514', null, 'pas de validation avant contrôle IA');
select lives_ok($$insert into ai_reviews(request_id,provider,model,prompt_version,status,qualification,summary,finished_at)
 values('20000000-0000-0000-0000-000000000001','fictif','test','v1','succeeded','eligible','Synthèse fictive',now())$$,
 'backend enregistre le contrôle IA');
select throws_ok($$select transition_hr_request('20000000-0000-0000-0000-000000000001','pending_approval')$$,
 '23514', null, 'pas de validation sans circuit');
insert into approval_steps(id,request_id,position,required_role,assignee_id) values
 ('40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',1,'manager','10000000-0000-0000-0000-000000000002'),
 ('40000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001',2,'hr','10000000-0000-0000-0000-000000000003');
select throws_ok($$select transition_hr_request('20000000-0000-0000-0000-000000000001','pending_approval')$$,
 '23514', null, 'seuil dépassé exige DRH');
insert into approval_steps(id,request_id,position,required_role,assignee_id) values
 ('40000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001',3,'director','10000000-0000-0000-0000-000000000004');
select lives_ok($$select transition_hr_request('20000000-0000-0000-0000-000000000001','pending_approval')$$, 'circuit complet accepté');
select throws_ok($$update approval_steps set status='pending' where id='40000000-0000-0000-0000-000000000002'$$,
 '23514', null, 'RH ne peut pas intervenir avant manager');
select lives_ok($$update approval_steps set status='pending' where id='40000000-0000-0000-0000-000000000001'$$, 'backend active manager');
select throws_ok($$select transition_hr_request('20000000-0000-0000-0000-000000000001','approved')$$,
 '23514', null, 'pas d’approbation finale prématurée');
select throws_ok($$update request_events set comment='Faux historique'$$, '42501', null, 'backend ne réécrit pas l’historique');
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is((select count(*)::integer from ai_reviews), 0, 'analyses internes invisibles au demandeur');
select throws_ok($$select decide_hr_approval('40000000-0000-0000-0000-000000000001',true,null)$$,
 '42501', null, 'demandeur ne décide pas pour le manager');
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select count(*)::integer from ai_reviews), 1, 'manager voit la synthèse de sa demande');
select lives_ok($$select decide_hr_approval('40000000-0000-0000-0000-000000000001',true,'Accord fictif')$$, 'manager décide');
select throws_ok($$select decide_hr_approval('40000000-0000-0000-0000-000000000001',false,'Nouvelle décision')$$,
 '42501', null, 'double décision interdite');
reset role;
set local request.jwt.claims = '{}';
set local role service_role;
update approval_steps set status='pending' where id='40000000-0000-0000-0000-000000000002';
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select decide_hr_approval('40000000-0000-0000-0000-000000000002',false,' ')$$,
 '23514', null, 'refus doit être motivé');
select lives_ok($$select decide_hr_approval('40000000-0000-0000-0000-000000000002',true,null)$$, 'RH décide');
reset role;
set local request.jwt.claims = '{}';
set local role service_role;
update approval_steps set status='pending' where id='40000000-0000-0000-0000-000000000003';
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}';
select lives_ok($$select decide_hr_approval('40000000-0000-0000-0000-000000000003',true,null)$$, 'DRH décide');
reset role;
set local request.jwt.claims = '{}';
set local role service_role;
select lives_ok($$select transition_hr_request('20000000-0000-0000-0000-000000000001','approved')$$, 'backend termine après toutes les validations');
select throws_ok($$select transition_hr_request('20000000-0000-0000-0000-000000000001','under_review')$$,
 '23514', null, 'demande terminée ne se rouvre pas');
reset role;
select is((select count(*)::integer from request_events where request_id='20000000-0000-0000-0000-000000000001' and event_type='approval_decided'), 3, 'trois décisions historisées');
select is((select count(*)::integer from notifications where request_id='20000000-0000-0000-0000-000000000001'), 7, 'quatre statuts et trois validateurs notifiés');
select ok((select completed_at is not null from requests where id='20000000-0000-0000-0000-000000000001'), 'horodatage permet la mesure du délai');
select ok(exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and tablename='requests'), 'demandes publiées pour dashboard temps réel');

set local role authenticated;
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok($$select cancel_hr_request('20000000-0000-0000-0000-000000000002')$$, 'salarié annule son brouillon');
select throws_ok($$select cancel_hr_request('20000000-0000-0000-0000-000000000001')$$,
 '42501', null, 'demande approuvée non annulable');
reset role;

-- Stockage : les tests ne créent que des métadonnées transactionnelles, aucun fichier physique.
set local role authenticated;
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok($$insert into storage.objects(bucket_id,name) values
 ('hr-attachments','20000000-0000-0000-0000-000000000003/50000000-0000-0000-0000-000000000001')$$, 'téléversement autorisé sur son brouillon');
select lives_ok($$insert into request_attachments(id,request_id,filename,mime_type,size_bytes,storage_path) values
 ('50000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000003','fictif.pdf','application/pdf',100,
 '20000000-0000-0000-0000-000000000003/50000000-0000-0000-0000-000000000001')$$, 'fiche du fichier autorisée');
select throws_ok($$insert into storage.objects(bucket_id,name) values ('hr-attachments','chemin-invalide')$$,
 '42501', null, 'chemin de fichier invalide bloqué');
with changed as (update storage.objects set name='remplacement' where
 name='20000000-0000-0000-0000-000000000003/50000000-0000-0000-0000-000000000001' returning id)
 select is((select count(*)::integer from changed), 0, 'remplacement silencieux de fichier bloqué');
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}';
select is((select count(*)::integer from storage.objects where bucket_id='hr-attachments' and
 name='20000000-0000-0000-0000-000000000003/50000000-0000-0000-0000-000000000001'),0,'fichier invisible à un autre salarié');
select throws_ok($$insert into storage.objects(bucket_id,name) values
 ('hr-attachments','20000000-0000-0000-0000-000000000003/50000000-0000-0000-0000-000000000002')$$,
 '42501',null,'autre salarié ne téléverse pas dans cette demande');
reset role;
set local request.jwt.claims = '{}';

-- Refus tracé et terminal, circuit sans DRH sur formation de test.
update approval_rules set active=false where request_type='training';
insert into approval_rules(id,request_type,version,name,active,director_amount_above,decision_hours,reminder_hours)
 values('30000000-0000-0000-0000-000000000002','training',999999,'Formation fictive de test',true,1000,48,24);
set local role authenticated;
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}';
select submit_hr_request('20000000-0000-0000-0000-000000000004');
reset role;
set local request.jwt.claims = '{}';
set local role service_role;
select transition_hr_request('20000000-0000-0000-0000-000000000004','under_review');
insert into ai_reviews(request_id,provider,model,prompt_version,status,qualification,summary,finished_at)
 values('20000000-0000-0000-0000-000000000004','fictif','test','v1','succeeded','needs_review','Synthèse fictive',now());
insert into approval_steps(id,request_id,position,required_role,assignee_id) values
 ('40000000-0000-0000-0000-000000000004','20000000-0000-0000-0000-000000000004',1,'manager','10000000-0000-0000-0000-000000000002'),
 ('40000000-0000-0000-0000-000000000005','20000000-0000-0000-0000-000000000004',2,'hr','10000000-0000-0000-0000-000000000003');
select lives_ok($$select transition_hr_request('20000000-0000-0000-0000-000000000004','pending_approval')$$,
 'sous le seuil : deux validations suffisent, synthèse IA non décisionnaire');
update approval_steps set status='pending' where id='40000000-0000-0000-0000-000000000004';
select throws_ok($$update approval_steps set status='rejected',decided_by=assignee_id
 where id='40000000-0000-0000-0000-000000000004'$$,'23514',null,'backend ne peut enregistrer un refus sans motif');
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';
select decide_hr_approval('40000000-0000-0000-0000-000000000004',false,'Refus fictif motivé');
reset role;
set local request.jwt.claims = '{}';
set local role service_role;
select lives_ok($$select transition_hr_request('20000000-0000-0000-0000-000000000004','rejected')$$, 'refus terminal après décision motivée');
select throws_ok($$update approval_steps set status='pending' where id='40000000-0000-0000-0000-000000000005'$$,
 '23514',null,'étape suivante bloquée après refus');
select throws_ok($$insert into ai_reviews(request_id,provider,model,prompt_version,input_tokens) values
 ('20000000-0000-0000-0000-000000000004','fictif','test','v1',-1)$$,'23514',null,'tokens et coûts ne peuvent être négatifs');
reset role;

-- Seuil exact : pas d'escalade. Annulation pendant une validation.
set local role authenticated;
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}';
insert into requests(id,request_type,title,amount,quantity) values
 ('20000000-0000-0000-0000-000000000005','equipment','Au seuil exact de test',1000,1);
select submit_hr_request('20000000-0000-0000-0000-000000000005');
reset role;
set local request.jwt.claims = '{}';
set local role service_role;
select transition_hr_request('20000000-0000-0000-0000-000000000005','under_review');
insert into ai_reviews(request_id,provider,model,prompt_version,status,qualification,summary,finished_at)
 values('20000000-0000-0000-0000-000000000005','fictif','test','v1','succeeded','eligible','Synthèse fictive',now());
insert into approval_steps(id,request_id,position,required_role,assignee_id) values
 ('40000000-0000-0000-0000-000000000006','20000000-0000-0000-0000-000000000005',1,'manager','10000000-0000-0000-0000-000000000002'),
 ('40000000-0000-0000-0000-000000000007','20000000-0000-0000-0000-000000000005',2,'hr','10000000-0000-0000-0000-000000000003');
select lives_ok($$select transition_hr_request('20000000-0000-0000-0000-000000000005','pending_approval')$$, 'seuil exact : DRH facultatif');
update approval_steps set status='pending' where id='40000000-0000-0000-0000-000000000006';
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok($$select cancel_hr_request('20000000-0000-0000-0000-000000000005')$$, 'annulation pendant la validation');
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$select decide_hr_approval('40000000-0000-0000-0000-000000000006',true,null)$$,
 '23514',null,'décision bloquée après annulation');
reset role;
set local request.jwt.claims = '{}';

-- Auto-approbation : un RH peut demander, mais doit être validé par un autre RH.
update profiles set manager_id='10000000-0000-0000-0000-000000000002' where id='10000000-0000-0000-0000-000000000003';
set local role authenticated;
set local request.jwt.claims = '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';
insert into requests(id,request_type,title,amount,quantity) values
 ('20000000-0000-0000-0000-000000000006','equipment','Demande personnelle RH fictive',100,1);
select submit_hr_request('20000000-0000-0000-0000-000000000006');
reset role;
set local request.jwt.claims = '{}';
set local role service_role;
select transition_hr_request('20000000-0000-0000-0000-000000000006','under_review');
select throws_ok($$insert into approval_steps(request_id,position,required_role,assignee_id) values
 ('20000000-0000-0000-0000-000000000006',2,'hr','10000000-0000-0000-0000-000000000003')$$,
 '23514',null,'RH ne peut pas valider sa propre demande');
reset role;

select * from finish();
rollback;
