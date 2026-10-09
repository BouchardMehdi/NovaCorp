
-- Exécuté exclusivement en local, dans la transaction du script Node.
do $seed$
declare owner_id uuid; item record; claim jsonb; current_step public.approval_steps;
 req_id uuid; phase text; iteration integer; new_ids uuid[]:='{}'; submitted timestamptz; completed timestamptz;
begin
 perform pg_advisory_xact_lock(hashtextextended('novacorp-demo-data-v1',0));
 select (payload->>'employee_id')::uuid into owner_id from demo_seed_context;
 if not exists(select 1 from auth.users where id=owner_id and email='demo.salarie@novacorp.test') then
  raise exception 'Le salarié de démonstration est absent.';
 end if;
 -- Aucun identifiant du jeu ne doit appartenir à une autre personne.
 if exists(select 1 from demo_seed_context c,jsonb_array_elements(c.payload->'scenarios') j
  join public.requests r on r.id=(j->>'id')::uuid where r.requester_id<>owner_id) then
  raise exception 'Un identifiant de démonstration est déjà utilisé.';
 end if;
 for item in select j.* from demo_seed_context c,
  jsonb_to_recordset(c.payload->'scenarios') as j(id uuid,request_type text,stage text,title text,
   description text,start_date date,end_date date,amount numeric,quantity integer,training_provider text,age_hours integer)
 loop
  if exists(select 1 from public.requests where id=item.id) then continue; end if;
  req_id:=item.id;phase:=item.stage;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
  insert into public.requests(id,requester_id,request_type,title,description,start_date,end_date,amount,quantity,training_provider)
   values(req_id,owner_id,item.request_type,item.title,item.description,item.start_date,item.end_date,item.amount,item.quantity,item.training_provider);
  new_ids:=array_append(new_ids,req_id);
  if phase='draft' then continue; end if;
  perform public.submit_hr_request(req_id);
  if phase='submitted' then continue; end if;
  if phase='cancelled' then perform public.cancel_hr_request(req_id);continue;end if;
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  if phase='failed' then
   for iteration in 1..3 loop
    claim:=public.claim_hr_qualification('demo-v1-'||req_id||'-'||iteration,'demo','fixture',req_id);
    if not coalesce((claim->>'claimed')::boolean,false) then raise exception 'Qualification fictive non réservée.';end if;
    perform public.fail_hr_qualification((claim->>'run_id')::uuid,(claim->>'lease_token')::uuid,'llm_http_error');
    if iteration<3 then update public.workflow_runs set retry_after=now()
     where id=(claim->>'run_id')::uuid;end if;
   end loop;
   continue;
  end if;
  claim:=public.claim_hr_qualification('demo-v1-'||req_id,'demo','fixture',req_id);
  if not coalesce((claim->>'claimed')::boolean,false) then raise exception 'Qualification fictive non réservée.';end if;
  perform public.complete_hr_qualification((claim->>'run_id')::uuid,(claim->>'lease_token')::uuid,
   jsonb_build_object('qualification','eligible','summary','Synthèse fictive : '||item.title||'. La décision appartient au validateur.','response_draft','Votre demande attend une décision humaine.'));
  for iteration in 1..3 loop
   select * into current_step from public.approval_steps where request_id=req_id and status='pending';
   if not found then exit;end if;
   if (phase in ('manager','reminder_manager') and current_step.position=1) or
    (phase in ('hr','overdue_hr') and current_step.position=2) or
    (phase in ('director','reminder_director') and current_step.position=3) then exit;end if;
   perform set_config('request.jwt.claims',jsonb_build_object('sub',current_step.assignee_id,'role','authenticated')::text,true);
   perform public.decide_hr_approval(current_step.id,phase<>'rejected',
    case when phase='rejected' then 'Refus fictif : formation non prioritaire pour cette démonstration.'
     else 'Accord fictif préparé pour la démonstration.' end);
   perform set_config('request.jwt.claims','{"role":"service_role"}',true);
   perform public.advance_hr_approvals('demo-v1-decision-'||req_id||'-'||iteration,req_id);
  end loop;
 end loop;
 -- Les états passent par les opérations métier ; seuls les horaires des NOUVELLES fixtures
 -- sont ensuite simulés, dans cette session. Aucun trigger global n'est désactivé.
 perform set_config('session_replication_role','replica',true);
 for item in select j.* from demo_seed_context c,
  jsonb_to_recordset(c.payload->'scenarios') as j(id uuid,stage text,age_hours integer)
  where j.id=any(new_ids) and j.stage not in ('draft','submitted')
 loop
  submitted:=now()-make_interval(hours=>item.age_hours);
  select case when status in ('approved','rejected') then submitted+make_interval(hours=>6*coalesce(
   (select max(position) from public.approval_steps where request_id=item.id and status in ('approved','rejected')),1))
   when status='cancelled' then submitted+interval '6 hours' else null end into completed
   from public.requests where id=item.id;
  update public.requests set created_at=submitted-interval '1 hour',submitted_at=submitted,
   completed_at=completed,updated_at=coalesce(completed,now()) where id=item.id;
  update public.approval_steps set activated_at=case when activated_at is not null then submitted+make_interval(hours=>6*(position-1))+interval '5 minutes' end,
   due_at=case when due_at is not null then submitted+make_interval(hours=>6*(position-1)+48)+interval '5 minutes' end,
   decided_at=case when decided_at is not null then submitted+make_interval(hours=>6*position) end
   where request_id=item.id;
  update public.workflow_runs set started_at=submitted+make_interval(mins=>attempt),
   finished_at=case when finished_at is not null then submitted+make_interval(mins=>attempt+1) end where request_id=item.id;
  update public.ai_reviews set started_at=submitted+interval '1 minute',
   finished_at=case when finished_at is not null then submitted+interval '4 minutes' end where request_id=item.id;
  update public.request_events e set occurred_at=case
   when event_type='created' then submitted-interval '1 hour'
   when event_type='approval_decided' then (select decided_at from public.approval_steps where id=e.approval_step_id)
   when new_status in ('approved','rejected','cancelled') then completed
   when new_status='under_review' then submitted+interval '1 minute'
   when new_status='pending_approval' then submitted+interval '5 minutes'
   else submitted end where request_id=item.id;
 end loop;
 perform set_config('session_replication_role','origin',true);
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 -- Les états et erreurs sont présentables ; les anciens emails du scénario ne sont pas expédiés.
 update public.notifications set status='sent',sent_at=now(),provider_message_id='demo-fixture-no-smtp'
  where request_id=any(new_ids) and kind='status_change';
 -- Ne pas envoyer une invitation déjà dépassée par une décision fictive.
 update public.notifications n set status='failed',next_attempt_at='infinity',last_error='Notification devenue obsolète.'
  where request_id=any(new_ids) and kind='approval_needed' and not exists(
   select 1 from public.approval_steps s join public.requests r on r.id=s.request_id
    where s.id=n.approval_step_id and s.status='pending' and r.status='pending_approval');
 -- Un échec SMTP démontrable sur la seule validation RH en retard.
 update public.notifications n set status='failed',attempts=5,next_attempt_at='infinity',
  last_error='Échec SMTP fictif ; vérification manuelle nécessaire.'
  where n.request_id=any(new_ids) and n.kind='approval_needed'
  and exists(select 1 from public.approval_steps s where s.id=n.approval_step_id and s.status='pending') and exists(
   select 1 from demo_seed_context c,jsonb_array_elements(c.payload->'scenarios') j
    where (j->>'id')::uuid=n.request_id and j->>'stage'='overdue_hr');
 perform public.queue_due_hr_reminders(owner_request.id)
  from public.requests owner_request where owner_request.id=any(new_ids);
 raise notice 'Démonstration : % demandes créées ; autres demandes conservées.',cardinality(new_ids);
end $seed$;
