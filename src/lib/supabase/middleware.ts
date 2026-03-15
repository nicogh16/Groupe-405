import { createServerClient } from "@supabase/ssr"
import { NextResponse, type NextRequest } from "next/server"

export async function updateSession(request: NextRequest) {
  const { pathname } = request.nextUrl

  // ─── Routes totalement publiques ──────────────────────────────────────────
  const isLoginPage = pathname === "/login"
  const isApiCron = pathname.startsWith("/api/cron")
  const isRobotsTxt = pathname === "/robots.txt"

  // Proteger les endpoints CRON avec un secret (avant toute chose)
  if (isApiCron) {
    const authHeader = request.headers.get("authorization")
    const cronSecret = process.env.CRON_SECRET
    if (!authHeader || authHeader !== `Bearer ${cronSecret}`) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
    }
    // CRON validé — continuer sans vérifier la session
    return NextResponse.next({ request })
  }

  let supabaseResponse = NextResponse.next({ request })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value)
          )
          supabaseResponse = NextResponse.next({ request })
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options)
          )
        },
      },
    }
  )

  // IMPORTANT: ne pas écrire de code entre createServerClient et supabase.auth.getUser()
  const {
    data: { user },
  } = await supabase.auth.getUser()

  // Rediriger vers /login si non authentifié
  if (!user && !isLoginPage && !isRobotsTxt) {
    const url = request.nextUrl.clone()
    url.pathname = "/login"
    return NextResponse.redirect(url)
  }

  // Rediriger vers / si déjà authentifié et sur /login
  if (user && isLoginPage) {
    const url = request.nextUrl.clone()
    url.pathname = "/"
    return NextResponse.redirect(url)
  }

  return supabaseResponse
}
