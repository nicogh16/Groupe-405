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
      <Card className="border-border/50 hover:border-border transition-colors cursor-pointer group">
        <CardContent className="p-4 space-y-4">
          {/* Header */}
          <div className="flex items-start justify-between">
            <div className="space-y-1">
              <div className="flex items-center gap-2">
                <div className={`h-2 w-2 rounded-full ${getStatusColor(client.status)}`} />
                <h3 className="text-sm font-semibold">{client.name}</h3>
              </div>
              <Badge variant={appConfig?.badgeVariant ?? "default"} className="text-[10px] px-1.5 py-0">
                {appConfig?.label ?? client.app.name}
              </Badge>
            </div>
            <ArrowRight className="h-4 w-4 text-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity" />
          </div>

          {/* Users */}
          <div className="flex items-center gap-2 text-sm">
            <Users className="h-3.5 w-3.5 text-muted-foreground" />
            <span className="font-medium">
              {latestSnapshot ? formatNumber(latestSnapshot.registered_users_count) : "—"}
            </span>
            <span className="text-muted-foreground text-xs">utilisateurs</span>
          </div>

          {/* Usage */}
          <div className="space-y-2">
            <UsageProgress label="Base de données" value={dbUsage} />
            <UsageProgress label="Stockage" value={storageUsage} />
          </div>

          {/* Financials */}
          <div className="flex items-center justify-between pt-2 border-t border-border/50 text-xs">
            <div>
              <span className="text-muted-foreground">Coût</span>
              <p className="font-medium">
                {latestSnapshot
                  ? formatCurrency(latestSnapshot.estimated_monthly_cost)
                  : formatCurrency(planLimits.monthlyCostBase)}
                /mois
              </p>
            </div>
            <div className="text-right">
              <span className="text-muted-foreground">Revenu</span>
              <p className="font-medium text-emerald-600 dark:text-emerald-400">
                {formatCurrency(client.monthly_revenue)}/mois
              </p>
            </div>
          </div>
        </CardContent>
      </Card>
    </Link>
  )
}
