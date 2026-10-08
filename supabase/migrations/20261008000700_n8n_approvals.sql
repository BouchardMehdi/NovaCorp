-- Orchestration après décisions humaines, atomique et rejouable.
create function public.advance_hr_approvals(p_execution_id text,p_request_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.requests; next_step public.approval_steps; action_name text;
begin
 if coalesce(length(btrim(p_execution_id)),0) not between 1 and 160 then
  raise exception 'Identifiant exécution obligatoire.' using errcode='23514';
 end if;
 if exists(select 1 from public.workflow_runs where workflow_key='hr_approvals_v1' and execution_id=p_execution_id) then
  return jsonb_build_object('processed',false,'replayed',true);
 end if;
 for r in select q.* from public.requests q where q.status='pending_approval'
  and (p_request_id is null or q.id=p_request_id)
  and not exists(select 1 from public.approval_steps s where s.request_id=q.id and s.status='pending')
  order by q.submitted_at,q.id for update skip locked
 loop
  if exists(select 1 from public.approval_steps where request_id=r.id and status='pending') then continue; end if;
  if exists(select 1 from public.approval_steps where request_id=r.id and status='rejected') then
   update public.requests set status='rejected' where id=r.id;
   action_name:='rejected';
  else
   select * into next_step from public.approval_steps where request_id=r.id and status='waiting'
    order by position limit 1 for update;
   if found then
    -- Les triggers vérifient tous les prédécesseurs et démarrent le délai de 48 h.
    if exists(select 1 from public.approval_steps where request_id=r.id
     and position<next_step.position and status<>'approved') then continue; end if;
    update public.approval_steps set status='pending' where id=next_step.id;
    action_name:='activate_'||next_step.required_role;
   else
    -- Le garde-fou SQL exige chaque validation obligatoire.
    update public.requests set status='approved' where id=r.id;
    action_name:='approved';
   end if;
  end if;
  insert into public.workflow_runs(request_id,workflow_key,execution_id,status,finished_at)
   values(r.id,'hr_approvals_v1',p_execution_id,'succeeded',now());
  return jsonb_build_object('processed',true,'request_id',r.id,'action',action_name);
 end loop;
 return jsonb_build_object('processed',false);
end $$;

create function public.claim_hr_notification_email(p_request_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare candidate record; r public.requests; n public.notifications; email text;
 step public.approval_steps; event public.request_events; body_text text; subject_text text; label text;
begin
 for candidate in select q.id as request_id,x.id as notification_id
  from public.requests q join public.notifications x on x.request_id=q.id
  where x.kind in ('approval_needed','status_change') and x.channel='email'
   and (x.attempts<5 or (x.status='sending' and x.lease_until<=now()))
   and (p_request_id is null or q.id=p_request_id)
   and ((x.status in ('queued','failed') and x.next_attempt_at<=now()) or
    (x.status='sending' and x.lease_until<=now()))
  order by x.created_at,x.id for update of q skip locked
 loop
  select * into r from public.requests where id=candidate.request_id;
  select * into n from public.notifications where id=candidate.notification_id for update skip locked;
  if not found then continue; end if;
  if n.kind='approval_needed' then
   select * into step from public.approval_steps where id=n.approval_step_id;
   if r.status<>'pending_approval' or step.status is distinct from 'pending'::public.approval_status then
    update public.notifications set status='failed',next_attempt_at='infinity',
     last_error='Notification devenue obsolète.' where id=n.id; continue;
   end if;
   subject_text:='NovaCorp : une demande attend votre validation';
   body_text:='La demande NC-'||lpad(r.reference::text,6,'0')||' (« '||r.title||
    ' ») attend votre décision ('||case step.required_role when 'manager' then 'manager'
     when 'hr' then 'RH' else 'DRH' end||'). Une décision humaine reste nécessaire.';
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

create function public.finish_hr_notification_email(p_notification_id uuid,p_lease_token uuid,
 p_sent boolean,p_message_id text default null) returns jsonb
 language plpgsql security definer set search_path='' as $$
declare req_id uuid; n public.notifications;
begin
 select request_id into req_id from public.notifications where id=p_notification_id;
 perform 1 from public.requests where id=req_id for update;
 select * into n from public.notifications where id=p_notification_id for update;
 if p_lease_token is null or n.id is null or n.kind not in ('approval_needed','status_change') or n.lease_token is distinct from p_lease_token then
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

revoke all on function public.advance_hr_approvals(text,uuid),
 public.claim_hr_notification_email(uuid),public.finish_hr_notification_email(uuid,uuid,boolean,text)
 from public,anon,authenticated;
grant execute on function public.advance_hr_approvals(text,uuid),
 public.claim_hr_notification_email(uuid),public.finish_hr_notification_email(uuid,uuid,boolean,text) to service_role;
