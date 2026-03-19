import { createClient as createServiceClient } from "@supabase/supabase-js"
import fs from "fs/promises"
import path from "path"

// ─── Types ───────────────────────────────────────────────────────────────────

interface ProvisioningStep {
  id: string
  label: string
  status: "pending" | "in_progress" | "completed" | "failed" | "skipped"
  started_at?: string
  completed_at?: string
  error?: string
  result?: Record<string, unknown>
  logs?: Array<{
    timestamp: string
    level: "info" | "error" | "success" | "warn"
    message: string
  }>
}

// ─── Liste des Edge Functions à déployer ─────────────────────────────────────
// Le format : { zip, entrypoint } — entrypoint dépend de la structure du zip.
// Zips avec source/index.ts → entrypoint = "source/index.ts"
// Zips avec index.ts à la racine → entrypoint = "index.ts"

const EDGE_FUNCTIONS = [
  { zip: "validate-transaction.zip", entrypoint: "source/index.ts" },
  { zip: "membercard.zip", entrypoint: "source/index.ts" },
  { zip: "get_transaction.zip", entrypoint: "source/index.ts" },
  { zip: "send-notification.zip", entrypoint: "source/index.ts" },
  { zip: "notify-new-user.zip", entrypoint: "source/index.ts" },
  { zip: "send-activation-notifications.zip", entrypoint: "source/index.ts" },
  { zip: "send-email.zip", entrypoint: "source/index.ts" },
  { zip: "update-disposable-emails.zip", entrypoint: "source/index.ts" },
  { zip: "handletransaction2.zip", entrypoint: "index.ts" },
  { zip: "send-member-welcome-email.zip", entrypoint: "index.ts" },
]

// ─── Helper : mettre à jour un step du job ──────────────────────────────────

async function updateStep(
  supabaseAdmin: ReturnType<typeof createServiceClient>,
  jobId: string,
  stepId: string,
  updates: Partial<ProvisioningStep>,
  logMessage?: string,
  logLevel: "info" | "error" | "success" | "warn" = "info"
) {
  const timestamp = new Date().toISOString()
  if (logMessage) console.log(`[EDGE-DEPLOY][${stepId}] ${logMessage}`)

  const { data: job } = await supabaseAdmin
    .from("provisioning_jobs")
    .select("steps")
    .eq("id", jobId)
    .single()

  if (!job) return

  const steps = (job.steps || []) as ProvisioningStep[]
  const idx = steps.findIndex((s) => s.id === stepId)
  if (idx === -1) return

  const cur = steps[idx]
  if (logMessage) {
    const logs = cur.logs || []
    logs.push({ timestamp, level: logLevel, message: logMessage })
    updates.logs = logs
  }
  steps[idx] = { ...cur, ...updates }

  await supabaseAdmin
    .from("provisioning_jobs")
    .update({ steps, updated_at: timestamp })
    .eq("id", jobId)
}

// ─── Helper : attendre que le project_ref soit disponible ───────────────────

async function waitForProjectRef(
  supabaseAdmin: ReturnType<typeof createServiceClient>,
  jobId: string,
  maxWaitMs = 300_000
): Promise<string | null> {
  const start = Date.now()
  while (Date.now() - start < maxWaitMs) {
    const { data: job } = await supabaseAdmin
      .from("provisioning_jobs")
      .select("supabase_project_ref, status")
      .eq("id", jobId)
      .single()

    if (!job) return null
    if (job.status === "failed" || job.status === "cancelled") return null
    if (job.supabase_project_ref) return job.supabase_project_ref

    await new Promise((r) => setTimeout(r, 3000))
  }
  return null
}

// ─── Helper : attendre que les migrations soient appliquées ────────────────

async function waitForMigrations(
  supabaseAdmin: ReturnType<typeof createServiceClient>,
  jobId: string,
  maxWaitMs = 600_000
): Promise<boolean> {
  const start = Date.now()
  while (Date.now() - start < maxWaitMs) {
    const { data: job } = await supabaseAdmin
      .from("provisioning_jobs")
      .select("steps, status")
      .eq("id", jobId)
      .single()

    if (!job) return false
    if (job.status === "failed" || job.status === "cancelled") return false

    const steps = (job.steps || []) as ProvisioningStep[]
    const migrationStep = steps.find((s) => s.id === "apply_migrations")

    if (migrationStep?.status === "completed") return true
    if (migrationStep?.status === "failed") return false

    await new Promise((r) => setTimeout(r, 5000))
  }
  return false
}

