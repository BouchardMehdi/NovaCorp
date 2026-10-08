export type LoginState = { error: string | null };

export function validateLogin(email: string, password: string): LoginState {
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return { error: "Saisissez une adresse email valide." };
  }
  if (!password) return { error: "Saisissez votre mot de passe." };
  return { error: null };
}

export function loginErrorMessage(code?: string) {
  if (code === "invalid_credentials" || code === "email_not_confirmed") {
    return "Adresse email ou mot de passe incorrect.";
  }
  if (code === "over_request_rate_limit") {
    return "Trop de tentatives. Réessayez dans quelques minutes.";
  }
  return "Connexion indisponible pour le moment. Réessayez dans quelques instants.";
}
