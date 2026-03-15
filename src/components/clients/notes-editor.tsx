"use client"

import { useState, useTransition } from "react"
import { updateNotes } from "@/app/(dashboard)/clients/[slug]/actions"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Textarea } from "@/components/ui/textarea"
import { Loader2, Save } from "lucide-react"
import { toast } from "sonner"

interface NotesEditorProps {
  clientId: string
  currentNotes: string
  isAdmin: boolean
}

export function NotesEditor({ clientId, currentNotes, isAdmin }: NotesEditorProps) {
  const [notes, setNotes] = useState(currentNotes)
  const [isPending, startTransition] = useTransition()

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()

    const formData = new FormData()
    formData.set("clientId", clientId)
    formData.set("notes", notes)

    startTransition(async () => {
      const result = await updateNotes(formData)
      if (result?.error) {
        toast.error(result.error)
      } else {
        toast.success("Notes mises à jour")
      }
    })
  }

  return (
    <Card className="border-border/50">
      <CardHeader className="pb-3">
        <CardTitle className="text-sm font-medium">Notes</CardTitle>
      </CardHeader>
      <CardContent>
        <form onSubmit={handleSubmit} className="space-y-3">
          <Textarea
            rows={4}
            placeholder={isAdmin ? "Ajouter des notes..." : "Aucune note"}
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            disabled={!isAdmin || isPending}
            className="resize-none"
          />
          {isAdmin && (
            <Button type="submit" size="sm" variant="outline" disabled={isPending}>
              {isPending ? (
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              ) : (
                <Save className="mr-2 h-4 w-4" />
              )}
              Sauvegarder
            </Button>
          )}
        </form>
      </CardContent>
    </Card>
  )
}
