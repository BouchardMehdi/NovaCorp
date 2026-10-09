import { execFileSync } from "node:child_process";
export function docker(args,input){
 return execFileSync("docker",args,{input,encoding:"utf8",maxBuffer:8*1024*1024,timeout:180000,stdio:["pipe","pipe","pipe"]});
}
export function container(){
 const id=docker(["compose","--profile","automation","ps","-q","n8n"]).trim();
 if(!id)throw new Error("Démarrez n8n avec npm run n8n:start.");
 return id;
}
export function inside(id,code,input){
 return docker(["exec","-i","-u","node",id,"node","-e",code],input);
}
