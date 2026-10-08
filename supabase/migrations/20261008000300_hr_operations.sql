-- Invariants applicables aussi au backend n8n (service_role).
create function private.guard_profile_manager() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.manager_id is not null and not exists (
    select 1 from public.profiles where id = new.manager_id and role = 'manager'
  ) then raise exception 'Le responsable doit avoir le rôle manager.' using errcode = '23514'; end if;
  if new.manager_id is not null and exists (
    with recursive chain as (
      select id, manager_id, array[id] as visited from public.profiles where id = new.manager_id
      union all
      select p.id, p.manager_id, c.visited || p.id from public.profiles p
        join chain c on p.id = c.manager_id where not p.id = any(c.visited)
    ) select 1 from chain where id = new.id
  ) then raise exception 'Cycle dans la hiérarchie des managers.' using errcode = '23514'; end if;
  if tg_op = 'UPDATE' and old.role = 'manager' and new.role <> 'manager' and exists (
    select 1 from public.profiles where manager_id = new.id
  ) then raise exception 'Réaffecter les salariés avant de changer le rôle du manager.' using errcode = '23514'; end if;
  return new;
end $$;
create trigger profiles_manager_guard before insert or update on public.profiles
  for each row execute function private.guard_profile_manager();

create function private.guard_approval_rule() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if exists (select 1 from public.requests where approval_rule_id = old.id) and
    (to_jsonb(new) - 'active') is distinct from (to_jsonb(old) - 'active') then
    raise exception 'Une règle utilisée est figée : créer une nouvelle version.' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger approval_rule_guard before update on public.approval_rules
  for each row execute function private.guard_approval_rule();

create function private.guard_request() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare rule public.approval_rules; needs_director boolean;
begin
  if tg_op = 'INSERT' then
    if new.status <> 'draft' then raise exception 'Créer un brouillon avant de soumettre.' using errcode = '23514'; end if;
    new.manager_id := null;
    new.approval_rule_id := null;
    new.submitted_at := null;
    new.completed_at := null;
    new.created_at := now();
  else
    if (new.id, new.requester_id, new.reference, new.created_at, new.request_type)
       is distinct from (old.id, old.requester_id, old.reference, old.created_at, old.request_type) then
      raise exception 'Identité de la demande immuable.' using errcode = '23514';
    end if;
    if old.status <> 'draft' and
      (new.title, new.description, new.start_date, new.end_date, new.requested_days,
       new.amount, new.currency, new.quantity, new.training_provider, new.manager_id, new.approval_rule_id, new.submitted_at)
      is distinct from
      (old.title, old.description, old.start_date, old.end_date, old.requested_days,
       old.amount, old.currency, old.quantity, old.training_provider, old.manager_id, old.approval_rule_id, old.submitted_at) then
      raise exception 'Le contenu soumis est figé.' using errcode = '23514';
    end if;
    if new.status <> old.status then
      if not (
        (old.status = 'draft' and new.status in ('submitted', 'cancelled')) or
        (old.status = 'submitted' and new.status in ('under_review', 'cancelled')) or
        (old.status = 'under_review' and new.status in ('pending_approval', 'cancelled')) or
        (old.status = 'pending_approval' and new.status in ('approved', 'rejected', 'cancelled'))
      ) then raise exception 'Transition de statut interdite.' using errcode = '23514'; end if;
      if new.status = 'submitted' then
        select * into rule from public.approval_rules
          where id = new.approval_rule_id and request_type = new.request_type and active for share;
        if not found then raise exception 'Aucune règle active pour ce type.' using errcode = '23514'; end if;
        if not exists (select 1 from public.request_types where code = new.request_type and active) then
          raise exception 'Type de demande désactivé.' using errcode = '23514';
        end if;
        select manager_id into new.manager_id from public.profiles where id = new.requester_id;
        if new.manager_id is null or new.manager_id = new.requester_id or not exists (
          select 1 from public.profiles where id = new.manager_id and role = 'manager'
        ) then raise exception 'Affecter un manager valide avant soumission.' using errcode = '23514'; end if;
        new.submitted_at := now();
      end if;
      if new.status = 'pending_approval' then
        if not exists (select 1 from public.ai_reviews where request_id = new.id and status = 'succeeded') then
          raise exception 'Un contrôle IA terminé est nécessaire.' using errcode = '23514';
        end if;
        select * into rule from public.approval_rules where id = new.approval_rule_id;
        needs_director := coalesce(new.amount > rule.director_amount_above, false)
          or coalesce(new.requested_days > rule.director_days_above, false);
        if not exists (select 1 from public.approval_steps where request_id = new.id and required_role = 'manager')
          or not exists (select 1 from public.approval_steps where request_id = new.id and required_role = 'hr')
          or (needs_director and not exists (
            select 1 from public.approval_steps where request_id = new.id and required_role = 'director'
          )) then raise exception 'Circuit de validation incomplet.' using errcode = '23514'; end if;
      end if;
      if new.status = 'approved' then
        select * into rule from public.approval_rules where id = new.approval_rule_id;
        needs_director := coalesce(new.amount > rule.director_amount_above, false)
          or coalesce(new.requested_days > rule.director_days_above, false);
        if not exists (select 1 from public.approval_steps where request_id = new.id and required_role = 'manager' and status = 'approved')
          or not exists (select 1 from public.approval_steps where request_id = new.id and required_role = 'hr' and status = 'approved')
          or (needs_director and not exists (
            select 1 from public.approval_steps where request_id = new.id and required_role = 'director' and status = 'approved'
          ))
          or exists (select 1 from public.approval_steps where request_id = new.id and status in ('waiting', 'pending', 'rejected'))
          then raise exception 'Toutes les validations requises doivent être approuvées.' using errcode = '23514'; end if;
      end if;
      if new.status = 'rejected' and not exists (
        select 1 from public.approval_steps where request_id = new.id and status = 'rejected'
      ) then raise exception 'Un refus tracé est nécessaire.' using errcode = '23514'; end if;
    end if;
    -- Même un UPDATE sans changement de statut ne peut réécrire les horodatages métier.
    if new.status = old.status then
      new.submitted_at := old.submitted_at;
      new.completed_at := old.completed_at;
      new.manager_id := old.manager_id;
      new.approval_rule_id := old.approval_rule_id;
    end if;
  end if;
  if new.status in ('approved', 'rejected', 'cancelled') and (tg_op = 'INSERT' or new.status <> old.status) then
    new.completed_at := now();
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger request_guard before insert or update on public.requests
  for each row execute function private.guard_request();

