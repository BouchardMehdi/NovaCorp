import Link from "next/link";
import {requireUser} from "@/lib/auth/session";
import {types,statuses,roles,date,reference} from "@/lib/hr";
import Live from "./live";
export const dynamic="force-dynamic";
export default async function Dashboard({searchParams}:{searchParams:Promise<Record<string,string|string[]|undefined>>}){
 const search=await searchParams;
 const value=(key:string)=>typeof search[key]==="string"?search[key] as string:"";
 const {supabase,user}=await requireUser();
 const {data:profile,error:profileError}=await supabase.from("profiles").select("first_name,last_name,role").eq("id",user.id).maybeSingle();
 const canTeam=profile&&profile.role!=="employee";
 const scope=canTeam&&value("scope")==="team"?"team":"own";
 const status=Object.hasOwn(statuses,value("status"))?value("status"):"";
 const kind=Object.hasOwn(types,value("type"))?value("type"):"";
 const rawPage=Number(value("page")||1),page=Number.isInteger(rawPage)&&rawPage>0&&rawPage<=10000?rawPage:1;
 let query=supabase.from("requests").select("*",{count:"exact"}).order("created_at",{ascending:false}).order("id").range((page-1)*20,page*20-1);
 query=scope==="own"?query.eq("requester_id",user.id):query.neq("requester_id",user.id);
 if(status)query=query.eq("status",status as import("@/types/database").Database["public"]["Enums"]["request_status"]);
 if(kind)query=query.eq("request_type",kind);
 const [{data:requests,count,error},{data:balance}]=await Promise.all([query,supabase.from("leave_balances").select("available_days,reserved_days").eq("employee_id",user.id).eq("year",new Date().getFullYear()).maybeSingle()]);
 const url=(number:number)=>"/tableau-de-bord?"+new URLSearchParams({scope,status,type:kind,page:String(number)});
 return <main className="dashboard-main"><Live/><p className="eyebrow muted">MON ESPACE</p><h1>Bienvenue{profile?.first_name?", "+profile.first_name:""}.</h1><p className="intro">Votre espace personnel NovaCorp.</p>
 <section className="account-card" aria-labelledby="account-title"><div className="account-icon" aria-hidden="true">✓</div><div><h2 id="account-title">Vous êtes connecté</h2><p>{user.email}</p>{profile&&<span className="role-badge">{roles[profile.role]}</span>}</div>{balance&&<p className="balance">{balance.available_days} jours disponibles<br/><small>{balance.reserved_days} jours réservés · {new Date().getFullYear()}</small></p>}</section>
 {(profileError||!profile)&&<p className="notice">Votre profil RH n’est pas encore disponible. Contactez le service RH.</p>}
 <div className="section-head"><h2>{scope==="team"?(profile?.role==="manager"?"Demandes de mon équipe":"Vue RH"):"Mes demandes"}</h2><Link className="button primary" href="/tableau-de-bord/demandes/nouvelle">Nouvelle demande</Link></div>
 <form className="filters" method="get"><div className="field"><label htmlFor="scope">Vue</label><select name="scope" id="scope" defaultValue={scope}><option value="own">Mes demandes</option>{canTeam&&<option value="team">{profile?.role==="manager"?"Mon équipe":"Vue RH"}</option>}</select></div><div className="field"><label htmlFor="type">Type</label><select name="type" id="type" defaultValue={kind}><option value="">Tous les types</option>{Object.entries(types).map(([key,label])=><option key={key} value={key}>{label}</option>)}</select></div><div className="field"><label htmlFor="status">Statut</label><select name="status" id="status" defaultValue={status}><option value="">Tous les statuts</option>{Object.entries(statuses).map(([key,label])=><option key={key} value={key}>{label}</option>)}</select></div><button className="button secondary">Filtrer</button></form>
 {error?<p role="alert" className="form-error">Les demandes ne peuvent pas être chargées. Réessayez dans un instant.</p>:<><p className="hint">{count||0} demande{count===1?"":"s"} · 20 par page</p><div className="request-list">{requests?.map(r=><Link className="request-card" href={"/tableau-de-bord/demandes/"+r.id} key={r.id}><div><p className="hint">{reference(r.reference)} · {types[r.request_type]}</p><h3>{r.title}</h3><p className="hint">Créée le {date(r.created_at)}{r.start_date?" · "+date(r.start_date)+" → "+date(r.end_date):""}</p></div><span className={"status status-"+r.status}>{statuses[r.status]}</span></Link>)}</div>{!requests?.length&&<section className="panel"><h3>Aucune demande dans cette vue.</h3><p className="hint">Créez une demande ou ajustez les filtres.</p></section>}<nav className="actions" aria-label="Pagination">{page>1&&<Link className="button secondary" href={url(page-1)}>Page précédente</Link>}{(count||0)>page*20&&<Link className="button secondary" href={url(page+1)}>Page suivante</Link>}</nav></>}
 </main>;
}