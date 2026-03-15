"use client"

import { useState, useTransition, useEffect } from "react"
import { useRouter } from "next/navigation"
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { Loader2, PlusCircle, Rocket } from "lucide-react"
import { toast } from "sonner"
import { startProvisioning, getActiveTemplates } from "@/app/(dashboard)/clients/actions"
import { SUPABASE_REGIONS } from "@/lib/validations/provisioning"
import { ProvisioningProgress } from "./provisioning-progress"
import type { ProjectTemplateWithApp } from "@/types"

export function ProvisionClientDialog() {
  const [open, setOpen] = useState(false)
  const [step, setStep] = useState<"form" | "progress">("form")
  const [isPending, startTransition] = useTransition()
  const [templates, setTemplates] = useState<ProjectTemplateWithApp[]>([])
  const [selectedTemplateId, setSelectedTemplateId] = useState("")
  const [clientName, setClientName] = useState("")
  const [clientSlug, setClientSlug] = useState("")
  const [activeJobId, setActiveJobId] = useState<string | null>(null)
  const router = useRouter()

  // Charger les templates à l'ouverture du dialog
  useEffect(() => {
    if (open) {
      getActiveTemplates().then((result) => {
        if (result.templates) {
          setTemplates(result.templates as ProjectTemplateWithApp[])
          if (result.templates.length > 0) {
            setSelectedTemplateId(result.templates[0].id)
          }
        }
      })
    }
  }, [open])

  // Auto-générer le slug à partir du nom
  useEffect(() => {
    const slug = clientName
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "")
    setClientSlug(slug)
  }, [clientName])

  function handleOpenChange(newOpen: boolean) {
    if (!newOpen && step === "progress") {
      // Si on ferme pendant le provisionnement, on refresh
      router.refresh()
    }
    if (!newOpen) {
      // Reset
      setStep("form")
      setClientName("")
      setClientSlug("")
      setActiveJobId(null)
    }
    setOpen(newOpen)
  }

  async function handleSubmit(formData: FormData) {
    startTransition(async () => {
      const result = await startProvisioning(formData)
      if (result.success && result.jobId) {
        toast.success("Provisionnement lancé !")
        setActiveJobId(result.jobId)
        setStep("progress")
      } else {
        toast.error(result.error || "Erreur lors du lancement")
      }
    })
  }

  function handleProvisioningComplete() {
    toast.success("Le nouveau client a été créé avec succès !")
    router.refresh()
  }

  const selectedTemplate = templates.find((t) => t.id === selectedTemplateId)

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger asChild>
        <Button className="gap-2">
          <PlusCircle className="h-4 w-4" />
          Nouveau client
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-lg">
        {step === "form" ? (
          <>
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2">
                <Rocket className="h-5 w-5" />
                Créer un nouveau client
              </DialogTitle>
              <DialogDescription>
                Provisionne automatiquement un projet Supabase, un repo GitHub et un projet
                Vercel pour le nouveau client.
              </DialogDescription>
            </DialogHeader>
            <form action={handleSubmit}>
              <div className="grid gap-4 py-4">
                {/* Template */}
                <div className="space-y-2">
                  <Label htmlFor="templateId">Produit</Label>
                  <input type="hidden" name="templateId" value={selectedTemplateId} />
                  <Select
                    value={selectedTemplateId}
                    onValueChange={setSelectedTemplateId}
                    disabled={isPending}
                  >
                    <SelectTrigger>
                      <SelectValue placeholder="Choisir un produit" />
                    </SelectTrigger>
                    <SelectContent>
                      {templates.map((t) => (
                        <SelectItem key={t.id} value={t.id}>
                          {t.app?.name ?? t.name}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  {selectedTemplate?.description && (
                    <p className="text-xs text-muted-foreground">{selectedTemplate.description}</p>
                  )}
                </div>

                {/* Nom du client */}
                <div className="space-y-2">
                  <Label htmlFor="clientName">Nom du client</Label>
                  <Input
                    id="clientName"
                    name="clientName"
                    placeholder="Restaurant Le Québécois"
                    value={clientName}
                    onChange={(e) => setClientName(e.target.value)}
                    required
                    disabled={isPending}
                  />
                </div>

                {/* Slug */}
                <div className="space-y-2">
                  <Label htmlFor="clientSlug">Slug (identifiant unique)</Label>
                  <Input
                    id="clientSlug"
                    name="clientSlug"
                    placeholder="restaurant-le-quebecois"
                    value={clientSlug}
                    onChange={(e) => setClientSlug(e.target.value)}
                    required
                    disabled={isPending}
                    className="font-mono text-sm"
                  />
                  <p className="text-xs text-muted-foreground">
                    Utilisé pour le nom du repo GitHub et le projet Vercel
                  </p>
                </div>

                {/* Plan Supabase */}
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>Plan Supabase</Label>
                    <Select name="supabasePlan" defaultValue="free" disabled={isPending}>
                      <SelectTrigger>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="free">Free</SelectItem>
                        <SelectItem value="pro">Pro (25$/mois)</SelectItem>
                        <SelectItem value="team">Team (599$/mois)</SelectItem>
                        <SelectItem value="enterprise">Enterprise</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>

                  {/* Région */}
                  <div className="space-y-2">
                    <Label>Région</Label>
                    <Select
                      name="supabaseRegion"
                      defaultValue="ca-central-1"
                      disabled={isPending}
                    >
                      <SelectTrigger>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {SUPABASE_REGIONS.map((r) => (
                          <SelectItem key={r.value} value={r.value}>
                            {r.label}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                </div>

                {/* Revenu mensuel */}
                <div className="space-y-2">
                  <Label htmlFor="monthlyRevenue">Revenu mensuel ($CAD)</Label>
                  <Input
                    id="monthlyRevenue"
                    name="monthlyRevenue"
                    type="number"
                    placeholder="0"
                    min="0"
                    step="0.01"
                    disabled={isPending}
                  />
                </div>
              </div>

              <DialogFooter>
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => handleOpenChange(false)}
                  disabled={isPending}
                >
                  Annuler
                </Button>
                <Button type="submit" disabled={isPending || !selectedTemplateId || !clientName}>
                  {isPending ? (
                    <>
                      <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                      Lancement...
                    </>
                  ) : (
                    <>
                      <Rocket className="mr-2 h-4 w-4" />
                      Lancer le provisionnement
                    </>
                  )}
                </Button>
              </DialogFooter>
            </form>
          </>
        ) : (
          <>
            <DialogHeader>
              <DialogTitle>Provisionnement en cours</DialogTitle>
              <DialogDescription>
                Ne fermez pas cette fenêtre pendant le provisionnement.
              </DialogDescription>
            </DialogHeader>
            {activeJobId && (
              <ProvisioningProgress
                jobId={activeJobId}
                onComplete={handleProvisioningComplete}
              />
            )}
            <DialogFooter>
              <Button variant="outline" onClick={() => handleOpenChange(false)}>
                Fermer
              </Button>
            </DialogFooter>
          </>
        )}
      </DialogContent>
    </Dialog>
  )
}
