"use client"

import { useEffect, useState, useCallback } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  CheckCircle2,
  Circle,
  Loader2,
  XCircle,
  SkipForward,
  ExternalLink,
  PartyPopper,
  Trash2,
  RefreshCw,
} from "lucide-react"
import { getProvisioningJobStatus, cancelProvisioningJob, retryProvisioningJob } from "@/app/(dashboard)/clients/actions"
import type { ProvisioningStep, ProvisioningJobStatus } from "@/types"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import { toast } from "sonner"
import { useRouter } from "next/navigation"

interface ProvisioningProgressProps {
  jobId: string
  onComplete?: () => void
}

function StepIcon({ status }: { status: ProvisioningStep["status"] }) {
  switch (status) {
    case "completed":
      return <CheckCircle2 className="h-5 w-5 text-emerald-500" />
    case "in_progress":
      return <Loader2 className="h-5 w-5 text-blue-500 animate-spin" />
    case "failed":
      return <XCircle className="h-5 w-5 text-red-500" />
    case "skipped":
      return <SkipForward className="h-5 w-5 text-muted-foreground" />
    default:
      return <Circle className="h-5 w-5 text-muted-foreground/40" />
  }
}

function statusLabel(status: ProvisioningJobStatus) {
  switch (status) {
    case "pending":
      return { text: "En attente", variant: "secondary" as const }
    case "running":
      return { text: "En cours", variant: "default" as const }
    case "completed":
      return { text: "Terminé", variant: "default" as const }
    case "failed":
      return { text: "Échec", variant: "destructive" as const }
    case "cancelled":
      return { text: "Annulé", variant: "secondary" as const }
  }
}