alter table public.approval_steps add column decided_by uuid references public.profiles(id) on delete restrict;
alter table public.approval_steps add constraint approval_decider
  check ((status in ('approved', 'rejected')) = (decided_by is not null));
create function private.guard_approval_step() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare r public.requests; hours integer;
begin
  select * into r from public.requests where id = new.request_id for update;
  if r.status not in ('under_review', 'pending_approval') then
    raise exception 'La demande ne peut pas recevoir de validation dans cet état.' using errcode = '23514';
  end if;
  if new.assignee_id = r.requester_id or not exists (
    select 1 from public.profiles where id = new.assignee_id and role = new.required_role
  ) or (new.required_role = 'manager' and new.assignee_id <> r.manager_id) then
    raise exception 'Validateur incompatible ou auto-approbation.' using errcode = '23514';
  end if;
  if tg_op = 'INSERT' then
    if new.status <> 'waiting' then raise exception 'Une étape commence en attente.' using errcode = '23514'; end if;
  else
    if (new.id, new.request_id, new.position, new.required_role, new.assignee_id, new.created_at)
      is distinct from (old.id, old.request_id, old.position, old.required_role, old.assignee_id, old.created_at) then
      raise exception 'Affectation de validation figée.' using errcode = '23514';
    end if;
    if new.status <> old.status then
      if not ((old.status = 'waiting' and new.status in ('pending', 'skipped')) or
        (old.status = 'pending' and new.status in ('approved', 'rejected'))) then
        raise exception 'Décision déjà prise ou transition interdite.' using errcode = '23514';
      end if;
      if new.status = 'skipped' and (new.required_role <> 'director' or exists (
        select 1 from public.approval_rules a where a.id = r.approval_rule_id and
          (coalesce(r.amount > a.director_amount_above, false) or coalesce(r.requested_days > a.director_days_above, false))
      )) then raise exception 'Une validation obligatoire ne peut pas être ignorée.' using errcode = '23514'; end if;
      if new.status = 'pending' then
        if r.status <> 'pending_approval' or (new.position > 1 and not exists (
          select 1 from public.approval_steps where request_id = new.request_id
            and position = new.position - 1 and status = 'approved'
        )) or exists (
          select 1 from public.approval_steps where request_id = new.request_id and position < new.position and status <> 'approved'
        ) then raise exception 'Respecter les validations successives.' using errcode = '23514'; end if;
        select decision_hours into hours from public.approval_rules where id = r.approval_rule_id;
        new.activated_at := now();
        new.due_at := now() + make_interval(hours => hours);
      end if;
      if new.status in ('approved', 'rejected') then
        if new.decided_by is distinct from new.assignee_id then
          raise exception 'Seul le validateur affecté peut décider.' using errcode = '23514';
        end if;
        new.activated_at := old.activated_at;
        new.due_at := old.due_at;
        new.decided_at := now();
      end if;
    else
      if to_jsonb(new) is distinct from to_jsonb(old) then
        raise exception 'Une étape ne se modifie que par transition de statut.' using errcode = '23514';
      end if;
    end if;
  end if;
  return new;
