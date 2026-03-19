import { createClient } from "@/lib/supabase/server"
import { redirect } from "next/navigation"
import { ClientGrid } from "@/components/dashboard/client-grid"
import { ProvisionClientDialog } from "@/components/clients/provision-client-dialog"
import { RecentJobs } from "@/components/clients/recent-jobs"
import type { Client, App, UsageSnapshot, Profile, ProvisioningJob } from "@/types"

export default async function ClientsPage() {
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

  // Charger les jobs de provisionnement récents (admin only)
  let recentJobs: ProvisioningJob[] = []
  if (isAdmin) {
    const { data: jobsRaw } = await supabase
      .from("provisioning_jobs")
      .select("*")
      .order("created_at", { ascending: false })
      .limit(10)

    recentJobs = (jobsRaw ?? []) as ProvisioningJob[]
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Clients</h1>
          <p className="text-sm text-muted-foreground mt-1">
            {clients.length} client{clients.length > 1 ? "s" : ""} au total
          </p>
        </div>
        {isAdmin && (
          <div className="flex items-center gap-2">
            <ProvisionClientDialog />
          </div>
        )}
      </div>
      <ClientGrid clients={clients} snapshots={snapshots} />
      {isAdmin && recentJobs.length > 0 && <RecentJobs jobs={recentJobs} />}
    </div>
  )
}
