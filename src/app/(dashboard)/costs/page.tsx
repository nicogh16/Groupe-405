import { createClient } from "@/lib/supabase/server"
import { redirect } from "next/navigation"
import { CostsTable } from "@/components/costs/costs-table"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { formatCurrency } from "@/lib/utils"
import { SUPABASE_PLAN_LIMITS } from "@/lib/constants"
import type { Client, App, UsageSnapshot, Profile } from "@/types"

export default async function CostsPage() {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) redirect("/login")

  // Vérifier si admin
  const { data: currentProfile } = await supabase
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .single()

  const isAdmin = (currentProfile as Profile | null)?.role === "admin"

  // Charger tous les clients avec leur app
  const { data: clientsRaw } = await supabase
    .from("clients")
    .select("*, app:apps(*)")
    .order("name")

  const clients = (clientsRaw ?? []) as unknown as (Client & { app: App })[]

  // Charger les derniers snapshots pour chaque client
  const snapshots: Record<string, UsageSnapshot | null> = {}
  if (clients.length > 0) {
    const { data: snapshotsRaw } = await supabase
      .from("usage_snapshots")
      .select("*")
      .in(
        "client_id",
        clients.map((c) => c.id)
      )
      .order("snapshot_date", { ascending: false })

    // Garder uniquement le snapshot le plus récent par client
    for (const snap of snapshotsRaw ?? []) {
      const s = snap as UsageSnapshot
      if (!snapshots[s.client_id]) {
        snapshots[s.client_id] = s
      }
    }
  }

  // Calculer les totaux
  const totalMonthlyCost = clients.reduce((sum, client) => {
    const snapshot = snapshots[client.id]
    const monthlyCost = snapshot
      ? snapshot.estimated_monthly_cost
      : SUPABASE_PLAN_LIMITS[client.supabase_plan]?.monthlyCostBase ?? 0
    return sum + monthlyCost
  }, 0)

  const totalMonthlyRevenue = clients.reduce((sum, client) => sum + (client.monthly_revenue ?? 0), 0)

  const totalMonthlyMargin = totalMonthlyRevenue - totalMonthlyCost

  const totalAnnualCost = totalMonthlyCost * 12
  const totalAnnualRevenue = totalMonthlyRevenue * 12
  const totalAnnualMargin = totalMonthlyMargin * 12

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Analyse des Coûts et Marges</h1>
        <p className="text-sm text-muted-foreground mt-1">
          Vue d&apos;ensemble des coûts et marges par client
        </p>
      </div>

      {/* Statistiques globales */}
      <div className="grid gap-4 grid-cols-1 md:grid-cols-3">
        <Card className="border-border/50">
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-medium">Coût Mensuel Total</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-bold">{formatCurrency(totalMonthlyCost)}</p>
            <p className="text-xs text-muted-foreground mt-1">
              {formatCurrency(totalAnnualCost)} / an
            </p>
          </CardContent>
        </Card>

        <Card className="border-border/50">
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-medium">Revenu Mensuel Total</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-bold text-emerald-600 dark:text-emerald-400">
              {formatCurrency(totalMonthlyRevenue)}
            </p>
            <p className="text-xs text-muted-foreground mt-1">
              {formatCurrency(totalAnnualRevenue)} / an
            </p>
          </CardContent>
        </Card>

        <Card className="border-border/50">
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-medium">Marge Mensuelle Totale</CardTitle>
          </CardHeader>
          <CardContent>
            <p
              className={`text-2xl font-bold ${
                totalMonthlyMargin >= 0
                  ? "text-emerald-600 dark:text-emerald-400"
                  : "text-red-600 dark:text-red-400"
              }`}
            >
              {formatCurrency(totalMonthlyMargin)}
            </p>
            <p className="text-xs text-muted-foreground mt-1">
              {formatCurrency(totalAnnualMargin)} / an
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Tableau des coûts */}
      <CostsTable clients={clients} snapshots={snapshots} isAdmin={isAdmin} />
    </div>
  )
}
