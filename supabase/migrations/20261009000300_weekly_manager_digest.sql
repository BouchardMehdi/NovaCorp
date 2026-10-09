-- S4 : photographie hebdomadaire, file SMTP distincte des notifications par demande.
create table public.manager_weekly_digests (
 id uuid primary key default gen_random_uuid(),
 manager_id uuid not null references public.profiles(id) on delete cascade,
 week_start date not null check (extract(isodow from week_start)=1),
 snapshot_at timestamptz not null,
 received_count integer not null check(received_count>=0),
 approved_count integer not null check(approved_count>=0),
 pending_count integer not null check(pending_count>=0),
 subject text not null,
 body text not null,
 status public.delivery_status not null default 'queued',
 attempts integer not null default 0 check(attempts between 0 and 5),
 next_attempt_at timestamptz not null default now(),
 lease_token uuid,
 lease_until timestamptz,
 sent_at timestamptz,
 provider_message_id text,
 last_error text,
 unique(manager_id,week_start),
 check((status='sent')=(sent_at is not null))
);
create index manager_weekly_digests_queue on public.manager_weekly_digests(status,next_attempt_at)
 where status in ('queued','failed','sending');
alter table public.manager_weekly_digests enable row level security;
revoke all on public.manager_weekly_digests from public,anon,authenticated;
grant all on public.manager_weekly_digests to service_role;

