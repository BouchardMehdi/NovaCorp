import { readFile } from "node:fs/promises";
import { container,inside } from "./n8n-tools.mjs";
try{
 const id=container();
 const workflow=JSON.parse(await readFile("n8n/workflows/setup-smoke.json","utf8"));
 const result=inside(id,`
 const fs=require("node:fs"),os=require("node:os"),path=require("node:path"),cp=require("node:child_process");
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),"novacorp-setup-"));
 let stage="configuration";
 try{
  if(!process.env.N8N_ENCRYPTION_KEY||!process.env.NOVACORP_SUPABASE_SERVICE_ROLE_KEY)throw new Error("missing config");
  const workflow=JSON.parse(fs.readFileSync(0,"utf8"));
  const credentials=[
   {id:"novacorpSupabaseLocal",name:"NovaCorp - Supabase local",type:"supabaseApi",data:{host:process.env.NOVACORP_SUPABASE_URL,serviceRole:process.env.NOVACORP_SUPABASE_SERVICE_ROLE_KEY}},
   {id:"novacorpMailhogLocal",name:"NovaCorp - MailHog local",type:"smtp",data:{host:"mailhog",port:1025,secure:false,disableStartTls:true,user:"",password:"",hostName:"novacorp.test"}}
  ];
  fs.writeFileSync(path.join(dir,"credentials.json"),JSON.stringify(credentials),{mode:0o600});
  fs.writeFileSync(path.join(dir,"workflow.json"),JSON.stringify([workflow]),{mode:0o600});
  stage="identifiants";cp.execFileSync("n8n",["import:credentials","--input",path.join(dir,"credentials.json")],{stdio:"pipe"});
  stage="workflow";cp.execFileSync("n8n",["import:workflow","--input",path.join(dir,"workflow.json")],{stdio:"pipe"});
  console.log("Connexions Supabase/MailHog et workflow manuel importés.");
 }catch{console.error("Import n8n échoué à l’étape : "+stage+".");process.exitCode=1;}
 finally{fs.rmSync(dir,{recursive:true,force:true});}
 `,JSON.stringify(workflow));
 console.log(result.trim());
}catch{
 console.error("Installation des connexions impossible. Vérifiez npm run n8n:start et la création du compte propriétaire dans n8n.");
 process.exitCode=1;
}
