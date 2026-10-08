import Link from "next/link";
import { redirect } from "next/navigation";
import { hasSupabaseConfig } from "@/lib/supabase/config";
import { createClient } from "@/lib/supabase/server";
import { LoginForm } from "./login-form";

export const dynamic = "force-dynamic";

export default async function LoginPage() {
  const configured = hasSupabaseConfig();
  if (configured) {
    const supabase = await createClient();
    const { data } = await supabase.auth.getUser();
    if (data.user) redirect("/tableau-de-bord");
  }
  return <main className="login-shell">
    <section className="brand-panel" aria-label="NovaCorp Espace RH">
      <Link href="/" className="brand"><span className="brand-mark" aria-hidden="true">N</span>NovaCorp<span className="brand-tag">ESPACE RH</span></Link>
      <div className="brand-story"><p className="eyebrow">VOTRE QUOTIDIEN, SIMPLIFIÉ</p><h1>Un espace commun.<br />Des démarches<br /><span>plus simples.</span></h1>
        <p className="brand-description">Retrouvez vos demandes et échangez avec votre service RH, dans un seul espace.</p>
        <div className="feature-line"><span aria-hidden="true">01</span><p>Vos demandes, au même endroit</p></div>
        <div className="feature-line"><span aria-hidden="true">02</span><p>Un suivi à chaque étape</p></div>
        <div className="feature-line"><span aria-hidden="true">03</span><p>Des échanges avec votre équipe RH</p></div>
      </div><p className="brand-footer">Plateforme interne · NovaCorp</p>
    </section>
    <section className="login-panel"><div className="login-card"><p className="eyebrow muted">BIENVENUE DANS VOTRE ESPACE</p><h2>Connexion</h2><p className="intro">Connectez-vous avec votre compte NovaCorp.</p>
      {!configured && <p role="status" className="notice">Le service est en cours de préparation. La connexion sera disponible prochainement.</p>}
      <LoginForm configured={configured} />
    </div><p className="login-footer">Un accès personnel pour vos démarches professionnelles.</p></section>
  </main>;
}
