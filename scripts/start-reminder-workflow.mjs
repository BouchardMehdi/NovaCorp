import {ready} from "./ngrok-tools.mjs";
import {container,inside,docker} from "./n8n-tools.mjs";
try{
 console.log(inside(container(),`
 const cp=require("node:child_process");
 try{
  for(const id of ["novacorpReminders","novacorpManagerReminders"])
   cp.execFileSync("n8n",["publish:workflow","--id",id],{stdio:"pipe"});
  console.log("Workflows publiés.");
 }catch{console.error("Publication impossible.");process.exitCode=1;}
 `).trim());
 docker(["compose","--profile","automation","restart","n8n"]);
 await ready();
 console.log("Rappel manager à 8 h (Paris) ; alertes RH surveillées chaque minute.");
}catch{console.error("Activation impossible. Vérifiez n8n et l’import des workflows.");process.exitCode=1;}
