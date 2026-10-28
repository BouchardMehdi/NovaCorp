// These functions are serialized into n8n Code nodes; keep them self-contained.
export function sanitizeRagContext(context){
 if(context?.method!=="postgres_fts_fr_v1"||typeof context.retrieved_at!=="string"||!Number.isFinite(Date.parse(context.retrieved_at))||!Array.isArray(context.passages)||context.passages.length>3)throw new Error("rag_context_invalid");
 const seen=new Set();
 const passages=context.passages.map(p=>{
  if(!p||typeof p.source_id!=="string"||!/^[-a-z0-9]{2,60}@[-a-zA-Z0-9.]{1,30}#[1-9][0-9]{0,3}$/.test(p.source_id)||seen.has(p.source_id))throw new Error("rag_context_invalid");
  seen.add(p.source_id);
  for(const [key,max] of [["title",180],["version",30],["section",160],["content",900],["source_path",255]])
   if(typeof p[key]!=="string"||!p[key].trim()||p[key].length>max)throw new Error("rag_context_invalid");
  if(/[\\/]/.test(p.source_path)||!/^[-a-zA-Z0-9.]{1,30}$/.test(p.version)||!/^[a-f0-9]{64}$/.test(p.sha256))throw new Error("rag_context_invalid");
  return Object.fromEntries(["source_id","title","version","section","content","source_path","sha256"].map(key=>[key,p[key]]));
 });
 return {method:context.method,retrieved_at:context.retrieved_at,passages};
}

export function applyRagPolicy(validation,input){
 if(!validation.valid||!input.rag)return validation;
 const citations=validation.result.citations;
 if(!Array.isArray(citations)||citations.length>3||new Set(citations).size!==citations.length||citations.some(id=>!input.rag.passages.some(p=>p.source_id===id)))return {valid:false,error_code:"llm_invalid_response"};
 const result={...validation.result};
 if(!input.rag.passages.length||!citations.length){
  if(result.qualification==="eligible")result.qualification="needs_review";
  result.summary="Références documentaires insuffisantes : vérification humaine nécessaire.\n"+result.summary.slice(0,7600);
 }
 return {...validation,result};
}
