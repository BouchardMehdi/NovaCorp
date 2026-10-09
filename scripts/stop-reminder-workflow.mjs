import {ready} from "./ngrok-tools.mjs";
import {container,inside,docker} from "./n8n-tools.mjs";
try{
 console.log(inside(container(),`
 const cp=require("node:child_process");
 try{
  for(const id of ["novacorpReminders","novacorpManagerReminders"])
   cp.execFileSync("n8n",["unpublish:workflow","--id",id],{stdio:"pipe"});
  console.log("Workflows dépubliés.");
 }catch{console.error("Arrêt des workflows impossible.");process.exitCode=1;}
 `).trim());
 docker(["compose","--profile","automation","restart","n8n"]);
 await ready();
}catch{console.error("Arrêt impossible. Vérifiez le service n8n.");process.exitCode=1;}
