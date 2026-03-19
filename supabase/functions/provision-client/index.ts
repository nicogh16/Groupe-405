  import "jsr:@supabase/functions-js/edge-runtime.d.ts"
  import { createClient } from "jsr:@supabase/supabase-js@2"

  // ─── Types ──────────────────────────────────────────────────────────────────────

  interface ProvisioningStep {
    id: string
    label: string
    status: "pending" | "in_progress" | "completed" | "failed" | "skipped"
    started_at?: string
    completed_at?: string
    error?: string
    result?: Record<string, unknown>
    logs?: Array<{ timestamp: string; level: "info" | "error" | "success" | "warn"; message: string }>
  }

  interface ProvisioningJob {
    id: string
    client_name: string
    client_slug: string
    app_id: string
    template_id: string
    supabase_plan: string
    supabase_region: string
    monthly_revenue: number
    status: "pending" | "running" | "completed" | "failed" | "cancelled"
    steps: ProvisioningStep[]
    supabase_project_ref?: string | null
    supabase_url?: string | null
    github_repo_url?: string | null
    vercel_project_url?: string | null
    client_id?: string | null
    error_message?: string | null
    error_step?: string | null
  }

  interface ProjectTemplate {
    id: string
    app_id: string
    name: string
    github_template_owner: string
    github_template_repo: string
    github_migrations_path: string
    default_supabase_plan: string
    default_supabase_region: string
    storage_buckets: Array<{
      name: string
      public: boolean
      file_size_limit?: number | null
      allowed_mime_types?: string[] | null
    }>
    vercel_framework: string
    vercel_build_command?: string | null
    vercel_output_directory?: string | null
    env_vars_template: Array<{
      key: string
      description: string
      auto?: boolean
      secret?: boolean
    }>
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────────

  async function updateStep(
    supabaseAdmin: any,
    jobId: string,
    stepId: string,
    updates: Partial<ProvisioningStep>,
    logMessage?: string,
    logLevel: "info" | "error" | "success" | "warn" = "info"
  ) {
    const timestamp = new Date().toISOString()
    if (logMessage) console.log(`[STEP ${stepId}] ${logMessage}`)

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

  function createResponse(data: any, status = 200): Response {
    return new Response(JSON.stringify(data), {
      status,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    })
  }

  async function verifyAdminAuth(
    req: Request,
    supabaseUrl: string,
    supabaseServiceKey: string
  ): Promise<{ valid: boolean; userId?: string; error?: string }> {
    const authHeader = req.headers.get("Authorization")
    if (!authHeader?.startsWith("Bearer ")) return { valid: false, error: "Token manquant" }

    const token = authHeader.replace("Bearer ", "")
    const client = createClient(supabaseUrl, supabaseServiceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    })
    const { data: { user }, error } = await client.auth.getUser(token)
    if (error || !user) return { valid: false, error: "Token invalide" }

    const { data: profile } = await client
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .single()
    if (!profile || profile.role !== "admin") return { valid: false, error: "Accès refusé - admin requis" }

    return { valid: true, userId: user.id }
  }

  async function updateJobStatus(
    supabaseAdmin: any,
    jobId: string,
    status: ProvisioningJob["status"],
    errorMessage?: string | null,
    errorStep?: string | null
  ) {
    const d: any = { status, updated_at: new Date().toISOString() }
    if (status === "running") d.started_at = d.updated_at
    if (status === "completed" || status === "failed") d.completed_at = d.updated_at
    if (errorMessage) d.error_message = errorMessage
    if (errorStep) d.error_step = errorStep
    await supabaseAdmin.from("provisioning_jobs").update(d).eq("id", jobId)
  }

  // ─── Helper : exécuter du SQL via la Management API avec retry ──────────────────

  async function execSQL(
    supabaseProjectRef: string,
    accessToken: string,
    query: string,
    retries = 3
  ): Promise<{ ok: boolean; status: number; error?: string }> {
    for (let attempt = 0; attempt <= retries; attempt++) {
      const res = await fetch(
        `https://api.supabase.com/v1/projects/${supabaseProjectRef}/database/query`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify({ query }),
        }
      )

      if (res.ok) return { ok: true, status: res.status }

      const errorText = await res.text()

      // Retry sur timeout (504) ou rate-limit (429)
      if ((res.status === 504 || res.status === 429) && attempt < retries) {
        const delay = Math.pow(2, attempt) * 2000
        console.warn(`[execSQL] ${res.status} — retry ${attempt + 1}/${retries} dans ${delay}ms`)
        await new Promise((r) => setTimeout(r, delay))
        continue
      }

      return { ok: false, status: res.status, error: errorText }
    }
    return { ok: false, status: 500, error: "Retries exhausted" }
  }

  // ─── Helper : séparer un gros fichier SQL en batches optimisés ──────────────

  function splitSQLIntoBatches(sql: string, maxBatchSizeKB = 512): string[] {
    // Si le fichier tient dans un seul batch, l'envoyer tel quel.
    // C'est le plus fiable : ça respecte l'ordre exact comme psql -f.
    if (sql.length <= maxBatchSizeKB * 1024) {
      return [sql]
    }

    // Fichier trop gros : découper par taille en respectant les limites de statements.
    // On ne découpe PAS par CREATE FUNCTION car les fonctions peuvent dépendre
    // d'autres statements (triggers, FK, etc.) dans le même fichier.
    return splitBySize(sql, maxBatchSizeKB)
  }

  function splitBySize(sql: string, maxBatchSizeKB: number): string[] {
    // Découpe simple par taille en évitant de couper au milieu d'un statement
    const batches: string[] = []
    const maxBytes = maxBatchSizeKB * 1024
    let start = 0

    while (start < sql.length) {
      let end = Math.min(start + maxBytes, sql.length)
      if (end < sql.length) {
        // Chercher le prochain point-virgule suivi d'un saut de ligne
        const nextBreak = sql.indexOf(";\n", end)
        if (nextBreak !== -1 && nextBreak - start < maxBytes * 1.5) {
          end = nextBreak + 2
        }
      }
      const chunk = sql.slice(start, end).trim()
      if (chunk) batches.push(chunk)
      start = end
    }

    return batches
  }

  // ─── Main ───────────────────────────────────────────────────────────────────────

  Deno.serve(async (req: Request) => {
    if (req.method === "OPTIONS") {
      return new Response("ok", {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
        },
      })
    }

    let job_id: string | null = null

    try {
      // ─── Vérification des secrets ────────────────────────────────────────────────
      const missing: string[] = []
      const supabaseUrl        = Deno.env.get("SUPABASE_URL")          || (missing.push("SUPABASE_URL"), "")
      const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || (missing.push("SUPABASE_SERVICE_ROLE_KEY"), "")
      const accessToken        = Deno.env.get("ACCESS_TOKEN")          || (missing.push("ACCESS_TOKEN"), "")
      const githubToken        = Deno.env.get("GITHUB_TOKEN")          || (missing.push("GITHUB_TOKEN"), "")
      const vercelToken        = Deno.env.get("VERCEL_TOKEN")          || (missing.push("VERCEL_TOKEN"), "")
      const orgId              = Deno.env.get("ORG_ID")                || (missing.push("ORG_ID"), "")
      const encryptionKey      = Deno.env.get("ENCRYPTION_KEY")        || (missing.push("ENCRYPTION_KEY"), "")

      // Auth avant de vérifier les secrets (pour retourner 401 et pas 500)
      if (supabaseUrl && supabaseServiceKey) {
        const auth = await verifyAdminAuth(req, supabaseUrl, supabaseServiceKey)
        if (!auth.valid) return createResponse({ error: auth.error }, 401)
        console.log(`[AUTH] ✅ ${auth.userId}`)
      }

      if (missing.length > 0) {
        return createResponse({ error: `Secrets manquants: ${missing.join(", ")}`, missing_secrets: missing }, 500)
      }

      const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
        auth: { autoRefreshToken: false, persistSession: false },
      })

      // ─── Récupérer le job ────────────────────────────────────────────────────────
      const body = await req.json().catch(() => null)
      job_id = body?.job_id
      if (!job_id) return createResponse({ error: "job_id requis" }, 400)

      const { data: job, error: jobError } = await supabaseAdmin
        .from("provisioning_jobs")
        .select("*")
        .eq("id", job_id)
        .single()
      if (jobError || !job) return createResponse({ error: "Job introuvable" }, 404)

      const pJob = job as unknown as ProvisioningJob
      if (pJob.status === "running") return createResponse({ error: "Job déjà en cours" }, 400)

      await updateJobStatus(supabaseAdmin, job_id, "running")

      // Récupérer le template
      const { data: tpl, error: tplErr } = await supabaseAdmin
        .from("project_templates")
        .select("*")
        .eq("id", pJob.template_id)
        .single()
      if (tplErr || !tpl) {
        await updateJobStatus(supabaseAdmin, job_id, "failed", "Template introuvable", "template_fetch")
        return createResponse({ error: "Template introuvable" }, 404)
      }
      const projectTemplate = tpl as unknown as ProjectTemplate

      console.log(`[INIT] Client: ${pJob.client_name}, Template: ${projectTemplate.name}`)

      // ═════════════════════════════════════════════════════════════════════════════
      // ÉTAPE 1 : Créer le projet Supabase
      // ═════════════════════════════════════════════════════════════════════════════
      await updateStep(supabaseAdmin, job_id, "create_supabase", {
        status: "in_progress", started_at: new Date().toISOString(),
      }, "Création du projet Supabase...")

      const projectName = `${pJob.client_slug}-${Date.now().toString(36)}`

      const createProjectRes = await fetch("https://api.supabase.com/v1/projects", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${accessToken}` },
        body: JSON.stringify({
          name: projectName,
          organization_slug: orgId,
          db_pass: crypto.randomUUID().replace(/-/g, ""),
          region_selection: { type: "specific", code: pJob.supabase_region },
        }),
      })

      if (!createProjectRes.ok) {
        const err = await createProjectRes.text()
        await updateStep(supabaseAdmin, job_id, "create_supabase", {
          status: "failed", error: err, completed_at: new Date().toISOString(),
        })
        await updateJobStatus(supabaseAdmin, job_id, "failed", `Création Supabase: ${err}`, "create_supabase")
        return createResponse({ error: err }, createProjectRes.status)
      }

      const sp = await createProjectRes.json()
      const projectRef = sp.ref || sp.id
      const projectUrl = `https://${projectRef}.supabase.co`

      await supabaseAdmin.from("provisioning_jobs")
        .update({ supabase_project_ref: projectRef, supabase_url: projectUrl })
        .eq("id", job_id)

      await updateStep(supabaseAdmin, job_id, "create_supabase", {
        status: "completed", completed_at: new Date().toISOString(),
        result: { ref: projectRef, url: projectUrl },
      }, `✅ Projet créé: ${projectRef}`, "success")

      // ═════════════════════════════════════════════════════════════════════════════
      // ÉTAPE 2 : Attendre les clés API
      // ═════════════════════════════════════════════════════════════════════════════
      await updateStep(supabaseAdmin, job_id, "wait_supabase", {
        status: "in_progress", started_at: new Date().toISOString(),
      }, "Attente des clés API...")

      let serviceRoleKey = ""
      let anonKey = ""

      for (let i = 0; i < 30; i++) {
        await new Promise((r) => setTimeout(r, 2000))
        const res = await fetch(
          `https://api.supabase.com/v1/projects/${projectRef}/api-keys?reveal=true`,
          { headers: { Authorization: `Bearer ${accessToken}` } }
        )
        if (res.ok) {
          const keys = await res.json()
          serviceRoleKey = keys.find((k: any) => k.name === "service_role" || k.type === "secret")?.api_key || ""
          anonKey = keys.find((k: any) => k.name === "anon" || k.type === "publishable")?.api_key || ""
          if (serviceRoleKey && anonKey) break
        }
        if (i % 5 === 4) {
          console.log(`[WAIT] Tentative ${i + 1}/30...`)
        }
      }

      if (!serviceRoleKey || !anonKey) {
        await updateStep(supabaseAdmin, job_id, "wait_supabase", {
          status: "failed", error: "Timeout clés API", completed_at: new Date().toISOString(),
        }, "❌ Timeout clés API", "error")
        await updateJobStatus(supabaseAdmin, job_id, "failed", "Timeout clés API", "wait_supabase")
        return createResponse({ error: "Timeout clés API" }, 500)
      }

      await updateStep(supabaseAdmin, job_id, "wait_supabase", {
        status: "completed", completed_at: new Date().toISOString(),
      }, "✅ Clés API récupérées", "success")

      // ═════════════════════════════════════════════════════════════════════════════
      // ÉTAPE 3 : Charger les fichiers SQL template depuis Storage
      // ═════════════════════════════════════════════════════════════════════════════
      await updateStep(supabaseAdmin, job_id, "fetch_migrations", {
        status: "in_progress", started_at: new Date().toISOString(),
      }, "Chargement des fichiers SQL template...")

      // Les 4 fichiers MyFidelity sont stockés dans le bucket "templates" sous myfidelity/
      const sqlFiles = [
        { key: "myfidelity/init.sql",    label: "Initialisation" },
        { key: "myfidelity/bucket.sql",  label: "Buckets Storage" },
        { key: "myfidelity/table.sql",   label: "Tables" },
        { key: "myfidelity/view-mv.sql", label: "Vues & Materialized Views" },
        { key: "myfidelity/function.sql", label: "Fonctions" },
      ]

      const storageClient = createClient(supabaseUrl, supabaseServiceKey, {
        auth: { autoRefreshToken: false, persistSession: false },
      })

      const loadedFiles: { key: string; label: string; content: string }[] = []

      try {
        for (const file of sqlFiles) {
          console.log(`[FETCH] Téléchargement: ${file.key}...`)

          const { data, error } = await storageClient.storage
            .from("templates")
            .download(file.key)

          if (error || !data) {
            throw new Error(`${file.key}: ${error?.message || "introuvable"}`)
          }

          const content = await data.text()
          if (!content || content.trim().length === 0) {
            throw new Error(`${file.key}: fichier vide`)
          }

          loadedFiles.push({ ...file, content })
          console.log(`[FETCH] ✅ ${file.key} (${(content.length / 1024).toFixed(1)} KB)`)
        }
      } catch (err) {
        const msg = `Erreur chargement SQL: ${err instanceof Error ? err.message : String(err)}`
        await updateStep(supabaseAdmin, job_id, "fetch_migrations", {
          status: "failed", error: msg, completed_at: new Date().toISOString(),
        })
        await updateJobStatus(supabaseAdmin, job_id, "failed", msg, "fetch_migrations")
        return createResponse({ error: msg }, 404)
      }

      const totalKB = loadedFiles.reduce((s, f) => s + f.content.length, 0) / 1024
      await updateStep(supabaseAdmin, job_id, "fetch_migrations", {
        status: "completed", completed_at: new Date().toISOString(),
        result: { files: loadedFiles.map(f => f.key), total_kb: totalKB.toFixed(1) },
      }, `✅ ${loadedFiles.length} fichiers chargés (${totalKB.toFixed(1)} KB)`, "success")

      // ═════════════════════════════════════════════════════════════════════════════
      // ÉTAPE 4 : Appliquer les fichiers SQL un par un (comme psql -f)
      // ═════════════════════════════════════════════════════════════════════════════
      // ═════════════════════════════════════════════════════════════════════════════
      // ÉTAPE 5 : Appliquer les fichiers SQL (batches optimisés)
      // ═════════════════════════════════════════════════════════════════════════════
      // Les fichiers de fonctions sont exécutés séquentiellement (dépendances entre
      // fonctions), mais regroupés en gros batches pour réduire les appels HTTP.
      // Les fichiers de tables/vues sans dépendances circulaires restent en un bloc.
      await updateStep(supabaseAdmin, job_id, "apply_migrations", {
        status: "in_progress", started_at: new Date().toISOString(),
      }, "Application des fichiers SQL...")

      let totalBatchesExecuted = 0

      // Helper pour vérifier si une erreur est ignorable
      const isIgnorableError = (err?: string) => err && (
        err.includes("already exists") ||
        (err.includes("extension") && err.includes("already")) ||
        (err.includes("schema") && err.includes("already"))
      )

      for (let fi = 0; fi < loadedFiles.length; fi++) {
        const file = loadedFiles[fi]
        const fileNum = fi + 1

        // Pré-traiter : IF NOT EXISTS sur CREATE SCHEMA
        const preprocessedContent = file.content
          .replace(/CREATE\s+SCHEMA\s+(?!IF\s+NOT\s+EXISTS\s+)/gi, "CREATE SCHEMA IF NOT EXISTS ")

        const isLargeFile = file.content.length > 100_000
        const isFunctionFile = file.key.includes("function")

        if (isFunctionFile || isLargeFile) {
          // ── Gros fichier : découper en batches et exécuter SÉQUENTIELLEMENT ──
          // Les fonctions peuvent se référencer entre elles, donc on doit
          // respecter l'ordre. Le gain vient du regroupement (2-6 batches
          // au lieu de 200+ appels individuels).
          // 512 KB par batch — function.sql (318 KB) passe en un seul appel
          const batches = splitSQLIntoBatches(preprocessedContent, 512)

          await updateStep(supabaseAdmin, job_id, "apply_migrations", {},
            `[${fileNum}/${loadedFiles.length}] ${file.label}: ${batches.length} batch(es) séquentiel(s) (${(file.content.length / 1024).toFixed(0)} KB)`, "info")

          for (let bi = 0; bi < batches.length; bi++) {
            const batch = batches[bi]
            const batchNum = bi + 1
            console.log(`[SQL] ${file.key} batch ${batchNum}/${batches.length} (${(batch.length / 1024).toFixed(0)} KB)`)

            const r = await execSQL(projectRef, accessToken, batch)
            if (!r.ok) {
              if (isIgnorableError(r.error)) {
                console.log(`[SQL] batch ${batchNum}: ignoré (already exists)`)
                continue
              }
              const preview = batch.substring(0, 150).replace(/\n/g, " ")
              const msg = `[${file.key}] batch ${batchNum}: ${r.error}\nSQL: ${preview}...`
              await updateStep(supabaseAdmin, job_id, "apply_migrations", {
                status: "failed", error: msg, completed_at: new Date().toISOString(),
              })
              await updateJobStatus(supabaseAdmin, job_id, "failed", msg, "apply_migrations")
              return createResponse({ error: msg }, r.status)
            }
            totalBatchesExecuted++
            console.log(`[SQL] ✅ ${file.key} batch ${batchNum}/${batches.length} OK`)
          }
        } else {
          // ── Petit fichier : exécuter en un seul bloc ──
          console.log(`[SQL] ${file.key} (${(file.content.length / 1024).toFixed(0)} KB) en un bloc`)
          const r = await execSQL(projectRef, accessToken, preprocessedContent)
          if (!r.ok) {
            if (!isIgnorableError(r.error)) {
              const msg = `[${file.key}] ${r.error}`
              await updateStep(supabaseAdmin, job_id, "apply_migrations", {
                status: "failed", error: msg, completed_at: new Date().toISOString(),
              })
              await updateJobStatus(supabaseAdmin, job_id, "failed", msg, "apply_migrations")
              return createResponse({ error: msg }, r.status)
            }
          }
          totalBatchesExecuted++
        }

        // 1 seul log par fichier terminé
        await updateStep(supabaseAdmin, job_id, "apply_migrations", {},
          `✅ [${fileNum}/${loadedFiles.length}] ${file.label} appliqué`, "success")
      }

      await updateStep(supabaseAdmin, job_id, "apply_migrations", {
        status: "completed", completed_at: new Date().toISOString(),
        result: {
          method: "batched_sequential",
          files_applied: loadedFiles.length,
          total_batches: totalBatchesExecuted,
          total_kb: totalKB.toFixed(1),
        },
      }, `✅ ${loadedFiles.length} fichiers SQL appliqués (${totalBatchesExecuted} batches)`, "success")

    // ═════════════════════════════════════════════════════════════════════════════
    // TERMINÉ — On s'arrête après les migrations SQL pour l'instant.
    // Les étapes suivantes (Edge Functions, GitHub, Vercel, env vars, register)
    // seront réactivées une par une plus tard.
    // ═════════════════════════════════════════════════════════════════════════════
    console.log("[DONE] Migrations SQL terminées — attente du déploiement Edge + création client")
    return createResponse({
      success: true,
      message: "Migrations SQL appliquées. Finalisation en cours (Edge Functions + création client).",
      project_ref: projectRef,
      project_url: projectUrl,
    }, 200)

    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error)
      console.error("[FATAL]", msg)
      if (job_id) {
        try {
          const url = Deno.env.get("SUPABASE_URL")
          const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
          if (url && key) {
            const admin = createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } })
            await admin.from("provisioning_jobs").update({
              status: "failed",
              error_message: `Erreur fatale: ${msg}`,
              error_step: "fatal_error",
              completed_at: new Date().toISOString(),
            }).eq("id", job_id)
          }
        } catch { /* best effort */ }
      }
      return createResponse({ error: "Erreur interne", message: msg }, 500)
    }
  })
