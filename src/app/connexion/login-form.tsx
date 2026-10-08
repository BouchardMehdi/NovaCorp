"use client";

import { useActionState } from "react";
import { login } from "./actions";

export function LoginForm({ configured }: { configured: boolean }) {
  const [state, action, pending] = useActionState(login, { error: null });
  return <form action={action} className="login-form">
    <div className="field"><label htmlFor="email">Adresse email professionnelle</label>
      <input id="email" name="email" type="email" autoComplete="username" placeholder="prenom.nom@novacorp.test" required disabled={pending || !configured} />
    </div>
    <div className="field"><label htmlFor="password">Mot de passe</label>
      <input id="password" name="password" type="password" autoComplete="current-password" required disabled={pending || !configured} />
    </div>
    {state.error && <p role="alert" className="form-error">{state.error}</p>}
    <button className="button primary" type="submit" disabled={pending || !configured}>{pending ? "Connexion en cours…" : "Se connecter"}<span aria-hidden="true">→</span></button>
    <p className="form-help">Besoin d’un accès ? Contactez votre service RH.</p>
  </form>;
}
