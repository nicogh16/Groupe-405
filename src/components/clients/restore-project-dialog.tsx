"use client"

import { useState, useTransition, useEffect } from "react"
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
import { Progress } from "@/components/ui/progress"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent } from "@/components/ui/card"
import {
  Loader2,
  Database,
  FileCode,
  CheckCircle2,
  Layers,
  Table,
  Eye,
  FunctionSquare,
  Sparkles,
  Circle,
} from "lucide-react"
import { toast } from "sonner"
import { restoreProjectDirectly } from "@/app/(dashboard)/clients/actions"

interface StepStatus {
  file: string
  status: "pending" | "running" | "completed" | "error"
  message?: string
  error?: string
}

const stepConfig = [
  {
    file: "init.sql",
    title: "Initialisation des schémas",
    icon: Layers,
    description: "Création des schémas de base de données",
    loadingMessage: "Création des schémas audit, dashboard_view et mv...",
    successMessage: "Schémas créés avec succès",
  },
  {
    file: "table.sql",
    title: "Création des tables",
    icon: Table,
    description: "Installation de toutes les tables",
    loadingMessage: "Installation des tables utilisateurs, transactions, restaurants...",
    successMessage: "Toutes les tables ont été créées",
  },
  {
    file: "view-mv.sql",
    title: "Vues et materialized views",
    icon: Eye,
    description: "Installation des vues pour le dashboard",
    loadingMessage: "Création des vues et materialized views pour les statistiques...",
    successMessage: "Vues et materialized views installées",
  },
  {
    file: "function.sql",
    title: "Fonctions PostgreSQL",
    icon: FunctionSquare,
    description: "Création des fonctions avec DECLARE",
    loadingMessage: "Installation des fonctions PostgreSQL avec triggers et logique métier...",
    successMessage: "Toutes les fonctions ont été créées",
  },
]

function StepIcon({ status }: { status: StepStatus["status"] }) {
  switch (status) {
    case "completed":
      return <CheckCircle2 className="h-5 w-5 text-success" />
    case "running":
      return <Loader2 className="h-5 w-5 text-primary animate-spin" />
    case "error":
      return <CheckCircle2 className="h-5 w-5 text-destructive" />
    default:
      return <Circle className="h-5 w-5 text-muted-foreground/40" />
  }
}

