-- Choix métier validés pour NovaCorp, distincts des exigences non chiffrées du PDF.
-- Nouvelle version : les circuits déjà utilisés restent intacts.
update public.approval_rules set active = false where active;
insert into public.approval_rules
  (request_type, version, name, active, director_amount_above, director_days_above, decision_hours, reminder_hours)
select t.code, coalesce((select max(version) from public.approval_rules where request_type = t.code), 0) + 1,
  'Circuit validé : ' || t.label, true,
  case t.code when 'equipment' then 1000 when 'training' then 1500 end,
  case t.code when 'leave' then 10 end, 48, 24
from public.request_types t;

create table public.hr_routing_settings (
  singleton boolean primary key default true check (singleton),
  hr_referent_id uuid not null references public.profiles(id) on delete restrict,
  director_referent_id uuid not null references public.profiles(id) on delete restrict,
  alternate_hr_id uuid references public.profiles(id) on delete restrict,
  alternate_director_id uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  check (hr_referent_id is distinct from alternate_hr_id),
  check (director_referent_id is distinct from alternate_director_id)
);
alter table public.hr_routing_settings enable row level security;
revoke all on public.hr_routing_settings from anon, authenticated;
grant select on public.hr_routing_settings to authenticated;
grant select, insert, update on public.hr_routing_settings to service_role;
create policy routing_settings_read on public.hr_routing_settings for select to authenticated
  using (private.current_app_role() in ('hr', 'director'));

alter table public.requests
  add column start_half_day boolean not null default false,
  add column end_half_day boolean not null default false,
  add column hr_referent_id uuid references public.profiles(id) on delete restrict,
  add column director_referent_id uuid references public.profiles(id) on delete restrict,
  add constraint half_days_leave_only check (
    (not start_half_day and not end_half_day) or request_type = 'leave'
  ),
  add constraint half_days_have_dates check (
    (not start_half_day or start_date is not null) and (not end_half_day or end_date is not null)
  ),
  add constraint same_day_not_empty check (
    not (start_date = end_date and start_half_day and end_half_day)
  );
grant insert (start_half_day, end_half_day), update (start_half_day, end_half_day)
  on public.requests to authenticated;

