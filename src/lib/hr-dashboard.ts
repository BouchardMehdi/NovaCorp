export interface DashboardData {
 generated_at:string;total:number;active:number;pending_count:number;overdue_count:number;
 issue_count:number;workflow_issue_count:number;mail_issue_count:number;mail_queue_count:number;
 closed_count:number;average_hours:number|null;median_hours:number|null;
 by_status:Record<string,number>;by_type:Record<string,number>;
 pending:{id:string;request_id:string;reference:number;title:string;required_role:string;assignee:string;due_at:string;overdue:boolean}[];
 issues:{id:string;request_id:string;reference:number;title:string;source:"workflow"|"email";code:string;occurred_at:string;retry_at:string|null;automatic_retry:boolean}[];
 waiting:{id:string;reference:number;title:string;request_type:string;status:string;submitted_at:string;age_hours:number}[];
}
export function duration(hours:number|null){
 if(hours===null)return "—";
 if(hours<1)return Math.round(hours*60)+" min";
 if(hours<48)return new Intl.NumberFormat("fr-FR",{maximumFractionDigits:1}).format(hours)+" h";
 return new Intl.NumberFormat("fr-FR",{maximumFractionDigits:1}).format(hours/24)+" j";
}
export function timestamp(value:string){
 return new Intl.DateTimeFormat("fr-FR",{dateStyle:"medium",timeStyle:"short",timeZone:"Europe/Paris"}).format(new Date(value));
}
export function issueLabel(code:string){
 return ({llm_http_error:"Service de qualification indisponible",llm_invalid_response:"Réponse de qualification à vérifier",
 technical_error:"Erreur de traitement",configuration_missing:"Configuration à vérifier",
 lease_expired:"Traitement interrompu",smtp_lease_expired:"Envoi interrompu",smtp_failed:"Email non envoyé"} as Record<string,string>)[code]||"Traitement à vérifier";
}
