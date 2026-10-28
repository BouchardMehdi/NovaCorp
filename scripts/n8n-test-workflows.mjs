import {readFile} from "node:fs/promises";
import {container,inside} from "./n8n-tools.mjs";
import {publicationSyncCode} from "./n8n-publication.mjs";
const installedChildren=new Set();

// Imports only named, random-ID test copies. The published workflows are untouched.
export async function executeTestWorkflow(name,id,requestId,model,ownedIds){
 const workflow=JSON.parse(await readFile("n8n/workflows/"+name+".json","utf8"));
 workflow.id=id;workflow.name="TEST NovaCorp "+id;workflow.active=false;
 for(const n of workflow.nodes.filter(n=>n.type==="n8n-nodes-base.scheduleTrigger"))delete workflow.connections[n.name];
 workflow.nodes=workflow.nodes.filter(n=>n.type!=="n8n-nodes-base.scheduleTrigger");
 const fields=workflow.nodes.find(n=>n.name==="Configuration").parameters.assignments.assignments;
 fields.find(f=>f.name==="request_id").value=requestId;
 if(model&&fields.some(f=>f.name==="model"))fields.find(f=>f.name==="model").value=model;
 const workflows=[workflow];
 if(name==="qualification"){
  const child=JSON.parse(await readFile("n8n/workflows/ai-qualification.json","utf8"));
  child.id=id+"Ai";child.name="TEST NovaCorp "+child.id;child.active=false;child.settings.callerIds=id;
  if(!ownedIds.includes(child.id))ownedIds.push(child.id);
  workflow.nodes.find(n=>n.type==="n8n-nodes-base.executeWorkflow").parameters.workflowId.value=child.id;
  if(model)child.nodes.find(n=>n.name==="Preparer le prompt").parameters.jsCode=
   child.nodes.find(n=>n.name==="Preparer le prompt").parameters.jsCode.replace("'qwen3:1.7b'",JSON.stringify(model));
  if(!installedChildren.has(child.id)){workflows.unshift(child);installedChildren.add(child.id);}
 }
 const output=inside(container(),`
  const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),cp=require('node:child_process');
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'novacorp-verify-'));
  try{
   const input=JSON.parse(fs.readFileSync(0,'utf8')),file=path.join(dir,'workflows.json');
   fs.writeFileSync(file,JSON.stringify(input.workflows),{mode:0o600});
   cp.execFileSync('n8n',['import:workflow','--input',file],{stdio:'pipe'});
   if(input.workflows.length>1){cp.execFileSync('n8n',['publish:workflow','--id',input.workflows[0].id],{stdio:'pipe'});const publicationIds=[input.workflows[0].id];${publicationSyncCode}}
   try{cp.execFileSync('n8n',['execute','--id',input.id],{stdio:'pipe',env:{...process.env,N8N_RUNNERS_BROKER_PORT:'56790'},timeout:240000,maxBuffer:8*1024*1024});console.log('success');}
   catch{
    // Emit node names only; never print execution data (it may include reservation tokens).
    try{const {DatabaseSync}=require('node:sqlite');const db=new DatabaseSync('/home/node/.n8n/database.sqlite');
     const parse=require(require.resolve('flatted',{paths:['/usr/local/lib/node_modules/n8n']})).parse;
     for(const w of input.workflows){const row=db.prepare('select d.data from execution_data d join execution_entity e on e.id=d.executionId where e.workflowId=? order by e.id desc limit 1').get(w.id);if(row){const data=parse(row.data);const error=data.resultData?.error;console.log('Diagnostic n8n:',w.id,error?.node?.name||data.resultData?.lastNodeExecuted||'inconnu',w.nodes.some(n=>n.credentials)?'':String(error?.message||'').slice(0,400));const call=data.resultData?.runData?.['Appeler le sous-workflow IA']?.[0];if(call){const message=call.error?.message||call.data?.main?.[0]?.[0]?.json?.error;console.log('Diagnostic appel IA:',String(message?.message||message||'').slice(0,400));}}}
     db.close();}catch{}
    console.log('failed');
   }
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
 `,JSON.stringify({workflows,id})).trim();
 for(const line of output.split(/\r?\n/).filter(x=>x.startsWith("Diagnostic ")))console.error(line);
 return output.split(/\r?\n/).at(-1);
}
