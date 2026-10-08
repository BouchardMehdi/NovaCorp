-- Opérations de préparation et de supervision appelées par les futurs workflows n8n.
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('status_change', 'approval_needed', 'reminder', 'overdue_alert'));

create or replace function private.guard_related_data() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_table_name = 'ai_reviews' then
    if new.workflow_run_id is not null and not exists (
      select 1 from public.workflow_runs where id = new.workflow_run_id and request_id = new.request_id
    ) then raise exception 'Exécution liée à une autre demande.' using errcode = '23514'; end if;
  end if;
  if tg_table_name = 'request_attachments' then
    if not exists (select 1 from public.requests where id = new.request_id and requester_id = new.uploaded_by and status = 'draft') then
      raise exception 'Pièce jointe réservée au brouillon du demandeur.' using errcode = '23514';
    end if;
    if not exists (select 1 from storage.objects where bucket_id = 'hr-attachments' and name = new.storage_path) then
      raise exception 'Téléverser le fichier dans Storage avant de créer sa fiche.' using errcode = '23514';
    end if;
  end if;
  if tg_table_name = 'notifications' then
    if new.event_id is not null and not exists (
      select 1 from public.request_events where id = new.event_id and request_id = new.request_id
    ) then raise exception 'Événement lié à une autre demande.' using errcode = '23514'; end if;
    if new.kind = 'status_change' and not exists (
      select 1 from public.requests where id = new.request_id and requester_id = new.recipient_id
    ) then raise exception 'Destinataire de statut incompatible.' using errcode = '23514'; end if;
    if new.approval_step_id is not null and not exists (
      select 1 from public.approval_steps s join public.requests r on r.id = s.request_id
      where s.id = new.approval_step_id and s.request_id = new.request_id and
        ((new.kind = 'overdue_alert' and new.recipient_id = r.hr_referent_id) or
         (new.kind <> 'overdue_alert' and new.recipient_id = s.assignee_id))
    ) then raise exception 'Validation ou destinataire incompatible.' using errcode = '23514'; end if;
  end if;
  return new;
end $$;

create function public.prepare_hr_approvals(p_request_id uuid) returns setof public.approval_steps
language plpgsql security definer set search_path = ''
as $$
declare r public.requests;
begin
  select * into r from public.requests where id = p_request_id for update;
  if not found or r.status not in ('under_review', 'pending_approval') then
    raise exception 'La demande doit être en contrôle ou en validation.' using errcode = '23514';
  end if;
  if r.manager_id is null or r.hr_referent_id is null then
    raise exception 'Référents de la demande incomplets.' using errcode = '23514';
  end if;
  insert into public.approval_steps(request_id, position, required_role, assignee_id) values
    (r.id, 1, 'manager', r.manager_id), (r.id, 2, 'hr', r.hr_referent_id)
    on conflict (request_id, position) do nothing;
  if r.director_referent_id is not null then
    insert into public.approval_steps(request_id, position, required_role, assignee_id)
      values (r.id, 3, 'director', r.director_referent_id) on conflict (request_id, position) do nothing;
  end if;
  return query select * from public.approval_steps where request_id = r.id order by position;
end $$;

create function public.queue_hr_approval_reminders(p_now timestamptz default now()) returns integer
language plpgsql security definer set search_path = ''
as $$
declare r record; s public.approval_steps; inserted integer; total integer := 0;
begin
  if p_now is null then raise exception 'Date de supervision obligatoire.' using errcode = '23514'; end if;
  -- Verrouille d'abord la demande, puis ses étapes, comme les décisions et les transitions.
  for r in select q.id, q.hr_referent_id, a.reminder_hours from public.requests q
    join public.approval_rules a on a.id = q.approval_rule_id
    where q.status = 'pending_approval' order by q.id for update of q skip locked
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
      elsif p_now >= s.activated_at + make_interval(hours => r.reminder_hours) then
        insert into public.notifications(request_id, recipient_id, approval_step_id, kind, deduplication_key)
          values(r.id, s.assignee_id, s.id, 'reminder', 'step:' || s.id || ':reminder:email')
          on conflict (deduplication_key) do nothing;
        get diagnostics inserted = row_count;
        total := total + inserted;
      end if;
    end loop;
  end loop;
  return total;
end $$;

create function public.get_hr_request_checks(p_request_id uuid) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare r public.requests; days numeric; conflicts uuid[] := '{}'::uuid[]; duplicates uuid[];
  enough_balance boolean := true; issues text[] := '{}'::text[]; part record; available numeric;
begin
  select * into r from public.requests where id = p_request_id;
  if not found then raise exception 'Demande introuvable.' using errcode = 'P0002'; end if;
  if r.request_type in ('leave', 'remote_work', 'training') and
    (r.start_date is null or r.end_date is null or r.end_date < r.start_date) then
    issues := array_append(issues, 'invalid_dates');
  elsif r.request_type = 'leave' then
    begin
      days := public.calculate_leave_days(r.start_date, r.end_date, r.start_half_day, r.end_half_day);
    exception when check_violation then
      issues := array_append(issues, 'invalid_leave_period');
    end;
    if days is not null then
      for part in select * from private.leave_days_by_year(r.start_date,r.end_date,r.start_half_day,r.end_half_day)
      loop
        select b.available_days + coalesce((select a.days from public.leave_allocations a
          where a.request_id = r.id and a.balance_id = b.id and a.state in ('reserved','consumed')), 0)
          into available from public.leave_balances b where b.employee_id = r.requester_id and b.year = part.year;
        if not found or available < part.days then enough_balance := false; end if;
      end loop;
      if not enough_balance then issues := array_append(issues, 'insufficient_leave_balance'); end if;
    end if;
  end if;
  if r.request_type in ('leave', 'remote_work') and r.start_date is not null and r.end_date >= r.start_date then
    conflicts := private.conflicting_requests(r.id,r.requester_id,r.start_date,r.end_date,r.start_half_day,r.end_half_day);
    if cardinality(conflicts) > 0 then issues := array_append(issues,'overlapping_request'); end if;
  end if;
  select coalesce(array_agg(q.id order by q.id), '{}') into duplicates from public.requests q
    where q.id <> r.id and q.requester_id = r.requester_id and q.request_type = r.request_type
      and q.status in ('submitted','under_review','pending_approval','approved')
      and lower(btrim(q.title)) = lower(btrim(r.title))
      and (q.start_date,q.end_date,q.start_half_day,q.end_half_day,q.amount,q.quantity)
        is not distinct from (r.start_date,r.end_date,r.start_half_day,r.end_half_day,r.amount,r.quantity);
  return jsonb_build_object('request_id',r.id,'calculated_leave_days',days,
    'sufficient_leave_balance',enough_balance, 'blocking_issues',issues,
    'conflicting_request_ids',conflicts,'possible_duplicate_ids',duplicates,
    'requires_human_review',cardinality(duplicates) > 0 or cardinality(issues) > 0);
end $$;

revoke all on function public.prepare_hr_approvals(uuid),
  public.queue_hr_approval_reminders(timestamptz), public.get_hr_request_checks(uuid)
  from public, anon, authenticated;
grant execute on function public.prepare_hr_approvals(uuid),
  public.queue_hr_approval_reminders(timestamptz), public.get_hr_request_checks(uuid) to service_role;
