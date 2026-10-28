"use client";

import Link from "next/link";
import {usePathname,useSearchParams} from "next/navigation";

export default function Navigation({role}:{role?:string}) {
 const pathname=usePathname();
 const search=useSearchParams();
 const root="/tableau-de-bord";
 const links=[{href:root,label:"Mes demandes",active:pathname===root&&search.get("scope")!=="team"}];
 if(role&&role!=="employee")links.push({href:root+"?scope=team",label:role==="manager"?"Mon équipe":"Toutes les demandes",active:pathname===root&&search.get("scope")==="team"});
 if(role&&["hr","director"].includes(role))links.push({href:root+"/supervision",label:"Supervision RH",active:pathname===root+"/supervision"});
 links.push({href:root+"/demandes/nouvelle",label:"Nouvelle demande",active:pathname===root+"/demandes/nouvelle"});
 return <nav className="dashboard-nav" aria-label="Navigation de l’espace">{links.map(link=><Link key={link.href} href={link.href} aria-current={link.active?"page":undefined}>{link.label}</Link>)}</nav>;
}