export function ProvisioningProgress({ jobId, onComplete }: ProvisioningProgressProps) {
  const [steps, setSteps] = useState<ProvisioningStep[]>([])
  const [jobStatus, setJobStatus] = useState<ProvisioningJobStatus>("pending")
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [clientName, setClientName] = useState("")
  const [resultUrls, setResultUrls] = useState<{
    supabaseUrl?: string
    githubRepoUrl?: string
    vercelProjectUrl?: string
  }>({})
  const [showCancelDialog, setShowCancelDialog] = useState(false)
  const [isCancelling, setIsCancelling] = useState(false)
  const [isRetrying, setIsRetrying] = useState(false)
  const router = useRouter()

  const pollJob = useCallback(async () => {
    const result = await getProvisioningJobStatus(jobId)
    if (result.error || !result.job) return false

    const job = result.job
    setSteps(job.steps || [])
    setJobStatus(job.status)
    setClientName(job.client_name)
    setErrorMessage(job.error_message)
    setResultUrls({
      supabaseUrl: job.supabase_url || undefined,
      githubRepoUrl: job.github_repo_url || undefined,
      vercelProjectUrl: job.vercel_project_url || undefined,
    })

    // Si terminé ou en erreur, arrêter le polling
    if (job.status === "completed" || job.status === "failed" || job.status === "cancelled") {
      if (job.status === "completed" && onComplete) {
        onComplete()
      }
      return false
    }

    return true // continuer le polling
  }, [jobId, onComplete])

  useEffect(() => {
    let interval: ReturnType<typeof setInterval> | null = null
    let active = true

    // Premier fetch immédiat
    pollJob().then((shouldContinue) => {
      if (shouldContinue && active) {
        interval = setInterval(async () => {
          const shouldContinue = await pollJob()
          if (!shouldContinue && interval) {
            clearInterval(interval)
          }
        }, 2000)
      }
    })

    return () => {
      active = false
      if (interval) clearInterval(interval)
    }
  }, [pollJob])

  const completedSteps = steps.filter((s) => s.status === "completed").length
  const totalSteps = steps.length
  const statusInfo = statusLabel(jobStatus)

  const handleCancel = async () => {
    setIsCancelling(true)
    const result = await cancelProvisioningJob(jobId)
    setIsCancelling(false)
    setShowCancelDialog(false)

    if (result.success) {
      toast.success(result.message || "Job annulé/supprimé")
      router.refresh()
      if (onComplete) onComplete()
    } else {
      toast.error(result.error || "Erreur lors de l'annulation")
    }
  }

  const canCancel = jobStatus === "pending" || jobStatus === "running"
  const canRetry = jobStatus === "pending" || jobStatus === "failed"

  const handleRetry = async () => {
    setIsRetrying(true)
    const result = await retryProvisioningJob(jobId)
    setIsRetrying(false)

    if (result.success) {
      toast.success(result.message || "Relance du job...")
      router.refresh()
      // Relancer le polling
      setTimeout(() => pollJob(), 1000)
    } else {
      toast.error(result.error || "Erreur lors de la relance")
    }
  }

  return (
    <Card className="border-border/50">
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <CardTitle className="text-sm font-medium">
            {clientName ? `Provisionnement : ${clientName}` : "Provisionnement en cours"}
          </CardTitle>
          <div className="flex items-center gap-2">
            <Badge variant={statusInfo.variant}>{statusInfo.text}</Badge>
            {canRetry && (
              <Button
                variant="outline"
                size="sm"
                className="h-7 gap-1.5 text-xs"
                onClick={handleRetry}
                disabled={isRetrying}
              >
                {isRetrying ? (
                  <>
                    <Loader2 className="h-3 w-3 animate-spin" />
                    Relance...
                  </>
                ) : (
                  <>
                    <RefreshCw className="h-3 w-3" />
                    Relancer
                  </>
                )}
              </Button>
            )}
            {canCancel && (
              <Dialog open={showCancelDialog} onOpenChange={setShowCancelDialog}>
                <DialogTrigger asChild>
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-7 w-7 text-destructive hover:bg-destructive/10"
                    disabled={isCancelling}
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                  </Button>
                </DialogTrigger>
                <DialogContent>
                  <DialogHeader>
                    <DialogTitle>Annuler le provisionnement ?</DialogTitle>
                    <DialogDescription>
                      {jobStatus === "running"
                        ? "Le provisionnement en cours sera annulé. Les ressources déjà créées (Supabase, GitHub, Vercel) ne seront pas supprimées automatiquement."
                        : "Ce job de provisionnement sera supprimé définitivement."}
                    </DialogDescription>
                  </DialogHeader>
                  <DialogFooter>
                    <Button variant="outline" onClick={() => setShowCancelDialog(false)} disabled={isCancelling}>
                      Annuler
                    </Button>
                    <Button variant="destructive" onClick={handleCancel} disabled={isCancelling}>
                      {isCancelling ? (
                        <>
                          <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                          {jobStatus === "running" ? "Annulation..." : "Suppression..."}
                        </>
                      ) : (
                        jobStatus === "running" ? "Annuler" : "Supprimer"
                      )}
                    </Button>
                  </DialogFooter>
                </DialogContent>
              </Dialog>
            )}
          </div>
        </div>
        {totalSteps > 0 && (
          <p className="text-xs text-muted-foreground mt-1">
            {completedSteps}/{totalSteps} étapes terminées
          </p>
        )}
      </CardHeader>
      <CardContent>
        <div className="space-y-3">
          {steps.map((step, index) => (
            <div key={step.id} className="flex items-start gap-3">
              <div className="mt-0.5">
                <StepIcon status={step.status} />
              </div>
              <div className="flex-1 min-w-0">
                <p
                  className={`text-sm font-medium ${
                    step.status === "pending" || step.status === "skipped"
                      ? "text-muted-foreground"
                      : ""
                  }`}
                >
                  {step.label}
                </p>
                {step.error && (
                  <p className="text-xs text-red-500 mt-0.5 break-all">{step.error}</p>
                )}
                {step.result && step.status === "completed" && (
                  <p className="text-xs text-muted-foreground mt-0.5">
                    {"url" in step.result && step.result.url ? (
                      <span className="font-mono text-[11px]">{String(step.result.url)}</span>
                    ) : null}
                    {"ref" in step.result && step.result.ref ? (
                      <span className="font-mono text-[11px]">Ref: {String(step.result.ref)}</span>
                    ) : null}
                    {"count" in step.result && step.result.count !== undefined ? (
                      <span>{String(step.result.count)} fichier(s)</span>
                    ) : null}
                    {"applied" in step.result && step.result.applied !== undefined ? (
                      <span>{String(step.result.applied)} migration(s) appliquée(s)</span>
                    ) : null}
                    {"buckets" in step.result && step.result.buckets !== undefined ? (
                      <span>{String(step.result.buckets)} bucket(s) créé(s)</span>
                    ) : null}
                    {"clientId" in step.result && step.result.clientId ? (
                      <span className="font-mono text-[11px]">
                        ID: {String(step.result.clientId)}
                      </span>
                    ) : null}
                  </p>
                )}
              </div>
              {index < steps.length - 1 && (
                <div className="absolute left-[18px] top-[28px] w-px h-[calc(100%-28px)] bg-border" />
              )}
            </div>
          ))}
        </div>

        {/* Erreur globale */}
        {errorMessage && (
          <div className="mt-4 p-3 rounded-md bg-red-500/10 border border-red-500/20">
            <p className="text-sm text-red-500 font-medium">Erreur</p>
            <p className="text-xs text-red-400 mt-1 break-all">{errorMessage}</p>
          </div>
        )}

        {/* Succès : liens vers les ressources */}
        {jobStatus === "completed" && (
          <div className="mt-4 p-4 rounded-md bg-emerald-500/10 border border-emerald-500/20">
            <div className="flex items-center gap-2 mb-3">
              <PartyPopper className="h-5 w-5 text-emerald-500" />
              <p className="text-sm text-emerald-500 font-medium">
                Projet créé avec succès !
              </p>
            </div>
            <div className="space-y-2">
              {resultUrls.supabaseUrl && (
                <a
                  href={`https://supabase.com/dashboard/project/${resultUrls.supabaseUrl.replace("https://", "").replace(".supabase.co", "")}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center gap-2 text-xs text-muted-foreground hover:text-foreground transition"
                >
                  <ExternalLink className="h-3.5 w-3.5" />
                  Supabase Dashboard
                </a>
              )}
              {resultUrls.githubRepoUrl && (
                <a
                  href={resultUrls.githubRepoUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center gap-2 text-xs text-muted-foreground hover:text-foreground transition"
                >
                  <ExternalLink className="h-3.5 w-3.5" />
                  Repository GitHub
                </a>
              )}
              {resultUrls.vercelProjectUrl && (
                <a
                  href={resultUrls.vercelProjectUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center gap-2 text-xs text-muted-foreground hover:text-foreground transition"
                >
                  <ExternalLink className="h-3.5 w-3.5" />
                  Projet Vercel
                </a>
              )}
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
