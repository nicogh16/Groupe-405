"use client"

import { useEffect, useState, useCallback, useRef } from "react"
import { Button } from "@/components/ui/button"
import {
  CheckCircle2,
  Loader2,
  XCircle,
  ExternalLink,
  Trash2,
  RefreshCw,
  Terminal,
  Database,
  Key,
  FileDown,
  FileCode2,
  Rocket,
  Sparkles,
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

// ─── Types ──────────────────────────────────────────────────────────────────────

interface ProvisioningProgressProps {
  jobId: string
  onComplete?: () => void
}

type LogEntry = {
  timestamp: string
  level: "info" | "error" | "success" | "warn"
  message: string
  step?: string
}

// ─── Icon mapping ───────────────────────────────────────────────────────────────

const STEP_ICONS: Record<string, React.ReactNode> = {
  create_supabase: <Database className="h-4 w-4" />,
  wait_supabase: <Key className="h-4 w-4" />,
  fetch_migrations: <FileDown className="h-4 w-4" />,
  apply_migrations: <FileCode2 className="h-4 w-4" />,
  deploy_edge_functions: <Rocket className="h-4 w-4" />,
  create_github: <FileCode2 className="h-4 w-4" />,
  create_vercel: <Rocket className="h-4 w-4" />,
  configure_env: <Key className="h-4 w-4" />,
  register_client: <Database className="h-4 w-4" />,
}

// ─── Helper: résultat lisible ───────────────────────────────────────────────────

function getStepResultText(step: ProvisioningStep): string | null {
  if (!step.result || step.status !== "completed") return null
  const r = step.result as Record<string, unknown>
  if ("ref" in r && r.ref) return `Ref: ${String(r.ref)}`
  if ("url" in r && r.url) return String(r.url)
  if ("files_applied" in r) return `${r.files_applied} fichier(s) · ${r.total_batches} batch(es)`
  if ("count" in r && r.count !== undefined) return `${r.count} fichier(s)`
  if ("deployed" in r && r.deployed !== undefined) {
    const base = `${r.deployed} fonction(s)`
    return r.failed ? `${base} · ${r.failed} échec(s)` : base
  }
  if ("clientId" in r && r.clientId) return `ID: ${String(r.clientId)}`
  return null
}

// ─── Connector ──────────────────────────────────────────────────────────────────

function Connector({ active, completed }: { active: boolean; completed: boolean }) {
  return (
    <div className="flex justify-center h-5">
      <div className="w-px h-full relative overflow-hidden">
        <div
          className={`absolute inset-0 transition-colors duration-500 ${
            completed ? "bg-success/60" : active ? "bg-primary/40" : "bg-border"
          }`}
        />
        {active && (
          <div className="absolute inset-0 overflow-hidden">
            <div
              className="absolute w-full animate-blueprint-flow"
              style={{
                height: "200%",
                background: "linear-gradient(180deg, transparent 0%, var(--primary) 45%, var(--primary) 55%, transparent 100%)",
                opacity: 0.5,
              }}
            />
          </div>
        )}
      </div>
    </div>
  )
}

// ─── Node ───────────────────────────────────────────────────────────────────────

function StepNode({ step, index }: { step: ProvisioningStep; index: number }) {
  const isActive = step.status === "in_progress"
  const isCompleted = step.status === "completed"
  const isFailed = step.status === "failed"
  const isPending = step.status === "pending" || step.status === "skipped"

  const icon = STEP_ICONS[step.id] || <Database className="h-4 w-4" />
  const resultText = getStepResultText(step)

  return (
    <div
      className="animate-blueprint-node-in opacity-0"
      style={{ animationDelay: `${index * 60}ms` }}
    >
      <div
        className={`
          relative flex items-center gap-3 rounded-lg border px-3 py-2.5 transition-all duration-400
          ${isActive
            ? "border-primary/40 bg-primary/5 shadow-[0_0_12px_rgba(255,107,53,0.08)]"
            : isCompleted
              ? "border-success/30 bg-success/5"
              : isFailed
                ? "border-destructive/30 bg-destructive/5"
                : "border-border bg-card"
          }
        `}
      >
        {/* Pulse ring */}
        {isActive && (
          <div className="absolute -inset-px rounded-lg border border-primary/20 animate-blueprint-pulse-ring pointer-events-none" />
        )}

        {/* Icon */}
        <div className="relative shrink-0">
          <div
            className={`
              flex items-center justify-center h-8 w-8 rounded-md transition-all duration-400
              ${isActive
                ? "bg-primary/10 text-primary"
                : isCompleted
                  ? "bg-success/10 text-success"
                  : isFailed
                    ? "bg-destructive/10 text-destructive"
                    : "bg-muted text-muted-foreground"
              }
            `}
          >
            {isActive ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : isCompleted ? (
              <CheckCircle2 className="h-4 w-4" />
            ) : isFailed ? (
              <XCircle className="h-4 w-4" />
            ) : (
              icon
            )}
          </div>
          <span
            className={`
              absolute -top-1 -left-1 flex items-center justify-center h-3.5 w-3.5 rounded-full text-[8px] font-bold leading-none text-white
              ${isActive ? "bg-primary" : isCompleted ? "bg-success" : isFailed ? "bg-destructive" : "bg-muted-foreground/40"}
            `}
          >
            {index + 1}
          </span>
        </div>

        {/* Label */}
        <div className="flex-1 min-w-0">
          <p className={`text-[13px] font-medium leading-tight ${
            isActive ? "text-foreground" : isCompleted ? "text-foreground" : isFailed ? "text-destructive" : "text-muted-foreground"
          }`}>
            {step.label}
          </p>
          {resultText && isCompleted && (
            <p className="text-[10px] text-success/80 font-mono mt-0.5 truncate">{resultText}</p>
          )}
          {step.error && isFailed && (
            <p className="text-[10px] text-destructive/80 mt-0.5 line-clamp-1">{step.error}</p>
          )}
        </div>

        {/* Dot */}
        <div className="shrink-0">
          {isActive && (
            <span className="relative flex h-2 w-2">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-primary opacity-50" />
              <span className="relative inline-flex rounded-full h-2 w-2 bg-primary" />
            </span>
          )}
          {isCompleted && <span className="block h-2 w-2 rounded-full bg-success" />}
          {isFailed && <span className="block h-2 w-2 rounded-full bg-destructive" />}
          {isPending && <span className="block h-1.5 w-1.5 rounded-full bg-border" />}
        </div>
      </div>
    </div>
  )
}

// ─── Main Component ─────────────────────────────────────────────────────────────

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
  const [consoleLogs, setConsoleLogs] = useState<LogEntry[]>([])
  const consoleRef = useRef<HTMLDivElement>(null)
  const hasCalledOnComplete = useRef(false)
  const router = useRouter()

  // ─── Polling ──────────────────────────────────────────────────────────────

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

    // Logs
    const logs: LogEntry[] = []
    newSteps.forEach((step: ProvisioningStep) => {
      if (step.logs && step.logs.length > 0) {
        step.logs.forEach((log) => {
          logs.push({ timestamp: log.timestamp, level: log.level, message: log.message, step: step.id })
        })
      } else {
        if (step.started_at) logs.push({ timestamp: step.started_at, level: "info", message: `[${step.label}] Démarrage...`, step: step.id })
        if (step.status === "completed" && step.completed_at) {
          const rm = step.result ? ` — ${Object.entries(step.result).map(([k, v]) => `${k}: ${v}`).join(", ")}` : ""
          logs.push({ timestamp: step.completed_at, level: "success", message: `[${step.label}] ✅ Terminé${rm}`, step: step.id })
        }
        if (step.status === "failed" && step.error) logs.push({ timestamp: step.completed_at || new Date().toISOString(), level: "error", message: `[${step.label}] ❌ ${step.error}`, step: step.id })
        if (step.status === "in_progress") logs.push({ timestamp: new Date().toISOString(), level: "info", message: `[${step.label}] ⏳ En cours...`, step: step.id })
      }
    })
    if (job.error_message) logs.push({ timestamp: job.completed_at || new Date().toISOString(), level: "error", message: `❌ ${job.error_message}` })
    logs.sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime())
    setConsoleLogs(logs)

    const allStepsDone = newSteps.length > 0 && newSteps.every(
      (s: ProvisioningStep) => s.status === "completed" || s.status === "failed" || s.status === "skipped"
    )
    const isJobTerminal = job.status === "completed" || job.status === "failed" || job.status === "cancelled"

    if (isJobTerminal && allStepsDone) {
      if (onComplete && !hasCalledOnComplete.current) { hasCalledOnComplete.current = true; onComplete() }
      return false
    }
    if (isJobTerminal && !allStepsDone) return true
    return true
  }, [jobId, onComplete])

  useEffect(() => {
    let interval: ReturnType<typeof setInterval> | null = null
    let active = true
    pollJob().then((shouldContinue) => {
      if (shouldContinue && active) {
        interval = setInterval(async () => {
          const cont = await pollJob()
          if (!cont && interval) clearInterval(interval)
        }, 2000)
      }
    })
    return () => { active = false; if (interval) clearInterval(interval) }
  }, [pollJob])

  // Auto-scroll console
  useEffect(() => {
    if (consoleRef.current) consoleRef.current.scrollTop = consoleRef.current.scrollHeight
  }, [consoleLogs])

  // ─── Computed ─────────────────────────────────────────────────────────────

  const completedSteps = steps.filter((s) => s.status === "completed").length
  const totalSteps = steps.length
  const pct = totalSteps > 0 ? Math.round((completedSteps / totalSteps) * 100) : 0

  const allStepsDone = steps.length > 0 && steps.every((s) => s.status === "completed" || s.status === "failed" || s.status === "skipped")
  const hasFailed = steps.some((s) => s.status === "failed")
  const isFullyComplete = jobStatus === "completed" && allStepsDone && !hasFailed
  const displayStatus: ProvisioningJobStatus = jobStatus === "completed" && !allStepsDone ? "running" : jobStatus

  const canCancel = !(jobStatus === "completed" && clientId)
  const canRetry = jobStatus === "pending" || jobStatus === "failed"

  // ─── Handlers ─────────────────────────────────────────────────────────────

  const handleCancel = async () => {
    setIsCancelling(true)
    const result = await cancelProvisioningJob(jobId)
    setIsCancelling(false)
    setShowCancelDialog(false)
    if (result.success) { toast.success(result.message || "Job supprimé"); router.refresh(); if (onComplete) onComplete() }
    else toast.error(result.error || "Erreur")
  }

  const handleRetry = async () => {
    setIsRetrying(true)
    const result = await retryProvisioningJob(jobId)
    setIsRetrying(false)
    if (result.success) { toast.success(result.message || "Relance..."); router.refresh(); setTimeout(() => pollJob(), 1000) }
    else toast.error(result.error || "Erreur")
  }

  // ─── Status config ────────────────────────────────────────────────────────

  const statusCfg: Record<ProvisioningJobStatus, { label: string; cls: string }> = {
    pending: { label: "En attente", cls: "bg-muted text-muted-foreground" },
    running: { label: "En cours", cls: "bg-primary/10 text-primary" },
    completed: { label: "Terminé", cls: "bg-success/10 text-success" },
    failed: { label: "Échec", cls: "bg-destructive/10 text-destructive" },
    cancelled: { label: "Annulé", cls: "bg-muted text-muted-foreground" },
  }
  const st = statusCfg[displayStatus]

  // ─── Render ───────────────────────────────────────────────────────────────

  return (
    <div className="h-full rounded-xl border border-border bg-card overflow-hidden shadow-sm">
      {/* ── Header ── */}
      <div className="px-4 py-3 border-b border-border bg-muted/30">
        <div className="flex items-center justify-between gap-3">
          <div className="flex items-center gap-2.5 min-w-0">
            <div className={`flex items-center justify-center h-7 w-7 rounded-md shrink-0 ${
              isFullyComplete ? "bg-success/10 text-success" : displayStatus === "failed" ? "bg-destructive/10 text-destructive" : "bg-primary/10 text-primary"
            }`}>
              {isFullyComplete ? <Sparkles className="h-3.5 w-3.5" /> : <Terminal className="h-3.5 w-3.5" />}
            </div>
            <div className="min-w-0">
              <h3 className="text-sm font-semibold text-foreground truncate">
                {clientName || "Provisionnement"}
              </h3>
              <p className="text-[10px] text-muted-foreground font-mono">
                {completedSteps}/{totalSteps} · {pct}%
              </p>
            </div>
          </div>

          <div className="flex items-center gap-1.5 shrink-0">
            <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-medium ${st.cls}`}>
              {displayStatus === "running" && <span className="h-1.5 w-1.5 rounded-full bg-primary animate-pulse" />}
              {st.label}
            </span>
            {canRetry && (
              <Button variant="outline" size="sm" className="h-6 px-2 text-[11px] gap-1" onClick={handleRetry} disabled={isRetrying}>
                {isRetrying ? <Loader2 className="h-3 w-3 animate-spin" /> : <RefreshCw className="h-3 w-3" />}
              </Button>
            )}
            {canCancel && (
              <Dialog open={showCancelDialog} onOpenChange={setShowCancelDialog}>
                <DialogTrigger asChild>
                  <Button variant="ghost" size="icon" className="h-6 w-6 text-muted-foreground hover:text-destructive" disabled={isCancelling}>
                    <Trash2 className="h-3 w-3" />
                  </Button>
                </DialogTrigger>
                <DialogContent className="sm:max-w-md">
                  <DialogHeader>
                    <DialogTitle>{jobStatus === "running" ? "Annuler ?" : "Supprimer ?"}</DialogTitle>
                    <DialogDescription>
                      {jobStatus === "running"
                        ? "Les ressources déjà créées ne seront pas supprimées automatiquement."
                        : "Ce job sera supprimé définitivement."}
                    </DialogDescription>
                  </DialogHeader>
                  <DialogFooter>
                    <Button variant="outline" onClick={() => setShowCancelDialog(false)} disabled={isCancelling}>Annuler</Button>
                    <Button variant="destructive" onClick={handleCancel} disabled={isCancelling}>
                      {isCancelling && <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />}
                      {jobStatus === "running" ? "Annuler" : "Supprimer"}
                    </Button>
                  </DialogFooter>
                </DialogContent>
              </Dialog>
            )}
          </div>
        </div>

        {/* Progress bar */}
        <div className="mt-2.5 h-1 rounded-full bg-border overflow-hidden">
          <div
            className={`h-full rounded-full transition-all duration-700 ease-out ${
              isFullyComplete ? "bg-success" : hasFailed ? "bg-destructive" : "bg-primary"
            }`}
            style={{ width: `${pct}%` }}
          />
        </div>
      </div>

      {/* ── Body : Pipeline + Console côte à côte ── */}
      <div className="grid grid-cols-1 lg:grid-cols-[minmax(0,1.2fr)_minmax(340px,0.8fr)] items-start min-h-0 h-[calc(100%-72px)]">
        {/* Left: Pipeline */}
        <div className="min-w-0 px-4 py-4 lg:border-r lg:border-border overflow-y-auto">
          <div className="space-y-0.5 pr-1">
            {steps.map((step, i) => {
            const prev = i > 0 ? steps[i - 1] : null
            return (
              <div key={step.id}>
                {i > 0 && <Connector active={step.status === "in_progress"} completed={prev?.status === "completed" || false} />}
                <StepNode step={step} index={i} />
              </div>
            )
            })}
          </div>

          {/* Success inline */}
          {isFullyComplete && (
            <div className="mt-4 flex items-center gap-2.5 rounded-lg border border-success/30 bg-success/5 px-3 py-2.5 animate-blueprint-node-in">
              <Sparkles className="h-4 w-4 text-success shrink-0" />
              <div className="flex-1 min-w-0">
                <p className="text-[13px] font-semibold text-success">Projet créé avec succès !</p>
                <div className="flex flex-wrap gap-1.5 mt-1.5">
                  {resultUrls.supabaseUrl && (
                    <a
                      href={`https://supabase.com/dashboard/project/${resultUrls.supabaseUrl.replace("https://", "").replace(".supabase.co", "")}`}
                      target="_blank" rel="noopener noreferrer"
                      className="inline-flex items-center gap-1 px-2 py-0.5 rounded text-[10px] font-medium bg-card border border-border text-foreground hover:bg-muted transition-colors"
                    >
                      <ExternalLink className="h-2.5 w-2.5" /> Supabase
                    </a>
                  )}
                  {resultUrls.githubRepoUrl && (
                    <a href={resultUrls.githubRepoUrl} target="_blank" rel="noopener noreferrer"
                      className="inline-flex items-center gap-1 px-2 py-0.5 rounded text-[10px] font-medium bg-card border border-border text-foreground hover:bg-muted transition-colors"
                    >
                      <ExternalLink className="h-2.5 w-2.5" /> GitHub
                    </a>
                  )}
                  {resultUrls.vercelProjectUrl && (
                    <a href={resultUrls.vercelProjectUrl} target="_blank" rel="noopener noreferrer"
                      className="inline-flex items-center gap-1 px-2 py-0.5 rounded text-[10px] font-medium bg-card border border-border text-foreground hover:bg-muted transition-colors"
                    >
                      <ExternalLink className="h-2.5 w-2.5" /> Vercel
                    </a>
                  )}
                </div>
              </div>
            </div>
          )}

          {/* Error inline */}
          {errorMessage && (
            <div className="mt-4 flex items-start gap-2.5 rounded-lg border border-destructive/30 bg-destructive/5 px-3 py-2.5">
              <XCircle className="h-4 w-4 text-destructive shrink-0 mt-0.5" />
              <div className="min-w-0">
                <p className="text-[12px] font-medium text-destructive">Erreur</p>
                <p className="text-[10px] text-destructive/70 break-words mt-0.5 line-clamp-3">{errorMessage}</p>
              </div>
            </div>
          )}
        </div>

        {/* Right: Console (toujours visible) */}
        <div className="min-w-0 px-4 pb-4 pt-3 lg:pl-3 lg:pr-4 lg:pt-4 lg:pb-4">
          <div className="flex h-full flex-col border border-white/10 rounded-xl overflow-hidden bg-[#0c0c0f] min-h-0">
          <div className="flex items-center gap-2 px-3 py-2 border-b border-white/10 shrink-0 bg-black/20">
            <Terminal className="h-3 w-3 text-white/40" />
            <span className="text-[10px] font-medium text-white/60 tracking-wide uppercase">Console</span>
            <span className="text-[9px] text-white/30 font-mono ml-auto">{consoleLogs.length} logs</span>
          </div>
          <div
            ref={consoleRef}
            className="h-[320px] max-h-[calc(92vh-280px)] overflow-auto px-3 py-2 font-mono text-[10px] leading-relaxed"
            style={{ fontFamily: "Consolas, Monaco, 'Courier New', monospace" }}
          >
            {consoleLogs.length === 0 ? (
              <p className="text-white/20">En attente...</p>
            ) : (
              <div className="space-y-px">
                {consoleLogs.map((log, i) => {
                  const t = new Date(log.timestamp).toLocaleTimeString("fr-CA", { hour: "2-digit", minute: "2-digit", second: "2-digit" })
                  const c = log.level === "error" ? "text-red-400" : log.level === "success" ? "text-emerald-400" : log.level === "warn" ? "text-amber-400" : "text-white/40"
                  return (
                    <div key={i} className="grid grid-cols-[auto_minmax(0,1fr)] items-start gap-1.5">
                      <span className="text-white/20 shrink-0 select-none">{t}</span>
                      <span className={`${c} whitespace-pre-wrap break-words`}>{log.message}</span>
                    </div>
                  )
                })}
              </div>
            )}
          </div>
          </div>
        </div>
      </div>
    </div>
  )
}
