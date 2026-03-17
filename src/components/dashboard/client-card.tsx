import Link from "next/link"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { UsageProgress } from "./usage-progress"
import { formatCurrency, formatNumber, getStatusColor, getUsagePercentage } from "@/lib/utils"
import { APP_CONFIG, SUPABASE_PLAN_LIMITS } from "@/lib/constants"
import { Users, ArrowRight } from "lucide-react"
import type { Client, App, UsageSnapshot } from "@/types"

interface ClientCardProps {
  client: Client & { app: App }
  latestSnapshot: UsageSnapshot | null
}

export function ClientCard({ client, latestSnapshot }: ClientCardProps) {
  const appConfig = APP_CONFIG[client.app.slug as keyof typeof APP_CONFIG]
  const planLimits = SUPABASE_PLAN_LIMITS[client.supabase_plan]

  const dbUsage = latestSnapshot
    ? getUsagePercentage(latestSnapshot.database_size_bytes, planLimits.databaseSizeBytes)
    : 0
  const storageUsage = latestSnapshot
    ? getUsagePercentage(latestSnapshot.storage_size_bytes, planLimits.storageSizeBytes)
    : 0

  return (
    <Link href={`/clients/${client.slug}`}>
      <Card className="border border-border/50 hover:border-border hover:shadow-lg transition-all cursor-pointer group shadow-sm">
        <CardContent className="p-6 space-y-4">
          {/* Header */}
          <div className="flex items-start justify-between">
            <div className="space-y-2.5">
              <div className="flex items-center gap-2.5">
                <div className={`h-2 w-2 rounded-full ${getStatusColor(client.status)}`} />
                <h3 className="text-base font-semibold text-foreground">{client.name}</h3>
              </div>
              <Badge variant={appConfig?.badgeVariant ?? "default"} className="text-xs px-2 py-1 font-medium">
                {appConfig?.label ?? client.app.name}
              </Badge>
            </div>
            <ArrowRight className="h-4 w-4 text-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity" />
          </div>

          {/* Users */}
          <div className="flex items-center gap-2.5 text-base">
            <Users className="h-4 w-4 text-muted-foreground/70" />
            <span className="font-medium text-foreground">
              {latestSnapshot ? formatNumber(latestSnapshot.registered_users_count) : "—"}
            </span>
            <span className="text-muted-foreground text-sm">utilisateurs</span>
          </div>

          {/* Usage */}
          <div className="space-y-3">
            <UsageProgress label="Base de données" value={dbUsage} />
            <UsageProgress label="Stockage" value={storageUsage} />
          </div>

          {/* Financials */}
          <div className="flex items-center justify-between pt-4 border-t border-border/50">
            <div>
              <span className="text-xs font-medium text-muted-foreground uppercase tracking-wide">Coût</span>
              <p className="text-sm font-semibold text-foreground mt-1">
                {latestSnapshot
                  ? formatCurrency(latestSnapshot.estimated_monthly_cost)
                  : formatCurrency(planLimits.monthlyCostBase)}
                <span className="text-xs font-normal text-muted-foreground">/mois</span>
              </p>
            </div>
            <div className="text-right">
              <span className="text-xs font-medium text-muted-foreground uppercase tracking-wide">Revenu</span>
              <p className="text-sm font-semibold text-success mt-1">
                {formatCurrency(client.monthly_revenue)}
                <span className="text-xs font-normal text-muted-foreground">/mois</span>
              </p>
            </div>
          </div>
        </CardContent>
      </Card>
    </Link>
  )
}
