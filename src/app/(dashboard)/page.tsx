import { createClient } from "@/lib/supabase/server"
import { StatsOverview } from "@/components/dashboard/stats-overview"
import { ClientGrid } from "@/components/dashboard/client-grid"
import { SUPABASE_PLAN_LIMITS } from "@/lib/constants"
import type { Client, App, UsageSnapshot, DashboardStats } from "@/types"

export default async function DashboardPage() {
  const supabase = await createClient()

  // Charger les clients avec leur app (colonnes securisees uniquement)
  const { data: clientsRaw } = await supabase
    .from("clients")
    .select("id, app_id, name, slug, supabase_project_ref, supabase_url, supabase_plan, monthly_revenue, vercel_project_url, github_repo_url, status, notes, created_at, updated_at, app:apps(*)")
    .order("created_at", { ascending: false })

  const clients = (clientsRaw ?? []) as unknown as (Client & { app: App })[]

  // Charger le dernier snapshot pour chaque client
  const snapshots: Record<string, UsageSnapshot | null> = {}

  if (clients.length > 0) {
    const clientIds = clients.map((c) => c.id)
    const { data: snapshotsRaw } = await supabase
      .from("usage_snapshots")
      .select("*")
      .in("client_id", clientIds)
      .order("snapshot_date", { ascending: false })

    const snapshotsList = (snapshotsRaw ?? []) as UsageSnapshot[]
    // Garder seulement le dernier snapshot par client
    for (const snap of snapshotsList) {
      if (!snapshots[snap.client_id]) {
        snapshots[snap.client_id] = snap
      }
    }
  }

  // Calculer les stats globales
  const activeClients = clients.filter((c) => c.status === "active")
  const totalAnnualRevenue = clients.reduce(
    (sum, c) => sum + (c.monthly_revenue ?? 0) * 12,
    0
  )
  const totalAnnualCost = clients.reduce((sum, c) => {
    const snapshot = snapshots[c.id]
    const monthlyCost = snapshot
      ? snapshot.estimated_monthly_cost
      : SUPABASE_PLAN_LIMITS[c.supabase_plan]?.monthlyCostBase ?? 0
    return sum + monthlyCost * 12
  }, 0)
  const totalUsers = Object.values(snapshots).reduce(
    (sum, s) => sum + (s?.registered_users_count ?? 0),
    0
  )

  const stats: DashboardStats = {
    totalClients: clients.length,
    activeClients: activeClients.length,
    totalAnnualRevenue,
    totalAnnualCost,
    totalUsers,
    netMargin: totalAnnualRevenue - totalAnnualCost,
  }

  return (
    <div className="space-y-8">
      <div className="space-y-1">
        <h1 className="text-3xl font-bold tracking-tight text-foreground">Dashboard</h1>
        <p className="text-sm text-muted-foreground">
          Vue d&apos;ensemble de toutes vos instances clients.
        </p>
      </div>
      <StatsOverview stats={stats} />
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-semibold text-foreground">Clients</h2>
        </div>
        <ClientGrid clients={clients} snapshots={snapshots} />
      </div>
    </div>
  )
}
