import {container,inside,docker} from "./n8n-tools.mjs";
try{
 const models=await fetch("http://127.0.0.1:11434/api/tags",{signal:AbortSignal.timeout(10000)});
 if(!models.ok||(await models.json()).models?.some(model=>model.name==="qwen3:1.7b")!==true)
  throw new Error("Modèle absent.");
 console.log(inside(container(),`
 const cp=require("node:child_process");
 try{
  for(const id of ["novacorpQualification"])
   cp.execFileSync("n8n",["publish:workflow","--id",id],{stdio:"pipe"});
  console.log("Workflows publiés.");
 }catch{console.error("Publication impossible.");process.exitCode=1;}
 `).trim());
 docker(["compose","--profile","automation","restart","n8n"]);
 docker(["compose","--profile","automation","up","-d","--wait","n8n"]);
 console.log("Qualification planifiée chaque minute. Les emails sont activés par n8n:approvals:start.");
}catch{console.error("Activation impossible. Vérifiez Ollama, le modèle et l’import des workflows.");process.exitCode=1;}
