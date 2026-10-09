-- S3 : rappel quotidien au manager a 08:00, apres strictement 48 h. Les alertes RH restent actives.
create or replace function private.queue_hr_approval_reminders(p_now timestamptz,p_request_id uuid) returns integer
language plpgsql security definer set search_path = ''
as $$
declare r record; s public.approval_steps; inserted integer; total integer := 0;
begin
  if p_now is null then raise exception 'Date de supervision obligatoire.' using errcode = '23514'; end if;
  -- Verrouille d'abord la demande, puis ses étapes, comme les décisions et les transitions.
  for r in select q.id, q.hr_referent_id, a.reminder_hours from public.requests q
    join public.approval_rules a on a.id = q.approval_rule_id
    where q.status = 'pending_approval' and (p_request_id is null or q.id=p_request_id) order by q.id for update of q skip locked
  loop
    for s in select * from public.approval_steps where request_id = r.id and status = 'pending'
      order by position for update skip locked
    loop
      if p_now >= s.due_at then
        insert into public.notifications(request_id, recipient_id, approval_step_id, kind, deduplication_key)
          values (r.id, r.hr_referent_id, s.id, 'overdue_alert', 'step:' || s.id || ':overdue:email')
          on conflict (deduplication_key) do nothing;
        get diagnostics inserted = row_count;
        total := total + inserted;
      end if;
    end loop;
  end loop;
  return total;
end $$;




