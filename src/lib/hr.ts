import type { Database } from "@/types/database";
export type Request = Database["public"]["Tables"]["requests"]["Row"];
export const types: Record<string,string> = {leave:"Congés",remote_work:"Télétravail",equipment:"Matériel",training:"Formation"};
export const statuses: Record<string,string> = {draft:"Brouillon",submitted:"Soumise",under_review:"En analyse",pending_approval:"En validation",approved:"Approuvée",rejected:"Refusée",cancelled:"Annulée"};
export const roles: Record<string,string> = {employee:"Salarié",manager:"Manager",hr:"Ressources humaines",director:"Direction RH"};
export function date(value:string|null){return value ? new Intl.DateTimeFormat("fr-FR",{dateStyle:"medium",timeZone:"UTC"}).format(new Date(value)) : "—";}
export function reference(value:number){return "NC-"+String(value).padStart(6,"0");}
export function validId(value:string){return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);}
