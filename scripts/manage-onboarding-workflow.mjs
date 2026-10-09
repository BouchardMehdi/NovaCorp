import {readFile} from "node:fs/promises";
import {container,inside,docker} from "./n8n-tools.mjs";
import {ready} from "./ngrok-tools.mjs";
const action=process.argv[2];
if(!["install","start","stop"].includes(action))throw new Error("Action attendue : install, start ou stop.");
try{
 if(action==="install"){
  const workflows=await Promise.all(["onboarding"].map(async name=>JSON.parse(await readFile("n8n/workflows/"+name+".json","utf8"))));
  inside(container(),`
   const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),cp=require('node:child_process');
   const dir=fs.mkdtempSync(path.join(os.tmpdir(),'novacorp-onboarding-'));
   try{const file=path.join(dir,'workflows.json');fs.writeFileSync(file,fs.readFileSync(0),{mode:0o600});cp.execFileSync('n8n',['import:workflow','--input',file],{stdio:'pipe'});}
   finally{fs.rmSync(dir,{recursive:true,force:true});}
  `,JSON.stringify(workflows));
  console.log("Onboarding importe. Activer avec npm run n8n:onboarding:start.");
 }else{
  inside(container(),`const cp=require('node:child_process');for(const id of ['novacorpOnboarding'])cp.execFileSync('n8n',[${JSON.stringify(action==="start"?"publish:workflow":"unpublish:workflow")},'--id',id],{stdio:'pipe'});`);
  docker(["compose","--profile","automation","restart","n8n"]);await ready();
  console.log(action==="start"?"Onboarding actif : envoi et reprises SMTP chaque minute.":"Onboarding depublie.");
 }
}catch{console.error("Operation onboarding impossible. Verifiez n8n et les connexions locales.");process.exitCode=1;}
