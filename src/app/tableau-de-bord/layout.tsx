import Link from "next/link";
import { requireUser } from "@/lib/auth/session";
import { logout } from "./actions";
export default async function DashboardLayout({children}:{children:React.ReactNode}){
 const {supabase,user}=await requireUser();
 const {data:profile}=await supabase.from("profiles").select("role").eq("id",user.id).maybeSingle();
 return <div className="dashboard-shell"><header className="dashboard-header"><Link href="/tableau-de-bord" className="brand dark"><span className="brand-mark" aria-hidden="true">N</span>NovaCorp<span className="brand-tag">ESPACE RH</span></Link><nav className="dashboard-nav" aria-label="Navigation de l’espace"><Link href="/tableau-de-bord">Mes demandes</Link>{profile&&["hr","director"].includes(profile.role)&&<Link href="/tableau-de-bord/supervision">Supervision RH</Link>}</nav><form action={logout}><button className="button secondary">Se déconnecter</button></form></header>{children}<footer className="dashboard-footer">NovaCorp · Plateforme de gestion des demandes RH</footer></div>;
}