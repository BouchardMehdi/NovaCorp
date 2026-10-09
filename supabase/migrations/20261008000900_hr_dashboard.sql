-- Supervision en lecture seule : session RH/DRH et RLS existantes.
create function public.get_hr_dashboard(p_request_type text default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
 if private.current_app_role() is null or private.current_app_role() not in ('hr','director') then
  raise exception 'Supervision réservée aux RH et à la DRH.' using errcode='42501';
 end if;
 if p_request_type is not null and not exists(select 1 from public.request_types where code=p_request_type) then
  raise exception 'Type de demande inconnu.' using errcode='23514';
 end if;
 with req as materialized (
  select * from public.requests where submitted_at is not null and status<>'draft'
   and (p_request_type is null or request_type=p_request_type)
 ), pending as (
  select s.id,s.request_id,s.required_role,s.assignee_id,s.activated_at,s.due_at,
   r.reference,r.title,r.request_type,r.status,
   s.due_at<=now() as overdue,p.first_name||' '||p.last_name as assignee
  from public.approval_steps s join req r on r.id=s.request_id
  join public.profiles p on p.id=s.assignee_id
  where s.status='pending' and r.status='pending_approval'
 ), latest_runs as (
  select distinct on(w.request_id,w.workflow_key) w.*,r.reference,r.title
  from public.workflow_runs w join req r on r.id=w.request_id
  where r.status in ('submitted','under_review','pending_approval')
  order by w.request_id,w.workflow_key,w.started_at desc,w.attempt desc,w.id
 ), workflow_issues as (
  select id,request_id,reference,title,'workflow'::text as source,
   coalesce(error_code,'lease_expired') as code,
   started_at as occurred_at,retry_after as retry_at,
   status='running' or (retry_after is not null and retry_after<>'infinity'::timestamptz) as automatic_retry
  from latest_runs where status='failed' or (status='running' and lease_until<=now())
 ), relevant_mail as (
  select n.*,r.reference,r.title from public.notifications n join req r on r.id=n.request_id
  left join public.approval_steps s on s.id=n.approval_step_id
  where n.channel='email' and (n.kind='status_change' or
   (r.status='pending_approval' and s.status='pending' and
    (n.kind='approval_needed' or (n.kind='reminder' and s.due_at>now()) or
     (n.kind='overdue_alert' and s.due_at<=now()))))
 ), mail_issues as (
  select id,request_id,reference,title,'email'::text as source,
   case when status='sending' then 'smtp_lease_expired' else 'smtp_failed' end as code,
   created_at as occurred_at,next_attempt_at as retry_at,
   attempts<5 and next_attempt_at<>'infinity'::timestamptz as automatic_retry
  from relevant_mail where status='failed' or (status='sending' and lease_until<=now())
 ), issues as (select * from workflow_issues union all select * from mail_issues),
 closed as (select extract(epoch from(completed_at-submitted_at))/3600 as hours from req
  where status in ('approved','rejected'))
 select jsonb_build_object(
  'generated_at',now(),
  'total',(select count(*) from req),
  'active',(select count(*) from req where status in ('submitted','under_review','pending_approval')),
  'pending_count',(select count(*) from pending),
  'overdue_count',(select count(*) from pending where overdue),
  'issue_count',(select count(*) from issues),
  'workflow_issue_count',(select count(*) from workflow_issues),
  'mail_issue_count',(select count(*) from mail_issues),
  'mail_queue_count',(select count(*) from relevant_mail where status in ('queued','sending','failed')),
  'closed_count',(select count(*) from closed),
  'average_hours',(select round(avg(hours)::numeric,2) from closed),
  'median_hours',(select round(percentile_cont(0.5) within group(order by hours)::numeric,2) from closed),
  'by_status',coalesce((select jsonb_object_agg(status,n) from
   (select status,count(*) as n from req group by status) counts),'{}'::jsonb),
  'by_type',coalesce((select jsonb_object_agg(request_type,n) from
   (select request_type,count(*) as n from req group by request_type) counts),'{}'::jsonb),
  'pending',coalesce((select jsonb_agg(to_jsonb(p)) from
   (select * from pending order by due_at,id limit 20) p),'[]'::jsonb),
  'issues',coalesce((select jsonb_agg(to_jsonb(i)) from
   (select * from issues order by occurred_at,id limit 20) i),'[]'::jsonb),
  'waiting',coalesce((select jsonb_agg(to_jsonb(w)) from
   (select id,reference,title,request_type,status,submitted_at,
    extract(epoch from(now()-submitted_at))/3600 as age_hours
    from req where status in ('submitted','under_review','pending_approval')
    order by submitted_at,id limit 20) w),'[]'::jsonb)
 ) into result;
 return result;
end $$;
revoke all on function public.get_hr_dashboard(text) from public,anon,service_role;
grant execute on function public.get_hr_dashboard(text) to authenticated;
