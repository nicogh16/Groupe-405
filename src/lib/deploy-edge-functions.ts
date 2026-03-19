import { createClient as createServiceClient } from "@supabase/supabase-js"
import fs from "fs/promises"
import path from "path"
import os from "os"
import { exec } from "child_process"
import { promisify } from "util"

const execAsync = promisify(exec)

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

interface ProvisioningJobRow {
  id: string
  app_id: string
  client_name: string
  client_slug: string
  supabase_project_ref: string | null
  supabase_url: string | null
  supabase_plan: "free" | "pro" | "team" | "enterprise"
  monthly_revenue: number
  github_repo_url: string | null
  vercel_project_url: string | null
  client_id: string | null
  steps: ProvisioningStep[]
}

// ─── Liste des Edge Functions à déployer ─────────────────────────────────────

const EDGE_FUNCTION_ZIPS = [
  "validate-transaction.zip",
  "membercard.zip",
  "get_transaction.zip",
  "send-notification.zip",
  "notify-new-user.zip",
  "send-activation-notifications.zip",
  "send-email.zip",
  "update-disposable-emails.zip",
  "handletransaction2.zip",
  "send-member-welcome-email.zip",
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

async function updateJobStatus(
  supabaseAdmin: ReturnType<typeof createServiceClient>,
  jobId: string,
  status: "pending" | "running" | "completed" | "failed" | "cancelled",
  fields?: Record<string, unknown>
) {
  const now = new Date().toISOString()
  const payload: Record<string, unknown> = {
    status,
    updated_at: now,
    ...(fields || {}),
  }

  if (status === "completed" || status === "failed" || status === "cancelled") {
    payload.completed_at = now
  }

  await supabaseAdmin.from("provisioning_jobs").update(payload).eq("id", jobId)
}

async function registerClientAndCompleteJob(
  supabaseAdmin: ReturnType<typeof createServiceClient>,
  jobId: string
): Promise<void> {
  await updateStep(
    supabaseAdmin,
    jobId,
    "register_client",
    {
      status: "in_progress",
      started_at: new Date().toISOString(),
    },
    "Création du client dans la table clients...",
    "info"
  )

  const { data: jobRaw, error: jobErr } = await supabaseAdmin
    .from("provisioning_jobs")
    .select("id, app_id, client_name, client_slug, supabase_project_ref, supabase_url, supabase_plan, monthly_revenue, github_repo_url, vercel_project_url, client_id, steps")
    .eq("id", jobId)
    .single()

  if (jobErr || !jobRaw) {
    throw new Error(jobErr?.message || "Job introuvable pour création client")
  }

  const job = jobRaw as ProvisioningJobRow

  let clientId = job.client_id
  if (!clientId) {
    const { data: existingClient } = await supabaseAdmin
      .from("clients")
      .select("id")
      .eq("slug", job.client_slug)
      .maybeSingle()

    if (existingClient?.id) {
      clientId = existingClient.id
    } else {
      const { data: createdClient, error: insertErr } = await supabaseAdmin
        .from("clients")
        .insert({
          app_id: job.app_id,
          name: job.client_name,
          slug: job.client_slug,
          supabase_project_ref: job.supabase_project_ref,
          supabase_url: job.supabase_url,
          supabase_plan: job.supabase_plan,
          monthly_revenue: job.monthly_revenue,
          github_repo_url: job.github_repo_url,
          vercel_project_url: job.vercel_project_url,
          status: "active",
        })
        .select("id")
        .single()

      if (insertErr || !createdClient) {
        throw new Error(insertErr?.message || "Impossible de créer le client")
      }

      clientId = createdClient.id
    }
  }

  await updateStep(
    supabaseAdmin,
    jobId,
    "register_client",
    {
      status: "completed",
      completed_at: new Date().toISOString(),
      result: { clientId },
    },
    `✅ Client créé: ${job.client_name}`,
    "success"
  )

  await updateJobStatus(supabaseAdmin, jobId, "completed", {
    client_id: clientId,
    error_message: null,
    error_step: null,
  })
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

  const tmpDir = path.join(os.tmpdir(), `edge-deploy-${jobId}-${Date.now()}`)

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

    // 4. Préparer le dossier temporaire avec la structure Supabase CLI v2
    const supabaseFunctionsDir = path.join(tmpDir, "supabase", "functions")
    await fs.mkdir(supabaseFunctionsDir, { recursive: true })

    // config.toml au format CLI v2 (project_id au top level)
    const configToml = `project_id = "${projectRef}"\n\n[api]\nenabled = false\n`
    await fs.writeFile(path.join(tmpDir, "supabase", "config.toml"), configToml)

    const templateDir = path.join(process.cwd(), "templates", "myfidelity")
    const deployed: Array<{ slug: string; ok: boolean; error?: string }> = []

    // 5. Extraire chaque zip dans la structure supabase/functions/<slug>/
    for (const zipFile of EDGE_FUNCTION_ZIPS) {
      const slug = zipFile.replace(/\.zip$/i, "")
      const zipPath = path.join(templateDir, zipFile)

      try {
        await fs.access(zipPath)

        const funcDir = path.join(supabaseFunctionsDir, slug)
        await fs.mkdir(funcDir, { recursive: true })

        const extractDir = path.join(tmpDir, `extract-${slug}`)
        await fs.mkdir(extractDir, { recursive: true })

        await execAsync(`tar -xf "${zipPath}" -C "${extractDir}"`)

        // Détecter : source/index.ts ou index.ts à la racine
        let hasSourceDir = false
        try {
          await fs.access(path.join(extractDir, "source", "index.ts"))
          hasSourceDir = true
        } catch { hasSourceDir = false }

        if (hasSourceDir) {
          await fs.copyFile(path.join(extractDir, "source", "index.ts"), path.join(funcDir, "index.ts"))
          try { await fs.copyFile(path.join(extractDir, "source", "deno.json"), path.join(funcDir, "deno.json")) } catch { /* optionnel */ }
        } else {
          await fs.copyFile(path.join(extractDir, "index.ts"), path.join(funcDir, "index.ts"))
          try { await fs.copyFile(path.join(extractDir, "deno.json"), path.join(funcDir, "deno.json")) } catch { /* optionnel */ }
        }

        console.log(`[EDGE-DEPLOY] 📂 ${slug} extrait (${hasSourceDir ? "source/" : "racine"})`)
      } catch (err) {
        const errMsg = err instanceof Error ? err.message : String(err)
        console.error(`[EDGE-DEPLOY] ❌ Erreur extraction ${slug}:`, errMsg)
        deployed.push({ slug, ok: false, error: `Extraction: ${errMsg}` })
      }
    }

    // 6. Déployer via la CLI Supabase
    const functionSlugs = EDGE_FUNCTION_ZIPS.map((z) => z.replace(/\.zip$/i, ""))
    const toDeployList = functionSlugs.filter(
      (slug) => !deployed.some((d) => d.slug === slug && !d.ok)
    )

    if (toDeployList.length > 0) {
      await updateStep(supabaseAdmin, jobId, "deploy_edge_functions", {},
        `🚀 Déploiement de ${toDeployList.length} fonctions via CLI…`, "info")

      for (const slug of toDeployList) {
        try {
          console.log(`[EDGE-DEPLOY] 🚀 Déploiement: ${slug}…`)

          const cmd = [
            "npx supabase functions deploy",
            slug,
            `--project-ref ${projectRef}`,
            "--no-verify-jwt",
            "--use-api",
          ].join(" ")

          const { stdout, stderr } = await execAsync(cmd, {
            cwd: tmpDir,
            env: { ...process.env, SUPABASE_ACCESS_TOKEN: accessToken },
            timeout: 120_000,
          })

          if (stdout) console.log(`[EDGE-DEPLOY] ${slug} stdout:`, stdout.trim())
          if (stderr && !stderr.includes("warn") && !stderr.includes("npm")) {
            console.log(`[EDGE-DEPLOY] ${slug} stderr:`, stderr.trim())
          }

          deployed.push({ slug, ok: true })
          console.log(`[EDGE-DEPLOY] ✅ ${slug} déployée`)

          await updateStep(supabaseAdmin, jobId, "deploy_edge_functions", {},
            `✅ ${slug} (${deployed.filter((d) => d.ok).length}/${toDeployList.length})`, "success")
        } catch (err: unknown) {
          const errMsg = err instanceof Error ? err.message : String(err)
          const stderr = (err as { stderr?: string })?.stderr || ""
          const fullError = stderr ? `${errMsg}\n${stderr}` : errMsg
          console.error(`[EDGE-DEPLOY] ❌ ${slug}:`, fullError)
          deployed.push({ slug, ok: false, error: fullError.substring(0, 500) })

          await updateStep(supabaseAdmin, jobId, "deploy_edge_functions", {},
            `❌ ${slug}: ${fullError.substring(0, 200)}`, "error")
        }
      }
    }

    // 7. Nettoyage
    try {
      await fs.rm(tmpDir, { recursive: true, force: true })
    } catch {
      console.warn("[EDGE-DEPLOY] Impossible de nettoyer:", tmpDir)
    }

    // 8. Résultat final
    const failed = deployed.filter((d) => !d.ok)
    const succeeded = deployed.filter((d) => d.ok)

    if (failed.length > 0 && succeeded.length === 0) {
      const errorMsg = `Toutes les Edge Functions ont échoué. Ex: ${failed[0].slug} — ${failed[0].error}`
      await updateStep(supabaseAdmin, jobId, "deploy_edge_functions", {
        status: "failed", error: errorMsg, completed_at: new Date().toISOString(),
      }, `❌ ${errorMsg}`, "error")
      await updateStep(supabaseAdmin, jobId, "register_client", {
        status: "skipped",
        completed_at: new Date().toISOString(),
      }, "⏭️ Client non créé car le déploiement Edge a échoué", "warn")
      await updateJobStatus(supabaseAdmin, jobId, "failed", {
        error_message: errorMsg,
        error_step: "deploy_edge_functions",
      })
      return
    }

    if (failed.length > 0) {
      const warnMsg = `${succeeded.length}/${deployed.length} déployées. Échecs: ${failed.map((f) => f.slug).join(", ")}`
      await updateStep(supabaseAdmin, jobId, "deploy_edge_functions", {
        status: "completed", completed_at: new Date().toISOString(),
        result: { deployed: succeeded.length, failed: failed.length, failed_names: failed.map((f) => f.slug) },
      }, `⚠️ ${warnMsg}`, "warn")
      await registerClientAndCompleteJob(supabaseAdmin, jobId)
      return
    }

    await updateStep(supabaseAdmin, jobId, "deploy_edge_functions", {
      status: "completed", completed_at: new Date().toISOString(),
      result: { deployed: succeeded.length },
    }, `✅ ${succeeded.length} Edge Functions déployées avec succès`, "success")
    await registerClientAndCompleteJob(supabaseAdmin, jobId)

  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error)
    console.error("[EDGE-DEPLOY] Erreur fatale:", msg)
    try {
      await updateStep(supabaseAdmin, jobId, "deploy_edge_functions", {
        status: "failed", error: `Erreur fatale: ${msg}`, completed_at: new Date().toISOString(),
      }, `❌ Erreur fatale: ${msg}`, "error")
    } catch { /* best effort */ }
    try {
      await updateStep(supabaseAdmin, jobId, "register_client", {
        status: "failed",
        error: `Impossible de créer le client: ${msg}`,
        completed_at: new Date().toISOString(),
      }, `❌ Création client échouée: ${msg}`, "error")
    } catch { /* best effort */ }
    try {
      await updateJobStatus(supabaseAdmin, jobId, "failed", {
        error_message: msg,
        error_step: "register_client",
      })
    } catch { /* best effort */ }

    try {
      await fs.rm(tmpDir, { recursive: true, force: true })
    } catch { /* ignore */ }
  }
}
