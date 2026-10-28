import Link from "next/link";
import {requireUser} from "@/lib/auth/session";
import {types,statuses,roles,date,reference} from "@/lib/hr";
import Live from "./live";
import ListFilters from "./list-filters";
import Pagination,{requestedPage,lastPage,pageSize} from "./pagination";
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
 const rawPage=requestedPage(value("page"));
 const getQuery=()=>{
 let query=supabase.from("requests").select("*",{count:"exact"}).order("created_at",{ascending:false}).order("id");
 query=scope==="own"?query.eq("requester_id",user.id):query.neq("requester_id",user.id);
 if(status)query=query.eq("status",status as import("@/types/database").Database["public"]["Enums"]["request_status"]);
 if(kind)query=query.eq("request_type",kind);
 return query;
 };
 const [initialResult,{data:balance}]=await Promise.all([getQuery().range((rawPage-1)*pageSize,rawPage*pageSize-1),supabase.from("leave_balances").select("available_days,reserved_days").eq("employee_id",user.id).eq("year",new Date().getFullYear()).maybeSingle()]);
 let result=initialResult;
 // PostgREST returns 416 without a count when the offset exceeds the result set.
 // Recover its size from the first row before requesting the last available page.
 if(result.error?.code==="PGRST103"&&rawPage>1)result=await getQuery().range(0,0);
 const page=Math.min(rawPage,lastPage(result.count||0));
 const {data:requests,count,error}=page!==rawPage&&!result.error?await getQuery().range((page-1)*pageSize,page*pageSize-1):result;
 return <main className="dashboard-main"><Live/><p className="eyebrow muted">MON ESPACE</p><h1>Bienvenue{profile?.first_name?", "+profile.first_name:""}.</h1><p className="intro">Votre espace personnel NovaCorp.</p>
 <section className="account-card" aria-labelledby="account-title"><div className="account-icon" aria-hidden="true">✓</div><div><h2 id="account-title">Vous êtes connecté</h2><p>{user.email}</p>{profile&&<span className="role-badge">{roles[profile.role]}</span>}</div>{balance&&<p className="balance">{balance.available_days} jours disponibles<br/><small>{balance.reserved_days} jours réservés · {new Date().getFullYear()}</small></p>}</section>
 {(profileError||!profile)&&<p className="notice">Votre profil RH n’est pas encore disponible. Contactez le service RH.</p>}
 <div className="section-head"><h2>{scope==="team"?(profile?.role==="manager"?"Demandes de mon équipe":"Toutes les demandes"):"Mes demandes"}</h2><Link className="button primary" href="/tableau-de-bord/demandes/nouvelle">Nouvelle demande</Link></div>
 <ListFilters key={[scope,kind,status].join(":")} scope={scope} type={kind} status={status} teamLabel={canTeam?(profile?.role==="manager"?"Mon équipe":"Toutes les demandes"):undefined}/>
 {error?<p role="alert" className="form-error">Les demandes ne peuvent pas être chargées. Réessayez dans un instant.</p>:<><p className="hint">{count||0} demande{count===1?"":"s"} · {pageSize} par page</p><div className="request-list">{requests?.map(r=><Link className="request-card" href={"/tableau-de-bord/demandes/"+r.id} key={r.id}><div><p className="hint">{reference(r.reference)} · {types[r.request_type]}</p><h3>{r.title}</h3><p className="hint">Créée le {date(r.created_at)}{r.start_date?" · "+date(r.start_date)+" → "+date(r.end_date):""}</p></div><span className={"status status-"+r.status}>{statuses[r.status]}</span></Link>)}</div>{!requests?.length&&<section className="panel"><h3>Aucune demande dans cette vue.</h3><p className="hint">Créez une demande ou ajustez les filtres.</p></section>}<Pagination page={page} total={count||0} pathname="/tableau-de-bord" params={{scope,status,type:kind}}/></>}
 </main>;
}