end $$;
create trigger approval_step_guard before insert or update on public.approval_steps
  for each row execute function private.guard_approval_step();

create function private.audit_request() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare event_id bigint;
begin
  if tg_op = 'INSERT' then
    insert into public.request_events(request_id, actor_id, event_type, new_status)
      values (new.id, auth.uid(), 'created', new.status);
  elsif new.status <> old.status then
    insert into public.request_events(request_id, actor_id, event_type, old_status, new_status)
      values (new.id, auth.uid(), 'status_changed', old.status, new.status) returning id into event_id;
    insert into public.notifications(request_id, recipient_id, event_id, kind, deduplication_key)
      values (new.id, new.requester_id, event_id, 'status_change', 'event:' || event_id || ':email');
  elsif (to_jsonb(new) - 'updated_at') is distinct from (to_jsonb(old) - 'updated_at') then
    insert into public.request_events(request_id, actor_id, event_type)
      values (new.id, auth.uid(), 'edited');
  end if;
  return new;
end $$;
create trigger request_audit after insert or update on public.requests
  for each row execute function private.audit_request();

create function private.audit_approval() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.status <> old.status and new.status = 'pending' then
    insert into public.notifications(request_id, recipient_id, approval_step_id, kind, deduplication_key)
      values(new.request_id, new.assignee_id, new.id, 'approval_needed', 'step:' || new.id || ':email');
  elsif new.status <> old.status and new.status in ('approved', 'rejected') then
    insert into public.request_events(request_id, actor_id, event_type, approval_step_id, comment)
      values(new.request_id, new.decided_by, 'approval_decided', new.id, new.decision_comment);
  end if;
  return new;
end $$;
create trigger approval_audit after update on public.approval_steps
  for each row execute function private.audit_approval();

create function private.audit_balance() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.leave_balance_history(balance_id, actor_id, old_values, new_values)
    values (new.id, auth.uid(), case when tg_op = 'UPDATE' then to_jsonb(old) end, to_jsonb(new));
  return new;
end $$;
-- AFTER pour que la FK du journal voie le nouveau solde ; updated_at se règle séparément.
create function private.touch_balance() returns trigger
language plpgsql set search_path = ''
as $$ begin new.updated_at := now(); return new; end $$;
create trigger balance_touch before update on public.leave_balances for each row execute function private.touch_balance();
create trigger balance_audit after insert or update on public.leave_balances for each row execute function private.audit_balance();

create function private.guard_related_data() returns trigger
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
      select 1 from public.approval_steps where id = new.approval_step_id and request_id = new.request_id
        and assignee_id = new.recipient_id
    ) then raise exception 'Validation ou destinataire incompatible.' using errcode = '23514'; end if;
  end if;
  return new;
