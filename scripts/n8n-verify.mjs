import { container,inside } from "./n8n-tools.mjs";
const subject="NovaCorp - verification n8n";
async function messages(){
 const response=await fetch("http://127.0.0.1:8025/api/v2/messages?limit=100",{signal:AbortSignal.timeout(10000)});
 if(!response.ok)throw new Error("MailHog indisponible.");
 return (await response.json()).items||[];
}
try{
 const id=container();
 const health=await fetch("http://127.0.0.1:5678/healthz/readiness",{signal:AbortSignal.timeout(10000)});
 if(!health.ok)throw new Error("n8n pas encore prêt.");
 const before=new Set((await messages()).map(message=>message.ID));
 const result=inside(id,`
 const cp=require("node:child_process");
 try{
  cp.execFileSync("n8n",["execute","--id","novacorpSetupSmoke"],{stdio:"pipe",env:{...process.env,N8N_RUNNERS_BROKER_PORT:"56790"},timeout:120000,maxBuffer:8*1024*1024});
  console.log("Workflow exécuté.");
 }catch{console.error("Échec du workflow de vérification.");process.exitCode=1;}
 `);
 const mail=(await messages()).find(message=>!before.has(message.ID)&&message.Content?.Headers?.Subject?.includes(subject)&&message.Content?.Headers?.To?.includes("verification@novacorp.test"));
 if(!mail)throw new Error("Aucun nouvel email de vérification reçu.");
 console.log(result.trim());
 console.log("OK : n8n prêt, 4 types RH lus dans Supabase, email fictif reçu dans MailHog.");
}catch{
 console.error("Vérification échouée. Vérifiez les services et exécutez npm run n8n:setup avant de réessayer.");
 process.exitCode=1;
}
