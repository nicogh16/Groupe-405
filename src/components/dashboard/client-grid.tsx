import { ClientCard } from "./client-card"
import type { Client, App, UsageSnapshot } from "@/types"

interface ClientGridProps {
  clients: (Client & { app: App })[]
  snapshots: Record<string, UsageSnapshot | null>
}

export function ClientGrid({ clients, snapshots }: ClientGridProps) {
  if (clients.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-16 text-center">
        <p className="text-muted-foreground text-sm">Aucun client pour le moment.</p>
        <p className="text-muted-foreground text-xs mt-1">
          Les clients apparaîtront ici une fois ajoutés.
        </p>
      </div>
    )
  }

  return (
    <div className="grid gap-4 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3">
      {clients.map((client) => (
        <ClientCard
          key={client.id}
          client={client}
          latestSnapshot={snapshots[client.id] ?? null}
        />
      ))}
    </div>
  )
}
