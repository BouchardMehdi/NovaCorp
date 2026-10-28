"use client";

import {useTransition} from "react";
import {useRouter} from "next/navigation";
import {statuses,types} from "@/lib/hr";

export default function ListFilters({scope,type,status,teamLabel,supervision=false}:{scope?:string;type:string;status:string;teamLabel?:string;supervision?:boolean}) {
 const router=useRouter();
 const [pending,startTransition]=useTransition();
 const path="/tableau-de-bord"+(supervision?"/supervision":"");
 return <form className={supervision?"filters supervision-filters":"filters"} action={path} aria-label="Filtres des demandes" aria-busy={pending}
  onSubmit={event=>event.preventDefault()}
  onChange={event=>{
   const values=new URLSearchParams();
   for(const [key,value] of new FormData(event.currentTarget))if(typeof value==="string"&&value)values.set(key,value);
   // A filter change always starts at the first page, including supervision lists.
   startTransition(()=>router.push(path+"?"+values.toString(),{scroll:false}));
  }}>
  {!supervision&&<div className="field"><label htmlFor="scope">Vue</label><select id="scope" name="scope" defaultValue={scope}><option value="own">Mes demandes</option>{teamLabel&&<option value="team">{teamLabel}</option>}</select></div>}
  <div className="field"><label htmlFor="type">Type de demande</label><select id="type" name="type" defaultValue={type}><option value="">Tous les types</option>{Object.entries(types).map(([key,label])=><option key={key} value={key}>{label}</option>)}</select></div>
  <div className="field"><label htmlFor="status">Statut</label><select id="status" name="status" defaultValue={status}><option value="">Tous les statuts</option>{Object.entries(statuses).filter(([key])=>!supervision||key!=="draft").map(([key,label])=><option key={key} value={key}>{label}</option>)}</select></div>
  <p className="filter-feedback" role="status">{pending?"Chargement des demandes…":"Filtres appliqués automatiquement"}</p>
 </form>;
}
