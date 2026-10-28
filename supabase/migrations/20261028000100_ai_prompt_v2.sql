-- Preserve past reviews and extend review uniqueness to the new prompt revision.
drop index public.qualification_one_review;
create unique index qualification_one_review on public.ai_reviews(workflow_run_id)
 where prompt_version in ('hr-qualification-v1','hr-qualification-v2') and workflow_run_id is not null;
create or replace function public.claim_hr_qualification(
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
   values(r.id,run.id,p_provider,p_model,'hr-qualification-v2',checks);
  return jsonb_build_object('claimed',true,'request_id',r.id,'run_id',run.id,
   'lease_token',run.lease_token,'checks',checks,'attempt',attempt_no,
   'request',jsonb_build_object('type',r.request_type,'title',r.title,'description',r.description,
    'start_date',r.start_date,'end_date',r.end_date,'start_half_day',r.start_half_day,
    'end_half_day',r.end_half_day,'requested_days',r.requested_days,'amount',r.amount,
    'currency',r.currency,'quantity',r.quantity,'training_provider',r.training_provider));
 end loop;
 return jsonb_build_object('claimed',false);
end $$;

