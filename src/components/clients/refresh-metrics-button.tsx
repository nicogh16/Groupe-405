"use client"

import { useState } from "react"
import { Button } from "@/components/ui/button"
import { RefreshCw, Loader2 } from "lucide-react"
import { toast } from "sonner"

interface RefreshMetricsButtonProps {
  clientId: string
  isAdmin: boolean
}

export function RefreshMetricsButton({ clientId, isAdmin }: RefreshMetricsButtonProps) {
  const [loading, setLoading] = useState(false)

  async function handleRefresh() {
    if (!isAdmin) return

    setLoading(true)
    try {
      const res = await fetch(`/api/clients/${clientId}/refresh-metrics`, {
        method: "POST",
      })

      const data = await res.json()

      if (!res.ok) {
        toast.error(data.error || "Erreur lors de la mise à jour")
        return
      }

      toast.success("Métriques mises à jour avec succès")
      // Rafraîchir la page pour afficher les nouvelles données
      window.location.reload()
    } catch (error) {
      toast.error("Erreur lors de la mise à jour des métriques")
    } finally {
      setLoading(false)
    }
  }

  if (!isAdmin) return null

  return (
    <Button
      variant="outline"
      size="sm"
      onClick={handleRefresh}
      disabled={loading}
      className="gap-2"
    >
      {loading ? (
        <>
          <Loader2 className="h-4 w-4 animate-spin" />
          Mise à jour...
        </>
      ) : (
        <>
          <RefreshCw className="h-4 w-4" />
          Actualiser les métriques
        </>
      )}
    </Button>
  )
}
