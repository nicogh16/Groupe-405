"use client"

import { useEffect, useState, useCallback, useRef } from "react"
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
  Terminal,
  ChevronDown,
  ChevronUp,
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
  const [clientId, setClientId] = useState<string | null>(null)
  const [resultUrls, setResultUrls] = useState<{
    supabaseUrl?: string
    githubRepoUrl?: string
    vercelProjectUrl?: string
  }>({})
  const [showCancelDialog, setShowCancelDialog] = useState(false)
  const [isCancelling, setIsCancelling] = useState(false)
  const [isRetrying, setIsRetrying] = useState(false)
  const [showConsole, setShowConsole] = useState(true)
  const [consoleLogs, setConsoleLogs] = useState<Array<{ timestamp: string; level: "info" | "error" | "success" | "warn"; message: string; step?: string }>>([])
  const consoleRef = useRef<HTMLDivElement>(null)
  const router = useRouter()

  const pollJob = useCallback(async () => {
    const result = await getProvisioningJobStatus(jobId)
    if (result.error || !result.job) return false

    const job = result.job
    const newSteps = job.steps || []
    setSteps(newSteps)
    setJobStatus(job.status)
    setClientName(job.client_name)
    setClientId(job.client_id || null)
    setErrorMessage(job.error_message)
    setResultUrls({
      supabaseUrl: job.supabase_url || undefined,
      githubRepoUrl: job.github_repo_url || undefined,
      vercelProjectUrl: job.vercel_project_url || undefined,
    })

    // Générer les logs de la console à partir des steps
    const logs: Array<{ timestamp: string; level: "info" | "error" | "success" | "warn"; message: string; step?: string }> = []
    
    newSteps.forEach((step: ProvisioningStep) => {
      // Utiliser les logs stockés dans le step si disponibles
      if (step.logs && step.logs.length > 0) {
        step.logs.forEach((log) => {
          logs.push({
            timestamp: log.timestamp,
            level: log.level,
            message: log.message,
            step: step.id,
          })
        })
      } else {
        // Fallback: générer des logs basiques si pas de logs stockés
        if (step.started_at) {
          logs.push({
            timestamp: step.started_at,
            level: "info",
            message: `[${step.label}] Démarrage...`,
            step: step.id,
          })
        }

        if (step.status === "completed" && step.completed_at) {
          const resultMsg = step.result
            ? ` - ${Object.entries(step.result)
                .map(([k, v]) => `${k}: ${v}`)
                .join(", ")}`
            : ""
          logs.push({
            timestamp: step.completed_at,
            level: "success",
            message: `[${step.label}] ✅ Terminé${resultMsg}`,
            step: step.id,
          })
        }

        if (step.status === "failed" && step.error) {
          logs.push({
            timestamp: step.completed_at || new Date().toISOString(),
            level: "error",
            message: `[${step.label}] ❌ ERREUR: ${step.error}`,
            step: step.id,
          })
        }

        if (step.status === "in_progress") {
          logs.push({
            timestamp: new Date().toISOString(),
            level: "info",
            message: `[${step.label}] ⏳ En cours...`,
            step: step.id,
          })
        }
      }
    })

    // Ajouter l'erreur globale si présente
    if (job.error_message) {
      logs.push({
        timestamp: job.completed_at || new Date().toISOString(),
        level: "error",
        message: `[GLOBAL] ❌ ERREUR: ${job.error_message}`,
      })
      
      // Si c'est une erreur de déploiement, ajouter un message d'aide
      if (job.error_message.includes("503") || job.error_message.includes("404") || job.error_message.includes("DEPLOY_PROVISIONING")) {
        logs.push({
          timestamp: new Date().toISOString(),
          level: "warn",
          message: `[GLOBAL] ⚠️ L'Edge Function "provision-client" doit être déployée. Consultez DEPLOY_PROVISIONING.md`,
        })
      }
    }

    // Trier par timestamp et mettre à jour
    logs.sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime())
    setConsoleLogs(logs)

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

  // Auto-scroll de la console vers le bas quand de nouveaux logs arrivent
  useEffect(() => {
    if (consoleRef.current && showConsole) {
      consoleRef.current.scrollTop = consoleRef.current.scrollHeight
    }
  }, [consoleLogs, showConsole])

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

  // Le bouton supprimer est visible sauf pour les jobs completed qui ont créé un client
  const canCancel = !(jobStatus === "completed" && clientId)
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
                    <DialogTitle>
                      {jobStatus === "running"
                        ? "Annuler le provisionnement ?"
                        : jobStatus === "failed" || jobStatus === "cancelled"
                          ? "Supprimer ce job ?"
                          : "Supprimer ce job ?"}
                    </DialogTitle>
                    <DialogDescription>
                      {jobStatus === "running"
                        ? "Le provisionnement en cours sera annulé. Les ressources déjà créées (Supabase, GitHub, Vercel) ne seront pas supprimées automatiquement."
                        : jobStatus === "failed" || jobStatus === "cancelled"
                          ? "Ce job de provisionnement sera supprimé définitivement de la base de données."
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

        {/* Console en temps réel */}
        <div className="mt-4 border rounded-lg overflow-hidden bg-[#1e1e1e]">
          <button
            onClick={() => setShowConsole(!showConsole)}
            className="w-full flex items-center justify-between p-3 bg-[#252526] hover:bg-[#2d2d30] transition text-left"
          >
            <div className="flex items-center gap-2">
              <Terminal className="h-4 w-4 text-emerald-400" />
              <span className="text-sm font-medium text-gray-200">Console (logs en temps réel)</span>
              <span className="text-xs text-gray-400">({consoleLogs.length} messages)</span>
            </div>
            {showConsole ? (
              <ChevronUp className="h-4 w-4 text-gray-400" />
            ) : (
              <ChevronDown className="h-4 w-4 text-gray-400" />
            )}
          </button>
          {showConsole && (
            <div
              ref={consoleRef}
              className="p-4 font-mono text-xs max-h-[300px] overflow-y-auto bg-[#1e1e1e]"
              style={{ fontFamily: "Consolas, Monaco, 'Courier New', monospace" }}
            >
              {consoleLogs.length === 0 ? (
                <p className="text-gray-500">En attente de logs...</p>
              ) : (
                <div className="space-y-0.5">
                  {consoleLogs.map((log, index) => {
                    const time = new Date(log.timestamp).toLocaleTimeString("fr-CA", {
                      hour: "2-digit",
                      minute: "2-digit",
                      second: "2-digit",
                      fractionalSecondDigits: 3,
                    })
                    const colorClass =
                      log.level === "error"
                        ? "text-red-400"
                        : log.level === "success"
                          ? "text-emerald-400"
                          : log.level === "warn"
                            ? "text-yellow-400"
                            : "text-gray-300"

                    return (
                      <div key={index} className="flex items-start gap-2 leading-relaxed">
                        <span className="text-gray-500 shrink-0 select-none">{time}</span>
                        <span className={`${colorClass} break-words`}>{log.message}</span>
                      </div>
                    )
                  })}
                </div>
              )}
            </div>
          )}
        </div>

        {/* Erreur globale */}
        {errorMessage && (
          <div className="mt-4 p-4 rounded-md bg-red-500/10 border border-red-500/20">
            <div className="flex items-start gap-2">
              <XCircle className="h-5 w-5 text-red-500 shrink-0 mt-0.5" />
              <div className="flex-1 min-w-0">
                <p className="text-sm text-red-500 font-medium mb-1">Erreur</p>
                <p className="text-xs text-red-400 break-words whitespace-pre-wrap">{errorMessage}</p>
                {(errorMessage.includes("503") || errorMessage.includes("404") || errorMessage.includes("DEPLOY_PROVISIONING")) && (
                  <div className="mt-3 pt-3 border-t border-red-500/20">
                    <p className="text-xs text-red-300 mb-2">
                      <strong>Solution :</strong> L&apos;Edge Function &quot;provision-client&quot; doit être déployée sur Supabase.
                    </p>
                    <ul className="text-xs text-red-300/80 space-y-1 list-disc list-inside">
                      <li>Va dans Supabase Dashboard → Edge Functions</li>
                      <li>Déploie la fonction &quot;provision-client&quot; depuis le dossier <code className="bg-red-500/20 px-1 rounded">supabase/functions/provision-client</code></li>
                      <li>Configure tous les secrets requis (voir <code className="bg-red-500/20 px-1 rounded">DEPLOY_PROVISIONING.md</code>)</li>
                    </ul>
                  </div>
                )}
              </div>
            </div>
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
