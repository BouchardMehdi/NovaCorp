-- Versioned, administrator-imported documents. No employee data is indexed.
create table public.hr_knowledge_documents(
 id uuid primary key default gen_random_uuid(),
 slug text not null check(slug ~ '^[a-z0-9][a-z0-9-]{1,59}$'),
 title text not null check(length(btrim(title)) between 1 and 180),
 version text not null check(version ~ '^[-a-zA-Z0-9.]{1,30}$'),
 request_types text[] not null check(cardinality(request_types) between 1 and 4 and request_types <@ array['leave','remote_work','equipment','training']::text[]),
 source_path text not null check(length(source_path) between 1 and 255 and source_path !~ '[/\\]'),
 sha256 text not null check(sha256 ~ '^[a-f0-9]{64}$'),
 active boolean not null default true,
 imported_at timestamptz not null default now(),
 unique(slug,version)
);
create unique index hr_knowledge_active_version on public.hr_knowledge_documents(slug) where active;
create table public.hr_knowledge_chunks(
 id uuid primary key default gen_random_uuid(),
 document_id uuid not null references public.hr_knowledge_documents(id) on delete cascade,
 position integer not null check(position between 1 and 2500),
 section text not null check(length(section) between 1 and 160),
 content text not null check(length(content) between 1 and 900),
 search_vector tsvector generated always as (to_tsvector('french'::regconfig,section||' '||content)) stored,
 unique(document_id,position)
);
create index hr_knowledge_search on public.hr_knowledge_chunks using gin(search_vector);
create table public.hr_knowledge_retrievals(
 id uuid primary key default gen_random_uuid(),
 workflow_run_id uuid not null unique references public.workflow_runs(id) on delete cascade,
 context jsonb not null check(jsonb_typeof(context)='object'),
 created_at timestamptz not null default now()
);
alter table public.hr_knowledge_documents enable row level security;
alter table public.hr_knowledge_chunks enable row level security;
alter table public.hr_knowledge_retrievals enable row level security;
revoke all on public.hr_knowledge_documents,public.hr_knowledge_chunks,public.hr_knowledge_retrievals from public,anon,authenticated;
grant all on public.hr_knowledge_documents,public.hr_knowledge_chunks,public.hr_knowledge_retrievals to service_role;
alter table public.ai_reviews add column rag_context jsonb check(rag_context is null or jsonb_typeof(rag_context)='object');
drop index public.qualification_one_review;
create unique index qualification_one_review on public.ai_reviews(workflow_run_id)
 where prompt_version in ('hr-qualification-v1','hr-qualification-v2','hr-qualification-v3-rag') and workflow_run_id is not null;