-- Le jour et le seuil sont calcules en heure de Paris, y compris lors du changement d'heure.
create function private.queue_daily_manager_reminders(p_now timestamptz,p_request_id uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare r record; s public.approval_steps; cutoff timestamptz; day_key text; total integer:=0; inserted integer;
begin
 if p_now is null then raise exception 'Date obligatoire.' using errcode='23514'; end if;
 cutoff:=((p_now at time zone 'Europe/Paris')::date+time '08:00') at time zone 'Europe/Paris';
 if p_now<cutoff then return 0; end if;
 day_key:=to_char(cutoff at time zone 'Europe/Paris','YYYY-MM-DD');
 -- Le passage quotidien attend les verrous existants : une concurrence a 8 h ne doit pas sauter une demande.
 for r in select id from public.requests where status='pending_approval'
  and (p_request_id is null or id=p_request_id) order by id for update
 loop
  for s in select * from public.approval_steps where request_id=r.id and status='pending'
   and required_role='manager' and activated_at<cutoff-interval '48 hours'
   order by position for update
  loop
   insert into public.notifications(request_id,recipient_id,approval_step_id,kind,deduplication_key)
    values(r.id,s.assignee_id,s.id,'reminder','step:'||s.id||':manager-daily:'||day_key||':email')
    on conflict(deduplication_key) do nothing;
   get diagnostics inserted=row_count;
   total:=total+inserted;
  end loop;
 end loop;
 return total;
end $$;

create function public.queue_daily_manager_reminders(p_request_id uuid default null)
returns integer language sql security definer set search_path='' as $$
 select private.queue_daily_manager_reminders(now(),p_request_id);
$$;
revoke all on function private.queue_daily_manager_reminders(timestamptz,uuid) from public,anon,authenticated,service_role;
revoke all on function public.queue_daily_manager_reminders(uuid) from public,anon,authenticated;
grant execute on function public.queue_daily_manager_reminders(uuid) to service_role;

create or replace function public.claim_hr_notification_email(p_request_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare candidate record; r public.requests; n public.notifications; email text;
 step public.approval_steps; event public.request_events; body_text text; subject_text text; label text; reminder_at timestamptz;
begin
 for candidate in select q.id as request_id,x.id as notification_id
  from public.requests q join public.notifications x on x.request_id=q.id
  where x.kind in ('approval_needed','status_change','reminder','overdue_alert') and x.channel='email'
   and (x.attempts<5 or (x.status='sending' and x.lease_until<=now()))
   and (p_request_id is null or q.id=p_request_id)
   and ((x.status in ('queued','failed') and x.next_attempt_at<=now()) or
    (x.status='sending' and x.lease_until<=now()))
  order by case x.kind when 'overdue_alert' then 0 when 'reminder' then 1 else 2 end,x.created_at,x.id for update of q skip locked
 loop
  select * into r from public.requests where id=candidate.request_id;
  select * into n from public.notifications where id=candidate.notification_id for update skip locked;
  if not found then continue; end if;
  if n.kind in ('approval_needed','reminder','overdue_alert') then
   select * into step from public.approval_steps where id=n.approval_step_id;
   if r.status<>'pending_approval' or step.status is distinct from 'pending'::public.approval_status then
    update public.notifications set status='failed',next_attempt_at='infinity',
     last_error='Notification devenue obsolète.' where id=n.id; continue;
   end if;

   if n.kind='reminder' then
    reminder_at:=((now() at time zone 'Europe/Paris')::date+time '08:00') at time zone 'Europe/Paris';
    if step.required_role<>'manager' or n.recipient_id<>step.assignee_id
     or step.activated_at>=reminder_at-interval '48 hours'
     or n.deduplication_key<>'step:'||step.id||':manager-daily:'||
      to_char(reminder_at at time zone 'Europe/Paris','YYYY-MM-DD')||':email' then
     update public.notifications set status='failed',next_attempt_at='infinity',
      last_error='Relance devenue obsolete.' where id=n.id; continue;
    end if;
    if now()<reminder_at then
     update public.notifications set next_attempt_at=reminder_at where id=n.id; continue;
    end if;
   elsif n.kind='overdue_alert' and now()<step.due_at then
    update public.notifications set next_attempt_at=step.due_at where id=n.id; continue;
   end if;
   label:=case step.required_role when 'manager' then 'manager' when 'hr' then 'RH' else 'DRH' end;
   subject_text:=case n.kind when 'reminder' then 'NovaCorp : rappel quotidien au manager'
    when 'overdue_alert' then 'NovaCorp : alerte RH — délai de 48 h dépassé'
    else 'NovaCorp : une demande attend votre validation' end;
   body_text:=case n.kind when 'reminder' then 'Relance : la demande '
    when 'overdue_alert' then 'Alerte RH : la demande ' else 'La demande ' end||
    'NC-'||lpad(r.reference::text,6,'0')||' (« '||r.title||' ») attend une décision ('||label||'). '||
    case n.kind when 'reminder' then 'Votre validation attend depuis plus de 48 heures. '
     when 'overdue_alert' then 'Le délai de décision de 48 heures est atteint. Aucune décision automatique. '
     else '' end||
    'Échéance : '||to_char(step.due_at at time zone 'Europe/Paris','DD/MM/YYYY HH24:MI')||
    ' (heure de Paris). Une décision humaine reste nécessaire.';
  else
   select * into event from public.request_events where id=n.event_id;
   label:=case event.new_status when 'submitted' then 'Soumise' when 'under_review' then 'En analyse'
    when 'pending_approval' then 'En validation' when 'approved' then 'Acceptée'
    when 'rejected' then 'Refusée' when 'cancelled' then 'Annulée' else null end;
   if label is null then
    update public.notifications set status='failed',next_attempt_at='infinity',
     last_error='Événement de statut indisponible.' where id=n.id; continue;
   end if;
   subject_text:='NovaCorp : demande NC-'||lpad(r.reference::text,6,'0')||' — '||label;
   body_text:='Votre demande NC-'||lpad(r.reference::text,6,'0')||' (« '||r.title||
    ' ») est passée au statut « '||label||' » le '||
    to_char(event.occurred_at at time zone 'Europe/Paris','DD/MM/YYYY HH24:MI')||
    E' (heure de Paris).
Ce message retrace cet événement ; consultez la fiche pour son état actuel.';
  end if;
  if n.attempts>=5 then
   update public.notifications set status='failed',next_attempt_at='infinity',
    last_error='Dernière réservation SMTP expirée ; vérification manuelle nécessaire.' where id=n.id; continue;
  end if;
  select u.email into email from auth.users u where u.id=n.recipient_id;
  if email is null then
   update public.notifications set status='failed',next_attempt_at='infinity',
    last_error='Adresse du destinataire absente.' where id=n.id; continue;
  end if;
  update public.notifications set status='sending',attempts=attempts+1,
   lease_token=gen_random_uuid(),lease_until=now()+interval '5 minutes',last_error=null
   where id=n.id returning * into n;
  return jsonb_build_object('claimed',true,'notification_id',n.id,'lease_token',n.lease_token,
   'to',email,'subject',subject_text,'text',body_text||
   E'
http://localhost:3000/tableau-de-bord/demandes/'||r.id);
 end loop;
 return jsonb_build_object('claimed',false);
end $$;


-- Supervision en lecture seule : session RH/DRH et RLS existantes.
create or replace function public.get_hr_dashboard(p_request_type text default null)
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
    (n.kind='approval_needed' or (n.kind='reminder' and s.required_role='manager' and n.deduplication_key='step:'||s.id||':manager-daily:'||to_char(now() at time zone 'Europe/Paris','YYYY-MM-DD')||':email') or
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
