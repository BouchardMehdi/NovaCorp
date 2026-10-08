-- Permissions explicites : aucun rôle métier ne provient des métadonnées utilisateur.
create function private.current_app_role() returns public.app_role
language sql stable security definer set search_path = ''
as $$ select role from public.profiles where id = (select auth.uid()) $$;

create function private.can_read_request(p_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.requests r where r.id = p_id and (
      r.requester_id = (select auth.uid()) or
      (r.status <> 'draft' and (
        private.current_app_role() in ('hr', 'director') or
        (private.current_app_role() = 'manager' and r.manager_id = (select auth.uid())) or
        exists (select 1 from public.approval_steps s where s.request_id = r.id
          and s.assignee_id = (select auth.uid()) and s.required_role = private.current_app_role())
      ))
    )
  )
$$;

create function private.can_review_request(p_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select private.can_read_request(p_id) and exists (
    select 1 from public.requests r where r.id = p_id and r.status <> 'draft'
      and r.requester_id <> (select auth.uid())
  )
$$;

create function private.can_edit_request(p_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.requests where id = p_id
  and requester_id = (select auth.uid()) and status = 'draft') $$;

-- Un nom de fichier est strictement request_uuid/attachment_uuid.
create function private.file_request_id(p_name text) returns uuid
language sql immutable set search_path = ''
as $$ select case when p_name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  then split_part(p_name, '/', 1)::uuid else null end $$;

grant usage on schema private to authenticated;
revoke all on all functions in schema private from public, anon, authenticated;
grant execute on function private.current_app_role(), private.can_read_request(uuid),
  private.can_review_request(uuid), private.can_edit_request(uuid), private.file_request_id(text) to authenticated;

drop policy "Les utilisateurs lisent uniquement leur profil" on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using (
  id = (select auth.uid()) or
  (private.current_app_role() = 'manager' and manager_id = (select auth.uid())) or
  private.current_app_role() in ('hr', 'director')
);

do $$
declare t text;
begin
  foreach t in array array['request_types', 'approval_rules', 'leave_balances', 'leave_balance_history',
    'requests', 'approval_steps', 'request_events', 'request_attachments', 'workflow_runs',
    'ai_reviews', 'notifications', 'process_measurements']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from anon, authenticated, service_role', t);
    execute format('grant select on table public.%I to authenticated', t);
    execute format('grant select, insert, update, delete on table public.%I to service_role', t);
  end loop;
end $$;
-- Les journaux ne sont pas modifiables par les clients, y compris n8n.
revoke update, delete on public.request_events, public.leave_balance_history from service_role;
-- La suppression définitive est réservée à une future procédure de conservation exécutée par l'administrateur.
revoke delete on public.requests, public.approval_steps from service_role;
grant usage, select on sequence public.requests_reference_seq, public.request_events_id_seq,
  public.leave_balance_history_id_seq to service_role;
grant usage, select on sequence public.requests_reference_seq to authenticated;

create policy request_types_read on public.request_types for select to authenticated using (true);
create policy approval_rules_read on public.approval_rules for select to authenticated using (true);
create policy requests_read on public.requests for select to authenticated using (requester_id = (select auth.uid()) or private.can_read_request(id));
grant insert (id, requester_id, request_type, title, description, start_date, end_date, requested_days,
  amount, currency, quantity, training_provider) on public.requests to authenticated;
grant update (title, description, start_date, end_date, requested_days, amount, currency, quantity,
  training_provider) on public.requests to authenticated;
create policy requests_create on public.requests for insert to authenticated
  with check (requester_id = (select auth.uid()) and status = 'draft');
create policy requests_edit on public.requests for update to authenticated
  using (requester_id = (select auth.uid()) and status = 'draft')
  with check (requester_id = (select auth.uid()) and status = 'draft');

create policy approvals_read on public.approval_steps for select to authenticated
  using (private.can_read_request(request_id));
create policy events_read on public.request_events for select to authenticated
  using (private.can_read_request(request_id));
create policy attachments_read on public.request_attachments for select to authenticated
  using (private.can_read_request(request_id));
grant insert (id, request_id, uploaded_by, filename, mime_type, size_bytes, storage_path),
  delete on public.request_attachments to authenticated;
create policy attachments_create on public.request_attachments for insert to authenticated
  with check (uploaded_by = (select auth.uid()) and private.can_edit_request(request_id));
create policy attachments_delete on public.request_attachments for delete to authenticated
  using (uploaded_by = (select auth.uid()) and private.can_edit_request(request_id));

create policy balances_read on public.leave_balances for select to authenticated using (
  employee_id = (select auth.uid()) or private.current_app_role() in ('hr', 'director') or
  (private.current_app_role() = 'manager' and exists (
    select 1 from public.profiles p where p.id = employee_id and p.manager_id = (select auth.uid())
  ))
);
create policy balance_history_read on public.leave_balance_history for select to authenticated
  using (exists (select 1 from public.leave_balances b where b.id = balance_id));

create policy workflow_runs_read on public.workflow_runs for select to authenticated
  using (private.current_app_role() in ('hr', 'director'));
create policy ai_reviews_read on public.ai_reviews for select to authenticated
  using (private.can_review_request(request_id));
create policy notifications_read on public.notifications for select to authenticated
  using (recipient_id = (select auth.uid()) or private.current_app_role() in ('hr', 'director'));
create policy measurements_read on public.process_measurements for select to authenticated
  using (private.current_app_role() in ('hr', 'director'));

insert into storage.buckets (id, name, public, file_size_limit)
  values ('hr-attachments', 'hr-attachments', false, 10485760);
create policy hr_files_read on storage.objects for select to authenticated using (
  bucket_id = 'hr-attachments' and private.can_read_request(private.file_request_id(name))
);
create policy hr_files_upload on storage.objects for insert to authenticated with check (
  bucket_id = 'hr-attachments' and private.can_edit_request(private.file_request_id(name))
);
create policy hr_files_delete on storage.objects for delete to authenticated using (
  bucket_id = 'hr-attachments' and private.can_edit_request(private.file_request_id(name))
);
-- Pas d'UPDATE/upsert : un document existant ne doit pas être remplacé silencieusement.
-- Realtime applique les mêmes politiques SELECT aux abonnements.
alter publication supabase_realtime add table public.requests, public.approval_steps,
  public.request_events, public.notifications;