create function public.import_hr_knowledge(p_slug text,p_title text,p_version text,p_types text[],p_source_path text,p_sha256 text,p_chunks jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare doc public.hr_knowledge_documents; chunk jsonb; replayed boolean;
begin
 if p_slug is null or p_slug !~ '^[a-z0-9][a-z0-9-]{1,59}$' or
  p_title is null or length(btrim(p_title)) not between 1 and 180 or
  p_version is null or p_version !~ '^[-a-zA-Z0-9.]{1,30}$' or
  p_types is null or cardinality(p_types) not between 1 and 4 or array_position(p_types,null) is not null or
  not p_types <@ array['leave','remote_work','equipment','training']::text[] or
  p_source_path is null or length(p_source_path) not between 1 and 255 or p_source_path ~ '[/\\]' or
  p_sha256 is null or p_sha256 !~ '^[a-f0-9]{64}$' or
  jsonb_typeof(p_chunks) is distinct from 'array' then
  raise exception 'Métadonnées documentaires invalides.' using errcode='23514';
 end if;
 if jsonb_array_length(p_chunks) not between 1 and 2500 then raise exception 'Passages invalides.' using errcode='23514'; end if;
 for chunk in select value from jsonb_array_elements(p_chunks) loop
  if jsonb_typeof(chunk->'section') is distinct from 'string' or length(chunk->>'section') not between 1 and 160 or
   jsonb_typeof(chunk->'content') is distinct from 'string' or length(btrim(chunk->>'content')) not between 1 and 900 then
   raise exception 'Passage invalide.' using errcode='23514';
  end if;
 end loop;
 perform pg_advisory_xact_lock(hashtextextended(p_slug,1));
 select * into doc from public.hr_knowledge_documents where slug=p_slug and version=p_version;
 replayed:=found;
 if replayed and (doc.sha256<>p_sha256 or doc.title<>p_title or doc.source_path<>p_source_path or doc.request_types<>p_types or
  (select jsonb_agg(jsonb_build_object('section',section,'content',content) order by position) from public.hr_knowledge_chunks where document_id=doc.id)<>p_chunks) then
  raise exception 'Une version est immuable : augmenter --version pour modifier le document.' using errcode='23514';
 end if;
 update public.hr_knowledge_documents set active=false where slug=p_slug and active and id is distinct from doc.id;
 if replayed then update public.hr_knowledge_documents set active=true where id=doc.id;
 else
  insert into public.hr_knowledge_documents(slug,title,version,request_types,source_path,sha256)
   values(p_slug,p_title,p_version,p_types,p_source_path,p_sha256) returning * into doc;
  insert into public.hr_knowledge_chunks(document_id,position,section,content)
   select doc.id,ordinality::integer,value->>'section',value->>'content' from jsonb_array_elements(p_chunks) with ordinality;
 end if;
 return jsonb_build_object('document_id',doc.id,'chunks',jsonb_array_length(p_chunks),'replayed',replayed);
end $$;

create function public.search_hr_knowledge(p_request_type text,p_query text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare query tsquery; words text[]; result jsonb; topic text;
begin
 topic:=case p_request_type when 'leave' then 'congés calendrier solde' when 'remote_work' then 'télétravail période'
  when 'equipment' then 'matériel montant' when 'training' then 'formation organisme' end;
 if topic is null or p_query is null or length(p_query)>4000 then raise exception 'Recherche documentaire invalide.' using errcode='23514'; end if;
 words:=tsvector_to_array(to_tsvector('french'::regconfig,topic||' '||p_query));
 -- Safe OR query from lexemes: input cannot become SQL or arbitrary tsquery operators.
 select string_agg(quote_literal(word),' | ')::tsquery into query from unnest(words) word;
 select coalesce(jsonb_agg(to_jsonb(matches) order by score desc,source_id),'[]'::jsonb) into result from (
  select d.slug||'@'||d.version||'#'||c.position as source_id,d.title,d.version,c.section,c.content,d.source_path,d.sha256,
   round(ts_rank_cd(c.search_vector,query,32)::numeric,6) as score
  from public.hr_knowledge_chunks c join public.hr_knowledge_documents d on d.id=c.document_id
  where d.active and p_request_type=any(d.request_types) and c.search_vector@@query
  order by score desc,d.slug,c.position limit 3
 ) matches;
 return result;
end $$;

create function public.retrieve_hr_knowledge(p_run_id uuid,p_lease_token uuid,p_query text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare run public.workflow_runs; request public.requests; retrieved public.hr_knowledge_retrievals; context jsonb;
begin
 select * into request from public.requests where id=(select request_id from public.workflow_runs where id=p_run_id) for update;
 select * into run from public.workflow_runs where id=p_run_id for update;
 if p_lease_token is null or run.id is null or run.workflow_key<>'hr_qualification_v1' or run.status<>'running' or
  run.lease_token is distinct from p_lease_token or coalesce(run.lease_until,now())<=now() or request.status<>'under_review' then
  raise exception 'Réservation documentaire invalide.' using errcode='23514';
 end if;
 select * into retrieved from public.hr_knowledge_retrievals where workflow_run_id=run.id;
 if not found then
  context:=jsonb_build_object('method','postgres_fts_fr_v1','retrieved_at',now(),'passages',public.search_hr_knowledge(request.request_type,p_query));
  insert into public.hr_knowledge_retrievals(workflow_run_id,context) values(run.id,context) returning * into retrieved;
 end if;
 update public.ai_reviews set prompt_version='hr-qualification-v3-rag',rag_context=retrieved.context where workflow_run_id=run.id;
 return retrieved.context;
end $$;
revoke all on function public.import_hr_knowledge(text,text,text,text[],text,text,jsonb),public.search_hr_knowledge(text,text),public.retrieve_hr_knowledge(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.import_hr_knowledge(text,text,text,text[],text,text,jsonb),public.search_hr_knowledge(text,text),public.retrieve_hr_knowledge(uuid,uuid,text) to service_role;

create or replace function public.complete_hr_qualification(p_run_id uuid,p_lease_token uuid,p_result jsonb,
 p_input_tokens integer default 0,p_output_tokens integer default 0)
 returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare run public.workflow_runs; r public.requests; req_id uuid; checks jsonb;
 qualification public.ai_qualification; summary text; response text; context jsonb; citations jsonb;
begin
 select request_id into req_id from public.workflow_runs where id=p_run_id;
 select * into r from public.requests where id=req_id for update;
 select * into run from public.workflow_runs where id=p_run_id for update;
 if p_lease_token is null or run.id is null or run.workflow_key<>'hr_qualification_v1' or
  run.lease_token is distinct from p_lease_token then
  return jsonb_build_object('completed',false,'reason','stale_lease');
 end if;
 if run.status='succeeded' then return jsonb_build_object('completed',true,'replayed',true); end if;
 if run.status<>'running' or coalesce(run.lease_until,now())<=now() then
  return jsonb_build_object('completed',false,'reason','stale_lease');
 end if;
 if r.status<>'under_review' then
  update public.workflow_runs set status='failed',finished_at=now(),retry_after='infinity',
   error_code='request_inactive',error_message='La demande ne peut plus être qualifiée.' where id=run.id;
  update public.ai_reviews set status='failed',finished_at=now(),error_code='request_inactive',
   error_message='La demande ne peut plus être qualifiée.' where workflow_run_id=run.id;
  return jsonb_build_object('completed',false,'reason','request_inactive');
 end if;
 if jsonb_typeof(p_result) is distinct from 'object' or
  coalesce(p_result->>'qualification','') not in ('eligible','needs_review','invalid') or
  jsonb_typeof(p_result->'summary') is distinct from 'string' or
  length(btrim(p_result->>'summary')) not between 1 and 7800 or
  jsonb_typeof(p_result->'response_draft') is distinct from 'string' or
  length(p_result->>'response_draft')>8000 or
  p_input_tokens is null or p_input_tokens<0 or p_output_tokens is null or p_output_tokens<0 then
  raise exception 'Réponse de qualification invalide.' using errcode='23514';
 end if;

 -- Only RAG-enabled executions require documentary evidence; legacy test fixtures/reviews remain compatible.
 if exists(select 1 from public.ai_reviews where workflow_run_id=run.id and prompt_version='hr-qualification-v3-rag') then
  select h.context into context from public.hr_knowledge_retrievals h where h.workflow_run_id=run.id;
  citations:=p_result->'citations';
  if context is null or jsonb_typeof(citations) is distinct from 'array' then
   raise exception 'RAG evidence required.' using errcode='23514';
  end if;
  if jsonb_array_length(citations)>3 or exists(select 1 from jsonb_array_elements(citations) c
   where jsonb_typeof(c) is distinct from 'string' or not exists(select 1 from jsonb_array_elements(context->'passages') source where source->'source_id'=c)) then
   raise exception 'Unknown documentary citation.' using errcode='23514';
  end if;
  if (jsonb_array_length(context->'passages')=0 or jsonb_array_length(citations)=0) and p_result->>'qualification'='eligible' then
   p_result:=jsonb_set(p_result,'{qualification}','"needs_review"'::jsonb);
  end if;
  update public.ai_reviews set rag_context=context||jsonb_build_object('citations',citations) where workflow_run_id=run.id;
 end if;
 checks:=public.get_hr_request_checks(r.id);
 qualification:=(p_result->>'qualification')::public.ai_qualification;
 summary:=btrim(p_result->>'summary'); response:=p_result->>'response_draft';
 if jsonb_array_length(checks->'blocking_issues')>0 then
  qualification:='invalid';
  summary:='Contrôles métier : des anomalies nécessitent une vérification humaine.'||E'\n'||summary;
 elsif (checks->>'requires_human_review')::boolean then
  qualification:='needs_review';
  summary:='Contrôles métier : un doublon potentiel doit être examiné.'||E'\n'||summary;
 end if;
 update public.ai_reviews set status='succeeded',finished_at=now(),checks=checks,
  qualification=qualification,summary=summary,response_draft=response,
  input_tokens=p_input_tokens,output_tokens=p_output_tokens where workflow_run_id=run.id;
 perform public.prepare_hr_approvals(r.id);
 update public.requests set status='pending_approval' where id=r.id;
 update public.approval_steps set status='pending' where request_id=r.id and position=1 and status='waiting';
 update public.workflow_runs set status='succeeded',finished_at=now() where id=run.id;
 return jsonb_build_object('completed',true,'request_id',r.id,'qualification',qualification);
end $$;

