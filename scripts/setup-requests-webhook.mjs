import { readFile } from "node:fs/promises";
import { container, inside, docker } from "./n8n-tools.mjs";
import { prepare, ready } from "./ngrok-tools.mjs";

try {
  const token = await prepare();
  const workflow = JSON.parse(await readFile("n8n/workflows/requests-webhook.json", "utf8"));
  const result = inside(container(), `
    const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),cp=require('node:child_process');
    const dir=fs.mkdtempSync(path.join(os.tmpdir(),'novacorp-webhook-'));
    try {
      const {workflow,token}=JSON.parse(fs.readFileSync(0,'utf8'));
      const credentials=[{id:'novacorpRequestsWebhookAuth',name:'NovaCorp - Webhook requests',type:'httpHeaderAuth',
        data:{name:'X-NovaCorp-Webhook-Token',value:token}}];
      fs.writeFileSync(path.join(dir,'credentials.json'),JSON.stringify(credentials),{mode:0o600});
      fs.writeFileSync(path.join(dir,'workflow.json'),JSON.stringify([workflow]),{mode:0o600});
      for(const [command,file] of [['import:credentials','credentials.json'],['import:workflow','workflow.json']])
        cp.execFileSync('n8n',[command,'--input',path.join(dir,file)],{stdio:'pipe'});
      cp.execFileSync('n8n',['publish:workflow','--id',workflow.id],{stdio:'pipe'});
      console.log('Webhook authentifié importé et publié. Aucun traitement RH ajouté.');
    } catch { console.error('Installation du webhook impossible.');process.exitCode=1; }
    finally { fs.rmSync(dir,{recursive:true,force:true}); }
  `, JSON.stringify({ workflow, token }));
  console.log(result.trim());
  docker(["compose", "--profile", "automation", "restart", "n8n"]);
  await ready();
  console.log("Webhook local prêt : http://localhost:5678/webhook/novacorp-requests");
} catch {
  console.error("Installation impossible. Vérifier n8n:start, le compte propriétaire et la configuration locale.");
  process.exitCode = 1;
}
