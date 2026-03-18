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

// ─── Helper : séparer un gros fichier SQL en fonctions individuelles ────────────

function splitSQLByFunctions(sql: string): string[] {
  // Sépare un fichier SQL contenant beaucoup de CREATE OR REPLACE FUNCTION
  // en morceaux exécutables individuellement.
  // On détecte chaque bloc « CREATE ... FUNCTION ... $tag$ ... $tag$ ... LANGUAGE ... ; »

  const chunks: string[] = []
  // Regex pour détecter le début d'un CREATE FUNCTION
  const funcStartRegex = /^CREATE\s+(OR\s+REPLACE\s+)?FUNCTION\s+/im

  // Si le fichier ne contient pas de fonctions, retourner tel quel
  if (!funcStartRegex.test(sql)) {
    return [sql]
  }

  // Séparer par « CREATE OR REPLACE FUNCTION » ou « CREATE FUNCTION »
  // On insère un marqueur avant chaque CREATE FUNCTION, puis on split.
  const marker = "\n---SPLIT_MARKER---\n"
  const marked = sql.replace(
    /\n(CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+)/gi,
    `${marker}$1`
  )
  const parts = marked.split(marker)

  for (const part of parts) {
    const trimmed = part.trim()
    if (!trimmed || trimmed.startsWith("--") && !trimmed.includes("CREATE")) continue
    chunks.push(trimmed)
  }

  return chunks.length > 0 ? chunks : [sql]
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
        await updateStep(supabaseAdmin, job_id, "wait_supabase", {},
          `Tentative ${i + 1}/30...`, "info")
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
        await updateStep(supabaseAdmin, job_id, "fetch_migrations", {},
          `Téléchargement: ${file.key}...`, "info")

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
        await updateStep(supabaseAdmin, job_id, "fetch_migrations", {},
          `✅ ${file.key} (${(content.length / 1024).toFixed(1)} KB)`, "success")
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
    // Les schémas sont créés directement par init.sql, pas de pré-exécution
    await updateStep(supabaseAdmin, job_id, "create_schemas", {
      status: "skipped", completed_at: new Date().toISOString(),
    }, "Schémas créés par les fichiers SQL directement", "info")

    // ═════════════════════════════════════════════════════════════════════════════
    // ÉTAPE 5 : Appliquer les fichiers SQL un par un (comme psql -f)
    // ═════════════════════════════════════════════════════════════════════════════
    await updateStep(supabaseAdmin, job_id, "apply_migrations", {
      status: "in_progress", started_at: new Date().toISOString(),
    }, "Application des fichiers SQL...")

    let totalExecuted = 0

    for (let fi = 0; fi < loadedFiles.length; fi++) {
      const file = loadedFiles[fi]
      const fileNum = fi + 1

      await updateStep(supabaseAdmin, job_id, "apply_migrations", {},
        `[${fileNum}/${loadedFiles.length}] ${file.label} (${file.key})...`, "info")

      // Pour function.sql (gros fichier avec $$ blocks), on split par fonction
      // Pour les autres fichiers, on essaie en un seul bloc
      const isLargeFile = file.content.length > 100_000 // > 100KB
      const isFunctionFile = file.key.includes("function")

      // Pré-traiter le SQL : ajouter IF NOT EXISTS aux CREATE SCHEMA
      // pour éviter les erreurs si un schéma existe déjà
      const preprocessedContent = file.content
        .replace(/CREATE\s+SCHEMA\s+(?!IF\s+NOT\s+EXISTS\s+)/gi, "CREATE SCHEMA IF NOT EXISTS ")

      if (isFunctionFile || isLargeFile) {
        // Séparer le fichier en blocs de fonctions individuelles
        const chunks = splitSQLByFunctions(preprocessedContent)

        await updateStep(supabaseAdmin, job_id, "apply_migrations", {},
          `${file.key} → ${chunks.length} bloc(s) à exécuter`, "info")

        for (let ci = 0; ci < chunks.length; ci++) {
          const chunk = chunks[ci].trim()
          if (!chunk || chunk.startsWith("--")) continue

          // Log allégé (tous les 25 blocs)
          if (ci % 25 === 0) {
            await updateStep(supabaseAdmin, job_id, "apply_migrations", {},
              `${file.key}: bloc ${ci + 1}/${chunks.length}...`, "info")
          }

          const r = await execSQL(projectRef, accessToken, chunk)
          if (!r.ok) {
            // Ignorer « already exists » pour extensions, index, constraints, schemas, types
            const ignorable = r.error && (
              r.error.includes("already exists") ||
              (r.error.includes("extension") && r.error.includes("already")) ||
              (r.error.includes("schema") && r.error.includes("already"))
            )
            if (ignorable) {
              continue // ignorer silencieusement
            }

            const preview = chunk.substring(0, 200).replace(/\n/g, " ")
            const msg = `[${file.key}] bloc ${ci + 1}: ${r.error}\nSQL: ${preview}...`
            await updateStep(supabaseAdmin, job_id, "apply_migrations", {
              status: "failed", error: msg, completed_at: new Date().toISOString(),
            })
            await updateJobStatus(supabaseAdmin, job_id, "failed", msg, "apply_migrations")
            return createResponse({ error: msg }, r.status)
          }
          totalExecuted++
        }
      } else {
        // Fichier petit/moyen : exécuter en un seul bloc
        const r = await execSQL(projectRef, accessToken, preprocessedContent)
        if (!r.ok) {
          // Vérifier si c'est une erreur ignorable (already exists)
          const ignorable = r.error && (
            r.error.includes("already exists") ||
            (r.error.includes("extension") && r.error.includes("already")) ||
            (r.error.includes("schema") && r.error.includes("already"))
          )
          if (!ignorable) {
            const msg = `[${file.key}] ${r.error}`
            await updateStep(supabaseAdmin, job_id, "apply_migrations", {
              status: "failed", error: msg, completed_at: new Date().toISOString(),
            })
            await updateJobStatus(supabaseAdmin, job_id, "failed", msg, "apply_migrations")
            return createResponse({ error: msg }, r.status)
          }
          // Erreur ignorable → on continue
          await updateStep(supabaseAdmin, job_id, "apply_migrations", {},
            `⚠️ ${file.key}: objet(s) existant(s) ignoré(s)`, "warn")
        }
        totalExecuted++
      }

      await updateStep(supabaseAdmin, job_id, "apply_migrations", {},
        `✅ ${file.key} appliqué`, "success")
    }

    await updateStep(supabaseAdmin, job_id, "apply_migrations", {
      status: "completed", completed_at: new Date().toISOString(),
      result: {
        method: "file_by_file",
        files_applied: loadedFiles.length,
        total_executed: totalExecuted,
        total_kb: totalKB.toFixed(1),
      },
    }, `✅ ${loadedFiles.length} fichiers SQL appliqués (${totalExecuted} blocs)`, "success")

    // ═════════════════════════════════════════════════════════════════════════════
    // ÉTAPE 6 : Créer les buckets Storage
    // ═════════════════════════════════════════════════════════════════════════════
    await updateStep(supabaseAdmin, job_id, "create_storage", {
      status: "in_progress", started_at: new Date().toISOString(),
    })

    for (const bucket of projectTemplate.storage_buckets || []) {
      const res = await fetch(
        `https://api.supabase.com/v1/projects/${projectRef}/storage/buckets`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: `Bearer ${accessToken}` },
          body: JSON.stringify({
            name: bucket.name,
            public: bucket.public,
            file_size_limit: bucket.file_size_limit || null,
            allowed_mime_types: bucket.allowed_mime_types || null,
          }),
        }
      )
      if (!res.ok && res.status !== 409) {
        const err = await res.text()
        await updateStep(supabaseAdmin, job_id, "create_storage", {
          status: "failed", error: `Bucket ${bucket.name}: ${err}`, completed_at: new Date().toISOString(),
        })
        await updateJobStatus(supabaseAdmin, job_id, "failed", `Bucket ${bucket.name}: ${err}`, "create_storage")
        return createResponse({ error: `Bucket ${bucket.name}: ${err}` }, res.status)
      }
    }

    await updateStep(supabaseAdmin, job_id, "create_storage", {
      status: "completed", completed_at: new Date().toISOString(),
      result: { buckets: projectTemplate.storage_buckets?.length || 0 },
    })

    // ═════════════════════════════════════════════════════════════════════════════
    // ÉTAPE 7 : Créer le repo GitHub depuis le template
    // ═════════════════════════════════════════════════════════════════════════════
    await updateStep(supabaseAdmin, job_id, "create_github", {
      status: "in_progress", started_at: new Date().toISOString(),
    })

    const ghOwner = projectTemplate.github_template_owner
    const ghTemplateRepo = projectTemplate.github_template_repo
    const ghRepoName = `${pJob.client_slug}-${ghTemplateRepo}`

    // Vérifier que le repo template existe et est un template
    const checkRes = await fetch(`https://api.github.com/repos/${ghOwner}/${ghTemplateRepo}`, {
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${githubToken}`,
        "X-GitHub-Api-Version": "2022-11-28",
      },
    })

    if (!checkRes.ok) {
      const err = `Template GitHub introuvable: ${ghOwner}/${ghTemplateRepo}`
      await updateStep(supabaseAdmin, job_id, "create_github", {
        status: "failed", error: err, completed_at: new Date().toISOString(),
      })
      await updateJobStatus(supabaseAdmin, job_id, "failed", err, "create_github")
      return createResponse({ error: err }, checkRes.status)
    }

    const tplRepo = await checkRes.json()
    if (!tplRepo.is_template) {
      const err = `${ghOwner}/${ghTemplateRepo} n'est pas un template GitHub`
      await updateStep(supabaseAdmin, job_id, "create_github", {
        status: "failed", error: err, completed_at: new Date().toISOString(),
      })
      await updateJobStatus(supabaseAdmin, job_id, "failed", err, "create_github")
      return createResponse({ error: err }, 400)
    }

    const createRepoRes = await fetch(
      `https://api.github.com/repos/${ghOwner}/${ghTemplateRepo}/generate`,
      {
        method: "POST",
        headers: {
          Accept: "application/vnd.github+json",
          Authorization: `Bearer ${githubToken}`,
          "X-GitHub-Api-Version": "2022-11-28",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          owner: ghOwner,
          name: ghRepoName,
          description: `Application ${pJob.client_name}`,
          private: true,
        }),
      }
    )

    if (!createRepoRes.ok) {
      const err = await createRepoRes.text()
      await updateStep(supabaseAdmin, job_id, "create_github", {
        status: "failed", error: err, completed_at: new Date().toISOString(),
      })
      await updateJobStatus(supabaseAdmin, job_id, "failed", `GitHub: ${err}`, "create_github")
      return createResponse({ error: `GitHub: ${err}` }, createRepoRes.status)
    }

    const ghRepo = await createRepoRes.json()
    const githubRepoUrl = ghRepo.html_url
    await supabaseAdmin.from("provisioning_jobs").update({ github_repo_url: githubRepoUrl }).eq("id", job_id)

    await updateStep(supabaseAdmin, job_id, "create_github", {
      status: "completed", completed_at: new Date().toISOString(),
      result: { url: githubRepoUrl },
    }, `✅ Repo créé: ${githubRepoUrl}`, "success")

    // ═════════════════════════════════════════════════════════════════════════════
    // ÉTAPE 8 : Créer le projet Vercel
    // ═════════════════════════════════════════════════════════════════════════════
    await updateStep(supabaseAdmin, job_id, "create_vercel", {
      status: "in_progress", started_at: new Date().toISOString(),
    })

    const vercelName = `${pJob.client_slug}-${ghTemplateRepo}`
    const createVercelRes = await fetch("https://api.vercel.com/v9/projects", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${vercelToken}` },
      body: JSON.stringify({
        name: vercelName,
        gitRepository: { type: "github", repo: ghRepoName, repoOwner: ghOwner },
        framework: projectTemplate.vercel_framework || null,
        buildCommand: projectTemplate.vercel_build_command || null,
        outputDirectory: projectTemplate.vercel_output_directory || null,
      }),
    })

    if (!createVercelRes.ok) {
      const err = await createVercelRes.text()
      await updateStep(supabaseAdmin, job_id, "create_vercel", {
        status: "failed", error: err, completed_at: new Date().toISOString(),
      })
      await updateJobStatus(supabaseAdmin, job_id, "failed", `Vercel: ${err}`, "create_vercel")
      return createResponse({ error: `Vercel: ${err}` }, createVercelRes.status)
    }

    const vp = await createVercelRes.json()
    const vercelProjectUrl = vp.url || vp.alias?.[0] || `https://${vp.name || vp.id}.vercel.app`
    await supabaseAdmin.from("provisioning_jobs").update({ vercel_project_url: vercelProjectUrl }).eq("id", job_id)

    await updateStep(supabaseAdmin, job_id, "create_vercel", {
      status: "completed", completed_at: new Date().toISOString(),
      result: { url: vercelProjectUrl },
    }, `✅ Projet Vercel: ${vercelProjectUrl}`, "success")

    // ═════════════════════════════════════════════════════════════════════════════
    // ÉTAPE 9 : Configurer les variables d'environnement Vercel
    // ═════════════════════════════════════════════════════════════════════════════
    await updateStep(supabaseAdmin, job_id, "configure_env", {
      status: "in_progress", started_at: new Date().toISOString(),
    })

    const envVars: Record<string, string> = {
      NEXT_PUBLIC_SUPABASE_URL: projectUrl,
      NEXT_PUBLIC_SUPABASE_ANON_KEY: anonKey,
      SUPABASE_SERVICE_ROLE_KEY: serviceRoleKey,
    }

    await Promise.all(
      Object.entries(envVars).map(([key, value]) =>
        fetch(`https://api.vercel.com/v9/projects/${vp.id}/env`, {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: `Bearer ${vercelToken}` },
          body: JSON.stringify({ key, value, type: "encrypted", target: ["production", "development", "preview"] }),
        }).then(async (r) => {
          if (!r.ok) console.warn(`[ENV] ${key}: ${await r.text()}`)
        })
      )
    )

    await updateStep(supabaseAdmin, job_id, "configure_env", {
      status: "completed", completed_at: new Date().toISOString(),
    }, "✅ Variables Vercel configurées", "success")

    // ═════════════════════════════════════════════════════════════════════════════
    // ÉTAPE 10 : Enregistrer le client dans le dashboard
    // ═════════════════════════════════════════════════════════════════════════════
    await updateStep(supabaseAdmin, job_id, "register_client", {
      status: "in_progress", started_at: new Date().toISOString(),
    })

    const { data: encKey, error: encErr } = await supabaseAdmin.rpc("encrypt_service_key", {
      p_service_role_key: serviceRoleKey,
      p_encryption_key: encryptionKey,
    })

    if (encErr || !encKey) {
      const msg = `Chiffrement: ${encErr?.message || "inconnu"}`
      await updateStep(supabaseAdmin, job_id, "register_client", {
        status: "failed", error: msg, completed_at: new Date().toISOString(),
      })
      await updateJobStatus(supabaseAdmin, job_id, "failed", msg, "register_client")
      return createResponse({ error: msg }, 500)
    }

    const { data: newClient, error: clientErr } = await supabaseAdmin
      .from("clients")
      .insert({
        app_id: pJob.app_id,
        name: pJob.client_name,
        slug: pJob.client_slug,
        supabase_project_ref: projectRef,
        supabase_url: projectUrl,
        supabase_service_role_key_encrypted: encKey,
        supabase_plan: pJob.supabase_plan as any,
        monthly_revenue: pJob.monthly_revenue,
        annual_revenue: pJob.monthly_revenue * 12,
        vercel_project_url: vercelProjectUrl,
        github_repo_url: githubRepoUrl,
        status: "active",
        notes: "Client provisionné automatiquement.",
      })
      .select("id")
      .single()

    if (clientErr || !newClient) {
      const msg = `Client: ${clientErr?.message || "inconnu"}`
      await updateStep(supabaseAdmin, job_id, "register_client", {
        status: "failed", error: msg, completed_at: new Date().toISOString(),
      })
      await updateJobStatus(supabaseAdmin, job_id, "failed", msg, "register_client")
      return createResponse({ error: msg }, 500)
    }

    await supabaseAdmin.from("provisioning_jobs").update({ client_id: newClient.id }).eq("id", job_id)

    await updateStep(supabaseAdmin, job_id, "register_client", {
      status: "completed", completed_at: new Date().toISOString(),
      result: { clientId: newClient.id },
    }, `✅ Client enregistré: ${newClient.id}`, "success")

    // ═════════════════════════════════════════════════════════════════════════════
    // TERMINÉ
    // ═════════════════════════════════════════════════════════════════════════════
    await updateJobStatus(supabaseAdmin, job_id, "completed")
    return createResponse({ success: true, client_id: newClient.id }, 200)

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
