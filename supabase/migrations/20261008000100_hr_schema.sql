-- Structure du cycle RH. Les seuils métier restent configurables et non activés.
create schema if not exists private;
revoke all on schema private from public;

create type public.request_status as enum
  ('draft', 'submitted', 'under_review', 'pending_approval', 'approved', 'rejected', 'cancelled');
create type public.approval_status as enum ('waiting', 'pending', 'approved', 'rejected', 'skipped');
create type public.execution_status as enum ('running', 'succeeded', 'failed');
create type public.ai_qualification as enum ('eligible', 'needs_review', 'invalid');
create type public.notification_channel as enum ('email', 'slack');
create type public.delivery_status as enum ('queued', 'sending', 'sent', 'failed');

create table public.request_types (
  code text primary key check (code in ('leave', 'remote_work', 'equipment', 'training')),
  label text not null,
  active boolean not null default true
);
insert into public.request_types (code, label) values
  ('leave', 'Congés'), ('remote_work', 'Télétravail'), ('equipment', 'Matériel'), ('training', 'Formation');

create table public.approval_rules (
  id uuid primary key default gen_random_uuid(),
  request_type text not null references public.request_types(code),
  version integer not null check (version > 0),
  name text not null check (length(btrim(name)) between 1 and 160),
  active boolean not null default false,
  director_amount_above numeric(12,2) check (director_amount_above >= 0),
  director_days_above numeric(6,2) check (director_days_above >= 0),
  decision_hours integer check (decision_hours > 0),
  reminder_hours integer check (reminder_hours > 0),
  created_at timestamptz not null default now(),
  unique (request_type, version),
  check (reminder_hours is null or decision_hours is null or reminder_hours <= decision_hours),
  check (not active or (decision_hours is not null and reminder_hours is not null))
);
create unique index approval_rules_one_active on public.approval_rules(request_type) where active;
-- Manager puis RH systématiquement ; le DRH intervient au-delà d'un seuil configuré.
-- NULL signifie absence de seuil de cette nature, pas une valeur imposée par le PDF.
insert into public.approval_rules(request_type, version, name)
  select code, 1, 'Circuit à configurer : ' || label from public.request_types;

