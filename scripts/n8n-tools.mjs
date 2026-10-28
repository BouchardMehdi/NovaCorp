import { execFileSync } from "node:child_process";
export function docker(args,input){
 return execFileSync("docker",args,{input,encoding:"utf8",maxBuffer:8*1024*1024,timeout:360000,stdio:["pipe","pipe","pipe"]});
}
export function container(){
 if(process.env.NOVACORP_TEST_CONTAINER){
  const id=process.env.NOVACORP_TEST_CONTAINER;
  if(!/^novacorp-verify-[a-f0-9]{12}$/.test(id))throw new Error("Conteneur de test invalide.");
  const main=docker(["ps","-a","--filter","label=com.docker.compose.project=novacorp","--filter","label=com.docker.compose.service=n8n","--filter","label=com.docker.compose.oneoff=False","--format","{{.ID}}"] ).trim();
  if(!main||docker(["inspect","--format","{{.State.Running}}",main]).trim()!=="false")throw new Error("Arreter le planificateur principal avant les tests isoles.");
  if(docker(["inspect","--format","{{index .Config.Labels \"com.docker.compose.service\"}}",id]).trim()!=="n8n")throw new Error("Service de test invalide.");
  return id;
 }
 const id=docker(["ps","--filter","label=com.docker.compose.project=novacorp","--filter","label=com.docker.compose.service=n8n","--filter","label=com.docker.compose.oneoff=False","--format","{{.ID}}"] ).trim();
 if(!id)throw new Error("Démarrez n8n avec npm run n8n:start.");
 return id;
}
export function assertSchedulersPaused(published){
 if(process.env.NOVACORP_TEST_CONTAINER){container();return;}
 if(published.length)throw new Error("Arreter les planificateurs avec le lanceur npm run demo:verify avant ce test.");
}
export function inside(id,code,input){
 return docker(["exec","-i","-u","node",id,"node","-e",code],input);
}
