import Link from "next/link";
import { requireUser } from "@/lib/auth/session";
import { logout } from "./actions";

export const dynamic = "force-dynamic";
const roleLabels: Record<string, string> = { employee: "Salarié", manager: "Manager", hr: "Ressources humaines", director: "Direction RH" };

export default async function DashboardPage() {
  const { supabase, user } = await requireUser();
  const { data: profile, error } = await supabase.from("profiles").select("first_name, last_name, role").eq("id", user.id).maybeSingle();
  return <div className="dashboard-shell"><header className="dashboard-header"><Link href="/tableau-de-bord" className="brand dark"><span className="brand-mark" aria-hidden="true">N</span>NovaCorp<span className="brand-tag">ESPACE RH</span></Link><form action={logout}><button className="button secondary" type="submit">Se déconnecter</button></form></header>
    <main className="dashboard-main"><p className="eyebrow muted">MON ESPACE</p><h1>Bienvenue{profile?.first_name ? ", " + profile.first_name : ""}.</h1><p className="intro">Votre espace personnel NovaCorp.</p>
      <section className="account-card" aria-labelledby="account-title"><div className="account-icon" aria-hidden="true">✓</div><div><h2 id="account-title">Vous êtes connecté</h2><p>{user.email}</p>{profile && <span className="role-badge">{roleLabels[profile.role] ?? "Compte interne"}</span>}</div></section>
      {(error || !profile) && <p role="status" className="notice">Votre profil RH n’est pas encore disponible. Contactez le service RH.</p>}
      <section className="next-card"><p className="eyebrow muted">VOTRE PLATEFORME RH</p><h2>Votre espace prend forme.</h2><p>Les formulaires de demandes et leur suivi seront disponibles dans les prochaines étapes du projet.</p></section>
    </main><footer className="dashboard-footer">NovaCorp · Plateforme de gestion des demandes RH</footer></div>;
}
