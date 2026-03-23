"use client"

import { useMemo } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import {
  BarChart,
  Bar,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
  Line,
  LineChart,
  Treemap,
} from "recharts"

type Row = Record<string, unknown>

interface StatsDashboardProps {
  source: string | null
  kpi: Record<string, unknown>
  userKpi?: Record<string, unknown>
  charts: Record<string, Row[]>
}

function toNumber(value: unknown): number {
  if (typeof value === "number") return value
  if (typeof value === "string") return Number(value) || 0
  return 0
}

function fmt(value: unknown): string {
  if (value === null || value === undefined) return "—"
  if (typeof value === "number") return Number.isInteger(value) ? value.toLocaleString("fr-CA") : value.toFixed(2)
  if (typeof value === "string" && !Number.isNaN(Date.parse(value))) return new Date(value).toLocaleString("fr-CA")
  return String(value)
}

function pct(value: unknown): string {
  return `${toNumber(value).toFixed(1)}%`
}

function safeRatio(numerator: number, denominator: number): number {
  if (!Number.isFinite(numerator) || !Number.isFinite(denominator) || denominator <= 0) return 0
  return (numerator / denominator) * 100
}

function heatColor(value: number, max: number): string {
  if (max <= 0 || value <= 0) return "rgba(148, 163, 184, 0.12)"
  const ratio = Math.min(Math.max(value / max, 0), 1)
  const alpha = 0.18 + ratio * 0.82
  return `rgba(37, 99, 235, ${alpha.toFixed(3)})`
}

function treemapColor(index: number): string {
  const palette = ["#2563eb", "#7c3aed", "#0ea5e9", "#14b8a6", "#22c55e", "#f59e0b", "#ef4444"]
  return palette[index % palette.length]
}

