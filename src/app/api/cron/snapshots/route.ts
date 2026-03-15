import { NextRequest, NextResponse } from "next/server"

/**
 * CRON Job — Exécuté quotidiennement par Vercel Cron.
 * Appelle l'Edge Function Supabase en mode "cron" pour sauvegarder
 * les snapshots de tous les clients.
 *
 * Aucune clé sensible dans ce code — tout est dans Supabase.
 */
export async function GET(request: NextRequest) {
  // Vérifier le secret CRON (Vercel envoie ce header)
  const authHeader = request.headers.get("authorization")
  const cronSecret = process.env.CRON_SECRET
  if (!authHeader || authHeader !== `Bearer ${cronSecret}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  try {
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
    const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY

    if (!supabaseUrl || !supabaseAnonKey) {
      throw new Error("Missing Supabase env vars")
    }

    // Appeler l'Edge Function en mode CRON
    // On utilise fetch direct car pas de session utilisateur pour le CRON
    const response = await fetch(
      `${supabaseUrl}/functions/v1/fetch-client-metrics`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          // Auth via anon key + cron_secret vérifié dans l'Edge Function
          Authorization: `Bearer ${supabaseAnonKey}`,
          apikey: supabaseAnonKey,
        },
        body: JSON.stringify({
          mode: "cron",
          cron_secret: cronSecret,
        }),
      }
    )

    if (!response.ok) {
      const errorText = await response.text()
      throw new Error(`Edge Function error: ${response.status} ${errorText}`)
    }

    const result = await response.json()

    return NextResponse.json({
      message: "CRON snapshots completed",
      ...result,
    })
  } catch (error) {
    console.error("CRON snapshots error:", error)
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    )
  }
}
