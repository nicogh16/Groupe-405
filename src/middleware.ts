import { type NextRequest, NextResponse } from "next/server"
import { updateSession } from "@/lib/supabase/middleware"

// URL Supabase pour autoriser les connexions API dans le CSP
const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? ""

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl

  // ─── Blocage défensif : aucune route /api ne doit être accessible sans auth ──
  // Les appels externes tentant d'abuser des endpoints sont bloqués ici.
  // Note : le sign-up public Supabase est désactivé directement sur le projet.

  // 1. Gerer la session auth + redirections
  const response = await updateSession(request)

  // 2. Content-Security-Policy — dashboard interne uniquement
  //    - Connexions API uniquement vers Supabase
  //    - Pas d'iframe, pas d'objets embarqués
  //    - Scripts : self uniquement (+ unsafe-inline pour Next.js hydration)
  const supabaseHost = SUPABASE_URL.replace("https://", "")
  const cspDirectives = [
    `default-src 'self'`,
    `script-src 'self' 'unsafe-inline' 'unsafe-eval'`, // unsafe-eval requis par Next.js en dev
    `style-src 'self' 'unsafe-inline'`,                 // unsafe-inline requis par shadcn/ui
    `img-src 'self' data: blob: https://*.supabase.co`,
    `font-src 'self' data:`,
    `connect-src 'self' https://${supabaseHost} wss://${supabaseHost} https://api.supabase.com`,
    `frame-src 'none'`,
    `object-src 'none'`,
    `base-uri 'self'`,
    `form-action 'self'`,
    `frame-ancestors 'none'`,
    `upgrade-insecure-requests`,
  ].join("; ")

  // 3. Tous les headers de sécurité
  const securityHeaders: Record<string, string> = {
    "Content-Security-Policy": cspDirectives,
    "Strict-Transport-Security": "max-age=63072000; includeSubDomains; preload",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "X-XSS-Protection": "0",                         // Désactivé — remplacé par CSP
    "Referrer-Policy": "strict-origin-when-cross-origin",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=(), payment=()",
    "Cross-Origin-Opener-Policy": "same-origin",
    "Cross-Origin-Resource-Policy": "same-origin",
    "Cross-Origin-Embedder-Policy": "require-corp",
  }

  Object.entries(securityHeaders).forEach(([key, value]) => {
    response.headers.set(key, value)
  })

  // 4. Supprimer les headers qui révèlent la stack technique
  response.headers.delete("x-powered-by")
  response.headers.delete("server")

  return response
}

export const config = {
  matcher: [
    /*
     * Match toutes les routes sauf :
     * - _next/static (fichiers statiques)
     * - _next/image (optimisation images)
     * - favicon.ico, sitemap.xml, robots.txt
     */
    "/((?!_next/static|_next/image|favicon.ico|sitemap.xml|robots.txt).*)",
  ],
}