export function StatsDashboard({ source, kpi, userKpi = {}, charts }: StatsDashboardProps) {
  const dailyTrends = (charts.daily_trends ?? []).map((row) => ({
    ...row,
    transactions: toNumber(row.transactions),
    points_distributed: toNumber(row.points_distributed),
    new_users: toNumber(row.new_users),
    active_users: toNumber(row.active_users),
  }))
  const publicDailyTrends = (charts.transaction_daily_public ?? []).map((row) => ({
    ...row,
    transactions: toNumber(row.transactions),
    points_distributed: toNumber(row.points_distributed),
  }))
  const publicHeatmap = (charts.transaction_heatmap_public ?? []).map((row) => ({
    ...row,
    day_of_week: toNumber(row.day_of_week),
    hour_of_day: toNumber(row.hour_of_day),
    count: toNumber(row.count),
  }))
  const publicPeakHours = (charts.transaction_peak_hours_public ?? []).map((row) => ({
    ...row,
    hour_of_day: toNumber(row.hour_of_day),
    transaction_count: toNumber(row.transaction_count),
  }))
  const transactionItemHeatmap = (charts.transaction_item_daily_heatmap_public ?? []).map((row) => ({
    ...row,
    item_name: String(row.item_name ?? ""),
    date: String(row.date ?? ""),
    day_of_month: toNumber(row.day_of_month),
    order_count: toNumber(row.order_count),
  }))
  const transactionTopItems = (charts.transaction_top_items_public ?? []).map((row) => ({
    ...row,
    item_name: String(row.item_name ?? ""),
    order_count: toNumber(row.order_count),
  }))
  const yearlyHourlyHeatmap = (charts.transaction_hourly_heatmap_year_public ?? []).map((row) => ({
    ...row,
    month_of_year: toNumber(row.month_of_year),
    month_label: String(row.month_label ?? ""),
    hour_of_day: toNumber(row.hour_of_day),
    count: toNumber(row.count),
  }))
  const publicMeta = charts.transaction_meta_public?.[0] ?? {}
  const weeklyActivity = (charts.weekly_activity ?? []).map((row) => ({
    ...row,
    access_count: toNumber(row.access_count),
    unique_users: toNumber(row.unique_users),
  }))
  const topRestaurants = (charts.top_restaurants ?? []).map((row) => ({
    ...row,
    transaction_count: toNumber(row.transaction_count),
  }))
  const timeToValue = (charts.time_to_value ?? []).map((row) => ({
    ...row,
    user_count: toNumber(row.user_count),
  }))
  const weeklyTrends = (charts.weekly_trends ?? []).map((row) => ({
    ...row,
    week_start: String(row.week_start ?? ""),
    transactions: toNumber(row.transactions),
    new_users: toNumber(row.new_users),
    active_users: toNumber(row.active_users),
    app_access_count: toNumber(row.app_access_count),
    points_distributed: toNumber(row.points_distributed),
  }))
  const monthlyTrends = (charts.monthly_trends ?? []).map((row) => ({
    ...row,
    month_start: String(row.month_start ?? ""),
    transactions: toNumber(row.transactions),
    new_users: toNumber(row.new_users),
    active_users: toNumber(row.active_users),
    app_access_count: toNumber(row.app_access_count),
    points_distributed: toNumber(row.points_distributed),
  }))

  const monthlyAsTrend = monthlyTrends.map((row) => ({
    date: row.month_start,
    transactions: row.transactions,
    points_distributed: row.points_distributed,
    new_users: row.new_users,
    active_users: row.active_users,
  }))
  const mainTrend = publicDailyTrends.length > 0
    ? publicDailyTrends
    : dailyTrends.length > 0
      ? dailyTrends
      : monthlyAsTrend
  const weeklyMax = Math.max(...weeklyActivity.map((d) => toNumber(d.access_count)), 1)
  const heatmapMax = Math.max(...publicHeatmap.map((d) => toNumber(d.count)), 1)
  const yearlyHeatmapMax = Math.max(...yearlyHourlyHeatmap.map((d) => toNumber(d.count)), 1)
  const isStartup = Object.prototype.hasOwnProperty.call(kpi, "total_users")
  const effectiveUserKpi =
    Object.keys(userKpi).length > 0 ? userKpi : isStartup ? kpi : {}
  const hasUserKpi = Object.keys(effectiveUserKpi).length > 0
  const hasTopRestaurants = topRestaurants.length > 0
  const hasTimeToValue = timeToValue.length > 0
  const hasPublicTx = publicDailyTrends.length > 0
  const hasPeakHours = publicPeakHours.length > 0
  const publicPeakHourLabel = String(publicMeta.peak_hour_label_utc ?? "—")
  const hasWeeklyActivity = weeklyActivity.length > 0
  const itemUsageData = useMemo(() => {
    if (transactionTopItems.length > 0) {
      return transactionTopItems
        .slice(0, 24)
        .map((row) => ({
          item_name: row.item_name,
          order_count: toNumber(row.order_count),
        }))
    }
    const totals = new Map<string, number>()
    for (const row of transactionItemHeatmap) {
      totals.set(row.item_name, (totals.get(row.item_name) ?? 0) + row.order_count)
    }
    return Array.from(totals.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, 24)
      .map(([item_name, order_count]) => ({
        item_name,
        order_count,
      }))
  }, [transactionTopItems, transactionItemHeatmap])

  const itemUsageMax = Math.max(...itemUsageData.map((item) => toNumber(item.order_count)), 1)
  const hasItemUsageMap = itemUsageData.length > 0
  const dayHourRows = [1, 2, 3, 4, 5, 6, 0]
  const monthRows = useMemo(() => {
    const labels = ["Jan", "Fev", "Mar", "Avr", "Mai", "Jun", "Jul", "Aou", "Sep", "Oct", "Nov", "Dec"]
    return labels.map((label, idx) => ({ month_of_year: idx + 1, month_label: label }))
  }, [])

  const yearlyHeatmapLookup = useMemo(() => {
    const lookup = new Map<string, number>()
    for (const row of yearlyHourlyHeatmap) {
      lookup.set(`${row.month_of_year}__${row.hour_of_day}`, row.count)
    }
    return lookup
  }, [yearlyHourlyHeatmap])

  const trendStart = mainTrend[0]
  const trendEnd = mainTrend[mainTrend.length - 1]
  const trendStartValue = isStartup ? toNumber(trendStart?.new_users) : toNumber(trendStart?.transactions)
  const trendEndValue = isStartup ? toNumber(trendEnd?.new_users) : toNumber(trendEnd?.transactions)
  const trendDelta = trendStartValue > 0 ? ((trendEndValue - trendStartValue) / trendStartValue) * 100 : 0

  const weeklyBestDay = hasWeeklyActivity
    ? weeklyActivity.reduce((best, day) =>
        toNumber(day.access_count) > toNumber(best.access_count) ? day : best, weeklyActivity[0])
    : null

  const topRestaurantShare = hasTopRestaurants
    ? (() => {
        const top = toNumber(topRestaurants[0]?.transaction_count)
        const total = topRestaurants.reduce((sum, r) => sum + toNumber(r.transaction_count), 0)
        if (total === 0) return 0
        return (top / total) * 100
      })()
    : 0

  const signal = (score: number) =>
    score >= 70 ? "bon" : score >= 45 ? "attention" : "critique"

  const latestWeekly = weeklyTrends[weeklyTrends.length - 1]
  const previousWeekly = weeklyTrends[weeklyTrends.length - 2]
  const latestMonthly = monthlyTrends[monthlyTrends.length - 1]
  const previousMonthly = monthlyTrends[monthlyTrends.length - 2]

  const weeklyDeltaFromSeries = isStartup
    ? safeRatio(
        toNumber(latestWeekly?.new_users) - toNumber(previousWeekly?.new_users),
        Math.max(toNumber(previousWeekly?.new_users), 1)
      )
    : safeRatio(
        toNumber(latestWeekly?.transactions) - toNumber(previousWeekly?.transactions),
        Math.max(toNumber(previousWeekly?.transactions), 1)
      )

  const monthlyDeltaFromSeries = isStartup
    ? safeRatio(
        toNumber(latestMonthly?.new_users) - toNumber(previousMonthly?.new_users),
        Math.max(toNumber(previousMonthly?.new_users), 1)
      )
    : safeRatio(
        toNumber(latestMonthly?.transactions) - toNumber(previousMonthly?.transactions),
        Math.max(toNumber(previousMonthly?.transactions), 1)
      )

  const strategicKpis = isStartup
    ? [
        {
          label: "Croissance hebdo",
          value: pct(toNumber(kpi.weekly_growth_percentage) || weeklyDeltaFromSeries),
          hint: "Nouveaux users semaine vs semaine precedente",
        },
        {
          label: "Croissance mensuelle",
          value: pct(toNumber(kpi.monthly_growth_percentage) || monthlyDeltaFromSeries),
          hint: "Nouveaux users mois vs mois precedent",
        },
        {
          label: "Stickiness (DAU/MAU)",
          value: pct(kpi.stickiness_percentage),
          hint: "Qualite de retention court terme",
        },
        {
          label: "Taux d'activation",
          value: pct(kpi.activation_rate),
          hint: "Users ayant converti vers transaction",
        },
        {
          label: "Variation users actifs",
          value: pct(kpi.active_users_monthly_change_percentage),
          hint: "Actifs du mois courant vs precedent",
        },
        {
          label: "Intensite usage (30j)",
          value: `${toNumber(kpi.app_access_30d).toLocaleString("fr-CA")}`,
          hint: `${toNumber(kpi.unique_users_30d).toLocaleString("fr-CA")} utilisateurs uniques`,
        },
      ]
    : [
        {
          label: "Croissance transactions",
          value: pct(toNumber(kpi.transactions_monthly_change_percentage) || monthlyDeltaFromSeries),
          hint: "Mois courant vs mois precedent",
        },
        {
          label: "Croissance points",
          value: pct(kpi.points_monthly_change_percentage),
          hint: "Evolution des points distribues",
        },
        {
          label: "Transactions / user actif",
          value: toNumber(kpi.avg_transactions_per_active_user).toFixed(2),
          hint: "Frequence de visite client",
        },
        {
          label: "Points / user actif",
          value: toNumber(kpi.avg_points_per_active_user).toFixed(2),
          hint: "Valeur moyenne engagement",
        },
        {
          label: "Participation sondages",
          value: pct(kpi.poll_participation_rate),
          hint: `${toNumber(kpi.voters_count).toLocaleString("fr-CA")} votants`,
        },
        {
          label: "Resto actifs",
          value: pct(safeRatio(toNumber(kpi.restaurants_with_transactions), Math.max(toNumber(kpi.total_restaurants), 1))),
          hint: `${toNumber(kpi.restaurants_with_transactions).toLocaleString("fr-CA")} / ${toNumber(kpi.total_restaurants).toLocaleString("fr-CA")}`,
        },
      ]

  const userKpiCards = hasUserKpi
    ? [
        {
          label: "Utilisateurs totaux",
          value: fmt(effectiveUserKpi.total_users),
          hint: "Base users",
        },
        {
          label: "Nouveaux users (30j)",
          value: fmt(effectiveUserKpi.new_users_30d),
          hint: `${pct(effectiveUserKpi.new_users_30d_percentage)} de la base`,
        },
        {
          label: "Actifs 7j",
          value: fmt(effectiveUserKpi.active_users_7d),
          hint: `${pct(effectiveUserKpi.active_users_percentage)} actifs`,
        },
        {
          label: "Stickiness",
          value: pct(effectiveUserKpi.stickiness_percentage),
          hint: "DAU / MAU",
        },
        {
          label: "Activation",
          value: pct(effectiveUserKpi.activation_rate),
          hint: "Users qui convertissent",
        },
        {
          label: "Acces app (30j)",
          value: fmt(effectiveUserKpi.app_access_30d),
          hint: `${fmt(effectiveUserKpi.unique_users_30d)} users uniques`,
        },
      ]
    : []

  const startupActivityPerUser =
    safeRatio(toNumber(kpi.app_access_30d), Math.max(toNumber(kpi.unique_users_30d), 1))

  const actionInsights = isStartup
    ? [
        {
          title: "Acquisition momentum",
          value: pct(toNumber(kpi.weekly_growth_percentage) || weeklyDeltaFromSeries),
          score: 50 + (toNumber(kpi.weekly_growth_percentage) || weeklyDeltaFromSeries),
          hint: "Objectif: rester > +5% / semaine",
        },
        {
          title: "Activation produit",
          value: pct(kpi.activation_rate),
          score: toNumber(kpi.activation_rate),
          hint: "Part des users qui convertissent vers une transaction",
        },
        {
          title: "Stickiness",
          value: pct(kpi.stickiness_percentage),
          score: toNumber(kpi.stickiness_percentage) * 3,
          hint: "DAU/MAU, objectif > 20%",
        },
        {
          title: "Frequence d'usage",
          value: `${startupActivityPerUser.toFixed(1)} sessions/user`,
          score: Math.min(startupActivityPerUser * 18, 100),
          hint: "Acces 30j / users uniques 30j",
        },
      ]
    : [
        {
          title: "Momentum transactions",
          value: pct(toNumber(kpi.transactions_monthly_change_percentage) || monthlyDeltaFromSeries),
          score: 50 + (toNumber(kpi.transactions_monthly_change_percentage) || monthlyDeltaFromSeries),
          hint: "Objectif: croissance mensuelle positive",
        },
        {
          title: "Engagement transactions",
          value: toNumber(kpi.avg_transactions_per_active_user).toFixed(2),
          score: Math.min(toNumber(kpi.avg_transactions_per_active_user) * 30, 100),
          hint: "Transactions / user actif",
        },
        {
          title: "Participation communautaire",
          value: pct(kpi.poll_participation_rate),
          score: Math.min(toNumber(kpi.poll_participation_rate) * 2.5, 100),
          hint: "Votants / users actifs",
        },
        {
          title: "Risque concentration",
          value: `${topRestaurantShare.toFixed(1)}%`,
          score: Math.max(100 - topRestaurantShare, 0),
          hint: "Part du top resto dans le volume",
        },
      ]

  const alerts = actionInsights
    .map((item) => ({ ...item, level: signal(item.score) }))
    .filter((item) => item.level !== "bon")

  const kpiCards = isStartup
    ? [
        {
          label: "Utilisateurs totaux",
          value: fmt(kpi.total_users),
          hint: "Base installée",
        },
        {
          label: "Nouveaux utilisateurs (30j)",
          value: fmt(kpi.new_users_30d),
          hint: `${pct(kpi.new_users_30d_percentage)} de la base`,
        },
        {
          label: "Utilisateurs actifs (7j)",
          value: fmt(kpi.active_users_7d),
          hint: `${pct(kpi.active_users_percentage)} d'activité`,
        },
      ]
    : [
        {
          label: "Transactions (30j)",
          value: hasPublicTx ? fmt(publicMeta.total_transactions_30d) : fmt(kpi.transactions_30d),
          hint: `${fmt(kpi.transactions_7d)} sur 7 jours`,
        },
        {
          label: "Points / transaction",
          value: hasPublicTx ? fmt(publicMeta.avg_points_per_transaction_30d) : fmt(kpi.avg_points_per_transaction),
          hint: "Moyenne 30 jours",
        },
        {
          label: "Heure de pointe",
          value: hasPublicTx ? publicPeakHourLabel : "—",
          hint: hasPublicTx ? "Basé sur public.transactions" : "Données indisponibles",
        },
      ]

  return (
    <div className="space-y-4">
      {source ? <p className="text-xs text-muted-foreground">Source: {source}</p> : null}
      <p className="text-xs text-muted-foreground">
        Series chargees: quotidien {mainTrend.length}, hebdo {weeklyTrends.length}, mensuel {monthlyTrends.length}.
      </p>
      <Tabs defaultValue="overview" className="space-y-4">
        <TabsList className="h-auto flex-wrap rounded-xl border border-border/60 bg-muted/40 p-1">
          <TabsTrigger value="overview" className="rounded-lg">Vue d'ensemble</TabsTrigger>
          <TabsTrigger value="trends" className="rounded-lg">Tendances</TabsTrigger>
          <TabsTrigger value="heatmaps" className="rounded-lg">Heatmaps</TabsTrigger>
          <TabsTrigger value="insights" className="rounded-lg">Insights</TabsTrigger>
        </TabsList>

        <TabsContent value="overview" className="space-y-4">
          <div className="grid gap-3 md:grid-cols-3">
            {kpiCards.map((item) => (
              <Card key={item.label} className="border-border/50">
                <CardContent className="p-4">
                  <p className="text-xs text-muted-foreground">{item.label}</p>
                  <p className="mt-1 text-2xl font-bold">{item.value}</p>
                  <p className="mt-1 text-xs text-muted-foreground">{item.hint}</p>
                </CardContent>
              </Card>
            ))}
          </div>

          <Card className="border-border/50 bg-gradient-to-br from-card to-blue-50/20 dark:to-blue-950/20">
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-medium">KPI strategiques a tracker</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
                {strategicKpis.map((item) => (
                  <div key={item.label} className="rounded-md border border-border/60 p-3">
                    <p className="text-xs text-muted-foreground">{item.label}</p>
                    <p className="mt-1 text-xl font-semibold">{item.value}</p>
                    <p className="mt-1 text-xs text-muted-foreground">{item.hint}</p>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>

          {hasUserKpi ? (
            <Card className="border-border/50">
              <CardHeader className="pb-3">
                <CardTitle className="text-sm font-medium">KPI Utilisateurs (Startup)</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
                  {userKpiCards.map((item) => (
                    <div key={item.label} className="rounded-md border border-border/60 p-3">
                      <p className="text-xs text-muted-foreground">{item.label}</p>
                      <p className="mt-1 text-xl font-semibold">{item.value}</p>
                      <p className="mt-1 text-xs text-muted-foreground">{item.hint}</p>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>
          ) : null}
        </TabsContent>

        <TabsContent value="trends" className="space-y-4">
          <Card className="border-border/50 bg-gradient-to-br from-card to-violet-50/20 dark:to-violet-950/20">
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-medium">
                {isStartup ? "Croissance quotidienne (30 jours)" : "Performance quotidienne (30 jours)"}
              </CardTitle>
            </CardHeader>
            <CardContent className="h-72">
              {mainTrend.length > 0 ? (
                <ResponsiveContainer width="100%" height="100%">
                  <LineChart data={mainTrend}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis dataKey="date" tick={{ fontSize: 12 }} />
                    <YAxis yAxisId="left" tick={{ fontSize: 12 }} />
                    <YAxis yAxisId="right" orientation="right" tick={{ fontSize: 12 }} />
                    <Tooltip />
                    {isStartup ? (
                      <>
                        <Line yAxisId="left" type="monotone" dataKey="new_users" stroke="#2563eb" strokeWidth={2} dot={false} />
                        <Line yAxisId="right" type="monotone" dataKey="active_users" stroke="#16a34a" strokeWidth={2} dot={false} />
                      </>
                    ) : (
                      <>
                        <Line yAxisId="left" type="monotone" dataKey="transactions" stroke="#2563eb" strokeWidth={2} dot={false} />
                        <Line yAxisId="right" type="monotone" dataKey="points_distributed" stroke="#7c3aed" strokeWidth={2} dot={false} />
                      </>
                    )}
                  </LineChart>
                </ResponsiveContainer>
              ) : (
                <div className="flex h-full items-center justify-center text-sm text-muted-foreground">
                  Pas assez de données pour la tendance.
                </div>
              )}
            </CardContent>
          </Card>

          <Card className="border-border/50">
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-medium">
                {hasTopRestaurants ? "Top restaurants (transactions)" : "Time To Value"}
              </CardTitle>
            </CardHeader>
            <CardContent className="h-72">
              {hasTopRestaurants || hasPeakHours || hasTimeToValue ? (
                <ResponsiveContainer width="100%" height="100%">
                  {hasTopRestaurants ? (
                    <BarChart data={topRestaurants.slice(0, 8)} layout="vertical" margin={{ left: 20 }}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis type="number" tick={{ fontSize: 12 }} />
                      <YAxis type="category" dataKey="restaurant_name" tick={{ fontSize: 11 }} width={120} />
                      <Tooltip />
                      <Bar dataKey="transaction_count" fill="#2563eb" radius={[0, 4, 4, 0]} />
                    </BarChart>
                  ) : hasPeakHours ? (
                    <BarChart data={publicPeakHours}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis dataKey="hour_of_day" tick={{ fontSize: 12 }} />
                      <YAxis tick={{ fontSize: 12 }} />
                      <Tooltip />
                      <Bar dataKey="transaction_count" fill="#0ea5e9" radius={[4, 4, 0, 0]} />
                    </BarChart>
                  ) : (
                    <BarChart data={timeToValue}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis dataKey="time_to_value" tick={{ fontSize: 11 }} />
                      <YAxis tick={{ fontSize: 12 }} />
                      <Tooltip />
                      <Bar dataKey="user_count" fill="#7c3aed" radius={[4, 4, 0, 0]} />
                    </BarChart>
                  )}
                </ResponsiveContainer>
              ) : (
                <div className="flex h-full items-center justify-center text-sm text-muted-foreground">
                  Pas assez de données pour ce graphe.
                </div>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="heatmaps" className="space-y-4">
          <Card className="border-border/50">
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-medium">Heatmap annuelle des commandes (12 mois x 24h)</CardTitle>
            </CardHeader>
            <CardContent>
              {yearlyHourlyHeatmap.length > 0 ? (
                <div className="space-y-3">
                  <div className="overflow-x-auto">
                    <div className="min-w-[860px] space-y-1 rounded-lg border border-border/40 bg-background/80 p-2 shadow-sm">
                      <div className="grid items-center gap-1" style={{ gridTemplateColumns: "48px repeat(24, minmax(22px, 1fr))" }}>
                        <p className="text-[10px] text-muted-foreground">Mois</p>
                        {Array.from({ length: 24 }).map((_, hour) => (
                          <p key={`annual-hour-${hour}`} className="text-center text-[9px] text-muted-foreground">
                            {hour % 3 === 0 ? String(hour).padStart(2, "0") : ""}
                          </p>
                        ))}
                      </div>
                      {monthRows.map((month) => (
                        <div
                          key={`annual-month-${month.month_of_year}`}
                          className="grid items-center gap-1"
                          style={{ gridTemplateColumns: "48px repeat(24, minmax(22px, 1fr))" }}
                        >
                          <p className="text-[10px] text-muted-foreground">{month.month_label}</p>
                          {Array.from({ length: 24 }).map((_, hour) => {
                            const count = yearlyHeatmapLookup.get(`${month.month_of_year}__${hour}`) ?? 0
                            return (
                              <div
                                key={`${month.month_of_year}-${hour}`}
                                className="h-5 rounded-[4px] border border-border/15"
                                style={{ backgroundColor: heatColor(count, yearlyHeatmapMax) }}
                                title={`${month.month_label} ${String(hour).padStart(2, "0")}h: ${count} commandes`}
                              />
                            )
                          })}
                        </div>
                      ))}
                    </div>
                  </div>
                  <p className="text-[10px] text-muted-foreground">
                    Permet d'identifier les plages horaires structurellement fortes sur l'annee.
                  </p>
                </div>
              ) : (
                <div className="flex h-40 items-center justify-center text-sm text-muted-foreground">
                  Donnees annuelles horaires indisponibles.
                </div>
              )}
            </CardContent>
          </Card>

          <Card className="border-border/50 bg-gradient-to-br from-card to-cyan-50/20 dark:to-cyan-950/20">
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-medium">Carte de chaleur des articles (sans notion de temps)</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {hasItemUsageMap ? (
                <div className="space-y-3">
                  <div className="h-80 overflow-hidden rounded-xl border border-border/40 bg-background/80 p-2 shadow-sm">
                    <ResponsiveContainer width="100%" height="100%">
                      <Treemap
                        data={itemUsageData}
                        dataKey="order_count"
                        nameKey="item_name"
                        stroke="rgba(255,255,255,0.6)"
                        fill="#2563eb"
                        isAnimationActive={false}
                        content={(props: any) => {
                          const { x, y, width, height, index, name, value } = props
                          if (width < 18 || height < 16) return null
                          const bg = treemapColor(index ?? 0)
                          const canShowText = width > 84 && height > 34
                          const canShowValue = width > 120 && height > 52
                          return (
                            <g>
                              <rect
                                x={x}
                                y={y}
                                width={width}
                                height={height}
                                rx={8}
                                ry={8}
                                fill={bg}
                                fillOpacity={0.9}
                                stroke="rgba(255,255,255,0.7)"
                                strokeWidth={1}
                              />
                              {canShowText ? (
                                <text x={x + 8} y={y + 18} fill="white" fontSize={11} fontWeight={600}>
                                  {String(name).slice(0, 22)}
                                </text>
                              ) : null}
                              {canShowValue ? (
                                <text x={x + 8} y={y + 34} fill="rgba(255,255,255,0.9)" fontSize={10}>
                                  {toNumber(value).toLocaleString("fr-CA")} cmd
                                </text>
                              ) : null}
                            </g>
                          )
                        }}
                      />
                    </ResponsiveContainer>
                  </div>
                  <div className="grid gap-2 md:grid-cols-2 xl:grid-cols-3">
                    {itemUsageData.slice(0, 6).map((item) => (
                      <div key={item.item_name} className="rounded-lg border border-border/50 bg-background/70 p-2">
                        <p className="truncate text-xs text-muted-foreground" title={item.item_name}>
                          {item.item_name}
                        </p>
                        <p className="text-sm font-semibold">{toNumber(item.order_count).toLocaleString("fr-CA")} commandes</p>
                      </div>
                    ))}
                  </div>
                </div>
              ) : (
                <div className="flex h-24 items-center justify-center text-sm text-muted-foreground">
                  Pas assez de donnees article pour construire la carte.
                </div>
              )}

              <div className="flex items-center gap-2 text-[10px] text-muted-foreground">
                <span>Intensite</span>
                <div className="h-2 w-16 rounded-sm" style={{ backgroundColor: heatColor(0, 1) }} />
                <span>0</span>
                <div className="h-2 w-16 rounded-sm" style={{ backgroundColor: heatColor(itemUsageMax * 0.5, itemUsageMax) }} />
                <span>moyen</span>
                <div className="h-2 w-16 rounded-sm" style={{ backgroundColor: heatColor(itemUsageMax, itemUsageMax) }} />
                <span>fort</span>
              </div>
            </CardContent>
          </Card>

          {publicHeatmap.length > 0 ? (
            <Card className="border-border/50 bg-gradient-to-br from-card to-emerald-50/20 dark:to-emerald-950/20">
              <CardHeader className="pb-3">
                <CardTitle className="text-sm font-medium">Heatmap hebdo (jour x heure)</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="space-y-2 rounded-lg border border-border/40 bg-background/80 p-2 shadow-sm">
                  {dayHourRows.map((day) => {
                    const dayRows = publicHeatmap.filter((item) => toNumber(item.day_of_week) === day)
                    const dayLabel = String(dayRows[0]?.day_name ?? "Jour").slice(0, 3)
                    return (
                      <div
                        key={`weekly-day-hour-${day}`}
                        className="grid items-center gap-1"
                        style={{ gridTemplateColumns: "42px repeat(24, minmax(22px, 1fr))" }}
                      >
                        <p className="text-[10px] text-muted-foreground">{dayLabel}</p>
                        {Array.from({ length: 24 }).map((_, hour) => {
                          const row = dayRows.find((item) => toNumber(item.hour_of_day) === hour)
                          const count = toNumber(row?.count)
                          return (
                            <div
                              key={`${day}-${hour}`}
                              className="h-4 rounded-sm border border-border/20"
                              style={{ backgroundColor: heatColor(count, heatmapMax) }}
                              title={`${dayLabel} ${String(hour).padStart(2, "0")}h: ${count} tx`}
                            />
                          )
                        })}
                      </div>
                    )
                  })}
                </div>
              </CardContent>
            </Card>
          ) : null}
        </TabsContent>

        <TabsContent value="insights" className="space-y-4">
          <Card className="border-border/50">
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-medium">Insights actionnables</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
                {actionInsights.map((item) => {
                  const level = signal(item.score)
                  const tone =
                    level === "bon"
                      ? "border-emerald-500/40 bg-emerald-500/5"
                      : level === "attention"
                        ? "border-amber-500/40 bg-amber-500/5"
                        : "border-red-500/40 bg-red-500/5"
                  return (
                  <div key={item.title} className="rounded-md border border-border/60 p-3">
                    <div className={`mb-2 inline-flex rounded px-2 py-0.5 text-[10px] uppercase tracking-wide ${tone}`}>
                      {level}
                    </div>
                    <p className="text-xs text-muted-foreground">{item.title}</p>
                    <p className="mt-1 text-xl font-semibold">{item.value}</p>
                    <p className="mt-1 text-xs text-muted-foreground">{item.hint}</p>
                  </div>
                )})}
              </div>
            </CardContent>
          </Card>

          <Card className="border-border/50">
            <CardHeader className="pb-3">
              <CardTitle className="text-sm font-medium">Alertes a surveiller</CardTitle>
            </CardHeader>
            <CardContent>
              {alerts.length > 0 ? (
                <div className="space-y-2">
                  {alerts.map((item) => (
                    <div key={`alert-${item.title}`} className="rounded-md border border-amber-500/40 bg-amber-500/5 p-3">
                      <p className="text-sm font-medium">{item.title}: {item.value}</p>
                      <p className="text-xs text-muted-foreground">{item.hint}</p>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="text-sm text-muted-foreground">
                  Aucun signal critique ou attention detecte pour le moment.
                </p>
              )}
            </CardContent>
          </Card>

          <p className="text-xs text-muted-foreground">
            Lecture rapide: utilise Vue d'ensemble pour le pilotage, Tendances pour l'evolution, Heatmaps pour les patterns d'usage.
          </p>
        </TabsContent>
      </Tabs>
    </div>
  )
}