export function RestoreProjectDialog() {
  const [open, setOpen] = useState(false)
  const [isPending, startTransition] = useTransition()
  const [projectRef, setProjectRef] = useState("")
  const [dbPassword, setDbPassword] = useState("")
  const [useMyFidelityTemplate, setUseMyFidelityTemplate] = useState(true)
  const [showSteps, setShowSteps] = useState(false)
  const [stepsStatus, setStepsStatus] = useState<StepStatus[]>([])
  const [currentStepIndex, setCurrentStepIndex] = useState(0)

  // Initialiser les étapes au démarrage
  useEffect(() => {
    if (showSteps) {
      setStepsStatus(
        stepConfig.map((config) => ({
          file: config.file,
          status: "pending" as const,
        }))
      )
      setCurrentStepIndex(0)
    }
  }, [showSteps])

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

    // Afficher les étapes
    setShowSteps(true)
    setStepsStatus(
      stepConfig.map((config) => ({
        file: config.file,
        status: "pending" as const,
      }))
    )

    startTransition(async () => {
      const formData = new FormData()
      formData.append("projectRef", projectRef.trim())
      formData.append("dbPassword", dbPassword.trim())
      formData.append("useMyFidelityTemplate", useMyFidelityTemplate.toString())

      // Démarrer l'animation des étapes
      let stepIndex = 0
      const animateSteps = () => {
        if (stepIndex < stepConfig.length) {
          setCurrentStepIndex(stepIndex)
          setStepsStatus((prev) =>
            prev.map((step, idx) => (idx === stepIndex ? { ...step, status: "running" } : step))
          )
          stepIndex++
          if (stepIndex < stepConfig.length) {
            setTimeout(animateSteps, 2500) // 2.5 secondes entre chaque étape
          }
        }
      }

      // Démarrer l'animation après un court délai
      setTimeout(animateSteps, 800)

      const result = (await restoreProjectDirectly(formData)) as any

      // Mettre à jour les statuts avec les vrais résultats
      if (result.details && Array.isArray(result.details)) {
        // Attendre que toutes les animations soient terminées
        setTimeout(() => {
          setStepsStatus(
            stepConfig.map((config) => {
              const detail = result.details.find((d: any) => d.file === config.file)
              if (detail) {
                return {
                  file: config.file,
                  status: detail.success ? ("completed" as const) : ("error" as const),
                  message: detail.message,
                  error: detail.error,
                }
              }
              return {
                file: config.file,
                status: "completed" as const, // Par défaut, on considère que c'est OK
              }
            })
          )

          if (result.success) {
            const ok = result.details.filter((d: any) => d.success)
            const ko = result.details.filter((d: any) => !d.success)
            toast.success(`Restauration terminée. ${ok.length} fichier(s) OK, ${ko.length} en erreur.`)
          } else {
            toast.error(result.error || "Erreur lors de la restauration")
          }
        }, stepConfig.length * 2500 + 1000) // Attendre la fin de toutes les animations
      } else if (result.success) {
        setTimeout(() => {
          setStepsStatus((prev) => prev.map((s) => ({ ...s, status: "completed" as const })))
          toast.success(result.message || "Restauration terminée avec succès !")
        }, stepConfig.length * 2500 + 1000)
      } else {
        toast.error(result.error || "Erreur lors de la restauration")
      }
    })
  }

  const handleReset = () => {
    setShowSteps(false)
    setStepsStatus([])
    setCurrentStepIndex(0)
    setProjectRef("")
    setDbPassword("")
  }

  const completedSteps = stepsStatus.filter((s) => s.status === "completed").length
  const totalSteps = stepsStatus.length
  const progress = totalSteps > 0 ? (completedSteps / totalSteps) * 100 : 0
  const allCompleted = completedSteps === totalSteps && totalSteps > 0
  const hasError = stepsStatus.some((s) => s.status === "error")

  return (
    <Dialog
      open={open}
      onOpenChange={(isOpen) => {
        setOpen(isOpen)
        if (!isOpen) {
          handleReset()
        }
      }}
    >
      <DialogTrigger asChild>
        <Button variant="outline" className="gap-2">
          <Database className="h-4 w-4" />
          Restaurer un projet
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-3xl max-h-[90vh] overflow-y-auto">
        {!showSteps ? (
          // Formulaire initial
          <form onSubmit={handleSubmit}>
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2">
                <Database className="h-5 w-5" />
                Restaurer un projet Supabase
              </DialogTitle>
              <DialogDescription>
                Restaurez directement un projet Supabase en exécutant le template SQL.
                Les étapes s&apos;exécuteront automatiquement après validation.
              </DialogDescription>
            </DialogHeader>
            <div className="grid gap-4 py-4">
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
                  Utiliser le template MyFidelity
                </Label>
              </div>
              <div className="rounded-lg bg-muted p-3 text-sm text-muted-foreground">
                <p className="font-medium mb-1">⚠️ Attention :</p>
                <ul className="list-disc list-inside space-y-1">
                  <li>Cette action va exécuter le SQL sur le projet spécifié</li>
                  <li>Assurez-vous que le projet est vide ou que vous acceptez d&apos;écraser les données</li>
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
                    Démarrage...
                  </>
                ) : (
                  <>
                    <Sparkles className="mr-2 h-4 w-4" />
                    Démarrer la restauration
                  </>
                )}
              </Button>
            </DialogFooter>
          </form>
        ) : (
          // Vue des étapes en cours
          <>
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2">
                <Database className="h-5 w-5" />
                Installation de la base de données
              </DialogTitle>
              <DialogDescription>
                Les étapes s&apos;exécutent automatiquement dans l&apos;ordre
              </DialogDescription>
            </DialogHeader>

            <div className="space-y-4">
              {/* Progress bar */}
              <div className="space-y-2">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-muted-foreground">Progression</span>
                  <Badge variant="secondary">
                    {completedSteps}/{totalSteps}
                  </Badge>
                </div>
                <Progress value={progress} />
              </div>

              {/* Liste des étapes */}
              <div className="space-y-3">
                {stepConfig.map((config, index) => {
                  const stepStatus = stepsStatus[index]
                  const isActive = index === currentStepIndex && stepStatus?.status === "running"
                  const Icon = config.icon

                  return (
                    <Card
                      key={config.file}
                      className={`transition-all ${
                        isActive ? "border-primary shadow-md" : ""
                      }`}
                    >
                      <CardContent className="p-4">
                        <div className="flex items-start gap-4">
                          <div className="flex items-center justify-center w-10 h-10 rounded-full bg-muted shrink-0">
                            {stepStatus ? (
                              <StepIcon status={stepStatus.status} />
                            ) : (
                              <Icon className="h-5 w-5 text-muted-foreground" />
                            )}
                          </div>
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center justify-between gap-2 mb-1">
                              <div className="flex items-center gap-2 flex-wrap">
                                <h3 className="font-semibold text-sm">{config.title}</h3>
                                <Badge variant="outline" className="text-xs">
                                  <FileCode className="h-3 w-3 mr-1" />
                                  {config.file}
                                </Badge>
                              </div>
                              {stepStatus && (
                                <Badge
                                  variant={
                                    stepStatus.status === "completed"
                                      ? "default"
                                      : stepStatus.status === "error"
                                        ? "destructive"
                                        : stepStatus.status === "running"
                                          ? "default"
                                          : "secondary"
                                  }
                                >
                                  {stepStatus.status === "completed"
                                    ? "Terminé"
                                    : stepStatus.status === "error"
                                      ? "Erreur"
                                      : stepStatus.status === "running"
                                        ? "En cours..."
                                        : "En attente"}
                                </Badge>
                              )}
                            </div>
                            <p className="text-sm text-muted-foreground mb-2">{config.description}</p>

                            {/* Message de chargement */}
                            {isActive && (
                              <div className="flex items-center gap-2 mt-2 p-2 bg-muted rounded-md">
                                <Loader2 className="h-4 w-4 text-primary animate-spin shrink-0" />
                                <p className="text-xs text-muted-foreground">{config.loadingMessage}</p>
                              </div>
                            )}

                            {/* Message de succès */}
                            {stepStatus?.status === "completed" && (
                              <div className="flex items-center gap-2 mt-2 p-2 bg-muted rounded-md">
                                <CheckCircle2 className="h-4 w-4 text-success shrink-0" />
                                <p className="text-xs text-muted-foreground">
                                  {stepStatus?.message || config.successMessage}
                                </p>
                              </div>
                            )}

                            {/* Message d'erreur */}
                            {stepStatus?.status === "error" && stepStatus?.error && (
                              <div className="flex items-start gap-2 mt-2 p-2 bg-destructive/10 rounded-md border border-destructive/20">
                                <CheckCircle2 className="h-4 w-4 text-destructive shrink-0 mt-0.5" />
                                <p className="text-xs text-destructive">{stepStatus.error}</p>
                              </div>
                            )}
                          </div>
                        </div>
                      </CardContent>
                    </Card>
                  )
                })}
              </div>
            </div>

            {/* Message de fin */}
            {allCompleted && !hasError && (
              <Card className="border-success">
                <CardContent className="p-4">
                  <div className="flex items-center gap-2 text-success">
                    <CheckCircle2 className="h-5 w-5" />
                    <span className="font-semibold">Installation terminée avec succès !</span>
                  </div>
                  <p className="text-sm text-muted-foreground mt-2">
                    Tous les scripts SQL ont été exécutés. La base de données MyFidelity est maintenant prête.
                  </p>
                </CardContent>
              </Card>
            )}

            {hasError && (
              <Card className="border-destructive">
                <CardContent className="p-4">
                  <div className="flex items-center gap-2 text-destructive">
                    <CheckCircle2 className="h-5 w-5" />
                    <span className="font-semibold">Erreur lors de l&apos;installation</span>
                  </div>
                  <p className="text-sm text-muted-foreground mt-2">
                    Certaines étapes ont échoué. Vérifiez les erreurs ci-dessus.
                  </p>
                </CardContent>
              </Card>
            )}

            <DialogFooter>
              <Button
                variant="outline"
                onClick={handleReset}
                disabled={isPending && !allCompleted}
              >
                Nouvelle restauration
              </Button>
              <Button
                onClick={() => setOpen(false)}
                disabled={isPending && !allCompleted}
              >
                Fermer
              </Button>
            </DialogFooter>
          </>
        )}
      </DialogContent>
    </Dialog>
  )
}
