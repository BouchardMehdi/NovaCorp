import {createClient} from "@supabase/supabase-js";
import {randomUUID} from "node:crypto";
import assert from "node:assert/strict";
import {mkdtemp,writeFile,rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {importDocument} from "./lib/rag-import.mjs";
import {sanitizeAiInput} from "../n8n/lib/ai-policy.mjs";
import {applyRagPolicy} from "../n8n/lib/rag.mjs";
import {buildOllamaBody,resultSchema,systemPrompt,validateOllamaResponse} from "../n8n/lib/qualification.mjs";

const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;
if(!url||!key||!["localhost","127.0.0.1","[::1]"].includes(new URL(url).hostname))throw new Error("Vérification réservée à Supabase local.");
const client=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
const slug="rag-verify-"+randomUUID().slice(0,8),dir=await mkdtemp(join(tmpdir(),"novacorp-rag-verify-"));
try{
 const file=join(dir,"politique-test.md");
 await writeFile(file,"# Accessoire OrbeAzur\n\n## Code documentaire OrbeAzur\n\nDocument de test fictif. Le code documentaire de l'accessoire OrbeAzur est MISTRAL-728. OrbeAzur est du matériel fictif. Ce code sert seulement au suivi documentaire. Une décision humaine est obligatoire ; aucun achat n'est approuvé automatiquement.");
 const document={file,slug,title:"Matériel OrbeAzur : document de test",version:"1",types:["equipment"]};
 const first=await importDocument(client,document);assert.equal(first.replayed,false);
 assert.equal((await importDocument(client,document)).replayed,true);
 const {data:passages,error}=await client.rpc("search_hr_knowledge",{p_request_type:"equipment",p_query:"Code documentaire accessoire OrbeAzur"});
 assert.equal(error,null);assert.ok(passages.some(p=>p.source_id.startsWith(slug+"@1#")));
 const other=await client.rpc("search_hr_knowledge",{p_request_type:"leave",p_query:"OrbeAzur"});assert.equal(other.error,null);assert.equal(other.data.some(p=>p.source_id.startsWith(slug+"@")),false);
 const input=sanitizeAiInput({operation:"qualify",request:{type:"equipment",title:"Accessoire OrbeAzur",description:"Indiquer dans la synthèse le code documentaire de l'accessoire OrbeAzur.",amount:80,quantity:1},checks:{blocking_issues:[],sufficient_leave_balance:true},rag:{method:"postgres_fts_fr_v1",retrieved_at:new Date().toISOString(),passages}});
 const response=await fetch("http://127.0.0.1:11434/api/chat",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(buildOllamaBody(input,"qwen3:1.7b",resultSchema,systemPrompt)),signal:AbortSignal.timeout(150000)});
 const result=applyRagPolicy(validateOllamaResponse({statusCode:response.status,body:await response.json()}),input);
 assert.equal(result.valid,true,"Réponse RAG structurée et citations connues attendues.");
 assert.ok(result.result.citations.some(id=>id.startsWith(slug+"@1#")),"Le modèle doit citer le nouveau document.");
 assert.ok(result.result.summary.includes("MISTRAL-728"),"La synthèse doit retrouver un fait présent uniquement dans le document importé. Résultat fictif : "+JSON.stringify(result.result));
 console.log("OK import réel, rejeu sans doublon, recherche typée et vrai Ollama : fait inédit retrouvé et source citée.");
}finally{
 const deleted=await client.from("hr_knowledge_documents").delete().eq("slug",slug);assert.equal(deleted.error,null);
 await rm(dir,{recursive:true,force:true});
}
