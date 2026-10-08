import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { validateLogin } from "../src/lib/auth/validation";

const password = "NovaCorpDemo2026!";

test("la validation refuse les champs invalides côté serveur", () => {
  expect(validateLogin("adresse-invalide", password).error).toBeTruthy();
  expect(validateLogin("salarie@novacorp.test", "").error).toBeTruthy();
  expect(validateLogin("salarie@novacorp.test", password).error).toBeNull();
});

test("un visiteur ne peut pas accéder à l’espace privé", async ({ page }) => {
  await page.goto("/tableau-de-bord");
  await expect(page).toHaveURL(/\/connexion$/);
  await expect(page.getByRole("heading", { name: "Connexion", exact: true })).toBeVisible();
});

test("une session forgée ne donne pas accès à l’espace privé", async ({ page, context }) => {
  const project = new URL(process.env.NEXT_PUBLIC_SUPABASE_URL!).hostname.split(".")[0];
  await context.addCookies([{ name: "sb-" + project + "-auth-token", value: "base64-eyJhY2Nlc3NfdG9rZW4iOiJmb3JnZWQifQ", domain: "localhost", path: "/" }]);
  await page.goto("/tableau-de-bord");
  await expect(page).toHaveURL(/\/connexion$/);
});

test("un mauvais mot de passe affiche une erreur sans ouvrir une session", async ({ page }) => {
  await page.goto("/connexion");
  await page.getByLabel("Adresse email professionnelle").fill("salarie@novacorp.test");
  await page.getByLabel("Mot de passe", { exact: true }).fill("MotDePasseIncorrect!");
  await page.getByRole("button", { name: "Se connecter" }).click();
  await expect(page.locator("form [role=alert]")).toHaveText("Adresse email ou mot de passe incorrect.");
  await expect(page).toHaveURL(/\/connexion$/);
});

test("connexion, maintien de session et déconnexion", async ({ page }) => {
  await page.goto("/connexion");
  await page.getByLabel("Adresse email professionnelle").fill("salarie@novacorp.test");
  await page.getByLabel("Mot de passe", { exact: true }).fill(password);
  await page.getByRole("button", { name: "Se connecter" }).click();
  await expect(page).toHaveURL(/\/tableau-de-bord$/);
  await expect(page.getByRole("heading", { name: "Bienvenue, Camille." })).toBeVisible();
  await expect(page.getByText("Salarié", { exact: true })).toBeVisible();
  await page.reload();
  await expect(page.getByRole("heading", { name: "Vous êtes connecté" })).toBeVisible();
  await page.goto("/connexion");
  await expect(page).toHaveURL(/\/tableau-de-bord$/);
  await page.getByRole("button", { name: "Se déconnecter" }).click();
  await expect(page).toHaveURL(/\/connexion$/);
  await page.goto("/tableau-de-bord");
  await expect(page).toHaveURL(/\/connexion$/);
});

test("la RLS isole les profils et interdit le changement de rôle", async () => {
  const client = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.signInWithPassword({ email: "salarie@novacorp.test", password });
  expect(error).toBeNull();
  const ownId = data.user!.id;
  const profiles = await client.from("profiles").select("id, role");
  expect(profiles.error).toBeNull();
  expect(profiles.data).toEqual([{ id: ownId, role: "employee" }]);
  const attempt = await client.from("profiles").update({ role: "director" }).eq("id", ownId);
  expect(attempt.error).not.toBeNull();
  const after = await client.from("profiles").select("role").eq("id", ownId).single();
  expect(after.data?.role).toBe("employee");
  await client.auth.signOut();
});

test("le formulaire reste utilisable sur mobile", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/connexion");
  await expect(page.getByRole("button", { name: "Se connecter" })).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBeTruthy();
  await page.screenshot({ path: "test-results/connexion-mobile.png", fullPage: true, caret: "initial" });
});

test("aperçu de la connexion sur ordinateur", async ({ page }) => {
  await page.goto("/connexion");
  await expect(page.getByRole("heading", { name: "Connexion", exact: true })).toBeVisible();
  await page.screenshot({ path: "test-results/connexion-desktop.png", fullPage: true, caret: "initial" });
});

test("l’inscription publique est désactivée et les profils sont privés", async () => {
  const anonymous = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const signup = await anonymous.auth.signUp({ email: "visiteur@novacorp.test", password });
  expect(signup.error?.code).toBe("signup_disabled");
  const profiles = await anonymous.from("profiles").select("id");
  expect(profiles.error).not.toBeNull();
});