end $$;
create trigger ai_review_related before insert or update on public.ai_reviews
  for each row execute function private.guard_related_data();
create trigger attachment_related before insert on public.request_attachments
  for each row execute function private.guard_related_data();
create trigger notification_related before insert or update on public.notifications
  for each row execute function private.guard_related_data();

-- RPC utilisateur : aucune permission directe sur les statuts ou sur les décisions.
create function public.submit_hr_request(p_request_id uuid) returns public.requests
language plpgsql security definer set search_path = ''
as $$
declare r public.requests; rule_id uuid;
begin
  select * into r from public.requests where id = p_request_id
    and requester_id = auth.uid() and status = 'draft' for update;
  if not found then raise exception 'Brouillon introuvable ou non autorisé.' using errcode = '42501'; end if;
  select id into rule_id from public.approval_rules where request_type = r.request_type and active for share;
  if not found then raise exception 'Configurer et activer le circuit de validation avant soumission.' using errcode = '23514'; end if;
  update public.requests set status = 'submitted', approval_rule_id = rule_id
    where id = r.id returning * into r;
  return r;
end $$;

create function public.cancel_hr_request(p_request_id uuid) returns public.requests
language plpgsql security definer set search_path = ''
as $$
declare r public.requests;
begin
  select * into r from public.requests where id = p_request_id and requester_id = auth.uid()
    and status in ('draft', 'submitted', 'under_review', 'pending_approval') for update;
  if not found then raise exception 'Demande non annulable ou non autorisée.' using errcode = '42501'; end if;
  update public.requests set status = 'cancelled' where id = r.id returning * into r;
  return r;
end $$;

create function public.decide_hr_approval(p_step_id uuid, p_approve boolean, p_comment text default null)
returns public.approval_steps language plpgsql security definer set search_path = ''
as $$
declare s public.approval_steps; request_id uuid;
begin
  -- Toujours verrouiller la demande avant l'étape : même ordre que les transitions backend.
  select a.request_id into request_id from public.approval_steps a where a.id = p_step_id;
  perform 1 from public.requests r where r.id = request_id for update;
  select * into s from public.approval_steps where id = p_step_id and assignee_id = auth.uid()
    and required_role = private.current_app_role() and status = 'pending' for update;
  if not found then raise exception 'Validation non autorisée ou déjà traitée.' using errcode = '42501'; end if;
  if p_approve is null then raise exception 'Une décision est obligatoire.' using errcode = '23514'; end if;
  if not p_approve and coalesce(length(btrim(p_comment)), 0) = 0 then
    raise exception 'Motiver le refus.' using errcode = '23514';
  end if;
  update public.approval_steps set status = case when p_approve then 'approved'::public.approval_status else 'rejected'::public.approval_status end,
    decided_by = auth.uid(), decision_comment = p_comment where id = s.id returning * into s;
  return s;
end $$;

-- Le backend reste l'orchestrateur : il active les étapes, traite les relances et termine la demande.
create function public.transition_hr_request(p_request_id uuid, p_status public.request_status)
returns public.requests language plpgsql security definer set search_path = ''
as $$
declare r public.requests;
begin
  update public.requests set status = p_status where id = p_request_id returning * into r;
  if not found then raise exception 'Demande introuvable.' using errcode = 'P0002'; end if;
  return r;
end $$;

revoke all on all functions in schema private from public, anon;
revoke all on function public.submit_hr_request(uuid), public.cancel_hr_request(uuid),
  public.decide_hr_approval(uuid, boolean, text), public.transition_hr_request(uuid, public.request_status)
  from public, anon, authenticated, service_role;
grant execute on function public.submit_hr_request(uuid), public.cancel_hr_request(uuid),
  public.decide_hr_approval(uuid, boolean, text) to authenticated;
grant execute on function public.transition_hr_request(uuid, public.request_status) to service_role;
-- Les fonctions de trigger n'ont pas à être exécutables via un client.
revoke all on function private.guard_profile_manager(), private.guard_approval_rule(), private.guard_request(),
  private.guard_approval_step(), private.audit_request(), private.audit_approval(), private.audit_balance(),
  private.touch_balance(), private.guard_related_data() from authenticated, service_role;
