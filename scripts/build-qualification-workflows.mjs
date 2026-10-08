import {writeFile,mkdir} from "node:fs/promises";
import {resultSchema,systemPrompt,buildOllamaBody,validateOllamaResponse} from "../n8n/lib/qualification.mjs";
const base="http://supabase_kong_NovaCorp:8000/rest/v1/rpc/";
const credentials={supabaseApi:{id:"novacorpSupabaseLocal",name:"NovaCorp - Supabase local"}};
const node=(name,type,parameters,x,y=0,extra={})=>({id:name,name,type:"n8n-nodes-base."+type,typeVersion:({httpRequest:4.2,code:2,if:2.2,set:3.4,emailSend:2.1,scheduleTrigger:1.2,manualTrigger:1,stopAndError:1})[type],parameters,position:[x,y],...extra});
const rpc=(name,fn,json,x,extra={})=>node(name,"httpRequest",{method:"POST",url:base+fn,authentication:"predefinedCredentialType",nodeCredentialType:"supabaseApi",sendBody:true,specifyBody:"json",jsonBody:json,options:{timeout:15000}},x,0,{credentials,...extra});
const condition=field=>({conditions:{options:{caseSensitive:true,leftValue:"",typeValidation:"strict",version:2},conditions:[{id:field,leftValue:"={{ $json."+field+" }}",rightValue:true,operator:{type:"boolean",operation:"true",singleValue:true}}],combinator:"and"},options:{}});
const config=fields=>({assignments:{assignments:Object.entries(fields).map(([name,value])=>({id:name,name,value,type:"string"}))},options:{}});
const connection=target=>[{node:target,type:"main",index:0}];
const workflow=(id,name,nodes,edges)=>({id,name,active:false,nodes,connections:Object.fromEntries(edges.map(([from,...to])=>[from,{main:to.map(target=>target?connection(target):[])}])),settings:{executionOrder:"v1",timezone:"Europe/Paris",executionTimeout:240,saveDataErrorExecution:"all",saveDataSuccessExecution:"none"},pinData:{}});
const triggers=[node("Manuel","manualTrigger",{},0),node("Toutes les minutes","scheduleTrigger",{rule:{interval:[{field:"minutes",minutesInterval:1}]}},0,200)];
const qualification=workflow("novacorpQualification","NovaCorp - Qualification des demandes",[
 ...triggers,node("Configuration","set",config({provider:"ollama",model:"qwen3:1.7b",endpoint:"http://ollama:11434/api/chat",request_id:""}),220),
 rpc("Reserver la demande","claim_hr_qualification","={{ {p_execution_id:String($execution.id),p_provider:$json.provider,p_model:$json.model,p_request_id:$json.request_id || null} }}",440),
 node("Demande reservee","if",condition("claimed"),660),
 node("Preparer le prompt","code",{jsCode:"const build="+buildOllamaBody.toString()+";\nconst claim=$input.first().json; const config=$('Configuration').first().json;\nreturn [{json:{...claim,body:build(claim,config.model,"+JSON.stringify(resultSchema)+","+JSON.stringify(systemPrompt)+")}}];"},880),
 node("Qualifier avec Ollama","httpRequest",{method:"POST",url:"={{ $('Configuration').first().json.endpoint }}",sendBody:true,specifyBody:"json",jsonBody:"={{ $json.body }}",options:{timeout:120000,response:{response:{fullResponse:true,neverError:true,responseFormat:"json"}}}},1100,0,{onError:"continueRegularOutput"}),
 node("Valider la reponse","code",{jsCode:"const validate="+validateOllamaResponse.toString()+";\nconst claim=$('Preparer le prompt').first().json;return [{json:{run_id:claim.run_id,lease_token:claim.lease_token,...validate($input.first().json)}}];"},1320),
 node("Reponse valide","if",condition("valid"),1540),
 rpc("Enregistrer et activer le manager","complete_hr_qualification","={{ {p_run_id:$json.run_id,p_lease_token:$json.lease_token,p_result:$json.result,p_input_tokens:$json.input_tokens,p_output_tokens:$json.output_tokens} }}",1760,{onError:"continueErrorOutput"}),
 rpc("Tracer l echec","fail_hr_qualification","={{ {p_run_id:$('Valider la reponse').first().json.run_id,p_lease_token:$('Valider la reponse').first().json.lease_token,p_error_code:$('Valider la reponse').first().json.error_code || 'technical_error'} }}",1760),
 node("Qualification interrompue","stopAndError",{errorMessage:"Qualification interrompue : consulter workflow_runs et ai_reviews. Aucune décision automatique."},1980)
],[
 ["Manuel","Configuration"],["Toutes les minutes","Configuration"],["Configuration","Reserver la demande"],
 ["Reserver la demande","Demande reservee"],["Demande reservee","Preparer le prompt",null],
 ["Preparer le prompt","Qualifier avec Ollama"],["Qualifier avec Ollama","Valider la reponse"],
 ["Valider la reponse","Reponse valide"],["Reponse valide","Enregistrer et activer le manager","Tracer l echec"],
 ["Enregistrer et activer le manager",null,"Tracer l echec"],["Tracer l echec","Qualification interrompue"]
]);
const mailer=workflow("novacorpManagerEmails","NovaCorp - Notifications manager",[
 ...triggers,node("Configuration","set",config({request_id:""}),220),
 rpc("Reserver le message","claim_hr_manager_email","={{ {p_request_id:$json.request_id || null} }}",440),
 node("Message reserve","if",condition("claimed"),660),
 node("Envoyer dans MailHog","emailSend",{fromEmail:"no-reply@novacorp.test",toEmail:"={{ $json.to }}",subject:"={{ $json.subject }}",emailFormat:"text",text:"={{ $json.text }}",options:{appendAttribution:false}},880,0,{credentials:{smtp:{id:"novacorpMailhogLocal",name:"NovaCorp - MailHog local"}},onError:"continueErrorOutput"}),
 rpc("Confirmer l envoi","finish_hr_manager_email","={{ {p_notification_id:$('Reserver le message').first().json.notification_id,p_lease_token:$('Reserver le message').first().json.lease_token,p_sent:true,p_message_id:$json.messageId || null} }}",1100),
 rpc("Tracer l echec SMTP","finish_hr_manager_email","={{ {p_notification_id:$('Reserver le message').first().json.notification_id,p_lease_token:$('Reserver le message').first().json.lease_token,p_sent:false} }}",1100),
 node("Envoi interrompu","stopAndError",{errorMessage:"Email non envoyé : tentative SMTP tracée, réessai limité."},1320)
],[
 ["Manuel","Configuration"],["Toutes les minutes","Configuration"],["Configuration","Reserver le message"],
 ["Reserver le message","Message reserve"],["Message reserve","Envoyer dans MailHog",null],
 ["Envoyer dans MailHog","Confirmer l envoi","Tracer l echec SMTP"],["Tracer l echec SMTP","Envoi interrompu"]
]);
for(const n of qualification.nodes)if(["Tracer l echec","Qualification interrompue"].includes(n.name))n.position[1]=240;
for(const n of mailer.nodes)if(["Tracer l echec SMTP","Envoi interrompu"].includes(n.name))n.position[1]=240;
await mkdir("n8n/workflows",{recursive:true});
for(const [name,data]of Object.entries({"qualification.json":qualification,"manager-emails.json":mailer}))
 await writeFile("n8n/workflows/"+name,JSON.stringify(data,null,2)+"\n");
console.log("Workflows de qualification et de notification générés sans secrets.");
