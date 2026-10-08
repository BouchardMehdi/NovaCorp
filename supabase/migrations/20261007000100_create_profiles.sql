-- Profils métier : l'identité et les mots de passe restent gérés par Supabase Auth.
create type public.app_role as enum ('employee', 'manager', 'hr', 'director');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  first_name text not null default '',
  last_name text not null default '',
  role public.app_role not null default 'employee',
  manager_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint manager_not_self check (manager_id is null or manager_id <> id)
);

alter table public.profiles enable row level security;
revoke all on table public.profiles from anon, authenticated;
grant select on table public.profiles to authenticated;
grant all on table public.profiles to service_role;

create policy "Les utilisateurs lisent uniquement leur profil"
  on public.profiles for select to authenticated
  using ((select auth.uid()) = id);

-- Aucun droit d'écriture côté utilisateur, en particulier sur le rôle et le manager.
-- Les comptes sont provisionnés par l'administration, sans inscription publique.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, first_name, last_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'first_name', ''),
    coalesce(new.raw_user_meta_data ->> 'last_name', '')
  );
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
