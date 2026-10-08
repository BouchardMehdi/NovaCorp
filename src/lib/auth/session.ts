import "server-only";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { hasSupabaseConfig } from "@/lib/supabase/config";

export async function requireUser() {
  if (!hasSupabaseConfig()) redirect("/connexion");
  const supabase = await createClient();
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) redirect("/connexion");
  return { supabase, user: data.user };
}
