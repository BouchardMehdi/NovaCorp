import {sanitizeRagContext} from "./rag.mjs";
export const promptVersion="hr-qualification-v3-rag";

// Serializable into n8n Code nodes: no filesystem, network or database access.
export function sanitizeAiInput(input){
 if(input?.operation!=="qualify"||!input.request||!input.checks)
  throw new Error("ai_scope_denied");
 const r=input.request,c=input.checks;
 if(!["leave","remote_work","equipment","training"].includes(r.type))throw new Error("ai_scope_denied");
 const clean=value=>{
  if(value===null||value===undefined)return null;
  if(typeof value!=="string"||value.length>8000)throw new Error("ai_input_invalid");
  return value.replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi,"[EMAIL MASQUE]")
   .replace(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/gi,"[ID MASQUE]")
   .replace(/(?:\+33|0)[1-9](?:[ .-]?\d{2}){4}\b/g,"[TELEPHONE MASQUE]");
 };
 const request={type:r.type};
 for(const k of ["title","description","start_date","end_date","currency","training_provider"])
  request[k]=clean(r[k]);
 for(const k of ["start_half_day","end_half_day"]){
  if(r[k]!==undefined&&typeof r[k]!=="boolean")throw new Error("ai_input_invalid");
  request[k]=r[k]??false;
 }
 for(const k of ["requested_days","amount","quantity"]){
  if(r[k]!==null&&r[k]!==undefined&&(typeof r[k]!=="number"||!Number.isFinite(r[k])||r[k]<0))throw new Error("ai_input_invalid");
  request[k]=r[k]??null;
 }
 if(!Array.isArray(c.blocking_issues)||c.blocking_issues.some(x=>typeof x!=="string"||!/^[a-z_]{1,80}$/.test(x)))throw new Error("ai_input_invalid");
 const count=(number,ids)=>{
  const value=number??(Array.isArray(ids)?ids.length:0);
  if(!Number.isInteger(value)||value<0)throw new Error("ai_input_invalid");return value;
 };
 if(c.calculated_leave_days!==null&&c.calculated_leave_days!==undefined&&(!Number.isFinite(c.calculated_leave_days)||c.calculated_leave_days<0))throw new Error("ai_input_invalid");
 return {operation:"qualify",request,...(input.rag?{rag:sanitizeRagContext(input.rag)}:{}),checks:{blocking_issues:[...c.blocking_issues],
  calculated_leave_days:c.calculated_leave_days??null,sufficient_leave_balance:c.sufficient_leave_balance===true,
  conflicting_requests:count(c.conflicting_requests,c.conflicting_request_ids),
  possible_duplicates:count(c.possible_duplicates,c.possible_duplicate_ids),requires_human_review:c.requires_human_review===true}};
}

export function applyAiPolicy(validation,input){
 if(!validation.valid)return validation;
 const result={...validation.result};
 if(input.checks.blocking_issues.length||input.checks.conflicting_requests>0||
  (input.request.type==="leave"&&!input.checks.sufficient_leave_balance))result.qualification="invalid";
 else if(input.checks.possible_duplicates>0||input.checks.requires_human_review)result.qualification="needs_review";
 return {...validation,result};
}