create table public.leave_allocations (
  request_id uuid not null references public.requests(id) on delete cascade,
  balance_id uuid not null references public.leave_balances(id) on delete restrict,
  days numeric(6,2) not null check (days > 0 and mod(days, 0.5) = 0),
  state text not null default 'reserved' check (state in ('reserved', 'consumed', 'released')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(request_id, balance_id)
);
create index leave_allocations_balance on public.leave_allocations(balance_id);
alter table public.leave_allocations enable row level security;
revoke all on public.leave_allocations from anon, authenticated, service_role;
grant select on public.leave_allocations to authenticated, service_role;
create policy leave_allocations_read on public.leave_allocations for select to authenticated
  using (private.can_read_request(request_id));
-- Les écritures se font exclusivement dans le trigger transactionnel ci-dessous.

create function private.guard_routing_settings() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if not exists (select 1 from public.profiles where id = new.hr_referent_id and role = 'hr')
    or not exists (select 1 from public.profiles where id = new.director_referent_id and role = 'director')
    or (new.alternate_hr_id is not null and not exists (
      select 1 from public.profiles where id = new.alternate_hr_id and role = 'hr'))
    or (new.alternate_director_id is not null and not exists (
      select 1 from public.profiles where id = new.alternate_director_id and role = 'director')) then
    raise exception 'Les référents et suppléants doivent avoir les rôles RH/DRH attendus.' using errcode = '23514';
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger routing_settings_guard before insert or update on public.hr_routing_settings
  for each row execute function private.guard_routing_settings();

-- Les demi-journées portent sur les bornes : départ l'après-midi, fin le matin.
-- Le calendrier de démonstration compte lundi-vendredi et ignore les jours fériés.
create function private.leave_days_by_year(p_start date, p_end date, p_start_half boolean, p_end_half boolean)
returns table(year integer, days numeric)
language sql immutable set search_path = ''
as $$
  select extract(year from d)::integer,
    sum(1::numeric - case when d::date = p_start and p_start_half then 0.5 else 0 end
      - case when d::date = p_end and p_end_half then 0.5 else 0 end)
  from generate_series(p_start::timestamp, p_end::timestamp, interval '1 day') d
  where extract(isodow from d) between 1 and 5
  group by 1 order by 1
$$;

create function public.calculate_leave_days(p_start date, p_end date,
  p_start_half boolean default false, p_end_half boolean default false) returns numeric
language plpgsql immutable security definer set search_path = ''
as $$
declare total numeric;
begin
  if p_start is null or p_end is null or p_start_half is null or p_end_half is null or p_end < p_start
    or extract(year from p_start) < 2000 or extract(year from p_end) > 2200 then
    raise exception 'Période de congés invalide (années prises en charge : 2000–2200).' using errcode = '23514';
  end if;
  if (p_start_half and extract(isodow from p_start) > 5)
    or (p_end_half and extract(isodow from p_end) > 5)
    or (p_start = p_end and p_start_half and p_end_half) then
    raise exception 'Demi-journée incohérente.' using errcode = '23514';
  end if;
  select coalesce(sum(days), 0) into total
    from private.leave_days_by_year(p_start, p_end, p_start_half, p_end_half);
  if total <= 0 then raise exception 'La période doit contenir un jour ouvré.' using errcode = '23514'; end if;
  return total;
end $$;
-- Calcul sans accès aux données personnelles : seule la fonction publique bornée est exposée.

create function private.conflicting_requests(p_id uuid, p_employee uuid, p_start date, p_end date,
  p_start_half boolean, p_end_half boolean) returns uuid[]
language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(r.id order by r.id), '{}'::uuid[])
  from public.requests r
  where r.id <> p_id and r.requester_id = p_employee
    and r.request_type in ('leave', 'remote_work')
    and r.status in ('submitted', 'under_review', 'pending_approval', 'approved')
    and r.start_date is not null
    and tsrange(r.start_date::timestamp + case when r.start_half_day then interval '12 hours' else interval '0' end,
      r.end_date::timestamp + case when r.end_half_day then interval '12 hours' else interval '1 day' end, '[)')
      && tsrange(p_start::timestamp + case when p_start_half then interval '12 hours' else interval '0' end,
        p_end::timestamp + case when p_end_half then interval '12 hours' else interval '1 day' end, '[)')
    and exists (
      select 1 from generate_series(greatest(r.start_date, p_start)::timestamp,
        least(r.end_date, p_end)::timestamp, interval '1 day') d
        where extract(isodow from d) between 1 and 5
    )
$$;

create function private.apply_request_business_rules() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare settings public.hr_routing_settings; rule public.approval_rules; part record;
  balance public.leave_balances; allocation record; needs_director boolean; conflicts uuid[];
