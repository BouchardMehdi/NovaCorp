"use client";
import { useActionState,useState } from "react";
import { saveRequest } from "./actions";
import { types,type Request } from "@/lib/hr";
export default function RequestForm({request}:{request?:Request}){
 const [state,action,pending]=useActionState(saveRequest,{error:""});
 const [kind,setKind]=useState(request?.request_type||"leave");
 const v=(key:string)=>state.values?.[key]??String(request?.[key as keyof Request]??"");
 return <form action={action} className="panel request-form"><fieldset className="request-fields" disabled={pending}>
 <input type="hidden" name="id" value={state.id||request?.id||""}/>
 {state.error&&<p className="form-error" role="alert">{state.error}</p>}
 <div className="field"><label htmlFor="request_type">Type de demande</label><select id="request_type" name="request_type" value={kind} onChange={e=>setKind(e.target.value)} disabled={!!request||!!state.id||pending}>{Object.entries(types).map(([key,label])=><option key={key} value={key}>{label}</option>)}</select>{(request||state.id)&&<input type="hidden" name="request_type" value={kind}/>}</div>
 <div className="field"><label htmlFor="title">Titre *</label><input id="title" name="title" required maxLength={160} defaultValue={v("title")}/></div>
 <div className="field"><label htmlFor="description">Motif et précisions</label><textarea id="description" name="description" maxLength={8000} rows={4} defaultValue={v("description")}/></div>
 {kind!=="equipment"&&<div className="form-grid"><div className="field"><label htmlFor="start_date">Date de début</label><input id="start_date" name="start_date" type="date" min="2000-01-01" max="2200-12-31" defaultValue={v("start_date")}/></div><div className="field"><label htmlFor="end_date">Date de fin</label><input id="end_date" name="end_date" type="date" min="2000-01-01" max="2200-12-31" defaultValue={v("end_date")}/></div></div>}
 {kind==="leave"&&<><label className="check"><input name="start_half_day" type="checkbox" defaultChecked={state.values?state.values.start_half_day==="on":request?.start_half_day}/> Commencer l’après-midi</label><label className="check"><input name="end_half_day" type="checkbox" defaultChecked={state.values?state.values.end_half_day==="on":request?.end_half_day}/> Terminer à midi</label><p className="hint">Le solde et les chevauchements sont vérifiés à la soumission. Le décompte inclut les jours du lundi au vendredi, hors week-ends.</p></>}
 {(kind==="equipment"||kind==="training")&&<div className="field"><label htmlFor="amount">Montant estimé (€)</label><input id="amount" name="amount" inputMode="decimal" placeholder="0,00" defaultValue={v("amount")}/></div>}
 {kind==="equipment"&&<div className="field"><label htmlFor="quantity">Quantité</label><input id="quantity" name="quantity" type="number" min="1" max="2147483647" step="1" defaultValue={v("quantity")||"1"}/></div>}
 {kind==="training"&&<div className="field"><label htmlFor="training_provider">Organisme de formation</label><input id="training_provider" name="training_provider" maxLength={200} defaultValue={v("training_provider")}/></div>}
 <p className="hint">Un brouillon peut être complété plus tard. Après soumission, la demande n’est plus modifiable.</p>
 <div className="actions"><button className="button secondary" name="intent" value="save" disabled={pending}>Enregistrer le brouillon</button><button className="button primary" name="intent" value="submit" disabled={pending}>{pending?"Enregistrement…":"Soumettre la demande"}</button></div>
 </fieldset></form>;
}
