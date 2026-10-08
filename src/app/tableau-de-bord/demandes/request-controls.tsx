"use client";
import {useActionState,useState} from "react";
import {changeRequest,decideApproval} from "./actions";
export function RequestControls({id,draft}:{id:string;draft:boolean}){
 const [state,action,pending]=useActionState(changeRequest,{error:""});
 const [confirm,setConfirm]=useState(false);
 return <form action={action}><input type="hidden" name="id" value={id}/>{state.error&&<p className="form-error" role="alert">{state.error}</p>}<div className="actions">{draft&&<button className="button primary" name="intent" value="submit" disabled={pending}>Soumettre</button>}{confirm?<><p>Confirmer l’annulation de cette demande ?</p><button className="button danger" name="intent" value="cancel" disabled={pending}>Confirmer l’annulation</button><button type="button" className="button secondary" onClick={()=>setConfirm(false)}>Conserver la demande</button></>:<button type="button" className="button secondary" onClick={()=>setConfirm(true)}>Annuler la demande</button>}</div></form>;
}
export function ApprovalControl({step}:{step:string}){
 const [state,action,pending]=useActionState(decideApproval,{error:""});
 return <form action={action} className="request-form"><input type="hidden" name="step" value={step}/>{state.error&&<p role="alert" className="form-error">{state.error}</p>}<div className="field"><label htmlFor={"comment-"+step}>Commentaire (obligatoire pour refuser)</label><textarea id={"comment-"+step} name="comment" maxLength={4000} rows={3}/></div><div className="actions"><button name="choice" value="approve" className="button primary" disabled={pending}>Approuver</button><button name="choice" value="reject" className="button danger" disabled={pending}>Refuser</button></div></form>;
}
