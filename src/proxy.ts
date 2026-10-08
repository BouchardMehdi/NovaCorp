import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { getSupabaseConfig, hasSupabaseConfig } from "@/lib/supabase/config";

export async function proxy(request: NextRequest) {
  const privateRoute = request.nextUrl.pathname.startsWith("/tableau-de-bord");
  if (!hasSupabaseConfig()) {
    return privateRoute
      ? NextResponse.redirect(new URL("/connexion", request.url))
      : NextResponse.next();
  }
  let response = NextResponse.next({ request });
  const { url, key } = getSupabaseConfig();
  const supabase = createServerClient(url, key, {
    cookies: {
      getAll() { return request.cookies.getAll(); },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
      },
    },
  });
  const { data, error } = await supabase.auth.getUser();
  response.headers.set("Cache-Control", "private, no-store");
  if (privateRoute && (error || !data.user)) {
    const redirectResponse = NextResponse.redirect(new URL("/connexion", request.url));
    response.cookies.getAll().forEach((cookie) => redirectResponse.cookies.set(cookie));
    redirectResponse.headers.set("Cache-Control", "private, no-store");
    return redirectResponse;
  }
  return response;
}

export const config = { matcher: ["/connexion", "/tableau-de-bord/:path*"] };
