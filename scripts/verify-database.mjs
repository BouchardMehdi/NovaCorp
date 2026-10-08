import { execFileSync, execFile } from "node:child_process";
import { promisify } from "node:util";
import { readFile, readdir } from "node:fs/promises";
import { randomBytes } from "node:crypto";
import assert from "node:assert/strict";

const execAsync = promisify(execFile);
const container = "supabase_db_NovaCorp";
const database = "novacorp_verify_" + randomBytes(6).toString("hex");
let created = false;
const psql = ["exec", "-i", container, "psql", "-U", "supabase_admin", "-d", database, "-v", "ON_ERROR_STOP=1"];

function docker(args, input) {
  return execFileSync("docker", args, { input, encoding: "utf8", maxBuffer: 32 * 1024 * 1024, timeout: 30000,
    stdio: ["pipe", "pipe", "pipe"] });
}
function sql(source) { return docker(psql, source); }
async function submit(id) {
  const child = execAsync("docker", [...psql, "-c", `begin; set local statement_timeout='10s';
    set local role authenticated;
    set local request.jwt.claims='{"sub":"12000000-0000-0000-0000-000000000001","role":"authenticated"}';
    select public.submit_hr_request('${id}'); select pg_sleep(0.3); commit;`],
    { encoding: "utf8", timeout: 15000 });
  try { await child; return { success: true }; }
  catch (error) { return { success: false, stderr: error.stderr }; }
}
async function checkRace(ids, expectedDays) {
  const results = await Promise.all(ids.map(submit));
  assert.equal(results.filter((r) => r.success).length, 1, "Une seule soumission concurrente doit réussir.");
  const failed = results.find((r) => !r.success);
  assert.match(failed.stderr, /Solde de congés insuffisant|chevauche une demande active/,
    "La seconde soumission doit échouer sur une règle métier, sans deadlock.");
  const state = JSON.parse(docker([...psql, "-At", "-c", `select json_build_object(
    'reserved', b.reserved_days, 'available', b.available_days,
    'ledger', (select coalesce(sum(days),0) from public.leave_allocations where balance_id=b.id and state='reserved'),
    'submitted', (select count(*) from public.requests where requester_id=b.employee_id and status='submitted'))
    from public.leave_balances b where employee_id='12000000-0000-0000-0000-000000000001' and year=2026;`]));
  assert.equal(state.submitted, 1);
  assert.equal(state.reserved, state.ledger);
  assert.ok(state.available >= 0);
  if (expectedDays !== undefined) assert.equal(state.reserved, expectedDays);
}
try {
  // Copie uniquement la structure, jamais les comptes, mots de passe ou demandes de la base locale.
  const schema = docker(["exec", container, "pg_dump", "-U", "supabase_admin", "-d", "postgres", "--schema-only", "--no-owner"]);
  docker(["exec", container, "createdb", "-U", "supabase_admin", database]);
  created = true;
  sql(schema);
  sql("drop schema if exists private cascade; drop schema public cascade; create schema public; grant usage on schema public to anon, authenticated, service_role;");
  const migrations = (await readdir("supabase/migrations")).filter((f) => f.endsWith(".sql")).sort();
  for (const migration of migrations) sql(await readFile("supabase/migrations/" + migration, "utf8"));
  console.log(migrations.length + " migrations rejouées dans une base temporaire.");
  let tests = 0;
  for (const file of (await readdir("supabase/tests/database")).filter((f) => f.endsWith(".sql")).sort()) {
    const result = sql(await readFile("supabase/tests/database/" + file, "utf8"));
    assert.doesNotMatch(result, /not ok \d+/, file + " doit réussir.");
    tests += (result.match(/ok \d+ -/g) || []).length;
  }
  console.log(tests + " tests SQL réussis sur le schéma reconstruit.");
  sql(`insert into auth.users(id,email) values
    ('12000000-0000-0000-0000-000000000001','concurrence-salarie@novacorp.test'),
    ('12000000-0000-0000-0000-000000000002','concurrence-manager@novacorp.test'),
    ('12000000-0000-0000-0000-000000000003','concurrence-rh@novacorp.test'),
    ('12000000-0000-0000-0000-000000000004','concurrence-drh@novacorp.test');
    update public.profiles set role='manager' where id='12000000-0000-0000-0000-000000000002';
    update public.profiles set role='hr' where id='12000000-0000-0000-0000-000000000003';
    update public.profiles set role='director' where id='12000000-0000-0000-0000-000000000004';
    update public.profiles set manager_id='12000000-0000-0000-0000-000000000002' where id='12000000-0000-0000-0000-000000000001';
    insert into public.hr_routing_settings(hr_referent_id,director_referent_id) values
      ('12000000-0000-0000-0000-000000000003','12000000-0000-0000-0000-000000000004');
    insert into public.leave_balances(employee_id,year,allocated_days) values('12000000-0000-0000-0000-000000000001',2026,25);
    insert into public.requests(id,requester_id,request_type,title,start_date,end_date) values
      ('22000000-0000-0000-0000-000000000001','12000000-0000-0000-0000-000000000001','leave','Course solde A','2026-10-01','2026-10-28'),
      ('22000000-0000-0000-0000-000000000002','12000000-0000-0000-0000-000000000001','leave','Course solde B','2026-11-02','2026-11-13');`);
  await checkRace(["22000000-0000-0000-0000-000000000001", "22000000-0000-0000-0000-000000000002"]);
  console.log("Concurrence : deux demandes totalisant 30 jours ne dépassent pas le solde de 25 jours.");
  sql(`update public.requests set status='cancelled' where status='submitted';
    insert into public.requests(id,requester_id,request_type,title,start_date,end_date) values
      ('22000000-0000-0000-0000-000000000003','12000000-0000-0000-0000-000000000001','leave','Course période A','2026-12-01','2026-12-14'),
      ('22000000-0000-0000-0000-000000000004','12000000-0000-0000-0000-000000000001','leave','Course période B','2026-12-01','2026-12-14');`);
  await checkRace(["22000000-0000-0000-0000-000000000003", "22000000-0000-0000-0000-000000000004"], 10);
  console.log("Concurrence : deux périodes identiques ne sont pas réservées simultanément.");
  sql("insert into public.requests(id,requester_id,request_type,title,amount,quantity) values('22000000-0000-0000-0000-000000000005','12000000-0000-0000-0000-000000000001','equipment','Course qualification',80,1); set role authenticated; set request.jwt.claims='{\"sub\":\"12000000-0000-0000-0000-000000000001\",\"role\":\"authenticated\"}'; select submit_hr_request('22000000-0000-0000-0000-000000000005');");
  const qualifications=await Promise.all(["claim-a","claim-b"].map(async execution=>{
    const {stdout}=await execAsync("docker",[...psql,"-At","-c",
      "begin; set local role service_role; select claim_hr_qualification('"+execution+"','ollama','qwen3:1.7b','22000000-0000-0000-0000-000000000005'); select pg_sleep(0.3); commit;"],{encoding:"utf8",timeout:15000});
    return JSON.parse(stdout.split(/\r?\n/).find(line=>line.startsWith("{"))).claimed;
  }));
  assert.equal(qualifications.filter(Boolean).length,1);
  console.log("Concurrence : une seule exécution n8n réserve la qualification.");

  sql("set role service_role; select complete_hr_qualification(id,lease_token,'{\"qualification\":\"eligible\",\"summary\":\"Fixture concurrence\",\"response_draft\":\"Attente\"}') from workflow_runs where request_id='22000000-0000-0000-0000-000000000005' and status='running'; reset role; set role authenticated; set request.jwt.claims='{\"sub\":\"12000000-0000-0000-0000-000000000002\",\"role\":\"authenticated\"}'; select decide_hr_approval(id,true) from approval_steps where request_id='22000000-0000-0000-0000-000000000005' and position=1;");
  const advances=await Promise.all(["advance-a","advance-b"].map(async execution=>{
    const {stdout}=await execAsync("docker",[...psql,"-At","-c",
      "begin; set local role service_role; select advance_hr_approvals('"+execution+"','22000000-0000-0000-0000-000000000005'); select pg_sleep(0.3); commit;"],{encoding:"utf8",timeout:15000});
    return JSON.parse(stdout.split(/\r?\n/).find(line=>line.startsWith("{"))).processed;
  }));
  assert.equal(advances.filter(Boolean).length,1);
  assert.equal(docker([...psql,"-At","-c","select count(*) from notifications where request_id='22000000-0000-0000-0000-000000000005' and kind='approval_needed';"]).trim(),"2");
  console.log("Concurrence : une seule activation RH et une seule notification.");
  sql("update notifications set status='sent',sent_at=now() where request_id='22000000-0000-0000-0000-000000000005' and kind='status_change';");
  const emails=await Promise.all([1,2].map(async()=>{
    const {stdout}=await execAsync("docker",[...psql,"-At","-c",
      "begin; set local role service_role; select claim_hr_notification_email('22000000-0000-0000-0000-000000000005'); select pg_sleep(0.3); commit;"],{encoding:"utf8",timeout:15000});
    return JSON.parse(stdout.split(/\r?\n/).find(line=>line.startsWith("{"))).claimed;
  }));
  assert.equal(emails.filter(Boolean).length,1);
  console.log("Concurrence : une seule réservation SMTP RH.");

  // Horodatages simulés uniquement dans la base temporaire de vérification.
  for(const hours of [24,49]){
    sql("begin; set local session_replication_role='replica'; update public.approval_steps set activated_at=now()-interval '"+hours+" hours',due_at=now()+interval '"+(48-hours)+" hours' where request_id='22000000-0000-0000-0000-000000000005' and position=2; commit;");
    const queued=await Promise.all([1,2].map(async()=>{
      const {stdout}=await execAsync("docker",[...psql,"-At","-c",
        "begin; set local role service_role; select queue_due_hr_reminders('22000000-0000-0000-0000-000000000005'); select pg_sleep(0.3); commit;"],{encoding:"utf8",timeout:15000});
      return Number(stdout.split(/\r?\n/).find(line=>/^\d+$/.test(line)));
    }));
    assert.deepEqual(queued.sort(),[0,1]);
    console.log("Concurrence : une seule "+(hours===24?"relance à 24 h":"alerte RH après 48 h")+".");
  }

} catch (error) {
  console.error(error.stderr || error.message);
  process.exitCode = 1;
} finally {
  // Cette base porte un nom aléatoire créé par ce script ; la base postgres n'est jamais supprimée.
  if (created) docker(["exec", container, "dropdb", "-U", "supabase_admin", database]);
}
