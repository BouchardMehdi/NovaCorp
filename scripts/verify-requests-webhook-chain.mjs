import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { sql } from "./requests-webhook-tools.mjs";
import { publicUrl } from "./ngrok-tools.mjs";

const requestId = randomUUID();
let created = false;
try {
  const expected = (await publicUrl()) + "/webhook/novacorp-requests";
  assert.equal(sql("select decrypted_secret from vault.decrypted_secrets where name='n8n_requests_webhook_url';"), expected,
    "Le Vault doit désigner le webhook public du tunnel actuel.");
  // Le seul brouillon créé est synthétique, sur le compte de démonstration Camille.
  const jobId = Number(sql(`begin;
    insert into public.requests(id,requester_id,request_type,title,description,amount,quantity)
    select '${requestId}',id,'equipment','[Test webhook] Transport synthétique','Ne pas exporter ce motif.',123,1
    from auth.users where email='salarie@novacorp.test';
    select id from net.http_request_queue
      where convert_from(body,'UTF8')::jsonb#>>'{record,id}'='${requestId}';
    commit;`));
  created = true;
  assert.ok(Number.isSafeInteger(jobId) && jobId > 0, "Une insertion réelle doit mettre un appel HTTP en file.");
  let result;
  for (let attempt = 0; attempt < 30; attempt++) {
    const output = sql(`select json_build_object('status',status_code,'content',content,'failed',timed_out or error_msg is not null)
      from net._http_response where id=${jobId};`);
    if (output) { result = JSON.parse(output); break; }
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
  assert.ok(result, "Réponse pg_net attendue sous 30 secondes.");
  assert.equal(result.failed, false, "Le transport pg_net doit réussir.");
  assert.equal(result.status, 200, "Le webhook public doit répondre 200.");
  assert.deepEqual(JSON.parse(result.content), {
    received: true, event: "INSERT", table: "requests", request_id: requestId, status: "draft", business_processing: false,
  });
  const state = JSON.parse(sql(`select json_build_object('status',r.status,
    'reviews',(select count(*) from public.ai_reviews where request_id=r.id),
    'approvals',(select count(*) from public.approval_steps where request_id=r.id),
    'notifications',(select count(*) from public.notifications where request_id=r.id))
    from public.requests r where id='${requestId}';`));
  assert.deepEqual(state, { status: "draft", reviews: 0, approvals: 0, notifications: 0 });
  console.log("OK : INSERT Supabase local → pg_net → ngrok → webhook n8n → réponse HTTP 200.");
  console.log("Payload limité vérifié ; le brouillon ne déclenche ni qualification, ni validation, ni email.");
} catch (error) {
  // Ne pas exposer stderr PostgreSQL ou une réponse contenant une configuration.
  console.error(error.status !== undefined ? "Vérification PostgreSQL impossible." : error.message);
  process.exitCode = 1;
} finally {
  if (created) {
    try {
      sql(`begin; set local session_replication_role=replica;
        delete from public.request_events where request_id='${requestId}';
        delete from public.requests where id='${requestId}' and title='[Test webhook] Transport synthétique' and status='draft';
        commit;`);
      console.log("Brouillon synthétique nettoyé ; les demandes existantes sont conservées.");
    } catch { console.error("Nettoyage de la fixture impossible : " + requestId); process.exitCode = 1; }
  }
}
