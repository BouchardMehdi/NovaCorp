-- S5 : un accueil par nouveau profil, sans rattrapage des comptes deja existants.
create table public.employee_onboardings (
 id uuid primary key default gen_random_uuid(),
 employee_id uuid not null unique references public.profiles(id) on delete cascade,
 checklist jsonb not null check(jsonb_typeof(checklist)='array' and jsonb_array_length(checklist)>0),
 status public.delivery_status not null default 'queued',
 attempts integer not null default 0 check(attempts between 0 and 5),
 created_at timestamptz not null default now(),
 next_attempt_at timestamptz not null default now(),
 lease_token uuid,
 lease_until timestamptz,
 sent_at timestamptz,
 provider_message_id text,
 last_error text,
 check((status='sent')=(sent_at is not null))
);
create index employee_onboardings_queue on public.employee_onboardings(status,next_attempt_at)
 where status in ('queued','failed','sending');
alter table public.employee_onboardings enable row level security;
revoke all on public.employee_onboardings from public,anon,authenticated;
grant all on public.employee_onboardings to service_role;

create function private.queue_employee_onboarding() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 insert into public.employee_onboardings(employee_id,checklist) values(new.id,
  '["Confirmer avec les RH les horaires et le lieu de votre accueil.",
    "Rencontrer votre manager et votre équipe.",
    "Vérifier votre accès à l’espace RH et aux outils de travail.",
    "Récupérer votre matériel et vérifier son fonctionnement.",
    "Prendre connaissance des consignes internes et de sécurité.",
    "Faire le point avec votre manager sur vos premières missions."]'::jsonb)
 on conflict(employee_id) do nothing;
 return new;
end $$;
revoke all on function private.queue_employee_onboarding() from public,anon,authenticated,service_role;
create trigger on_profile_created_onboarding after insert on public.profiles
 for each row execute function private.queue_employee_onboarding();

create function public.claim_employee_onboarding(p_employee_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.employee_onboardings; email text; first_name text; checklist_text text;
begin
 for d in select * from public.employee_onboardings where
  (p_employee_id is null or employee_id=p_employee_id) and
  ((status in ('queued','failed') and next_attempt_at<=now() and attempts<5) or
   (status='sending' and lease_until<=now()))
  order by created_at,id for update skip locked
 loop
  if d.attempts>=5 then
   update public.employee_onboardings set status='failed',next_attempt_at='infinity',
    last_error='Dernière réservation SMTP expirée ; vérification manuelle nécessaire.' where id=d.id; continue;
  end if;
  select u.email,p.first_name into email,first_name from auth.users u join public.profiles p on p.id=u.id where u.id=d.employee_id;
  if email is null or btrim(email)='' then
   update public.employee_onboardings set status='failed',next_attempt_at='infinity',
    last_error='Adresse du nouvel employé absente.' where id=d.id; continue;
  end if;
  select string_agg('[ ] '||item,E'\n' order by position) into checklist_text
   from jsonb_array_elements_text(d.checklist) with ordinality as tasks(item,position);
  update public.employee_onboardings set status='sending',attempts=attempts+1,
   lease_token=gen_random_uuid(),lease_until=now()+interval '5 minutes',last_error=null
   where id=d.id returning * into d;
  return jsonb_build_object('claimed',true,'notification_id',d.id,'lease_token',d.lease_token,'to',email,
   'subject','Bienvenue chez NovaCorp !','text',
   case when btrim(coalesce(first_name,''))='' then 'Bonjour,' else 'Bonjour '||first_name||',' end||
   E'\n\nBienvenue chez NovaCorp ! Votre espace RH est prêt.\n\nChecklist du premier jour :\n'||checklist_text||
   E'\n\nVotre manager et les RH peuvent vous accompagner pour ces étapes.\nAccéder à votre espace RH : http://localhost:3000/connexion\nUtilisez les modalités de connexion communiquées séparément par les RH.');
 end loop;
 return jsonb_build_object('claimed',false);
end $$;

create function public.finish_employee_onboarding(p_notification_id uuid,p_lease_token uuid,p_sent boolean,p_message_id text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.employee_onboardings;
begin
 select * into d from public.employee_onboardings where id=p_notification_id for update;
 if d.id is null or p_lease_token is null or d.lease_token is distinct from p_lease_token then return jsonb_build_object('recorded',false); end if;
 if d.status='sent' then return jsonb_build_object('recorded',true,'replayed',true); end if;
 if d.status<>'sending' or p_sent is null then return jsonb_build_object('recorded',false); end if;
 if p_sent then
  update public.employee_onboardings set status='sent',sent_at=now(),provider_message_id=left(p_message_id,300),last_error=null where id=d.id;
 else
  update public.employee_onboardings set status='failed',next_attempt_at=case when attempts>=5 then 'infinity'::timestamptz
   else now()+make_interval(mins=>attempts) end,last_error='Échec SMTP ; envoi à réessayer.' where id=d.id;
 end if;
 return jsonb_build_object('recorded',true);
end $$;
revoke all on function public.claim_employee_onboarding(uuid),public.finish_employee_onboarding(uuid,uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.claim_employee_onboarding(uuid),public.finish_employee_onboarding(uuid,uuid,boolean,text) to service_role;