// ─── Helper : déployer un zip via l'API Management Supabase ─────────────────

async function deployOneFunction(
  accessToken: string,
  projectRef: string,
  slug: string,
  zipBuffer: Buffer,
  zipFileName: string,
  entrypoint: string
): Promise<{ ok: boolean; error?: string }> {
  // L'API /v1/projects/{ref}/functions/deploy accepte un FormData avec :
  //   - file: le zip
  //   - metadata: JSON { name, entrypoint_path, verify_jwt }
  const blob = new Blob([zipBuffer], { type: "application/zip" })

  const formData = new FormData()
  formData.append("file", blob, zipFileName)
  formData.append(
    "metadata",
    JSON.stringify({
      name: slug,
      entrypoint_path: entrypoint,
      verify_jwt: false,
    })
  )

  const res = await fetch(
    `https://api.supabase.com/v1/projects/${projectRef}/functions/deploy`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${accessToken}` },
      body: formData,
    }
  )

  if (res.ok) return { ok: true }

  const errorText = await res.text().catch(() => res.statusText)
  return { ok: false, error: `HTTP ${res.status}: ${errorText}` }
}

// ─── Fonction principale (appelée en background, sans await) ────────────────

export async function deployEdgeFunctionsForJob(jobId: string): Promise<void> {
  console.log(`[EDGE-DEPLOY] 🚀 Lancé pour job ${jobId}`)

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
  const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY
  const accessToken = process.env.SUPABASE_ACCESS_TOKEN || process.env.ACCESS_TOKEN

  if (!supabaseUrl || !supabaseServiceKey) {
    console.error("[EDGE-DEPLOY] ❌ SUPABASE_URL ou SUPABASE_SERVICE_ROLE_KEY manquant")
    return
  }

  if (!accessToken) {
    console.error("[EDGE-DEPLOY] ❌ SUPABASE_ACCESS_TOKEN manquant dans .env.local")
    return
  }

  const supabaseAdmin = createServiceClient(supabaseUrl, supabaseServiceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })

  try {
    // 1. Marquer le step comme "in_progress"
    await updateStep(supabaseAdmin, jobId, "deploy_edge_functions", {
      status: "in_progress",
      started_at: new Date().toISOString(),
    }, "⏳ En attente du project_ref et des migrations…", "info")

    // 2. Attendre le project_ref
    console.log("[EDGE-DEPLOY] Attente du project_ref…")
    const projectRef = await waitForProjectRef(supabaseAdmin, jobId)

    if (!projectRef) {
      await updateStep(supabaseAdmin, jobId, "deploy_edge_functions", {
        status: "failed",
        error: "Timeout ou job échoué — project_ref non disponible",
        completed_at: new Date().toISOString(),
      }, "❌ Impossible de récupérer le project_ref", "error")
      return
    }

    await updateStep(supabaseAdmin, jobId, "deploy_edge_functions", {},
      `📍 project_ref: ${projectRef} — en attente des migrations…`, "info")

    // 3. Attendre que les migrations soient terminées
    console.log("[EDGE-DEPLOY] Attente des migrations…")
    const migrationsOk = await waitForMigrations(supabaseAdmin, jobId)

    if (!migrationsOk) {
      await updateStep(supabaseAdmin, jobId, "deploy_edge_functions", {
        status: "failed",
        error: "Les migrations ont échoué ou le job a été annulé",
        completed_at: new Date().toISOString(),
      }, "❌ Migrations non terminées — abandon", "error")
      return
    }

    await updateStep(supabaseAdmin, jobId, "deploy_edge_functions", {},
      "✅ Migrations terminées — lancement du déploiement", "success")

    // 4. Lire les zips et déployer via l'API Management
    const templateDir = path.join(process.cwd(), "templates", "myfidelity")
    const deployed: Array<{ slug: string; ok: boolean; error?: string }> = []

    await updateStep(supabaseAdmin, jobId, "deploy_edge_functions", {},
      `🚀 Déploiement de ${EDGE_FUNCTIONS.length} fonctions via API Management…`, "info")

    for (const func of EDGE_FUNCTIONS) {
      const slug = func.zip.replace(/\.zip$/i, "")
      const zipPath = path.join(templateDir, func.zip)

      try {
        console.log(`[EDGE-DEPLOY] 🚀 ${slug} (entrypoint: ${func.entrypoint})…`)

        // Lire le zip depuis le disque
        const zipBuffer = await fs.readFile(zipPath)

        // Tenter le déploiement avec l'entrypoint connu
        let result = await deployOneFunction(
          accessToken, projectRef, slug, zipBuffer, func.zip, func.entrypoint
        )

        // Si entrypoint pas trouvé, essayer l'autre variante
        if (!result.ok && result.error?.includes("Entrypoint path does not exist")) {
          const altEntrypoint = func.entrypoint === "index.ts" ? "source/index.ts" : "index.ts"
          console.log(`[EDGE-DEPLOY] ⚠️ ${slug}: entrypoint ${func.entrypoint} pas trouvé, essai ${altEntrypoint}…`)
          result = await deployOneFunction(
            accessToken, projectRef, slug, zipBuffer, func.zip, altEntrypoint
          )
        }

        if (result.ok) {
          deployed.push({ slug, ok: true })
          console.log(`[EDGE-DEPLOY] ✅ ${slug} déployée`)
          await updateStep(supabaseAdmin, jobId, "deploy_edge_functions", {},
            `✅ ${slug} (${deployed.filter((d) => d.ok).length}/${EDGE_FUNCTIONS.length})`, "success")
        } else {
          deployed.push({ slug, ok: false, error: result.error })
          console.error(`[EDGE-DEPLOY] ❌ ${slug}:`, result.error)
          await updateStep(supabaseAdmin, jobId, "deploy_edge_functions", {},
            `❌ ${slug}: ${(result.error || "").substring(0, 200)}`, "error")
        }
      } catch (err) {
        const errMsg = err instanceof Error ? err.message : String(err)
        console.error(`[EDGE-DEPLOY] ❌ ${slug}:`, errMsg)
        deployed.push({ slug, ok: false, error: errMsg })
        await updateStep(supabaseAdmin, jobId, "deploy_edge_functions", {},
          `❌ ${slug}: ${errMsg.substring(0, 200)}`, "error")
      }

      // Petite pause entre chaque deploy pour éviter les rate limits
      await new Promise((r) => setTimeout(r, 1000))
    }

    // 5. Résultat final
    const failed = deployed.filter((d) => !d.ok)
    const succeeded = deployed.filter((d) => d.ok)

    if (failed.length > 0 && succeeded.length === 0) {
      const errorMsg = `Toutes les Edge Functions ont échoué. Ex: ${failed[0].slug} — ${failed[0].error}`
      await updateStep(supabaseAdmin, jobId, "deploy_edge_functions", {
        status: "failed", error: errorMsg, completed_at: new Date().toISOString(),
      }, `❌ ${errorMsg}`, "error")
      return
    }

    if (failed.length > 0) {
      const warnMsg = `${succeeded.length}/${deployed.length} déployées. Échecs: ${failed.map((f) => f.slug).join(", ")}`
      await updateStep(supabaseAdmin, jobId, "deploy_edge_functions", {
        status: "completed", completed_at: new Date().toISOString(),
        result: { deployed: succeeded.length, failed: failed.length, failed_names: failed.map((f) => f.slug) },
      }, `⚠️ ${warnMsg}`, "warn")
      return
    }

    await updateStep(supabaseAdmin, jobId, "deploy_edge_functions", {
      status: "completed", completed_at: new Date().toISOString(),
      result: { deployed: succeeded.length },
    }, `✅ ${succeeded.length} Edge Functions déployées avec succès`, "success")

  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error)
    console.error("[EDGE-DEPLOY] Erreur fatale:", msg)
    try {
      await updateStep(supabaseAdmin, jobId, "deploy_edge_functions", {
        status: "failed", error: `Erreur fatale: ${msg}`, completed_at: new Date().toISOString(),
      }, `❌ Erreur fatale: ${msg}`, "error")
    } catch { /* best effort */ }
  }
}
