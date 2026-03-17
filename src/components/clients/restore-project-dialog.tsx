"use client"

import { useState, useTransition } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import { Loader2, Database } from "lucide-react"
import { toast } from "sonner"
import { restoreProjectDirectly } from "@/app/(dashboard)/clients/actions"

export function RestoreProjectDialog() {
  const [open, setOpen] = useState(false)
  const [isPending, startTransition] = useTransition()
  const [projectRef, setProjectRef] = useState("")
  const [dbPassword, setDbPassword] = useState("")
  const [useMyFidelityTemplate, setUseMyFidelityTemplate] = useState(true)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    
    if (!projectRef.trim()) {
      toast.error("Le project ref est requis")
      return
    }

    if (!dbPassword.trim()) {
      toast.error("Le mot de passe de la base de données est requis")
      return
    }

    startTransition(async () => {
      const formData = new FormData()
      formData.append("projectRef", projectRef.trim())
      formData.append("dbPassword", dbPassword.trim())
      formData.append("useMyFidelityTemplate", useMyFidelityTemplate.toString())

      const result = await restoreProjectDirectly(formData)
      
      if (result.success) {
        toast.success(result.message || "Restauration terminée avec succès !")
        setOpen(false)
        setProjectRef("")
        setDbPassword("")
      } else {
        toast.error(result.error || "Erreur lors de la restauration")
      }
    })
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline" className="gap-2">
          <Database className="h-4 w-4" />
          Restaurer un projet
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-md">
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Restaurer un projet Supabase</DialogTitle>
            <DialogDescription>
              Restaurez directement un projet Supabase en exécutant le template SQL.
              Cette action se fait sans passer par l&apos;Edge Function.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label htmlFor="projectRef">Project Ref Supabase</Label>
              <Input
                id="projectRef"
                placeholder="xxkqixokcppnajcoxntz"
                value={projectRef}
                onChange={(e) => setProjectRef(e.target.value)}
                disabled={isPending}
                required
              />
              <p className="text-xs text-muted-foreground">
                Le project ref se trouve dans l&apos;URL de votre projet Supabase
              </p>
            </div>
            <div className="space-y-2">
              <Label htmlFor="dbPassword">Mot de passe de la base de données</Label>
              <Input
                id="dbPassword"
                type="password"
                placeholder="Votre mot de passe PostgreSQL"
                value={dbPassword}
                onChange={(e) => setDbPassword(e.target.value)}
                disabled={isPending}
                required
              />
              <p className="text-xs text-muted-foreground">
                Le mot de passe PostgreSQL de votre projet Supabase
              </p>
            </div>
            <div className="flex items-center space-x-2">
              <input
                type="checkbox"
                id="useMyFidelityTemplate"
                checked={useMyFidelityTemplate}
                onChange={(e) => setUseMyFidelityTemplate(e.target.checked)}
                disabled={isPending}
                className="h-4 w-4 rounded border-gray-300"
              />
              <Label
                htmlFor="useMyFidelityTemplate"
                className="text-sm font-normal cursor-pointer"
              >
                Utiliser le template MyFidelity (supabase_new_project.sql)
              </Label>
            </div>
            <div className="rounded-lg bg-muted p-3 text-sm text-muted-foreground">
              <p className="font-medium mb-1">⚠️ Attention :</p>
              <ul className="list-disc list-inside space-y-1">
                <li>Cette action va exécuter le SQL sur le projet spécifié</li>
                <li>Assurez-vous que le projet est vide ou que vous acceptez d&apos;écraser les données</li>
                <li>Le fichier template doit être disponible dans Storage ou à la racine du projet</li>
              </ul>
            </div>
          </div>
          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={() => setOpen(false)}
              disabled={isPending}
            >
              Annuler
            </Button>
            <Button type="submit" disabled={isPending}>
              {isPending ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  Restauration en cours...
                </>
              ) : (
                "Restaurer"
              )}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
