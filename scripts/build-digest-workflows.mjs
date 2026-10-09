import {readFile,writeFile} from "node:fs/promises";
const queue=JSON.parse(await readFile("n8n/workflows/manager-reminders.json","utf8"));
queue.id="novacorpWeeklyDigest";queue.name="NovaCorp - Digest manager lundi 8 h";
const timer=queue.nodes.find(n=>n.type==="n8n-nodes-base.scheduleTrigger");
delete queue.connections[timer.name];timer.id=timer.name="Chaque lundi a 8 h";
queue.connections[timer.name]={main:[[{node:"Configuration",type:"main",index:0}]]};
timer.parameters={rule:{interval:[{field:"cronExpression",expression:"0 8 * * 1"}]}};
queue.nodes.find(n=>n.name==="Configuration").parameters.assignments.assignments=[{id:"manager_id",name:"manager_id",value:"",type:"string"}];
const rpc=queue.nodes.find(n=>n.type==="n8n-nodes-base.httpRequest");
rpc.parameters.url="http://supabase_kong_NovaCorp:8000/rest/v1/rpc/queue_weekly_manager_digests";
rpc.parameters.jsonBody="={{ {p_manager_id:$json.manager_id || null} }}";
const mail=JSON.parse(await readFile("n8n/workflows/notifications.json","utf8"));
mail.id="novacorpDigestEmails";mail.name="NovaCorp - Envoi des digests manager";
mail.nodes.find(n=>n.name==="Configuration").parameters.assignments.assignments=[{id:"manager_id",name:"manager_id",value:"",type:"string"}];
for(const node of mail.nodes.filter(n=>n.type==="n8n-nodes-base.httpRequest")){
 node.parameters.url=node.parameters.url.replace("claim_hr_notification_email","claim_weekly_manager_digest").replace("finish_hr_notification_email","finish_weekly_manager_digest");
 if(node.name==="Reserver le message")node.parameters.jsonBody="={{ {p_manager_id:$json.manager_id || null} }}";
}
for(const [name,workflow] of [["weekly-digest",queue],["digest-emails",mail]])
 await writeFile("n8n/workflows/"+name+".json",JSON.stringify(workflow,null,2)+"\n");
console.log("Workflows digest generes sans secrets.");
