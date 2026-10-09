import {createClient} from "@supabase/supabase-js";
import {randomUUID} from "node:crypto";
import {readFile} from "node:fs/promises";
import assert from "node:assert/strict";
import {container,inside} from "./n8n-tools.mjs";
const url=process.env.NEXT_PUBLIC_SUPABASE_URL;
if(!url||!["localhost","127.0.0.1","[::1]"].includes(new URL(url).hostname))throw new Error("Verification reservee a Supabase local.");
const admin=createClient(url,process.env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
const suffix=randomUUID().slice(0,8),ids=["onboardingTest"+suffix];
let employeeId;
async function execute(name,id){
 const workflow=JSON.parse(await readFile("n8n/workflows/"+name+".json","utf8"));
 workflow.id=id;workflow.name="TEST NovaCorp "+id;workflow.active=false;
 for(const n of workflow.nodes.filter(n=>n.type==="n8n-nodes-base.scheduleTrigger"))delete workflow.connections[n.name];
 workflow.nodes=workflow.nodes.filter(n=>n.type!=="n8n-nodes-base.scheduleTrigger");
 workflow.nodes.find(n=>n.name==="Configuration").parameters.assignments.assignments[0].value=employeeId;
 inside(container(),`
  const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),cp=require('node:child_process');
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'novacorp-onboarding-test-'));
  try{const file=path.join(dir,'workflow.json'),w=JSON.parse(fs.readFileSync(0,'utf8'));fs.writeFileSync(file,JSON.stringify([w]),{mode:0o600});
   cp.execFileSync('n8n',['import:workflow','--input',file],{stdio:'pipe'});
   cp.execFileSync('n8n',['execute','--id',w.id],{stdio:'pipe',env:{...process.env,N8N_RUNNERS_BROKER_PORT:'56790'},timeout:170000,maxBuffer:8*1024*1024});
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
 `,JSON.stringify(workflow));
}
async function messages(){const response=await fetch("http://127.0.0.1:8025/api/v2/messages?limit=500",{signal:AbortSignal.timeout(10000)});assert.ok(response.ok);return (await response.json()).items||[];}
try{

 const published=JSON.parse(inside(container(),`const {DatabaseSync}=require('node:sqlite');const db=new DatabaseSync('/home/node/.n8n/database.sqlite');try{console.log(JSON.stringify(db.prepare('select id from workflow_entity where id=? and activeVersionId is not null').all('novacorpOnboarding')));}finally{db.close();}`));
 assert.equal(published.length,0,'Depubliez onboarding avec npm run n8n:onboarding:stop avant le test.');
 const email='onboarding-'+suffix+'@novacorp.test';
 const created=await admin.auth.admin.createUser({email,password:randomUUID()+'Aa1!',email_confirm:true,user_metadata:{first_name:'Nina',last_name:'Verification'}});assert.equal(created.error,null);employeeId=created.data.user.id;
 const queued=await admin.from('employee_onboardings').select('*').eq('employee_id',employeeId).single();assert.equal(queued.error,null);assert.equal(queued.data.status,'queued');assert.equal(queued.data.checklist.length,6);
 const before=new Set((await messages()).map(m=>m.ID));
 await execute('onboarding',ids[0]);
 const fresh=(await messages()).filter(m=>!before.has(m.ID)&&JSON.stringify(m.Content.Headers.To).includes(email));assert.equal(fresh.length,1);
 const mail=fresh[0],encoding=mail.Content.Headers['Content-Transfer-Encoding']?.[0];let body=mail.Content.Body;
 if(encoding==='quoted-printable')body=Buffer.from(body.replace(/=\r?\n/g,'').replace(/=([0-9A-F]{2})/gi,(_,h)=>String.fromCharCode(parseInt(h,16))),'latin1').toString('utf8');
 else if(encoding==='base64')body=Buffer.from(body,'base64').toString('utf8');
 assert.ok(body.includes('Bonjour Nina'));assert.ok(body.includes('Checklist du premier jour'));assert.equal((body.match(/\[ \]/g)||[]).length,6);assert.ok(body.includes('localhost:3000/connexion'));
 const sent=await admin.from('employee_onboardings').select('status,attempts').eq('employee_id',employeeId).single();assert.equal(sent.error,null);assert.equal(sent.data.status,'sent');assert.equal(sent.data.attempts,1);
 assert.equal((await admin.from('profiles').update({first_name:'Nina mise a jour'}).eq('id',employeeId)).error,null);
 await execute('onboarding',ids[0]);
 assert.equal((await messages()).filter(m=>JSON.stringify(m.Content.Headers.To).includes(email)).length,1);
 console.log('OK onboarding : nouveau profil, email de bienvenue, checklist de six etapes, lien et rejeu sans doublon.');
}catch(error){console.error("Verification onboarding echouee :",error.message);process.exitCode=1;}
finally{
 if(employeeId)assert.equal((await admin.auth.admin.deleteUser(employeeId)).error,null);
 inside(container(),`
  const {DatabaseSync}=require('node:sqlite');const db=new DatabaseSync('/home/node/.n8n/database.sqlite');
  try{db.exec('PRAGMA foreign_keys=ON; PRAGMA busy_timeout=10000; BEGIN;');for(const id of JSON.parse(require('node:fs').readFileSync(0,'utf8'))){db.prepare('DELETE FROM execution_entity WHERE workflowId=?').run(id);db.prepare('DELETE FROM workflow_entity WHERE id=?').run(id);}db.exec('COMMIT;');}
  catch(e){try{db.exec('ROLLBACK;');}catch{}throw e;}finally{db.close();}
 `,JSON.stringify(ids));
}
