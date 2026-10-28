import Link from "next/link";
import { requireUser } from "@/lib/auth/session";
import { logout } from "./actions";
import {Suspense} from "react";
import Navigation from "./navigation";
export default async function DashboardLayout({children}:{children:React.ReactNode}){
 const {supabase,user}=await requireUser();
 const {data:profile}=await supabase.from("profiles").select("role").eq("id",user.id).maybeSingle();
 return <div className="dashboard-shell"><header className="dashboard-header"><div className="header-top"><Link href="/tableau-de-bord" className="brand dark"><span className="brand-mark" aria-hidden="true">N</span>NovaCorp<span className="brand-tag">ESPACE RH</span></Link><form action={logout}><button className="button secondary">Se déconnecter</button></form></div><Suspense fallback={<nav className="dashboard-nav" aria-label="Navigation de l’espace"/>}><Navigation role={profile?.role}/></Suspense></header>{children}<footer className="dashboard-footer">NovaCorp · Plateforme de gestion des demandes RH</footer></div>;
}
