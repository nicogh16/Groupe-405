"use client"

import { useState, useTransition } from "react"
import { updateRevenue } from "@/app/(dashboard)/clients/[slug]/actions"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Loader2, Save } from "lucide-react"
import { toast } from "sonner"

interface RevenueFormProps {
  clientId: string
  currentRevenue: number
  isAdmin: boolean
}

export function RevenueForm({ clientId, currentRevenue, isAdmin }: RevenueFormProps) {
  const [revenue, setRevenue] = useState(currentRevenue.toString())
  const [isPending, startTransition] = useTransition()

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()

    const formData = new FormData()
    formData.set("clientId", clientId)
    formData.set("monthlyRevenue", revenue)

    startTransition(async () => {
      const result = await updateRevenue(formData)
      if (result?.error) {
        toast.error(result.error)
      } else {
        toast.success("Revenu mis à jour")
      }
    })
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-2">
      <Label className="text-xs text-muted-foreground">Revenu mensuel ($ CAD)</Label>
      <div className="flex items-center gap-2">
        <Input
          type="number"
          step="0.01"
          min="0"
          value={revenue}
          onChange={(e) => setRevenue(e.target.value)}
          disabled={!isAdmin || isPending}
          className="max-w-[200px]"
        />
        {isAdmin && (
          <Button type="submit" size="sm" variant="outline" disabled={isPending}>
            {isPending ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <Save className="h-4 w-4" />
            )}
          </Button>
        )}
      </div>
    </form>
  )
}
