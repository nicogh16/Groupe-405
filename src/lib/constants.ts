/**
 * Limites des plans Supabase pour calculer les pourcentages d'usage.
 */
export const SUPABASE_PLAN_LIMITS = {
  free: {
    label: "Free",
    databaseSizeBytes: 500 * 1024 * 1024,       // 500 MB
    storageSizeBytes: 1 * 1024 * 1024 * 1024,    // 1 GB
    monthlyActiveUsers: 50_000,
    edgeFunctionInvocations: 500_000,
    realtimeMessages: 2_000_000,
    monthlyCostBase: 0,
  },
  pro: {
    label: "Pro",
    databaseSizeBytes: 8 * 1024 * 1024 * 1024,   // 8 GB
    storageSizeBytes: 100 * 1024 * 1024 * 1024,   // 100 GB
    monthlyActiveUsers: 100_000,
    edgeFunctionInvocations: 2_000_000,
    realtimeMessages: 5_000_000,
    monthlyCostBase: 25,
  },
  team: {
    label: "Team",
    databaseSizeBytes: 8 * 1024 * 1024 * 1024,   // 8 GB
    storageSizeBytes: 100 * 1024 * 1024 * 1024,   // 100 GB
    monthlyActiveUsers: 100_000,
    edgeFunctionInvocations: 2_000_000,
    realtimeMessages: 5_000_000,
    monthlyCostBase: 599,
  },
  enterprise: {
    label: "Enterprise",
    databaseSizeBytes: 100 * 1024 * 1024 * 1024,
    storageSizeBytes: 1024 * 1024 * 1024 * 1024,
    monthlyActiveUsers: 1_000_000,
    edgeFunctionInvocations: 10_000_000,
    realtimeMessages: 50_000_000,
    monthlyCostBase: 0,
  },
} as const

export type SupabasePlan = keyof typeof SUPABASE_PLAN_LIMITS

export const APP_CONFIG = {
  myfidelity: {
    label: "MyFidelity",
    color: "bg-blue-500",
    textColor: "text-blue-500",
    badgeVariant: "default" as const,
  },
  studioconnect: {
    label: "StudioConnect",
    color: "bg-violet-500",
    textColor: "text-violet-500",
    badgeVariant: "secondary" as const,
  },
} as const

export const NAV_ITEMS = [
  { label: "Dashboard", href: "/", icon: "LayoutDashboard" },
  { label: "Clients", href: "/clients", icon: "Users" },
  { label: "Paramètres", href: "/settings", icon: "Settings" },
] as const
