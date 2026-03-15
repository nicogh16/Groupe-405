"use client"

import { Button } from "@/components/ui/button"
import { AlertTriangle } from "lucide-react"

export default function DashboardError({
  error,
  reset,
}: {
  error: Error & { digest?: string }
  reset: () => void
}) {
  return (
    <div className="flex flex-col items-center justify-center py-16 space-y-4">
      <AlertTriangle className="h-10 w-10 text-destructive" />
      <div className="text-center space-y-1">
        <h2 className="text-lg font-semibold">Une erreur est survenue</h2>
        <p className="text-sm text-muted-foreground max-w-md">
          Impossible de charger le dashboard. Veuillez réessayer.
        </p>
      </div>
      <Button variant="outline" onClick={reset}>
        Réessayer
      </Button>
    </div>
  )
}
