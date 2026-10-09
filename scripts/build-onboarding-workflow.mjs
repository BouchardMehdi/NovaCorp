import {readFile,writeFile} from "node:fs/promises";
const mail=JSON.parse(await readFile("n8n/workflows/notifications.json","utf8"));
mail.id="novacorpOnboarding";mail.name="NovaCorp - Bienvenue et checklist premier jour";
mail.nodes.find(n=>n.name==="Configuration").parameters.assignments.assignments=[{id:"employee_id",name:"employee_id",value:"",type:"string"}];
for(const node of mail.nodes.filter(n=>n.type==="n8n-nodes-base.httpRequest")){
 node.parameters.url=node.parameters.url.replace("claim_hr_notification_email","claim_employee_onboarding").replace("finish_hr_notification_email","finish_employee_onboarding");
 if(node.name==="Reserver le message")node.parameters.jsonBody="={{ {p_employee_id:$json.employee_id || null} }}";
}
await writeFile("n8n/workflows/onboarding.json",JSON.stringify(mail,null,2)+"\n");
console.log("Workflow onboarding généré sans secrets.");
