import {container,inside,docker} from "./n8n-tools.mjs";
try{
 console.log(inside(container(),`
 const cp=require("node:child_process");
 try{
  for(const id of ["novacorpReminders"])
   cp.execFileSync("n8n",["publish:workflow","--id",id],{stdio:"pipe"});
  console.log("Workflows publiés.");
 }catch{console.error("Publication impossible.");process.exitCode=1;}
 `).trim());
 docker(["compose","--profile","automation","restart","n8n"]);
 docker(["compose","--profile","automation","up","-d","--wait","n8n"]);
 console.log("Supervision des délais planifiée chaque minute.");
}catch{console.error("Activation impossible. Vérifiez n8n et l’import des workflows.");process.exitCode=1;}