create function private.queue_weekly_manager_digests(p_now timestamptz,p_manager_id uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare local_day date; cutoff timestamptz; period_start timestamptz; period_end timestamptz;
 m record; snapshot record; details text; inserted integer; total integer:=0;
begin
 if p_now is null then raise exception 'Date obligatoire.' using errcode='23514'; end if;
 local_day:=(p_now at time zone 'Europe/Paris')::date;
 cutoff:=(local_day+time '08:00') at time zone 'Europe/Paris';
 if extract(isodow from local_day)<>1 or p_now<cutoff then return 0; end if;
 period_end:=local_day::timestamp at time zone 'Europe/Paris';
 period_start:=(local_day-7)::timestamp at time zone 'Europe/Paris';
 for m in select id from public.profiles where role='manager'
  and (p_manager_id is null or id=p_manager_id) order by id
 loop
  -- Un seul statement donne des compteurs et une liste coherents sous concurrence.
  with team as materialized (
   select r.*,exists(select 1 from public.approval_steps s where s.request_id=r.id
    and s.required_role='manager' and s.assignee_id=m.id and s.status='pending'
    and s.activated_at<=p_now) and r.status='pending_approval' as waiting
   from public.requests r where r.manager_id=m.id and r.submitted_at is not null
  )
  select count(*) filter(where submitted_at>=period_start and submitted_at<period_end)::integer as received,
   count(*) filter(where status='approved' and completed_at>=period_start and completed_at<period_end)::integer as approved,
   count(*) filter(where waiting)::integer as pending,
   (select string_agg('NC-'||lpad(reference::text,6,'0')||' - '||replace(replace(title,E'\n',' '),E'\r',' '),E'\n' order by submitted_at,id)
    from (select id,reference,title,submitted_at from team where waiting order by submitted_at,id limit 20) items) as details
   into snapshot from team;
  details:=coalesce(snapshot.details,'Aucune demande en attente de votre validation.');
  if snapshot.pending>20 then details:=details||E'\nListe limitee aux 20 demandes les plus anciennes ; consultez Mon equipe pour la suite.'; end if;
  insert into public.manager_weekly_digests(manager_id,week_start,snapshot_at,received_count,approved_count,pending_count,subject,body)
   values(m.id,local_day,p_now,snapshot.received,snapshot.approved,snapshot.pending,
    'NovaCorp : recapitulatif hebdomadaire du '||to_char(local_day,'DD/MM/YYYY'),
    'Semaine du '||to_char(local_day-7,'DD/MM/YYYY')||' au '||to_char(local_day-1,'DD/MM/YYYY')||E' (heure de Paris).\n'||
    'Demandes recues : '||snapshot.received||E'\nDemandes finalement approuvees : '||snapshot.approved||
    E'\nEn attente de votre validation au passage du workflow : '||snapshot.pending||E'\n\n'||details||
    E'\n\nCe recapitulatif est une photographie ; consultez les demandes pour leur etat actuel.\nhttp://localhost:3000/tableau-de-bord?scope=team')
   on conflict(manager_id,week_start) do nothing;
  get diagnostics inserted=row_count; total:=total+inserted;
 end loop;
 return total;
end $$;

create function public.queue_weekly_manager_digests(p_manager_id uuid default null)
returns integer language sql security definer set search_path='' as $$
 select private.queue_weekly_manager_digests(now(),p_manager_id);
$$;

create function public.claim_weekly_manager_digest(p_manager_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.manager_weekly_digests; email text; monday date;
begin
 monday:=date_trunc('week',now() at time zone 'Europe/Paris')::date;
 for d in select * from public.manager_weekly_digests where
  (p_manager_id is null or manager_id=p_manager_id) and
  ((status in ('queued','failed') and next_attempt_at<=now() and attempts<5) or
   (status='sending' and lease_until<=now()))
  order by week_start,id for update skip locked
 loop
  if d.week_start<>monday or not exists(select 1 from public.profiles where id=d.manager_id and role='manager') then
   update public.manager_weekly_digests set status='failed',next_attempt_at='infinity',last_error='Recapitulatif obsolete ou role manager retire.' where id=d.id; continue;
  end if;
  if d.attempts>=5 then
   update public.manager_weekly_digests set status='failed',next_attempt_at='infinity',last_error='Derniere reservation SMTP expiree ; verification manuelle necessaire.' where id=d.id; continue;
  end if;
  if now()<(monday+time '08:00') at time zone 'Europe/Paris' then
   update public.manager_weekly_digests set next_attempt_at=(monday+time '08:00') at time zone 'Europe/Paris' where id=d.id; continue;
  end if;
  select u.email into email from auth.users u where u.id=d.manager_id;
  if email is null then
   update public.manager_weekly_digests set status='failed',next_attempt_at='infinity',last_error='Adresse du manager absente.' where id=d.id; continue;
  end if;
  update public.manager_weekly_digests set status='sending',attempts=attempts+1,lease_token=gen_random_uuid(),
   lease_until=now()+interval '5 minutes',last_error=null where id=d.id returning * into d;
  return jsonb_build_object('claimed',true,'notification_id',d.id,'lease_token',d.lease_token,'to',email,'subject',d.subject,'text',d.body);
 end loop;
 return jsonb_build_object('claimed',false);
end $$;

create function public.finish_weekly_manager_digest(p_notification_id uuid,p_lease_token uuid,p_sent boolean,p_message_id text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.manager_weekly_digests;
begin
 select * into d from public.manager_weekly_digests where id=p_notification_id for update;
 if d.id is null or p_lease_token is null or d.lease_token is distinct from p_lease_token then
  return jsonb_build_object('recorded',false);
 end if;
 if d.status='sent' then return jsonb_build_object('recorded',true,'replayed',true); end if;
 if d.status<>'sending' or p_sent is null then return jsonb_build_object('recorded',false); end if;
 if p_sent then
  update public.manager_weekly_digests set status='sent',sent_at=now(),provider_message_id=left(p_message_id,300),last_error=null where id=d.id;
 else
  update public.manager_weekly_digests set status='failed',next_attempt_at=case when attempts>=5 then 'infinity'::timestamptz
   else now()+make_interval(mins=>attempts) end,last_error='Echec SMTP ; envoi a reessayer.' where id=d.id;
 end if;
 return jsonb_build_object('recorded',true);
end $$;

revoke all on function private.queue_weekly_manager_digests(timestamptz,uuid) from public,anon,authenticated,service_role;
revoke all on function public.queue_weekly_manager_digests(uuid),public.claim_weekly_manager_digest(uuid),
 public.finish_weekly_manager_digest(uuid,uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.queue_weekly_manager_digests(uuid),public.claim_weekly_manager_digest(uuid),
 public.finish_weekly_manager_digest(uuid,uuid,boolean,text) to service_role;