begin
  if tg_op = 'INSERT' then
    new.hr_referent_id := null;
    new.director_referent_id := null;
    return new;
  end if;
  if old.status <> 'draft' and
    (new.start_half_day, new.end_half_day, new.hr_referent_id, new.director_referent_id)
      is distinct from (old.start_half_day, old.end_half_day, old.hr_referent_id, old.director_referent_id) then
    raise exception 'Demi-journées et référents de la demande soumise sont figés.' using errcode = '23514';
  end if;
  if old.status = 'draft' and new.status = 'submitted' then
    -- Sérialise les soumissions d'un même salarié, y compris deux demandes différentes.
    perform 1 from public.profiles where id = new.requester_id for no key update;
    select * into rule from public.approval_rules
      where id = new.approval_rule_id and request_type = new.request_type and active for share;
    if not found then raise exception 'Circuit de validation indisponible.' using errcode = '23514'; end if;
    if new.request_type = 'leave' then
      new.requested_days := public.calculate_leave_days(new.start_date, new.end_date, new.start_half_day, new.end_half_day);
    end if;
    if new.request_type in ('leave', 'remote_work') and new.start_date is not null and new.end_date >= new.start_date then
      conflicts := private.conflicting_requests(new.id, new.requester_id, new.start_date, new.end_date,
        new.start_half_day, new.end_half_day);
      if cardinality(conflicts) > 0 then
        raise exception 'La période chevauche une demande active de congés ou de télétravail.' using errcode = '23514';
      end if;
    end if;
    select * into settings from public.hr_routing_settings where singleton for share;
    if not found then raise exception 'Configurer les référents RH et DRH.' using errcode = '23514'; end if;
    new.hr_referent_id := case when settings.hr_referent_id = new.requester_id
      then settings.alternate_hr_id else settings.hr_referent_id end;
    if new.hr_referent_id is null or new.hr_referent_id = new.requester_id or not exists (
      select 1 from public.profiles where id = new.hr_referent_id and role = 'hr'
    ) then raise exception 'Affecter un autre RH pour cette demande.' using errcode = '23514'; end if;
    needs_director := coalesce(new.amount > rule.director_amount_above, false)
      or coalesce(new.requested_days > rule.director_days_above, false);
    new.director_referent_id := null;
    if needs_director then
      new.director_referent_id := case when settings.director_referent_id = new.requester_id
        then settings.alternate_director_id else settings.director_referent_id end;
      if new.director_referent_id is null or new.director_referent_id = new.requester_id or not exists (
        select 1 from public.profiles where id = new.director_referent_id and role = 'director'
      ) then raise exception 'Affecter un autre DRH pour cette demande.' using errcode = '23514'; end if;
    end if;
    if new.request_type = 'leave' then
      for part in select * from private.leave_days_by_year(new.start_date, new.end_date, new.start_half_day, new.end_half_day)
      loop
        select * into balance from public.leave_balances where employee_id = new.requester_id and year = part.year for update;
        if not found or balance.available_days < part.days then
          raise exception 'Solde de congés insuffisant ou absent pour l’année %.', part.year using errcode = '23514';
        end if;
        update public.leave_balances set reserved_days = reserved_days + part.days where id = balance.id;
        insert into public.leave_allocations(request_id, balance_id, days) values(new.id, balance.id, part.days);
      end loop;
    end if;
  elsif new.status <> old.status and new.status in ('approved', 'rejected', 'cancelled') and old.request_type = 'leave' then
    perform 1 from public.profiles where id = new.requester_id for no key update;
    for allocation in select a.* from public.leave_allocations a join public.leave_balances b on b.id = a.balance_id
      where a.request_id = new.id and a.state = 'reserved' order by b.year for update of a, b
    loop
      update public.leave_balances set reserved_days = reserved_days - allocation.days,
        consumed_days = consumed_days + case when new.status = 'approved' then allocation.days else 0 end
        where id = allocation.balance_id;
      update public.leave_allocations set state = case when new.status = 'approved' then 'consumed' else 'released' end,
        updated_at = now() where request_id = new.id and balance_id = allocation.balance_id;
    end loop;
  elsif old.status = 'draft' then
    new.hr_referent_id := old.hr_referent_id;
    new.director_referent_id := old.director_referent_id;
  end if;
  return new;
end $$;
-- L'ordre alphabétique des triggers place le calcul avant request_guard et ses contraintes.
create trigger request_business_rules before insert or update on public.requests
  for each row execute function private.apply_request_business_rules();

create function private.guard_step_referents() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare r public.requests;
begin
  select * into r from public.requests where id = new.request_id;
  if (new.required_role = 'hr' and r.hr_referent_id is not null and new.assignee_id <> r.hr_referent_id)
    or (new.required_role = 'director' and r.director_referent_id is not null and new.assignee_id <> r.director_referent_id) then
    raise exception 'Respecter le référent capturé à la soumission.' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger approval_step_referents before insert or update on public.approval_steps
  for each row execute function private.guard_step_referents();

revoke all on function private.guard_routing_settings(), private.leave_days_by_year(date,date,boolean,boolean),
  private.conflicting_requests(uuid,uuid,date,date,boolean,boolean), private.apply_request_business_rules(),
  private.guard_step_referents() from public, anon;
revoke all on function private.guard_routing_settings(), private.conflicting_requests(uuid,uuid,date,date,boolean,boolean),
  private.apply_request_business_rules(), private.guard_step_referents() from authenticated, service_role;
revoke all on function public.calculate_leave_days(date,date,boolean,boolean) from public, anon;
grant execute on function public.calculate_leave_days(date,date,boolean,boolean) to authenticated, service_role;
