import {container,inside,docker} from "./n8n-tools.mjs";
try{
 console.log(inside(container(),`
 const cp=require("node:child_process");
 try{
  cp.execFileSync("n8n",["unpublish:workflow","--id","novacorpManagerEmails"],{stdio:"pipe"});
  for(const id of ["novacorpApprovals","novacorpNotifications"])
   cp.execFileSync("n8n",["publish:workflow","--id",id],{stdio:"pipe"});
  console.log("Workflows publiés.");
 }catch{console.error("Publication impossible.");process.exitCode=1;}
 `).trim());
 docker(["compose","--profile","automation","restart","n8n"]);
 docker(["compose","--profile","automation","up","-d","--wait","n8n"]);
 console.log("Avancement et notifications planifiés chaque minute. Ancien envoi manager désactivé.");
}catch{console.error("Activation impossible. Vérifiez n8n et l’import des workflows.");process.exitCode=1;}
