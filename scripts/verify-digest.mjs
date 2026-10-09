import {createClient} from "@supabase/supabase-js";
import {randomUUID} from "node:crypto";
import {readFile} from "node:fs/promises";
import assert from "node:assert/strict";
import {container,inside,docker} from "./n8n-tools.mjs";
const url=process.env.NEXT_PUBLIC_SUPABASE_URL;
if(!url||!["localhost","127.0.0.1","[::1]"].includes(new URL(url).hostname))throw new Error("Verification reservee a Supabase local.");
const admin=createClient(url,process.env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
const suffix=randomUUID().slice(0,8),ids=["digestQueueTest"+suffix,"digestMailTest"+suffix];
let managerId;
const sql=source=>docker(["exec","-i","supabase_db_NovaCorp","psql","-U","supabase_admin","-d","postgres","-v","ON_ERROR_STOP=1","-At"],source);
async function execute(name,id){
 const workflow=JSON.parse(await readFile("n8n/workflows/"+name+".json","utf8"));
 workflow.id=id;workflow.name="TEST NovaCorp "+id;workflow.active=false;
 for(const n of workflow.nodes.filter(n=>n.type==="n8n-nodes-base.scheduleTrigger"))delete workflow.connections[n.name];
 workflow.nodes=workflow.nodes.filter(n=>n.type!=="n8n-nodes-base.scheduleTrigger");
 workflow.nodes.find(n=>n.name==="Configuration").parameters.assignments.assignments[0].value=managerId;
 inside(container(),`
  const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),cp=require('node:child_process');
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'novacorp-digest-test-'));
  try{const file=path.join(dir,'workflow.json'),w=JSON.parse(fs.readFileSync(0,'utf8'));fs.writeFileSync(file,JSON.stringify([w]),{mode:0o600});
   cp.execFileSync('n8n',['import:workflow','--input',file],{stdio:'pipe'});
   cp.execFileSync('n8n',['execute','--id',w.id],{stdio:'pipe',env:{...process.env,N8N_RUNNERS_BROKER_PORT:'56790'},timeout:170000,maxBuffer:8*1024*1024});
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
 `,JSON.stringify(workflow));
}
async function messages(){const response=await fetch("http://127.0.0.1:8025/api/v2/messages?limit=500",{signal:AbortSignal.timeout(10000)});assert.ok(response.ok);return (await response.json()).items||[];}
try{
 const published=JSON.parse(inside(container(),`const {DatabaseSync}=require('node:sqlite');const db=new DatabaseSync('/home/node/.n8n/database.sqlite');try{console.log(JSON.stringify(db.prepare('select id from workflow_entity where id in (?,?) and activeVersionId is not null').all('novacorpWeeklyDigest','novacorpDigestEmails')));}finally{db.close();}`));
 assert.equal(published.length,0,"Depubliez les digests avec npm run n8n:digest:stop avant le test.");
 const email="digest-"+suffix+"@novacorp.test";
 const created=await admin.auth.admin.createUser({email,password:randomUUID()+"Aa1!",email_confirm:true});assert.equal(created.error,null);managerId=created.data.user.id;
 assert.equal((await admin.from("profiles").update({role:"manager"}).eq("id",managerId)).error,null);
 await execute("weekly-digest",ids[0]);
 const monday=sql("select date_trunc('week',now() at time zone 'Europe/Paris')::date;").trim();
 // Simulation du passage du lundi uniquement pour ce manager fictif, sans demandes RH.
 sql("select private.queue_weekly_manager_digests(('"+monday+" 08:00 Europe/Paris')::timestamptz,'"+managerId+"');");
 const afterEight=sql("select now()>=(date_trunc('week',now() at time zone 'Europe/Paris')::date+time '08:00') at time zone 'Europe/Paris';").trim()==="t";
 const before=new Set((await messages()).map(m=>m.ID));
 await execute("digest-emails",ids[1]);
 const fresh=(await messages()).filter(m=>!before.has(m.ID)&&JSON.stringify(m.Content.Headers.To).includes(email));
 assert.equal(fresh.length,afterEight?1:0);
 const row=await admin.from("manager_weekly_digests").select("*").eq("manager_id",managerId).single();assert.equal(row.error,null);
 assert.equal(row.data.received_count+row.data.approved_count+row.data.pending_count,0);
 assert.equal(row.data.status,afterEight?"sent":"queued");
 if(afterEight){
  const mail=fresh[0],encoding=mail.Content.Headers["Content-Transfer-Encoding"]?.[0];let body=mail.Content.Body;
  if(encoding==="quoted-printable")body=Buffer.from(body.replace(/=\r?\n/g,"").replace(/=([0-9A-F]{2})/gi,(_,h)=>String.fromCharCode(parseInt(h,16))),"latin1").toString("utf8");
  else if(encoding==="base64")body=Buffer.from(body,"base64").toString("utf8");
  assert.ok(body.includes("Demandes recues : 0"));assert.ok(body.includes("scope=team"));
  await execute("digest-emails",ids[1]);
  assert.equal((await messages()).filter(m=>JSON.stringify(m.Content.Headers.To).includes(email)).length,1);
  console.log("OK digest : planification ciblee, email MailHog, compteurs et lien, rejeu sans doublon.");
 }else console.log("OK lundi avant 8 h : email differe jusqu'a 8 h.");
}catch(error){console.error("Verification digest echouee :",error.message);process.exitCode=1;}
finally{
 if(managerId)assert.equal((await admin.auth.admin.deleteUser(managerId)).error,null);
 inside(container(),`
  const {DatabaseSync}=require('node:sqlite');const db=new DatabaseSync('/home/node/.n8n/database.sqlite');
  try{db.exec('PRAGMA foreign_keys=ON; PRAGMA busy_timeout=10000; BEGIN;');for(const id of JSON.parse(require('node:fs').readFileSync(0,'utf8'))){db.prepare('DELETE FROM execution_entity WHERE workflowId=?').run(id);db.prepare('DELETE FROM workflow_entity WHERE id=?').run(id);}db.exec('COMMIT;');}
  catch(e){try{db.exec('ROLLBACK;');}catch{}throw e;}finally{db.close();}
 `,JSON.stringify(ids));
}
