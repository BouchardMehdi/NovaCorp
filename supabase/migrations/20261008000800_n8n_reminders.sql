-- Supervision serveur et envoi des relances/alertes sans décision automatique.
create function private.queue_hr_approval_reminders(p_now timestamptz,p_request_id uuid) returns integer
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


create or replace function public.queue_hr_approval_reminders(p_now timestamptz default now())
returns integer language sql security definer set search_path='' as $$
 select private.queue_hr_approval_reminders(p_now,null);
$$;

create function public.queue_due_hr_reminders(p_request_id uuid default null)
returns integer language sql security definer set search_path='' as $$
 select private.queue_hr_approval_reminders(now(),p_request_id);
$$;

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
   select step.activated_at+make_interval(hours=>a.reminder_hours) into reminder_at
    from public.approval_rules a where a.id=r.approval_rule_id;
   if n.kind='reminder' and now()<reminder_at then
    update public.notifications set next_attempt_at=reminder_at where id=n.id; continue;
   elsif n.kind='reminder' and now()>=step.due_at then
    update public.notifications set status='failed',next_attempt_at='infinity',
     last_error='Relance dépassée par l’alerte de délai.' where id=n.id; continue;
   elsif n.kind='overdue_alert' and now()<step.due_at then
    update public.notifications set next_attempt_at=step.due_at where id=n.id; continue;
   end if;
   label:=case step.required_role when 'manager' then 'manager' when 'hr' then 'RH' else 'DRH' end;
   subject_text:=case n.kind when 'reminder' then 'NovaCorp : relance de validation à 24 h'
    when 'overdue_alert' then 'NovaCorp : alerte RH — délai de 48 h dépassé'
    else 'NovaCorp : une demande attend votre validation' end;
   body_text:=case n.kind when 'reminder' then 'Relance : la demande '
    when 'overdue_alert' then 'Alerte RH : la demande ' else 'La demande ' end||
    'NC-'||lpad(r.reference::text,6,'0')||' (« '||r.title||' ») attend une décision ('||label||'). '||
    case n.kind when 'reminder' then 'Le délai de relance de 24 heures est atteint. '
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

create or replace function public.finish_hr_notification_email(p_notification_id uuid,p_lease_token uuid,
 p_sent boolean,p_message_id text default null) returns jsonb
 language plpgsql security definer set search_path='' as $$
declare req_id uuid; n public.notifications;
begin
 select request_id into req_id from public.notifications where id=p_notification_id;
 perform 1 from public.requests where id=req_id for update;
 select * into n from public.notifications where id=p_notification_id for update;
 if p_lease_token is null or n.id is null or n.kind not in ('approval_needed','status_change','reminder','overdue_alert') or n.lease_token is distinct from p_lease_token then
  return jsonb_build_object('recorded',false);
 end if;
 if n.status='sent' then return jsonb_build_object('recorded',true,'replayed',true); end if;
 if n.status<>'sending' or p_sent is null then return jsonb_build_object('recorded',false); end if;
 if p_sent then
  update public.notifications set status='sent',sent_at=now(),provider_message_id=left(p_message_id,300),
   last_error=null where id=n.id;
 else
  update public.notifications set status='failed',
   next_attempt_at=case when attempts>=5 then 'infinity'::timestamptz
    else now()+make_interval(mins=>attempts) end,last_error='Échec SMTP ; envoi à réessayer.'
   where id=n.id;
 end if;
 return jsonb_build_object('recorded',true);
end $$;

revoke all on function private.queue_hr_approval_reminders(timestamptz,uuid) from public,anon,authenticated,service_role;
revoke all on function public.queue_due_hr_reminders(uuid) from public,anon,authenticated;
grant execute on function public.queue_due_hr_reminders(uuid) to service_role;
