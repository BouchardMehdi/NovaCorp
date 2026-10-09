import {readFile,writeFile} from "node:fs/promises";
const mail=JSON.parse(await readFile("n8n/workflows/manager-emails.json","utf8"));
mail.id="novacorpNotifications";mail.name="NovaCorp - Notifications RH et salarié";
for(const node of mail.nodes) {
 if(node.type==="n8n-nodes-base.httpRequest") {
  node.parameters.url=node.parameters.url.replace("claim_hr_manager_email","claim_hr_notification_email").replace("finish_hr_manager_email","finish_hr_notification_email");
 }
}
const template=mail.nodes.find(n=>n.name==="Reserver le message");
const advance={id:"novacorpApprovals",name:"NovaCorp - Avancement des validations",active:false,
 nodes:[...mail.nodes.filter(n=>["Manuel","Toutes les minutes","Configuration"].includes(n.name)),
 {...template,id:"Avancer le circuit",name:"Avancer le circuit",parameters:{...template.parameters,
 url:"http://supabase_kong_NovaCorp:8000/rest/v1/rpc/advance_hr_approvals",
 jsonBody:"={{ {p_execution_id:String($execution.id),p_request_id:$json.request_id || null} }}"}}],
 connections:{"Manuel":{main:[[{node:"Configuration",type:"main",index:0}]]},
 "Toutes les minutes":{main:[[{node:"Configuration",type:"main",index:0}]]},
 "Configuration":{main:[[{node:"Avancer le circuit",type:"main",index:0}]]}},
 settings:mail.settings,pinData:{}};
for(const [name,data]of Object.entries({"approvals":advance,"notifications":mail}))
 await writeFile("n8n/workflows/"+name+".json",JSON.stringify(data,null,2)+"\n");
console.log("Workflows avancement et notifications générés.");
