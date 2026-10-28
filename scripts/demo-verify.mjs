import {execFileSync} from "node:child_process";
import {randomBytes} from "node:crypto";
import {mkdir,writeFile} from "node:fs/promises";
import {container,docker} from "./n8n-tools.mjs";
import {ready} from "./ngrok-tools.mjs";
const cases={S1:"verify-qualification.mjs",S2:"verify-approvals.mjs",S3:"verify-reminders.mjs",S4:"verify-digest.mjs",S5:"verify-onboarding.mjs",IA:"verify-ai-policy.mjs"};
const requested=process.argv.slice(2);
const scenario=requested[0]||"all";
if((scenario==="all"&&requested.length>1)||requested.some(x=>x!=="all"&&!Object.hasOwn(cases,x)))throw new Error("Choisir all ou une liste parmi S1, S2, S3, S4, S5, IA.");
if(process.env.NOVACORP_TEST_CONTAINER)throw new Error("Ne pas imbriquer les lanceurs de recette.");
const entries=scenario==="all"?Object.entries(cases):[...new Set(requested)].map(name=>[name,cases[name]]);
const cid=container(),testId="novacorp-verify-"+randomBytes(6).toString("hex");
const report={started_at:new Date().toISOString(),environment:"local-fictitious",scenarios:[],restored:false};
let stopped=false,created=false;
await mkdir("test-results",{recursive:true});
const save=()=>writeFile("test-results/demo-report.json",JSON.stringify(report,null,2)+"\n");
await save();
try{
 if(entries.some(([name])=>name!=="IA")){
  console.log("Arret temporaire du service n8n ; publications et configuration conservees.");
  stopped=true;docker(["stop","--time","270",cid]);
  // A one-off container shares the existing volume/credentials but runs no server or scheduler.
  // No ports are published; n8n CLI executes only the random-ID test workflows.
  docker(["compose","--profile","automation","run","-d","--no-deps","--name",testId,"--entrypoint","node","n8n","-e","setInterval(()=>{},60000)"]);created=true;
 }
 for(const [name,file] of entries){
  const start=Date.now();let passed=false;
  try{execFileSync(process.execPath,["--env-file=.env.local","scripts/"+file,...(name==="S2"?["--real-llm"]:[])],{stdio:"inherit",timeout:1800000,env:{...process.env,...(created?{NOVACORP_TEST_CONTAINER:testId}:{})}});passed=true;}
  finally{report.scenarios.push({scenario:name,passed,duration_ms:Date.now()-start});await save();}
 }
}catch(error){console.error("Verification interrompue :",error.message);process.exitCode=1;}
finally{
 try{
  if(created)docker(["rm","-f",testId]);
  if(stopped){docker(["start",cid]);await ready();}
  report.restored=true;
 }catch{console.error("Verifier la reprise du service n8n avec docker start "+cid);process.exitCode=1;}
 report.finished_at=new Date().toISOString();await save();
 console.log("Rapport : test-results/demo-report.json ; sans cle ni contenu de demande.");
}
