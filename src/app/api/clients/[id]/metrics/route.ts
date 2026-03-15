import { NextRequest, NextResponse } from "next/server"
import { createClient } from "@/lib/supabase/server"
import type { Profile } from "@/types"

/**
 * GET /api/clients/[id]/metrics
 * Retourne les metriques live d'un client (depuis les snapshots).
 * Authentification requise (verifiee via middleware + server client).
 */
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params
    const supabase = await createClient()

    // Verifier l'authentification
    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
    }

    // Charger le client (utilise la vue securisee)
    const { data: client, error: clientError } = await supabase
      .from("clients_safe")
      .select("*")
      .eq("id", id)
      .single()

    if (clientError || !client) {
      return NextResponse.json({ error: "Client not found" }, { status: 404 })
    }

    // Charger le dernier snapshot
    const { data: snapshot } = await supabase
      .from("usage_snapshots")
      .select("*")
      .eq("client_id", id)
      .order("snapshot_date", { ascending: false })
      .limit(1)
      .single()

    return NextResponse.json({
      client,
      latestSnapshot: snapshot ?? null,
    })
  } catch (error) {
    console.error("Metrics API error:", error)
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    )
  }
}
