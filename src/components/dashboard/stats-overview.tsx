import { Card, CardContent } from "@/components/ui/card"
import { formatCurrency, formatNumber } from "@/lib/utils"
import { Users, DollarSign, TrendingUp, BarChart3 } from "lucide-react"
import type { DashboardStats } from "@/types"

export function StatsOverview({ stats }: { stats: DashboardStats }) {
  const items = [
    {
      label: "Clients actifs",
      value: formatNumber(stats.activeClients),
      subLabel: `${stats.totalClients} total`,
      icon: Users,
    },
    {
      label: "Revenu annuel",
      value: formatCurrency(stats.totalAnnualRevenue),
      subLabel: `${formatCurrency(stats.totalAnnualRevenue / 12)}/mois`,
      icon: DollarSign,
    },
    {
      label: "Coût annuel",
      value: formatCurrency(stats.totalAnnualCost),
      subLabel: `${formatCurrency(stats.totalAnnualCost / 12)}/mois`,
      icon: BarChart3,
    },
    {
      label: "Marge nette",
      value: formatCurrency(stats.netMargin),
      subLabel: stats.totalAnnualRevenue > 0
        ? `${Math.round((stats.netMargin / stats.totalAnnualRevenue) * 100)}%`
        : "—",
      icon: TrendingUp,
    },
  ]

  return (
    <div className="grid gap-4 grid-cols-2 lg:grid-cols-4">
      {items.map((item) => (
        <Card key={item.label} className="border-border/50">
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <p className="text-xs font-medium text-muted-foreground">{item.label}</p>
              <item.icon className="h-4 w-4 text-muted-foreground" />
            </div>
            <div className="mt-2">
              <p className="text-xl font-bold tracking-tight">{item.value}</p>
              <p className="text-xs text-muted-foreground mt-0.5">{item.subLabel}</p>
            </div>
          </CardContent>
        </Card>
      ))}
    </div>
  )
}
