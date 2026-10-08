-- Réservations du travail n8n : opérations exclusivement backend.
alter table public.workflow_runs add column lease_token uuid;
alter table public.workflow_runs add column lease_until timestamptz;
alter table public.workflow_runs add column retry_after timestamptz;
create unique index qualification_one_running on public.workflow_runs(request_id)
 where workflow_key='hr_qualification_v1' and status='running';
create unique index qualification_one_success on public.workflow_runs(request_id)
 where workflow_key='hr_qualification_v1' and status='succeeded';
create unique index qualification_one_review on public.ai_reviews(workflow_run_id)
 where prompt_version='hr-qualification-v1' and workflow_run_id is not null;
alter table public.notifications add column lease_token uuid;
alter table public.notifications add column lease_until timestamptz;

create function public.claim_hr_qualification(
 p_execution_id text, p_provider text, p_model text, p_request_id uuid default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.requests; old_run public.workflow_runs; run public.workflow_runs;
 checks jsonb; attempt_no integer;
begin
 if coalesce(length(btrim(p_execution_id)),0) not between 1 and 160 or
    coalesce(length(btrim(p_provider)),0) not between 1 and 200 or
    coalesce(length(btrim(p_model)),0) not between 1 and 200 then
  raise exception 'Configuration de qualification incomplète.' using errcode='23514';
 end if;
 for r in select q.* from public.requests q
  where q.status in ('submitted','under_review') and (p_request_id is null or q.id=p_request_id)
  order by q.submitted_at,q.id for update skip locked
 loop
  if exists(select 1 from public.workflow_runs w where w.request_id=r.id
   and w.workflow_key='hr_qualification_v1' and w.status='succeeded') then continue; end if;
  select * into old_run from public.workflow_runs w where w.request_id=r.id
   and w.workflow_key='hr_qualification_v1' order by w.attempt desc,w.started_at desc limit 1 for update;
  if found then
   if old_run.status='running' and coalesce(old_run.lease_until,'infinity')>now() then continue; end if;
   if old_run.status='failed' and coalesce(old_run.retry_after,'infinity')>now() then continue; end if;
   if old_run.status='running' then
    update public.workflow_runs set status='failed',finished_at=now(),
     error_code='lease_expired',error_message='Le traitement a dépassé sa réservation.'
     where id=old_run.id;
    update public.ai_reviews set status='failed',finished_at=now(),
     error_code='lease_expired',error_message='Le traitement a dépassé sa réservation.'
     where workflow_run_id=old_run.id and status='running';
   end if;
   attempt_no:=old_run.attempt+1;
  else attempt_no:=1; end if;
  if attempt_no>3 then continue; end if;
  if exists(select 1 from public.workflow_runs where workflow_key='hr_qualification_v1'
   and execution_id=p_execution_id) then return jsonb_build_object('claimed',false); end if;
  if r.status='submitted' then
   update public.requests set status='under_review' where id=r.id returning * into r;
  end if;
  checks:=public.get_hr_request_checks(r.id);
  insert into public.workflow_runs(request_id,workflow_key,execution_id,attempt,lease_token,lease_until)
   values(r.id,'hr_qualification_v1',p_execution_id,attempt_no,gen_random_uuid(),now()+interval '5 minutes')
   returning * into run;
  insert into public.ai_reviews(request_id,workflow_run_id,provider,model,prompt_version,checks)
   values(r.id,run.id,p_provider,p_model,'hr-qualification-v1',checks);
  return jsonb_build_object('claimed',true,'request_id',r.id,'run_id',run.id,
   'lease_token',run.lease_token,'checks',checks,'attempt',attempt_no,
   'request',jsonb_build_object('type',r.request_type,'title',r.title,'description',r.description,
    'start_date',r.start_date,'end_date',r.end_date,'start_half_day',r.start_half_day,
    'end_half_day',r.end_half_day,'requested_days',r.requested_days,'amount',r.amount,
    'currency',r.currency,'quantity',r.quantity,'training_provider',r.training_provider));
 end loop;
 return jsonb_build_object('claimed',false);
end $$;

create function public.complete_hr_qualification(p_run_id uuid,p_lease_token uuid,p_result jsonb,
 p_input_tokens integer default 0,p_output_tokens integer default 0)
 returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare run public.workflow_runs; r public.requests; req_id uuid; checks jsonb;
 qualification public.ai_qualification; summary text; response text;
begin
 select request_id into req_id from public.workflow_runs where id=p_run_id;
 select * into r from public.requests where id=req_id for update;
 select * into run from public.workflow_runs where id=p_run_id for update;
 if p_lease_token is null or run.id is null or run.workflow_key<>'hr_qualification_v1' or
  run.lease_token is distinct from p_lease_token then
  return jsonb_build_object('completed',false,'reason','stale_lease');
 end if;
 if run.status='succeeded' then return jsonb_build_object('completed',true,'replayed',true); end if;
 if run.status<>'running' or coalesce(run.lease_until,now())<=now() then
  return jsonb_build_object('completed',false,'reason','stale_lease');
 end if;
 if r.status<>'under_review' then
  update public.workflow_runs set status='failed',finished_at=now(),retry_after='infinity',
   error_code='request_inactive',error_message='La demande ne peut plus être qualifiée.' where id=run.id;
  update public.ai_reviews set status='failed',finished_at=now(),error_code='request_inactive',
   error_message='La demande ne peut plus être qualifiée.' where workflow_run_id=run.id;
  return jsonb_build_object('completed',false,'reason','request_inactive');
 end if;
 if jsonb_typeof(p_result) is distinct from 'object' or
  coalesce(p_result->>'qualification','') not in ('eligible','needs_review','invalid') or
  jsonb_typeof(p_result->'summary') is distinct from 'string' or
  length(btrim(p_result->>'summary')) not between 1 and 7800 or
  jsonb_typeof(p_result->'response_draft') is distinct from 'string' or
  length(p_result->>'response_draft')>8000 or
  p_input_tokens is null or p_input_tokens<0 or p_output_tokens is null or p_output_tokens<0 then
  raise exception 'Réponse de qualification invalide.' using errcode='23514';
 end if;
 checks:=public.get_hr_request_checks(r.id);
 qualification:=(p_result->>'qualification')::public.ai_qualification;
 summary:=btrim(p_result->>'summary'); response:=p_result->>'response_draft';
 if jsonb_array_length(checks->'blocking_issues')>0 then
  qualification:='invalid';
  summary:='Contrôles métier : des anomalies nécessitent une vérification humaine.'||E'\n'||summary;
 elsif (checks->>'requires_human_review')::boolean then
  qualification:='needs_review';
  summary:='Contrôles métier : un doublon potentiel doit être examiné.'||E'\n'||summary;
 end if;
 update public.ai_reviews set status='succeeded',finished_at=now(),checks=checks,
  qualification=qualification,summary=summary,response_draft=response,
  input_tokens=p_input_tokens,output_tokens=p_output_tokens where workflow_run_id=run.id;
 perform public.prepare_hr_approvals(r.id);
 update public.requests set status='pending_approval' where id=r.id;
 update public.approval_steps set status='pending' where request_id=r.id and position=1 and status='waiting';
 update public.workflow_runs set status='succeeded',finished_at=now() where id=run.id;
 return jsonb_build_object('completed',true,'request_id',r.id,'qualification',qualification);
end $$;

create function public.fail_hr_qualification(p_run_id uuid,p_lease_token uuid,p_error_code text)
 returns jsonb language plpgsql security definer set search_path='' as $$
declare run public.workflow_runs; req_id uuid; current_status public.request_status;
begin
 select request_id into req_id from public.workflow_runs where id=p_run_id;
 select status into current_status from public.requests where id=req_id for update;
 select * into run from public.workflow_runs where id=p_run_id for update;
 if p_lease_token is null or run.id is null or run.workflow_key<>'hr_qualification_v1' or
  run.status<>'running' or run.lease_token is distinct from p_lease_token then
  return jsonb_build_object('recorded',false);
 end if;
 if p_error_code not in ('configuration_missing','llm_http_error','llm_invalid_response','technical_error') or
  p_error_code is null then p_error_code:='technical_error'; end if;
 update public.workflow_runs set status='failed',finished_at=now(),
  retry_after=case when attempt>=3 or current_status<>'under_review' then 'infinity'::timestamptz
   else now()+make_interval(mins=>attempt) end,
  error_code=p_error_code,error_message='Qualification interrompue ; aucune décision automatique.'
  where id=run.id;
 update public.ai_reviews set status='failed',finished_at=now(),error_code=p_error_code,
  error_message='Qualification interrompue ; aucune décision automatique.' where workflow_run_id=run.id;
 return jsonb_build_object('recorded',true,'attempt',run.attempt);
end $$;

create function public.claim_hr_manager_email(p_request_id uuid default null)
 returns jsonb language plpgsql security definer set search_path='' as $$
declare candidate record; r public.requests; n public.notifications; email text; step_status public.approval_status;
begin
 for candidate in select q.id as request_id,x.id as notification_id
  from public.requests q join public.notifications x on x.request_id=q.id
  join public.approval_steps s on s.id=x.approval_step_id
  where x.kind='approval_needed' and x.channel='email' and s.position=1 and (x.attempts<5 or (x.status='sending' and x.lease_until<=now()))
   and (p_request_id is null or q.id=p_request_id)
   and ((x.status in ('queued','failed') and x.next_attempt_at<=now()) or
    (x.status='sending' and x.lease_until<=now()))
  order by x.created_at,x.id for update of q skip locked
 loop
  select * into r from public.requests where id=candidate.request_id;
  select * into n from public.notifications where id=candidate.notification_id for update skip locked;
  if not found then continue; end if;
  select status into step_status from public.approval_steps where id=n.approval_step_id;
  if r.status<>'pending_approval' or step_status<>'pending' then
   update public.notifications set status='failed',next_attempt_at='infinity',
    last_error='Notification devenue obsolète.' where id=n.id;
   continue;
  end if;
  if n.attempts>=5 then
   update public.notifications set status='failed',next_attempt_at='infinity',
    last_error='Dernière réservation SMTP expirée ; vérification manuelle nécessaire.' where id=n.id;
   continue;
  end if;
  select u.email into email from auth.users u where u.id=n.recipient_id;
  if email is null then
   update public.notifications set status='failed',next_attempt_at='infinity',
    last_error='Adresse du destinataire absente.' where id=n.id;
   continue;
  end if;
  update public.notifications set status='sending',attempts=attempts+1,
   lease_token=gen_random_uuid(),lease_until=now()+interval '5 minutes',last_error=null
   where id=n.id returning * into n;
  return jsonb_build_object('claimed',true,'notification_id',n.id,'lease_token',n.lease_token,
   'to',email,'subject','NovaCorp : une demande attend votre validation',
   'text','La demande NC-'||lpad(r.reference::text,6,'0')||' (« '||r.title||
    ' ») attend votre décision. Consultez http://localhost:3000/tableau-de-bord/demandes/'||r.id||
    E'\nUne décision humaine reste nécessaire.');
 end loop;
 return jsonb_build_object('claimed',false);
end $$;

create function public.finish_hr_manager_email(p_notification_id uuid,p_lease_token uuid,
 p_sent boolean,p_message_id text default null) returns jsonb
 language plpgsql security definer set search_path='' as $$
declare req_id uuid; n public.notifications;
begin
 select request_id into req_id from public.notifications where id=p_notification_id;
 perform 1 from public.requests where id=req_id for update;
 select * into n from public.notifications where id=p_notification_id for update;
 if p_lease_token is null or n.id is null or n.kind<>'approval_needed' or n.lease_token is distinct from p_lease_token then
  return jsonb_build_object('recorded',false);
 end if;
 if n.status='sent' then return jsonb_build_object('recorded',true,'replayed',true); end if;
 if n.status<>'sending' or p_sent is null then return jsonb_build_object('recorded',false); end if;
 if p_sent then
  update public.notifications set status='sent',sent_at=now(),provider_message_id=left(p_message_id,300),
   last_error=null where id=n.id;
 else
  update public.notifications set status='failed',
   next_attempt_at=case when attempts>=5 then 'infinity'::timestamptz
    else now()+make_interval(mins=>attempts) end,last_error='Échec SMTP ; envoi à réessayer.'
   where id=n.id;
 end if;
 return jsonb_build_object('recorded',true);
end $$;

revoke all on function public.claim_hr_qualification(text,text,text,uuid),
 public.complete_hr_qualification(uuid,uuid,jsonb,integer,integer),
 public.fail_hr_qualification(uuid,uuid,text),public.claim_hr_manager_email(uuid),
 public.finish_hr_manager_email(uuid,uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.claim_hr_qualification(text,text,text,uuid),
 public.complete_hr_qualification(uuid,uuid,jsonb,integer,integer),
 public.fail_hr_qualification(uuid,uuid,text),public.claim_hr_manager_email(uuid),
 public.finish_hr_manager_email(uuid,uuid,boolean,text) to service_role;
