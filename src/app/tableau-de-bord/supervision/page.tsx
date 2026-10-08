import Link from "next/link";
import {notFound} from "next/navigation";
import {requireUser} from "@/lib/auth/session";
import {types,statuses,roles,reference} from "@/lib/hr";
import {duration,timestamp,issueLabel,type DashboardData} from "@/lib/hr-dashboard";
import Live from "../live";
export const dynamic="force-dynamic";
export default async function Supervision({searchParams}:{searchParams:Promise<Record<string,string|string[]|undefined>>}){
 const {supabase,user}=await requireUser();
 const {data:profile,error:profileError}=await supabase.from("profiles").select("role").eq("id",user.id).maybeSingle();
 if(profileError)throw new Error("Votre profil est temporairement indisponible.");
 if(!profile||!["hr","director"].includes(profile.role))notFound();
 const search=await searchParams;
 const type=typeof search.type==="string"&&Object.hasOwn(types,search.type)?search.type:"";
 const {data,error}=await supabase.rpc("get_hr_dashboard",{p_request_type:type||undefined});
 const report=data as unknown as DashboardData|null;
 const detail=(id:string)=>"/tableau-de-bord/demandes/"+id;
 return <main className="dashboard-main supervision-main"><Live supervision/>
 <Link href="/tableau-de-bord" className="back">← Mon espace</Link>
 <p className="eyebrow muted">PILOTAGE RH</p><h1>Supervision RH</h1>
 <p className="intro">Les demandes soumises, leurs validations et les traitements à surveiller.</p>
 <form method="get" className="supervision-filter"><div className="field"><label htmlFor="dashboard-type">Type de demande</label><select id="dashboard-type" name="type" defaultValue={type}><option value="">Tous les types</option>{Object.entries(types).map(([key,label])=><option key={key} value={key}>{label}</option>)}</select></div><button className="button secondary">Filtrer</button><Link className="button secondary" href={"/tableau-de-bord/supervision"+(type?"?type="+type:"")}>Actualiser</Link></form>
 {error||!report?<section className="panel"><p role="alert" className="form-error">La supervision ne peut pas être chargée. Réessayez dans un instant.</p></section>:<>
 <p className="hint">Toutes les demandes soumises{type?" · "+types[type]:""} · Actualisé le {timestamp(report.generated_at)} (heure de Paris). Les brouillons sont exclus.</p>
 <div className="metric-grid">
 {[["Demandes soumises",report.total],["Demandes en cours",report.active],["Validations en retard",report.overdue_count],["Incidents à surveiller",report.issue_count]].map(([label,value])=><section className="metric-card" key={label} aria-label={String(label)}><p>{label}</p><strong>{value}</strong></section>)}
 </div>
 <div className="supervision-columns">
 <section className="panel"><h2>Répartition par statut</h2><dl className="distribution">{Object.entries(statuses).filter(([key])=>key!=="draft").map(([key,label])=><div key={key}><dt>{label}</dt><dd><span className="distribution-track" aria-hidden="true"><span style={{width:(report.total?100*(report.by_status[key]||0)/report.total:0)+"%"}}/></span><strong>{report.by_status[key]||0}</strong></dd></div>)}</dl></section>
 <section className="panel"><h2>Répartition par type</h2><dl className="distribution">{Object.entries(types).map(([key,label])=><div key={key}><dt>{label}</dt><dd><span className="distribution-track" aria-hidden="true"><span style={{width:(report.total?100*(report.by_type[key]||0)/report.total:0)+"%"}}/></span><strong>{report.by_type[key]||0}</strong></dd></div>)}</dl></section>
 </div>
 <section className="panel"><h2>Délais de traitement</h2><dl className="details"><div><dt>Délai moyen</dt><dd>{duration(report.average_hours)}</dd></div><div><dt>Délai médian</dt><dd>{duration(report.median_hours)}</dd></div></dl><p className="hint">{report.closed_count?report.closed_count+(report.closed_count===1?" demande approuvée ou refusée":" demandes approuvées ou refusées")+", de la soumission à la décision finale.":"Aucune demande approuvée ou refusée pour calculer un délai."} Heures calendaires ; annulations exclues.</p></section>
 <section className="panel"><h2>Validations à suivre</h2><p className="hint">{report.pending_count} {report.pending_count===1?"validation active":"validations actives"} · Affichage : {report.pending.length} sur {report.pending_count}, par échéance. Les délais commencent à l’activation de chaque étape.</p>
 {!report.pending.length?<p>Aucune validation en attente.</p>:<ul className="supervision-list">{report.pending.map(step=><li key={step.id}><Link href={detail(step.request_id)}><span className="hint">{reference(step.reference)} · {roles[step.required_role]}</span><strong>{step.title}</strong></Link><p className="hint">{step.assignee} · Échéance : {timestamp(step.due_at)}</p><span className={step.overdue?"status status-rejected":"status"}>{step.overdue?"En retard":"À valider"}</span></li>)}</ul>}
 </section>
 <section className="panel"><h2>Incidents d’automatisation et d’envoi</h2><p className="hint">Automatisation : {report.workflow_issue_count} · Envoi : {report.mail_issue_count} · Emails en attente : {report.mail_queue_count}. Affichage : {report.issues.length} sur {report.issue_count} incidents.</p>
 {!report.issues.length?<p>Aucun incident à surveiller.</p>:<ul className="supervision-list">{report.issues.map(issue=><li key={issue.source+issue.id}><Link href={detail(issue.request_id)}><span className="hint">{reference(issue.reference)} · {issue.source==="email"?"Email":"Automatisation"}</span><strong>{issue.title}</strong></Link><p>{issueLabel(issue.code)}</p><p className="hint">{timestamp(issue.occurred_at)} · {issue.automatic_retry?"Reprise automatique prévue":"Vérification manuelle nécessaire"}{issue.automatic_retry&&issue.retry_at&&issue.retry_at!=="infinity"?" · "+timestamp(issue.retry_at):""}</p></li>)}</ul>}
 <p className="hint">Les échecs suivis d’une reprise réussie et les notifications devenues obsolètes sont exclus. Consultez les traces n8n pour examiner un incident ; les décisions restent humaines.</p>
 </section>
 <section className="panel"><h2>Demandes en attente</h2><p className="hint">{report.active} {report.active===1?"demande en cours":"demandes en cours"} · Affichage : {report.waiting.length} sur {report.active}, des plus anciennes aux plus récentes.</p>
 {!report.waiting.length?<p>Aucune demande en cours.</p>:<ul className="supervision-list">{report.waiting.map(r=><li key={r.id}><Link href={detail(r.id)}><span className="hint">{reference(r.reference)} · {types[r.request_type]}</span><strong>{r.title}</strong></Link><p className="hint">Soumise le {timestamp(r.submitted_at)} · Depuis {duration(r.age_hours)}</p><span className={"status status-"+r.status}>{statuses[r.status]}</span></li>)}</ul>}
 </section></>}
 </main>;
}
