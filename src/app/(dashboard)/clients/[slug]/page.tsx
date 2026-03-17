import { createClient } from "@/lib/supabase/server"
import { notFound } from "next/navigation"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Separator } from "@/components/ui/separator"
import { UsageProgress } from "@/components/dashboard/usage-progress"
import { RevenueForm } from "@/components/clients/revenue-form"
import { NotesEditor } from "@/components/clients/notes-editor"
import { LinksSection } from "@/components/clients/links-section"
import { RefreshMetricsButton } from "@/components/clients/refresh-metrics-button"
import { ExpensesManager } from "@/components/clients/expenses-manager"
import {
  formatBytes,
  formatCurrency,
  formatNumber,
  getStatusColor,
  getUsagePercentage,
} from "@/lib/utils"
import { APP_CONFIG, SUPABASE_PLAN_LIMITS } from "@/lib/constants"
import { Users, HardDrive, Activity, UserCheck } from "lucide-react"
import type { Client, App, UsageSnapshot, Profile, Expense } from "@/types"

export default async function ClientDetailPage({
  params,
}: {
  params: Promise<{ slug: string }>
}) {
  const { slug } = await params
  const supabase = await createClient()

  // Verifier si l'utilisateur est admin
  const {
    data: { user },
  } = await supabase.auth.getUser()
  const { data: profile } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", user!.id)
    .single()
  const isAdmin = (profile as Profile | null)?.role === "admin"

  // Charger le client (colonnes securisees uniquement)
  const { data: clientRaw } = await supabase
    .from("clients")
    .select("id, app_id, name, slug, supabase_project_ref, supabase_url, supabase_plan, monthly_revenue, vercel_project_url, github_repo_url, status, notes, created_at, updated_at, app:apps(*)")
    .eq("slug", slug)
    .single()

  if (!clientRaw) notFound()

  const client = clientRaw as unknown as Client & { app: App }
  const appConfig = APP_CONFIG[client.app.slug as keyof typeof APP_CONFIG]
  const planLimits = SUPABASE_PLAN_LIMITS[client.supabase_plan]

  // Charger les snapshots (derniers 30 jours)
  const { data: snapshotsRaw } = await supabase
    .from("usage_snapshots")
    .select("*")
    .eq("client_id", client.id)
    .order("snapshot_date", { ascending: false })
    .limit(30)

  const snapshots = (snapshotsRaw ?? []) as UsageSnapshot[]
  const latest = snapshots[0] ?? null

  // Charger les dépenses du client
  const { data: expensesRaw } = await supabase
    .from("expenses")
    .select("*")
    .eq("client_id", client.id)
    .order("expense_date", { ascending: false })

  const expenses = (expensesRaw ?? []) as Expense[]

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-start justify-between">
        <div className="space-y-1">
          <div className="flex items-center gap-3">
            <div className={`h-3 w-3 rounded-full ${getStatusColor(client.status)}`} />
            <h1 className="text-2xl font-bold tracking-tight">{client.name}</h1>
            <Badge variant={appConfig?.badgeVariant ?? "default"}>
              {appConfig?.label ?? client.app.name}
            </Badge>
          </div>
          <p className="text-sm text-muted-foreground">
            Plan {planLimits.label} &middot; Créé le{" "}
            {new Date(client.created_at).toLocaleDateString("fr-CA")}
          </p>
        </div>
        <RefreshMetricsButton clientId={client.id} isAdmin={isAdmin} />
      </div>

      {/* Metriques */}
      <div className="grid gap-4 grid-cols-2 lg:grid-cols-4">
        {[
          {
            label: "Utilisateurs",
            value: latest ? formatNumber(latest.registered_users_count) : "—",
            icon: Users,
          },
          {
            label: "Stockage",
            value: latest ? formatBytes(latest.storage_size_bytes) : "—",
            icon: HardDrive,
          },
          {
            label: "Req. API (7j)",
            value: latest
              ? latest.api_requests_count > 0
                ? formatNumber(latest.api_requests_count)
                : "—"
              : "—",
            icon: Activity,
          },
          {
            label: "MAU",
            value: latest ? formatNumber(latest.monthly_active_users) : "—",
            icon: UserCheck,
          },
        ].map((item) => (
          <Card key={item.label} className="border-border/50">
            <CardContent className="p-4">
              <div className="flex items-center justify-between">
                <p className="text-xs font-medium text-muted-foreground">{item.label}</p>
                <item.icon className="h-4 w-4 text-muted-foreground" />
              </div>
              <p className="mt-2 text-xl font-bold">{item.value}</p>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Usage du plan — limites disponibles via l'API publique Supabase */}
      <Card className="border-border/50">
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-medium">
            Usage du plan {planLimits.label} — Limites surveillées
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <UsageProgress
            label={`Stockage (${latest ? formatBytes(latest.storage_size_bytes) : "0 B"} / ${formatBytes(planLimits.storageSizeBytes)})`}
            value={
              latest
                ? getUsagePercentage(latest.storage_size_bytes, planLimits.storageSizeBytes)
                : 0
            }
          />
          <UsageProgress
            label={`Utilisateurs actifs (MAU) (${latest ? formatNumber(latest.monthly_active_users) : "0"} / ${formatNumber(planLimits.monthlyActiveUsers)})`}
            value={
              latest
                ? getUsagePercentage(latest.monthly_active_users, planLimits.monthlyActiveUsers)
                : 0
            }
          />
          {/* Note : Edge Function invocations et Realtime messages ne sont pas disponibles
              via l'API Management publique Supabase. Ces chiffres sont uniquement accessibles
              via l'API interne privée utilisée par le dashboard Supabase. */}
        </CardContent>
      </Card>

      <div className="grid gap-6 lg:grid-cols-2">
        {/* Section financiere */}
        <Card className="border-border/50">
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-medium">Finances</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <p className="text-xs text-muted-foreground">Coût mensuel</p>
                <p className="text-lg font-bold">
                  {latest ? formatCurrency(latest.estimated_monthly_cost) : formatCurrency(planLimits.monthlyCostBase)}
                </p>
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Coût annuel</p>
                <p className="text-lg font-bold">
                  {formatCurrency(
                    (latest ? latest.estimated_monthly_cost : planLimits.monthlyCostBase) * 12
                  )}
                </p>
              </div>
            </div>
            <Separator />
            <RevenueForm
              clientId={client.id}
              currentRevenue={client.monthly_revenue}
              isAdmin={isAdmin}
            />
            <Separator />
            <div className="grid grid-cols-2 gap-4">
              <div>
                <p className="text-xs text-muted-foreground">Revenu annuel</p>
                <p className="text-lg font-bold text-success">
                  {formatCurrency(client.monthly_revenue * 12)}
                </p>
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Marge annuelle</p>
                <p className="text-lg font-bold">
                  {formatCurrency(
                    client.monthly_revenue * 12 -
                      (latest ? latest.estimated_monthly_cost : planLimits.monthlyCostBase) * 12
                  )}
                </p>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Liens et notes */}
        <div className="space-y-6">
          <LinksSection
            supabaseProjectRef={client.supabase_project_ref}
            vercelProjectUrl={client.vercel_project_url}
            githubRepoUrl={client.github_repo_url}
          />
          <NotesEditor
            clientId={client.id}
            currentNotes={client.notes ?? ""}
            isAdmin={isAdmin}
          />
        </div>
      </div>

      {/* Section Dépenses */}
      <Card className="border-border/50">
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-medium">Dépenses</CardTitle>
        </CardHeader>
        <CardContent>
          <ExpensesManager clientId={client.id} expenses={expenses} isAdmin={isAdmin} />
        </CardContent>
      </Card>
    </div>
  )
}
