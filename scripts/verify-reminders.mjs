import {createClient} from "@supabase/supabase-js";
import {randomUUID} from "node:crypto";
import {readFile} from "node:fs/promises";
import assert from "node:assert/strict";
import {container,inside,docker} from "./n8n-tools.mjs";
const url=process.env.NEXT_PUBLIC_SUPABASE_URL;
if(!url||!["localhost","127.0.0.1","[::1]"].includes(new URL(url).hostname))throw new Error("Test réservé à Supabase local.");
const admin=createClient(url,process.env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
const user=createClient(url,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
const suffix=randomUUID().slice(0,8);
const workflowIds=["reminderTest"+suffix,"reminderMailTest"+suffix,"dailyReminderTest"+suffix];
let userId;
async function execute(workflowName,id,requestId,model){
 const workflow=JSON.parse(await readFile("n8n/workflows/"+workflowName+".json","utf8"));
 workflow.id=id;workflow.name="TEST NovaCorp "+id;workflow.active=false;
 for(const node of workflow.nodes.filter(node=>node.type==="n8n-nodes-base.scheduleTrigger"))delete workflow.connections[node.name];
 workflow.nodes=workflow.nodes.filter(node=>node.type!=="n8n-nodes-base.scheduleTrigger");
 const assignments=workflow.nodes.find(node=>node.name==="Configuration").parameters.assignments.assignments;
 assignments.find(field=>field.name==="request_id").value=requestId;
 if(model)assignments.find(field=>field.name==="model").value=model;
 return inside(container(),`
 const fs=require("node:fs"),os=require("node:os"),path=require("node:path"),cp=require("node:child_process");
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),"novacorp-verify-"));
 try{
  const workflow=JSON.parse(fs.readFileSync(0,"utf8")),file=path.join(dir,"workflow.json");
  fs.writeFileSync(file,JSON.stringify([workflow]),{mode:0o600});
  cp.execFileSync("n8n",["import:workflow","--input",file],{stdio:"pipe"});
  try{
   cp.execFileSync("n8n",["execute","--id",workflow.id],{stdio:"pipe",env:{...process.env,N8N_RUNNERS_BROKER_PORT:"56790"},timeout:170000,maxBuffer:8*1024*1024});
   console.log("success");
  }catch{console.log("failed");}
 }finally{fs.rmSync(dir,{recursive:true,force:true});}
 `,JSON.stringify(workflow)).trim();
}
async function messages(){
 const r=await fetch("http://127.0.0.1:8025/api/v2/messages?limit=200",{signal:AbortSignal.timeout(10000)});
 assert.ok(r.ok);return (await r.json()).items||[];
}
const sql=source=>docker(["exec","-i","supabase_db_NovaCorp","psql","-U","supabase_admin","-d","postgres","-v","ON_ERROR_STOP=1","-At"],source);
const get=async(table,id)=>{const r=await admin.from(table).select("*").eq("request_id",id);assert.equal(r.error,null);return r.data;};
const decide=async(id,position,approve)=>{
 const step=(await get("approval_steps",id)).find(s=>s.position===position);
 assert.equal(step.status,"pending");assert.match(step.assignee_id,/^[a-f0-9-]{36}$/);
 sql("begin; set local role authenticated; set local request.jwt.claims='"+JSON.stringify({sub:step.assignee_id,role:"authenticated"})+"'; select public.decide_hr_approval('"+step.id+"',"+approve+",'Vérification fictive'); commit;");
};
const qualify=async id=>{
 const claim=await admin.rpc("claim_hr_qualification",{p_execution_id:"approval-test-"+randomUUID(),p_provider:"test",p_model:"fixture",p_request_id:id});assert.equal(claim.error,null);
 const done=await admin.rpc("complete_hr_qualification",{p_run_id:claim.data.run_id,p_lease_token:claim.data.lease_token,p_result:{qualification:"eligible",summary:"Fixture : test après qualification",response_draft:"Attente décision humaine"}});
 assert.equal(done.error,null);assert.equal(done.data.completed,true);
};
const notify=async(id,kind)=>{
 for(const n of await get("notifications",id))if(n.status==="queued"&&n.kind!==kind)
  assert.equal((await admin.from("notifications").update({status:"sent",sent_at:new Date().toISOString()}).eq("id",n.id)).error,null);
 const before=new Set((await messages()).map(m=>m.ID));
 assert.equal(await execute("notifications",workflowIds[1],id),"success");
 const fresh=(await messages()).filter(m=>!before.has(m.ID));
 assert.equal(fresh.length,1);
 const mail=fresh[0],encoding=mail.Content.Headers["Content-Transfer-Encoding"]?.[0];
 if(encoding==="quoted-printable")mail.Content.Body=Buffer.from(mail.Content.Body.replace(/=\r?\n/g,"").replace(/=([0-9A-F]{2})/gi,(_,hex)=>String.fromCharCode(parseInt(hex,16))),"latin1").toString("utf8");
 else if(encoding==="base64")mail.Content.Body=Buffer.from(mail.Content.Body,"base64").toString("utf8");
 assert.ok(mail.Content.Body.includes(id));return mail;
};
const age=(id,position,hours)=>{
 assert.match(id,/^[a-f0-9-]{36}$/);assert.match(userId,/^[a-f0-9-]{36}$/);
 assert.ok(Number.isInteger(hours)&&hours>=0&&hours<=100);
 // Simulation limitée aux étapes de la fixture ; aucun trigger global désactivé.
 sql("begin; set local session_replication_role='replica'; update public.approval_steps s set activated_at=now()-interval '"+hours+" hours',due_at=now()+interval '"+(48-hours)+" hours' from public.requests r where r.id=s.request_id and r.requester_id='"+userId+"' and r.id='"+id+"' and s.position="+position+"; commit;");
};
const supervise=async id=>assert.equal(await execute("reminders",workflowIds[0],id),"success");
try{
 assert.equal(JSON.parse(inside(container(),"const {DatabaseSync}=require(\"node:sqlite\");const db=new DatabaseSync(\"/home/node/.n8n/database.sqlite\");try{console.log(JSON.stringify(db.prepare(\"SELECT id FROM workflow_entity WHERE id IN (?,?,?,?,?,?,?,?) AND activeVersionId IS NOT NULL\").all(\"novacorpQualification\",\"novacorpManagerEmails\",\"novacorpApprovals\",\"novacorpNotifications\",\"novacorpReminders\",\"novacorpManagerReminders\",\"novacorpWeeklyDigest\",\"novacorpDigestEmails\")));}finally{db.close();}")).length,0,"Dépubliez qualification, validations, supervision et digests avant ce test.");
 const email="reminders-"+suffix+"@novacorp.test";
 const created=await admin.auth.admin.createUser({email,password:"QualificationDemo2026!",email_confirm:true});
 assert.equal(created.error,null);userId=created.data.user.id;
 const manager=(await admin.from("profiles").select("id").eq("role","manager").limit(1).single()).data;
 assert.equal((await admin.from("profiles").update({manager_id:manager.id}).eq("id",userId)).error,null);
 assert.equal((await user.auth.signInWithPassword({email,password:"QualificationDemo2026!"})).error,null);
 const request=await user.from("requests").insert({requester_id:userId,request_type:"equipment",title:"Test relances "+suffix,amount:1501,quantity:1}).select("id").single();
 assert.equal(request.error,null);const id=request.data.id;
 assert.equal((await user.rpc("submit_hr_request",{p_request_id:id})).error,null);await qualify(id);
 await supervise(id);
 assert.equal((await get("notifications",id)).filter(n=>["reminder","overdue_alert"].includes(n.kind)).length,0);
 console.log("OK supervision : aucune relance immediate.");

 age(id,1,24);await supervise(id);
 assert.equal((await get("notifications",id)).filter(n=>n.kind==="reminder").length,0);
 console.log("OK : aucune relance a 24 h.");
 // Viser le seuil de 8 h Paris, pas l'heure courante du lancement du test.
 const parisDay=sql("select (now() at time zone 'Europe/Paris')::date;").trim();
 const afterEight=sql("select (now() at time zone 'Europe/Paris')::time>=time '08:00';").trim()==="t";
 sql("begin;set local session_replication_role='replica';update public.approval_steps set activated_at=('"+parisDay+" 08:00 Europe/Paris')::timestamptz-interval '49 hours',due_at=('"+parisDay+" 08:00 Europe/Paris')::timestamptz-interval '1 hour' where request_id='"+id+"' and position=1;commit;");
 assert.equal(await execute("manager-reminders",workflowIds[2],id),"success");
 assert.equal((await get("notifications",id)).filter(n=>n.kind==="reminder").length,afterEight?1:0);
 if(afterEight){
  const managerMail=await notify(id,"reminder");assert.ok(managerMail.Content.Body.includes("plus de 48 heures"));
  const managerUser=await admin.auth.admin.getUserById(manager.id);assert.equal(managerUser.error,null);
  assert.ok(JSON.stringify(managerMail.Content.Headers.To).includes(managerUser.data.user.email));
  assert.equal(await execute("manager-reminders",workflowIds[2],id),"success");
  assert.equal((await get("notifications",id)).filter(n=>n.kind==="reminder").length,1);
  const before=(await messages()).length;
  assert.equal(await execute("notifications",workflowIds[1],id),"success");assert.equal((await messages()).length,before);
  console.log("OK rappel quotidien : email au manager, rejeu sans doublon.");
 }else console.log("OK avant 8 h : aucun rappel ; envoi quotidien couvert par les tests SQL.");
 age(id,1,49);await supervise(id);
 const step=(await get("approval_steps",id)).find(s=>s.position===1);assert.equal(step.status,"pending");
 const alert=await notify(id,"overdue_alert");assert.ok(alert.Content.Body.includes("48 heures"));assert.ok(alert.Content.Body.includes("Aucune décision automatique"));
 const referent=(await admin.from("requests").select("hr_referent_id,status").eq("id",id).single()).data;assert.equal(referent.status,"pending_approval");
 const hrUser=await admin.auth.admin.getUserById(referent.hr_referent_id);assert.equal(hrUser.error,null);
 assert.ok(JSON.stringify(alert.Content.Headers.To).includes(hrUser.data.user.email));
 await supervise(id);assert.equal((await get("notifications",id)).filter(n=>n.kind==="overdue_alert").length,1);
 console.log("OK 48 h : email au RH référent et aucune décision automatique.");
 await decide(id,1,true);
 const advanced=await admin.rpc("advance_hr_approvals",{p_execution_id:"reminders-advance-"+suffix,p_request_id:id});assert.equal(advanced.error,null);assert.equal(advanced.data.action,"activate_hr");
 await supervise(id);assert.equal((await get("notifications",id)).filter(n=>n.kind==="reminder").length,afterEight?1:0);
 age(id,2,24);await supervise(id);
 assert.equal(await execute("manager-reminders",workflowIds[2],id),"success");
 assert.equal((await get("notifications",id)).filter(n=>n.kind==="reminder").length,afterEight?1:0);
 age(id,2,49);await supervise(id);
 assert.equal((await user.rpc("cancel_hr_request",{p_request_id:id})).error,null);
 for(const n of await get("notifications",id))if(n.status==="queued"&&n.kind==="status_change")
  assert.equal((await admin.from("notifications").update({status:"sent",sent_at:new Date().toISOString()}).eq("id",n.id)).error,null);
 const afterCancel=(await messages()).length;
 assert.equal(await execute("notifications",workflowIds[1],id),"success");assert.equal((await messages()).length,afterCancel);
 await supervise(id);
 assert.equal((await admin.from("requests").select("status").eq("id",id).single()).data.status,"cancelled");
 console.log("OK étape RH : délai indépendant, aucun rappel quotidien RH, alerte annulée non envoyée.");
}catch(error){
 console.error("Vérification relances échouée :",error.message);
 process.exitCode=1;
}finally{
 if(userId){
  const {data:requests}=await user.from("requests").select("id,status").eq("requester_id",userId);
  for(const request of requests||[])if(!["approved","rejected","cancelled"].includes(request.status))await user.rpc("cancel_hr_request",{p_request_id:request.id});
  docker(["exec","-i","supabase_db_NovaCorp","psql","-U","supabase_admin","-d","postgres","-v","ON_ERROR_STOP=1"],
   "begin; delete from public.requests where requester_id='"+userId+"'; delete from public.leave_balances where employee_id='"+userId+"'; commit;");
  assert.equal((await admin.auth.admin.deleteUser(userId)).error,null);
 }
 // Delete only workflows and their executions whose random IDs were created by this test.
 inside(container(),`
 const {DatabaseSync}=require("node:sqlite");
 const db=new DatabaseSync("/home/node/.n8n/database.sqlite");
 try{
  db.exec("PRAGMA foreign_keys=ON; PRAGMA busy_timeout=10000; BEGIN;");
  for(const id of JSON.parse(require("node:fs").readFileSync(0,"utf8"))){
   db.prepare("DELETE FROM execution_entity WHERE workflowId = ?").run(id);
   db.prepare("DELETE FROM workflow_entity WHERE id = ?").run(id);
  }
  db.exec("COMMIT;");console.log("Workflows fictifs nettoyés.");
 }catch{try{db.exec("ROLLBACK;");}catch{}console.error("Nettoyage des workflows fictifs échoué.");process.exitCode=1;}
 finally{db.close();}
 `,JSON.stringify(workflowIds));
}
