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
const workflowIds=["qualTest"+suffix,"mailTest"+suffix,"failTest"+suffix];
let userId;
async function execute(workflowName,id,requestId,model){
 const workflow=JSON.parse(await readFile("n8n/workflows/"+workflowName+".json","utf8"));
 workflow.id=id;workflow.name="TEST NovaCorp "+id;workflow.active=false;
 workflow.nodes=workflow.nodes.filter(node=>node.type!=="n8n-nodes-base.scheduleTrigger");
 delete workflow.connections["Toutes les minutes"];
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
try{
 const published=inside(container(),`
 const {DatabaseSync}=require("node:sqlite");const db=new DatabaseSync("/home/node/.n8n/database.sqlite");
 try{console.log(JSON.stringify(db.prepare("SELECT id FROM workflow_entity WHERE id IN (?,?,?,?) AND activeVersionId IS NOT NULL").all("novacorpQualification","novacorpManagerEmails","novacorpApprovals","novacorpNotifications")));}finally{db.close();}
 `);
 assert.equal(JSON.parse(published).length,0,"Dépubliez les workflows avec npm run n8n:qualification:stop et npm run n8n:approvals:stop avant la vérification.");
 const {data:created,error}=await admin.auth.admin.createUser({email:"qualification-"+suffix+"@novacorp.test",password:"QualificationDemo2026!",email_confirm:true});
 assert.equal(error,null);userId=created.user.id;
 const {data:manager}=await admin.from("profiles").select("id").eq("role","manager").limit(1).single();
 assert.ok(manager);assert.equal((await admin.from("profiles").update({manager_id:manager.id}).eq("id",userId)).error,null);
 assert.equal((await admin.from("leave_balances").insert({employee_id:userId,year:2026,allocated_days:25})).error,null);
 assert.equal((await user.auth.signInWithPassword({email:created.user.email,password:"QualificationDemo2026!"})).error,null);
 for(const kind of ["leave","remote_work","equipment","training"]){
  const payload={requester_id:userId,request_type:kind,title:"Vérification "+kind+" "+suffix,description:"Demande fictive pour vérifier le circuit. Merci de résumer le besoin sans décider.",
   ...(kind==="equipment"?{amount:1501,quantity:1}:{start_date:"2026-11-02",end_date:"2026-11-03",...(kind==="training"?{amount:1501,training_provider:"Centre fictif"}:{})})};
  const {data:request,error}=await user.from("requests").insert(payload).select("id,reference").single();assert.equal(error,null);
  assert.equal((await user.rpc("submit_hr_request",{p_request_id:request.id})).error,null);
  assert.equal(await execute("qualification",workflowIds[0],request.id),"success","Qualification n8n doit réussir.");
  const {data:after}=await admin.from("requests").select("status").eq("id",request.id).single();assert.equal(after.status,"pending_approval");
  const {data:reviews}=await admin.from("ai_reviews").select("qualification,summary,status,provider,model").eq("request_id",request.id);assert.equal(reviews.length,1);assert.equal(reviews[0].status,"succeeded");assert.equal(reviews[0].provider,"ollama");assert.ok(reviews[0].summary.trim());
  const {data:steps}=await admin.from("approval_steps").select("position,status").eq("request_id",request.id).order("position");assert.equal(steps[0].status,"pending");assert.ok(steps.slice(1).every(step=>step.status==="waiting"));assert.equal(steps.length,["equipment","training"].includes(kind)?3:2);
  const before=new Set((await messages()).map(mail=>mail.ID));
  assert.equal(await execute("manager-emails",workflowIds[1],request.id),"success");
  const newMail=(await messages()).filter(mail=>!before.has(mail.ID));
  assert.equal(newMail.length,1,"Un seul email manager doit être reçu.");
  assert.ok(newMail[0].Content.Body.includes(request.id));
  assert.equal((await admin.from("notifications").select("status").eq("request_id",request.id).eq("kind","approval_needed").single()).data.status,"sent");
  assert.equal(await execute("qualification",workflowIds[0],request.id),"success");
  const countBefore=(await messages()).length;
  assert.equal(await execute("manager-emails",workflowIds[1],request.id),"success");assert.equal((await messages()).length,countBefore);
  assert.equal((await admin.from("ai_reviews").select("id").eq("request_id",request.id)).data.length,1);
  assert.equal((await user.rpc("cancel_hr_request",{p_request_id:request.id})).error,null);
  console.log("OK "+kind+" : vrai modèle local, manager seul actif, email reçu, rejeu sans doublon.");
 }
 const {data:failure}=await user.from("requests").insert({requester_id:userId,request_type:"equipment",title:"Modèle absent "+suffix,amount:10,quantity:1}).select("id").single();
 assert.equal((await user.rpc("submit_hr_request",{p_request_id:failure.id})).error,null);
 assert.equal(await execute("qualification",workflowIds[2],failure.id,"novacorp-modele-inexistant"),"failed");
 assert.equal((await admin.from("workflow_runs").select("status,error_code").eq("request_id",failure.id).single()).data.error_code,"llm_http_error");
 assert.equal((await admin.from("requests").select("status").eq("id",failure.id).single()).data.status,"under_review");
 assert.equal((await admin.from("approval_steps").select("id").eq("request_id",failure.id)).data.length,0);
 console.log("OK erreur Ollama : échec tracé, aucune validation ni décision automatique.");
}catch(error){
 console.error("Vérification qualification échouée :",error.message);
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
