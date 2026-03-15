import { NextRequest, NextResponse } from "next/server"
import { createClient } from "@/lib/supabase/server"
import type { Profile } from "@/types"

/**
 * POST /api/clients/[id]/refresh-metrics
 * Met à jour les métriques d'un client en temps réel via l'Edge Function.
 * Admin seulement. Aucune clé sensible dans ce code.
 */
export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params
    const supabase = await createClient()

    // Vérifier l'authentification et les droits admin
    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
    }

    const { data: profile } = await supabase
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .single()

    if ((profile as Profile | null)?.role !== "admin") {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 })
    }

    // Appeler l'Edge Function — tout le travail sensible se fait dans Supabase
    const { data, error } = await supabase.functions.invoke(
      "fetch-client-metrics",
      {
        body: {
          client_id: id,
          save_snapshot: true, // Sauvegarder le snapshot automatiquement
        },
      }
    )

    if (error) {
      return NextResponse.json(
        { error: "Failed to fetch metrics", details: error.message },
        { status: 500 }
      )
    }

    if (!data?.success) {
      return NextResponse.json(
        { error: data?.error || "Failed to fetch metrics" },
        { status: 500 }
      )
    }

    return NextResponse.json({
      success: true,
      metrics: data.metrics,
      message: "Metrics refreshed successfully",
    })
  } catch (error) {
    console.error("Refresh metrics error:", error)
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    )
  }
}
