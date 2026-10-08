"use server";
import { requireUser } from "@/lib/auth/session";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { types, validId } from "@/lib/hr";
export type FormState = {error:string;id?:string;values?:Record<string,string>};
function fail(message:string):never {throw new Error(message);}
function dateValue(value:string){if(!value)return null; if(!/^\d{4}-\d{2}-\d{2}$/.test(value)||value<"2000-01-01"||value>"2200-12-31"||(!Number.isFinite(new Date(value).getTime())||new Date(value).toISOString().slice(0,10)!==value))fail("Vérifiez les dates (entre 2000 et 2200).");return value;}
export async function saveRequest(_:FormState,form:FormData):Promise<FormState>{
 const {supabase,user}=await requireUser();
 const values=Object.fromEntries([...form.entries()].filter((entry):entry is [string,string]=>typeof entry[1]==="string"));
 let id=values.id||undefined;
 try{
 const kind=values.request_type;
 if(!Object.hasOwn(types,kind))fail("Choisissez un type de demande.");
 const title=(values.title||"").trim(), description=(values.description||"").trim();
 if(!title||title.length>160||description.length>8000)fail("Indiquez un titre de 1 à 160 caractères et un motif de 8 000 caractères maximum.");
 const start=dateValue(values.start_date||""),end=dateValue(values.end_date||"");
 if(Boolean(start)!==Boolean(end)||(start&&end&&start>end))fail("Renseignez les deux dates dans l’ordre chronologique.");
 const money=(values.amount||"").trim().replace(",",".");
 if(money&&!/^\d{1,10}(\.\d{1,2})?$/.test(money))fail("Le montant doit être positif ou nul, avec deux décimales maximum.");
 const quantity=values.quantity?.trim();
 if(quantity&&(!/^\d+$/.test(quantity)||Number(quantity)<1||Number(quantity)>2147483647))fail("Indiquez une quantité entière positive.");
 const submitting=values.intent==="submit";
 if(submitting&&((kind==="leave"||kind==="remote_work"||kind==="training")&&!start))fail("Les dates sont obligatoires pour soumettre cette demande.");
 if(submitting&&(kind==="equipment"||kind==="training")&&!money)fail("Le montant est obligatoire pour soumettre cette demande.");
 if(submitting&&kind==="equipment"&&!quantity)fail("La quantité est obligatoire.");
 if((values.training_provider||"").length>200)fail("L’organisme doit comporter 200 caractères maximum.");
 const payload={title,description,start_date:kind==="equipment"?null:start,end_date:kind==="equipment"?null:end,requested_days:null,amount:kind==="equipment"||kind==="training"?(money?Number(money):null):null,quantity:kind==="equipment"&&quantity?Number(quantity):null,training_provider:kind==="training"?(values.training_provider||"").trim()||null:null,currency:"EUR",start_half_day:kind==="leave"&&values.start_half_day==="on",end_half_day:kind==="leave"&&values.end_half_day==="on"};
 if(id){
 if(!validId(id))fail("Demande introuvable.");
 const {data:existing}=await supabase.from("requests").select("request_type,status").eq("id",id).eq("requester_id",user.id).maybeSingle();
 if(!existing||existing.status!=="draft"||existing.request_type!==kind)fail("Seul votre brouillon peut être modifié.");
 const {data,error}=await supabase.from("requests").update(payload).eq("id",id).eq("status","draft").eq("requester_id",user.id).select("id").single();
 if(error||!data)fail("Le brouillon n’a pas pu être enregistré. Rechargez la page.");
 }else{
 const {data,error}=await supabase.from("requests").insert({...payload,request_type:kind,requester_id:user.id}).select("id").single();
 if(error||!data)fail("Le brouillon n’a pas pu être enregistré.");
 id=data.id;
 }
 if(submitting){const {error}=await supabase.rpc("submit_hr_request",{p_request_id:id});if(error)fail(error.message);}
 }catch(error){return {error:error instanceof Error?error.message:"La demande n’a pas pu être enregistrée.",id,values};}
 revalidatePath("/tableau-de-bord","layout");
 redirect("/tableau-de-bord/demandes/"+id);
}
export async function changeRequest(_:FormState,form:FormData):Promise<FormState>{
 const {supabase}=await requireUser();
 const id=String(form.get("id")||""),intent=String(form.get("intent")||"");
 if(!validId(id))return {error:"Demande introuvable."};
 const {error}=intent==="submit"?await supabase.rpc("submit_hr_request",{p_request_id:id}):intent==="cancel"?await supabase.rpc("cancel_hr_request",{p_request_id:id}):{error:{message:"Action inconnue."}};
 if(error)return {error:error.message};
 revalidatePath("/tableau-de-bord","layout");
 return {error:""};
}
export async function decideApproval(_:FormState,form:FormData):Promise<FormState>{
 const {supabase}=await requireUser();
 const step=String(form.get("step")||""),choice=String(form.get("choice")||""),comment=String(form.get("comment")||"").trim();
 if(!validId(step)||!["approve","reject"].includes(choice))return {error:"Décision invalide."};
 if(comment.length>4000||choice==="reject"&&!comment)return {error:"Un motif est obligatoire pour refuser (4 000 caractères maximum)."};
 const {error}=await supabase.rpc("decide_hr_approval",{p_step_id:step,p_approve:choice==="approve",p_comment:comment||undefined});
 if(error)return {error:error.message};
 revalidatePath("/tableau-de-bord","layout");
 return {error:""};
}
