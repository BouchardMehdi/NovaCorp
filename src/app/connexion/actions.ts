"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { hasSupabaseConfig } from "@/lib/supabase/config";
import { loginErrorMessage, validateLogin, type LoginState } from "@/lib/auth/validation";

export async function login(_previousState: LoginState, formData: FormData): Promise<LoginState> {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  const validation = validateLogin(email, password);
  if (validation.error) return validation;
  if (!hasSupabaseConfig()) return { error: "Le service de connexion n’est pas encore configuré." };
  try {
    const supabase = await createClient();
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) return { error: loginErrorMessage(error.code) };
  } catch {
    return { error: loginErrorMessage() };
  }
  redirect("/tableau-de-bord");
}