create table public.leave_balances (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete restrict,
  year integer not null check (year between 2000 and 2200),
  allocated_days numeric(6,2) not null default 0 check (allocated_days >= 0),
  consumed_days numeric(6,2) not null default 0 check (consumed_days >= 0),
  reserved_days numeric(6,2) not null default 0 check (reserved_days >= 0),
  available_days numeric(6,2) generated always as (allocated_days - consumed_days - reserved_days) stored,
  updated_at timestamptz not null default now(),
  unique (employee_id, year),
  check (consumed_days + reserved_days <= allocated_days)
);
create table public.leave_balance_history (
  id bigint generated always as identity primary key,
  balance_id uuid not null references public.leave_balances(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  old_values jsonb,
  new_values jsonb not null,
  recorded_at timestamptz not null default now()
);

create table public.requests (
  id uuid primary key default gen_random_uuid(),
  reference bigint generated always as identity unique,
  requester_id uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  manager_id uuid references public.profiles(id) on delete restrict,
  request_type text not null references public.request_types(code),
  status public.request_status not null default 'draft',
  title text not null check (length(btrim(title)) between 1 and 160),
  description text not null default '' check (length(description) <= 8000),
  start_date date,
  end_date date,
  requested_days numeric(6,2) check (requested_days > 0),
  amount numeric(12,2) check (amount >= 0),
  currency text not null default 'EUR' check (currency = 'EUR'),
  quantity integer check (quantity > 0),
  training_provider text check (length(training_provider) <= 200),
  approval_rule_id uuid references public.approval_rules(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  submitted_at timestamptz,
  completed_at timestamptz,
  check ((start_date is null) = (end_date is null)),
  check (end_date >= start_date),
  check (requested_days is null or request_type = 'leave'),
  check (quantity is null or request_type = 'equipment'),
  check (training_provider is null or request_type = 'training'),
  check (amount is null or request_type in ('equipment', 'training')),
  check (request_type <> 'equipment' or start_date is null),
  check (status in ('draft', 'cancelled') or (submitted_at is not null and approval_rule_id is not null and manager_id is not null)),
  check (status in ('draft', 'cancelled') or
    case request_type
      when 'leave' then start_date is not null and requested_days is not null
      when 'remote_work' then start_date is not null
      when 'equipment' then amount is not null and quantity is not null
      when 'training' then amount is not null and start_date is not null
    end),
  check ((status in ('approved', 'rejected', 'cancelled')) = (completed_at is not null))
);
create index requests_requester_created on public.requests(requester_id, created_at desc);
create index requests_manager_status on public.requests(manager_id, status);
create index requests_status_submitted on public.requests(status, submitted_at);
create index requests_type on public.requests(request_type);
create index requests_rule on public.requests(approval_rule_id);

create table public.approval_steps (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.requests(id) on delete cascade,
  position smallint not null check (position between 1 and 3),
  required_role public.app_role not null check (required_role in ('manager', 'hr', 'director')),
  assignee_id uuid not null references public.profiles(id) on delete restrict,
  status public.approval_status not null default 'waiting',
  activated_at timestamptz,
  due_at timestamptz,
  decided_at timestamptz,
  decision_comment text check (length(decision_comment) <= 4000),
  created_at timestamptz not null default now(),
  unique (request_id, position),
  unique (request_id, required_role),
  check ((position = 1 and required_role = 'manager') or
         (position = 2 and required_role = 'hr') or
         (position = 3 and required_role = 'director')),
  check (due_at is null or (activated_at is not null and due_at > activated_at)),
  check (status <> 'pending' or (activated_at is not null and due_at is not null)),
  check ((status in ('approved', 'rejected')) = (decided_at is not null)),
  check (status <> 'rejected' or coalesce(length(btrim(decision_comment)), 0) > 0)
);
create index approval_steps_assignee_status on public.approval_steps(assignee_id, status, due_at);

create table public.request_events (
  id bigint generated always as identity primary key,
  request_id uuid not null references public.requests(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  event_type text not null check (event_type in ('created', 'edited', 'status_changed', 'approval_decided')),
  old_status public.request_status,
  new_status public.request_status,
  approval_step_id uuid references public.approval_steps(id) on delete set null,
  comment text check (length(comment) <= 4000),
  occurred_at timestamptz not null default now()
);
create index request_events_request_time on public.request_events(request_id, occurred_at, id);

create table public.request_attachments (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.requests(id) on delete cascade,
  uploaded_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  filename text not null check (length(btrim(filename)) between 1 and 255),
  mime_type text not null check (length(mime_type) between 1 and 160),
  size_bytes bigint not null check (size_bytes between 1 and 10485760),
  storage_path text not null unique,
  created_at timestamptz not null default now(),
  check (storage_path = request_id::text || '/' || id::text)
);
create index attachments_request on public.request_attachments(request_id);

create table public.workflow_runs (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.requests(id) on delete cascade,
  workflow_key text not null check (length(workflow_key) between 1 and 160),
  execution_id text not null check (length(execution_id) between 1 and 160),
  status public.execution_status not null default 'running',
  attempt integer not null default 1 check (attempt > 0),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  error_code text,
  error_message text check (length(error_message) <= 2000),
  unique(workflow_key, execution_id),
  check ((status <> 'running') = (finished_at is not null)),
  check (finished_at >= started_at)
);
create index workflow_runs_request on public.workflow_runs(request_id, started_at desc);
create index workflow_runs_status on public.workflow_runs(status, started_at);

create table public.ai_reviews (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.requests(id) on delete cascade,
  workflow_run_id uuid references public.workflow_runs(id) on delete set null,
  status public.execution_status not null default 'running',
  provider text not null,
  model text not null,
  prompt_version text not null,
  checks jsonb not null default '{}'::jsonb check (jsonb_typeof(checks) = 'object'),
  qualification public.ai_qualification,
  summary text check (length(summary) <= 8000),
  response_draft text check (length(response_draft) <= 8000),
  input_tokens integer not null default 0 check (input_tokens >= 0),
  output_tokens integer not null default 0 check (output_tokens >= 0),
  cost_amount numeric(12,6) not null default 0 check (cost_amount >= 0),
  cost_currency text not null default 'EUR' check (cost_currency in ('EUR', 'USD')),
  error_code text,
  error_message text check (length(error_message) <= 2000),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  check ((status <> 'running') = (finished_at is not null)),
  check (finished_at >= started_at),
  check (status <> 'succeeded' or (qualification is not null and summary is not null))
);
create index ai_reviews_request on public.ai_reviews(request_id, started_at desc);
create index ai_reviews_run on public.ai_reviews(workflow_run_id);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.requests(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete restrict,
  event_id bigint references public.request_events(id) on delete cascade,
  approval_step_id uuid references public.approval_steps(id) on delete cascade,
  kind text not null check (kind in ('status_change', 'approval_needed', 'reminder')),
  channel public.notification_channel not null default 'email',
  status public.delivery_status not null default 'queued',
  deduplication_key text not null unique check (length(deduplication_key) between 1 and 300),
  attempts integer not null default 0 check (attempts >= 0),
  next_attempt_at timestamptz not null default now(),
  provider_message_id text,
  last_error text check (length(last_error) <= 2000),
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  check ((status = 'sent') = (sent_at is not null)),
  check (kind <> 'status_change' or event_id is not null),
  check (kind = 'status_change' or approval_step_id is not null)
);
create index notifications_recipient on public.notifications(recipient_id, created_at desc);
create index notifications_queue on public.notifications(status, next_attempt_at) where status in ('queued', 'failed');
create index notifications_request on public.notifications(request_id);
create index notifications_event on public.notifications(event_id);
create index notifications_step on public.notifications(approval_step_id);

-- Mesures manuelles avant/après pour comparer au délai réel des demandes horodatées.
create table public.process_measurements (
  id uuid primary key default gen_random_uuid(),
  phase text not null check (phase in ('before', 'after')),
  period_start date not null,
  period_end date not null check (period_end >= period_start),
  sample_size integer not null check (sample_size > 0),
  average_processing_hours numeric(12,2) not null check (average_processing_hours >= 0),
  cost_per_request_eur numeric(12,2) check (cost_per_request_eur >= 0),
  measurement_method text not null check (length(btrim(measurement_method)) between 1 and 2000),
  recorded_at timestamptz not null default now()
);
create index profiles_manager on public.profiles(manager_id);
