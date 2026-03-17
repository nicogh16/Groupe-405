import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "jsr:@supabase/supabase-js@2"

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

// Helper: Mettre à jour une étape du job avec logs
async function updateStep(
  supabaseAdmin: any,
  jobId: string,
  stepId: string,
  updates: Partial<ProvisioningStep>,
  logMessage?: string,
  logLevel: "info" | "error" | "success" | "warn" = "info"
) {
  const stepLabel = updates.label || stepId
  const timestamp = new Date().toISOString()
  
  if (logMessage) {
    console.log(`[STEP ${stepId}] ${logMessage}`)
  }

  const { data: job } = await supabaseAdmin
    .from("provisioning_jobs")
    .select("steps")
    .eq("id", jobId)
    .single()

  if (!job) {
    console.error(`[STEP ${stepId}] Job ${jobId} introuvable`)
    return
  }

  const steps = (job.steps || []) as ProvisioningStep[]
  const stepIndex = steps.findIndex((s) => s.id === stepId)
  if (stepIndex === -1) {
    console.error(`[STEP ${stepId}] Étape introuvable dans le job`)
    return
  }

  const oldStatus = steps[stepIndex].status
  const currentStep = steps[stepIndex]
  
  // Ajouter le log au step si un message est fourni
  if (logMessage) {
    const stepLogs = currentStep.logs || []
    stepLogs.push({
      timestamp,
      level: logLevel,
      message: logMessage,
    })
    updates.logs = stepLogs
  }

  steps[stepIndex] = {
    ...currentStep,
    ...updates,
  }

  const newStatus = steps[stepIndex].status
  if (oldStatus !== newStatus) {
    console.log(`[STEP ${stepId}] Statut: ${oldStatus} → ${newStatus}`)
    if (updates.error) {
      console.error(`[STEP ${stepId}] ERREUR: ${updates.error}`)
    }
    if (updates.result) {
      console.log(`[STEP ${stepId}] Résultat:`, JSON.stringify(updates.result))
    }
  }

  const { error } = await supabaseAdmin
    .from("provisioning_jobs")
    .update({ steps, updated_at: timestamp })
    .eq("id", jobId)

  if (error) {
    console.error(`[STEP ${stepId}] Erreur lors de la mise à jour:`, error.message)
  }
}

// Helper: Créer une réponse avec les en-têtes CORS
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

// Helper: Vérifier l'authentification et le rôle admin
async function verifyAdminAuth(
  req: Request,
  supabaseUrl: string,
  supabaseServiceKey: string
): Promise<{ valid: boolean; userId?: string; error?: string }> {
  const authHeader = req.headers.get("Authorization")
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return { valid: false, error: "Token manquant" }
  }
  
  const token = authHeader.replace("Bearer ", "")
  const adminClient = createClient(supabaseUrl, supabaseServiceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })
  
  const { data: { user }, error } = await adminClient.auth.getUser(token)
  
  if (error || !user) {
    return { valid: false, error: "Token invalide" }
  }
  
  // Vérifier que l'utilisateur est admin
  const { data: profile, error: profileError } = await adminClient
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .single()
  
  if (profileError || !profile || profile.role !== "admin") {
    return { valid: false, error: "Accès refusé - admin requis" }
  }
  
  return { valid: true, userId: user.id }
}

// Helper: Mettre à jour le statut global du job
async function updateJobStatus(
  supabaseAdmin: any,
  jobId: string,
  status: ProvisioningJob["status"],
  errorMessage?: string | null,
  errorStep?: string | null
) {
  const updateData: any = {
    status,
    updated_at: new Date().toISOString(),
  }

  if (status === "running" && !errorMessage) {
    updateData.started_at = new Date().toISOString()
  }

  if (status === "completed" || status === "failed") {
    updateData.completed_at = new Date().toISOString()
  }

  if (errorMessage) {
    updateData.error_message = errorMessage
  }

  if (errorStep) {
    updateData.error_step = errorStep
  }

  await supabaseAdmin.from("provisioning_jobs").update(updateData).eq("id", jobId)
}

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

  // Variable pour stocker job_id accessible dans le catch
  let job_id: string | null = null
  
  try {
    // Vérifier TOUTES les variables d'environnement nécessaires AVANT de les utiliser
    const missingSecrets: string[] = []
    
    const supabaseUrl = Deno.env.get("SUPABASE_URL")
    if (!supabaseUrl) missingSecrets.push("SUPABASE_URL")
    
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    if (!supabaseServiceKey) missingSecrets.push("SUPABASE_SERVICE_ROLE_KEY")
    
    // Vérifier l'authentification et le rôle admin AVANT de continuer
    if (supabaseUrl && supabaseServiceKey) {
      const authResult = await verifyAdminAuth(req, supabaseUrl, supabaseServiceKey)
      if (!authResult.valid) {
        console.error(`[AUTH] Échec authentification: ${authResult.error}`)
        return createResponse({ error: authResult.error || "Non autorisé" }, 401)
      }
      console.log(`[AUTH] ✅ Utilisateur authentifié: ${authResult.userId}`)
    }
    
    const supabaseAccessToken = Deno.env.get("ACCESS_TOKEN")
    if (!supabaseAccessToken) missingSecrets.push("ACCESS_TOKEN")
    
    const githubToken = Deno.env.get("GITHUB_TOKEN")
    if (!githubToken) missingSecrets.push("GITHUB_TOKEN")
    
    const vercelToken = Deno.env.get("VERCEL_TOKEN")
    if (!vercelToken) missingSecrets.push("VERCEL_TOKEN")
    
    const supabaseOrgId = Deno.env.get("ORG_ID")
    if (!supabaseOrgId) missingSecrets.push("ORG_ID")
    
    const sourceSupabaseProjectRef = Deno.env.get("SOURCE_SUPABASE_PROJECT_REF")
    if (!sourceSupabaseProjectRef) missingSecrets.push("SOURCE_SUPABASE_PROJECT_REF")
    
    const encryptionKey = Deno.env.get("ENCRYPTION_KEY")
    if (!encryptionKey) missingSecrets.push("ENCRYPTION_KEY")

    if (missingSecrets.length > 0) {
      const errorMsg = `Secrets manquants: ${missingSecrets.join(", ")}. Vérifiez la configuration de l'Edge Function dans Supabase Dashboard → Edge Functions → provision-client → Settings → Secrets.`
      console.error(`[INIT] ERREUR: ${errorMsg}`)
      return createResponse(
        { 
          error: errorMsg,
          missing_secrets: missingSecrets 
        },
        500
      )
    }

    // Maintenant on peut créer le client Supabase en toute sécurité
    const supabaseAdmin = createClient(supabaseUrl!, supabaseServiceKey!, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    console.log("=".repeat(80))
    console.log("[PROVISION-CLIENT] Démarrage du provisionnement")
    console.log("=".repeat(80))

    // Parser le body avec gestion d'erreur
    let body: any
    try {
      body = await req.json()
    } catch (parseError) {
      console.error("[INIT] ERREUR: Impossible de parser le body JSON")
      return createResponse({ error: "Body JSON invalide" }, 400)
    }

    job_id = body.job_id

    console.log(`[INIT] Job ID reçu: ${job_id}`)

    if (!job_id) {
      console.error("[INIT] ERREUR: job_id manquant")
      return createResponse({ error: "job_id requis" }, 400)
    }

    console.log("[INIT] Tous les secrets sont présents")

    // Récupérer le job
    console.log(`[INIT] Récupération du job ${job_id}...`)
    const { data: job, error: jobError } = await supabaseAdmin
      .from("provisioning_jobs")
      .select("*")
      .eq("id", job_id)
      .single()

    if (jobError || !job) {
      console.error(`[INIT] ERREUR: Job introuvable - ${jobError?.message || "inconnu"}`)
      return createResponse({ error: "Job introuvable" }, 404)
    }

    const provisioningJob = job as unknown as ProvisioningJob
    console.log(`[INIT] Job trouvé: ${provisioningJob.client_name} (${provisioningJob.client_slug})`)
    console.log(`[INIT] Statut actuel: ${provisioningJob.status}`)

    // Vérifier que le job n'est pas déjà en cours
    if (provisioningJob.status === "running") {
      console.warn(`[INIT] Job déjà en cours, arrêt`)
      return createResponse({ error: "Job déjà en cours" }, 400)
    }

    // Marquer le job comme running
    console.log("[INIT] Passage du job en statut 'running'...")
    await updateJobStatus(supabaseAdmin, job_id, "running")
    console.log("[INIT] Job marqué comme 'running'")

    // Récupérer le template
    console.log(`[TEMPLATE] Récupération du template ${provisioningJob.template_id}...`)
    const { data: template, error: templateError } = await supabaseAdmin
      .from("project_templates")
      .select("*")
      .eq("id", provisioningJob.template_id)
      .single()

    if (templateError || !template) {
      console.error(`[TEMPLATE] ERREUR: ${templateError?.message || "Template introuvable"}`)
      await updateJobStatus(supabaseAdmin, job_id, "failed", "Template introuvable", "template_fetch")
      return createResponse({ error: "Template introuvable" }, 404)
    }

    const projectTemplate = template as unknown as ProjectTemplate
    console.log(`[TEMPLATE] Template trouvé: ${projectTemplate.name}`)
    console.log(`[TEMPLATE] GitHub: ${projectTemplate.github_template_owner}/${projectTemplate.github_template_repo}`)
    console.log(`[TEMPLATE] Région: ${provisioningJob.supabase_region}, Plan: ${provisioningJob.supabase_plan}`)
    
    // Récupérer l'app pour déterminer le fichier template à utiliser
    console.log(`[TEMPLATE] Récupération de l'app avec app_id: ${projectTemplate.app_id}`)
    const { data: app, error: appError } = await supabaseAdmin
      .from("apps")
      .select("slug, name")
      .eq("id", projectTemplate.app_id)
      .single()
    
    if (appError || !app) {
      console.error(`[TEMPLATE] ERREUR: Impossible de récupérer l'app - ${appError?.message || "app introuvable"}`)
      console.warn(`[TEMPLATE] Utilisation du template par défaut (app_id: ${projectTemplate.app_id})`)
    } else {
      console.log(`[TEMPLATE] App trouvée: ${app.name} (slug: ${app.slug})`)
    }
    
    const appSlug = app?.slug || ""
    console.log(`[TEMPLATE] App slug déterminé: "${appSlug}"`)

    // ─── ÉTAPE 1: Créer le projet Supabase ──────────────────────────────────────
    console.log("\n" + "─".repeat(80))
    console.log("[ÉTAPE 1] Création du projet Supabase")
    console.log("─".repeat(80))

    await updateStep(
      supabaseAdmin,
      job_id,
      "create_supabase",
      {
        status: "in_progress",
        started_at: new Date().toISOString(),
      },
      "Démarrage de la création du projet Supabase"
    )

    const supabaseProjectName = `${provisioningJob.client_slug}-${Date.now().toString(36)}`
    console.log(`[ÉTAPE 1] Nom du projet: ${supabaseProjectName}`)
    console.log(`[ÉTAPE 1] Organisation: ${supabaseOrgId}`)
    console.log(`[ÉTAPE 1] Région: ${provisioningJob.supabase_region}`)

    let createProjectRes: Response
    try {
      // Endpoint correct selon la documentation Supabase: POST /v1/projects
      createProjectRes = await fetch(
        `https://api.supabase.com/v1/projects`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${supabaseAccessToken}`,
          },
          body: JSON.stringify({
            name: supabaseProjectName,
            organization_slug: supabaseOrgId, // Utiliser organization_slug au lieu de organization_id
            db_pass: Math.random().toString(36).slice(-12) + Math.random().toString(36).slice(-12),
            region_selection: {
              type: "specific",
              code: provisioningJob.supabase_region, // Utiliser 'code' au lieu de 'region' pour type: "specific"
            },
          }),
        }
      )

      console.log(`[ÉTAPE 1] Réponse API: ${createProjectRes.status} ${createProjectRes.statusText}`)

      if (!createProjectRes.ok) {
        const errorText = await createProjectRes.text()
        console.error(`[ÉTAPE 1] ERREUR API: ${errorText}`)
        await updateStep(
          supabaseAdmin,
          job_id,
          "create_supabase",
          {
            status: "failed",
            error: `API Supabase: ${createProjectRes.status} - ${errorText}`,
            completed_at: new Date().toISOString(),
          },
          `Échec: ${errorText}`
        )
        await updateJobStatus(
          supabaseAdmin,
          job_id,
          "failed",
          `Échec création Supabase: ${errorText}`,
          "create_supabase"
        )
        return createResponse({ error: `Échec création Supabase: ${errorText}` }, createProjectRes.status)
      }
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error)
      console.error(`[ÉTAPE 1] ERREUR EXCEPTION: ${errorMsg}`)
      await updateStep(
        supabaseAdmin,
        job_id,
        "create_supabase",
        {
          status: "failed",
          error: `Exception: ${errorMsg}`,
          completed_at: new Date().toISOString(),
        },
        `Exception: ${errorMsg}`
      )
      await updateJobStatus(supabaseAdmin, job_id, "failed", `Exception: ${errorMsg}`, "create_supabase")
      return createResponse({ error: `Exception: ${errorMsg}` }, 500)
    }

    const supabaseProject = await createProjectRes.json()
    // Le project ref peut être dans 'id' ou 'ref' selon la réponse API
    const supabaseProjectRef = supabaseProject.ref || supabaseProject.id
    const supabaseProjectUrl = `https://${supabaseProjectRef}.supabase.co`

    console.log(`[ÉTAPE 1] ✅ Projet créé avec succès!`)
    console.log(`[ÉTAPE 1] Project Ref: ${supabaseProjectRef}`)
    console.log(`[ÉTAPE 1] URL: ${supabaseProjectUrl}`)

    await supabaseAdmin
      .from("provisioning_jobs")
      .update({
        supabase_project_ref: supabaseProjectRef,
        supabase_url: supabaseProjectUrl,
      })
      .eq("id", job_id)

    await updateStep(
      supabaseAdmin,
      job_id,
      "create_supabase",
      {
        status: "completed",
        completed_at: new Date().toISOString(),
        result: { ref: supabaseProjectRef, url: supabaseProjectUrl },
      },
      `✅ Projet Supabase créé avec succès! Ref: ${supabaseProjectRef}, URL: ${supabaseProjectUrl}`,
      "success"
    )

    // ─── ÉTAPE 2: Attendre l'initialisation Supabase et récupérer les clés ──────
    console.log("\n" + "─".repeat(80))
    console.log("[ÉTAPE 2] Attente de l'initialisation Supabase et récupération des clés API")
    console.log("─".repeat(80))

    await updateStep(
      supabaseAdmin,
      job_id,
      "wait_supabase",
      {
        status: "in_progress",
        started_at: new Date().toISOString(),
      },
      "Attente de l'initialisation du projet Supabase..."
    )

    let serviceRoleKey = ""
    let anonKey = ""
    let projectReady = false

    for (let i = 0; i < 30; i++) {
      await updateStep(
        supabaseAdmin,
        job_id,
        "wait_supabase",
        {},
        `Tentative ${i + 1}/30 de récupération des clés API...`,
        "info"
      )

      await new Promise((resolve) => setTimeout(resolve, 2000))

      const keysRes = await fetch(
        `https://api.supabase.com/v1/projects/${supabaseProjectRef}/api-keys?reveal=true`,
        {
          headers: { Authorization: `Bearer ${supabaseAccessToken}` },
        }
      )

      if (keysRes.ok) {
        const keys = await keysRes.json()
        // Gérer les anciennes clés (anon/service_role) et les nouvelles (publishable/secret)
        serviceRoleKey = keys.find((k: any) => k.name === "service_role" || k.type === "secret")?.api_key || ""
        anonKey = keys.find((k: any) => k.name === "anon" || k.type === "publishable")?.api_key || ""

        if (serviceRoleKey && anonKey) {
          console.log(`[ÉTAPE 2] ✅ Clés API récupérées après ${i + 1} tentative(s)`)
          projectReady = true
          break
        } else {
          await updateStep(
            supabaseAdmin,
            job_id,
            "wait_supabase",
            {},
            `Clés partiellement disponibles, nouvelle tentative...`,
            "warn"
          )
        }
      } else {
        await updateStep(
          supabaseAdmin,
          job_id,
          "wait_supabase",
          {},
          `Réponse API: ${keysRes.status} ${keysRes.statusText}, nouvelle tentative...`,
          "warn"
        )
      }
    }

    if (!projectReady) {
      console.error(`[ÉTAPE 2] ❌ Timeout après 30 tentatives`)
      await updateStep(
        supabaseAdmin,
        job_id,
        "wait_supabase",
        {
          status: "failed",
          error: "Timeout: clés API non disponibles après 30 tentatives (60 secondes)",
          completed_at: new Date().toISOString(),
        },
        "❌ Timeout: clés API non disponibles",
        "error"
      )
      await updateJobStatus(supabaseAdmin, job_id, "failed", "Timeout: clés API Supabase", "wait_supabase")
      return createResponse({ error: "Timeout: clés API Supabase" }, 500)
    }

    await updateStep(
      supabaseAdmin,
      job_id,
      "wait_supabase",
      {
        status: "completed",
        completed_at: new Date().toISOString(),
      },
      "✅ Clés API récupérées avec succès (service_role et anon)",
      "success"
    )

    // ─── ÉTAPE 3: Charger le fichier SQL template ──────────
    // Déterminer le nom du fichier template selon l'app
    const templateFileName = appSlug === "myfidelity" 
      ? "supabase_new_project.sql"
      : "supabase-template-zdicqtupwckhvxhlkiuf.sql"
    
    await updateStep(
      supabaseAdmin,
      job_id,
      "fetch_migrations",
      {
        status: "in_progress",
        started_at: new Date().toISOString(),
      },
      `Chargement du fichier SQL template: ${templateFileName}`
    )

    // Charger le fichier SQL template depuis le bucket Storage Supabase
    const templateProjectRef = appSlug === "myfidelity" ? "new_project" : "zdicqtupwckhvxhlkiuf"
    
    await updateStep(
      supabaseAdmin,
      job_id,
      "fetch_migrations",
      {},
      `Lecture du fichier template: ${templateFileName}`,
      "info"
    )

    let templateSQL: string
    try {
      // Lire le fichier template depuis un bucket Storage Supabase
      // Le bucket "templates" doit contenir le fichier template (supabase_new_project.sql pour MyFidelity, ou supabase-template-zdicqtupwckhvxhlkiuf.sql pour les autres)
      await updateStep(
        supabaseAdmin,
        job_id,
        "fetch_migrations",
        {},
        `Récupération du fichier template depuis Storage...`,
        "info"
      )

      // Créer un client Supabase pour accéder au Storage
      const storageClient = createClient(supabaseUrl!, supabaseServiceKey!, {
        auth: { autoRefreshToken: false, persistSession: false },
      })

      // Télécharger le fichier depuis le bucket "templates"
      const { data: fileData, error: downloadError } = await storageClient
        .storage
        .from("templates")
        .download(templateFileName)

      if (downloadError || !fileData) {
        throw new Error(downloadError?.message || "Fichier introuvable dans le bucket Storage")
      }

      // Convertir le Blob en texte
      templateSQL = await fileData.text()
      
      if (!templateSQL || templateSQL.trim().length === 0) {
        throw new Error("Le fichier template est vide")
      }
      
      await updateStep(
        supabaseAdmin,
        job_id,
        "fetch_migrations",
        {},
        `✅ Fichier template chargé depuis Storage (${(templateSQL.length / 1024).toFixed(2)} KB)`,
        "success"
      )
    } catch (error) {
      const errorMsg = `Impossible de charger le fichier template ${templateFileName} depuis Storage: ${error instanceof Error ? error.message : String(error)}. Vérifiez que le bucket "templates" existe et contient le fichier ${templateFileName}.`
      await updateStep(supabaseAdmin, job_id, "fetch_migrations", {
        status: "failed",
        error: errorMsg,
        completed_at: new Date().toISOString(),
      })
      await updateJobStatus(supabaseAdmin, job_id, "failed", errorMsg, "fetch_migrations")
      return createResponse({ error: errorMsg }, 404)
    }

    // Créer un objet migration unique contenant tout le template SQL
    const sqlMigrations: { name: string; content: string }[] = [{
      name: `template-${templateProjectRef}`,
      content: templateSQL
    }]

    await updateStep(
      supabaseAdmin,
      job_id,
      "fetch_migrations",
      {
        status: "completed",
        completed_at: new Date().toISOString(),
        result: { template_file: templateFileName, size_kb: (templateSQL.length / 1024).toFixed(2) },
      },
      `✅ Template SQL chargé avec succès (${(templateSQL.length / 1024).toFixed(2)} KB)`,
      "success"
    )

    // ─── ÉTAPE 4: Créer les schémas nécessaires ──────────────────────────────────
    await updateStep(supabaseAdmin, job_id, "create_schemas", {
      status: "in_progress",
      started_at: new Date().toISOString(),
    })

    // Détecter les schémas utilisés dans le template SQL
    const schemasUsed = new Set<string>()
    
    // Tous les schémas système Supabase/PostgreSQL (ne doivent pas être créés)
    const reservedSchemas = [
      // Schémas PostgreSQL système
      "pg_catalog", "information_schema", "pg_toast", "pg_temp", "pg_toast_temp",
      // Tous les schémas commençant par pg_ (réservés par PostgreSQL)
      // Schémas Supabase par défaut
      "public", "auth", "storage", "extensions",
      // Schémas Supabase services
      "realtime", "graphql_public", "vault", "supabase_functions", "supabase_migrations",
      // Schémas d'extensions Supabase courantes
      "net", "pgmq", "pgsodium", "cron", "pgbouncer", "graphql"
    ]
    
    // Fonction pour vérifier si un schéma est réservé par Supabase/PostgreSQL
    const isReservedSchema = (schemaName: string): boolean => {
      const lowerName = schemaName.toLowerCase()
      
      // Tous les schémas commençant par pg_ sont réservés par PostgreSQL
      if (lowerName.startsWith('pg_')) {
        return true
      }
      
      // Vérifier dans la liste des schémas réservés
      if (reservedSchemas.includes(lowerName)) {
        return true
      }
      
      return false
    }
    
    const templateContent = sqlMigrations[0].content
    
    // Détecter CREATE SCHEMA
    const createSchemaRegex = /CREATE\s+(?:OR\s+REPLACE\s+)?SCHEMA\s+(?:IF\s+NOT\s+EXISTS\s+)?["']?(\w+)["']?/gi
    let match
    while ((match = createSchemaRegex.exec(templateContent)) !== null) {
      const schemaName = match[1]
      if (schemaName && !isReservedSchema(schemaName)) {
        schemasUsed.add(schemaName)
      }
    }
    
    // Détecter les références de type schema.table ou schema.function
    const schemaRefRegex = /["']?(\w+)["']?\.["']?\w+["']?/g
    while ((match = schemaRefRegex.exec(templateContent)) !== null) {
      const schemaName = match[1]
      if (schemaName && !isReservedSchema(schemaName)) {
        schemasUsed.add(schemaName)
      }
    }
    
    // Détecter SET search_path ou SET SCHEMA
    const setSchemaRegex = /SET\s+(?:search_path|SCHEMA)\s*=\s*["']?(\w+)["']?/gi
    while ((match = setSchemaRegex.exec(templateContent)) !== null) {
      const schemaName = match[1]
      if (schemaName && !isReservedSchema(schemaName)) {
        schemasUsed.add(schemaName)
      }
    }
    
    // Filtrer les schémas réservés
    const validSchemas = Array.from(schemasUsed).filter(schema => !isReservedSchema(schema))

    await updateStep(
      supabaseAdmin,
      job_id,
      "create_schemas",
      {},
      `${validSchemas.length} schéma(s) valide(s) à créer (${schemasUsed.size - validSchemas.length} schéma(s) réservé(s) ignoré(s))`,
      "info"
    )

    // Créer les schémas manquants (uniquement les schémas valides, pas les réservés)
    for (const schemaName of validSchemas) {
      await updateStep(
        supabaseAdmin,
        job_id,
        "create_schemas",
        {},
        `Création du schéma: ${schemaName}`,
        "info"
      )

      const createSchemaRes = await fetch(
        `https://api.supabase.com/v1/projects/${supabaseProjectRef}/database/query`,
        {
          method: "POST",
        headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${supabaseAccessToken}`,
          },
          body: JSON.stringify({ 
            query: `CREATE SCHEMA IF NOT EXISTS "${schemaName}";` 
          }),
        }
      )

      if (!createSchemaRes.ok) {
        const errorText = await createSchemaRes.text()
        await updateStep(supabaseAdmin, job_id, "create_schemas", {
        status: "failed",
          error: `Échec création schéma ${schemaName}: ${errorText}`,
        completed_at: new Date().toISOString(),
      })
        await updateJobStatus(
          supabaseAdmin,
          job_id,
          "failed",
          `Échec création schéma ${schemaName}: ${errorText}`,
          "create_schemas"
        )
        return createResponse({ error: `Échec création schéma ${schemaName}: ${errorText}` }, createSchemaRes.status)
      }
    }

    await updateStep(supabaseAdmin, job_id, "create_schemas", {
      status: "completed",
      completed_at: new Date().toISOString(),
      result: { schemas: validSchemas, reserved_ignored: schemasUsed.size - validSchemas.length },
    })

    // ─── ÉTAPE 5: Appliquer le schéma SQL étape par étape ────────────────────────────────────────
    await updateStep(supabaseAdmin, job_id, "apply_migrations", {
      status: "in_progress",
      started_at: new Date().toISOString(),
    })

    // Le template SQL contient déjà tout dans le bon ordre
    // templateContent est déjà défini dans l'étape précédente (ligne 712)
    
    await updateStep(
      supabaseAdmin,
      job_id,
      "apply_migrations",
      {},
      `Analyse du template SQL et extraction des statements individuels...`,
      "info"
    )

    // OPTIMISATION: Au lieu de parser tout le SQL (trop coûteux en CPU), 
    // on exécute le template SQL directement par sections
    // Le template est déjà dans le bon ordre (extensions → schémas → types → tables → vues → fonctions)
    
    await updateStep(
      supabaseAdmin,
      job_id,
      "apply_migrations",
      {},
      `Exécution du template SQL par sections (optimisé pour réduire le temps CPU)...`,
      "info"
    )
    
    // Diviser le template en sections principales pour un meilleur suivi
    const sections = [
      { name: "Extensions", pattern: /-- =+[\s\S]*?EXTENSIONS[\s\S]*?=+[\s\S]*?(?=-- =+)/i },
      { name: "Schémas", pattern: /-- =+[\s\S]*?SCHÉMAS[\s\S]*?=+[\s\S]*?(?=-- =+)/i },
      { name: "Types", pattern: /-- =+[\s\S]*?TYPES[\s\S]*?=+[\s\S]*?(?=-- =+)/i },
      { name: "Tables", pattern: /-- =+[\s\S]*?TABLES[\s\S]*?=+[\s\S]*?(?=-- =+)/i },
      { name: "Vues", pattern: /-- =+[\s\S]*?VUES[\s\S]*?=+[\s\S]*?(?=-- =+)/i },
      { name: "Fonctions", pattern: /-- =+[\s\S]*?FONCTIONS[\s\S]*?=+[\s\S]*?(?=-- =+)/i },
      { name: "Migrations", pattern: /-- =+[\s\S]*?MIGRATIONS[\s\S]*?=+[\s\S]*?(?=-- =+)/i },
      { name: "Storage Buckets", pattern: /-- =+[\s\S]*?STORAGE[\s\S]*?=+[\s\S]*?(?=-- =+|$)/i },
    ]
    
    // Si on ne trouve pas de sections, exécuter tout le template d'un coup
    let hasSections = false
    for (const section of sections) {
      if (section.pattern.test(templateContent)) {
        hasSections = true
        break
      }
    }
    
    if (!hasSections) {
      // Pas de sections détectées, exécuter tout le template d'un coup
      await updateStep(
        supabaseAdmin,
        job_id,
        "apply_migrations",
        {},
        `Exécution du template SQL complet...`,
        "info"
      )
      
      const applyRes = await fetch(
        `https://api.supabase.com/v1/projects/${supabaseProjectRef}/database/query`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${supabaseAccessToken}`,
          },
          body: JSON.stringify({ query: templateContent }),
        }
      )
      
      if (!applyRes.ok) {
        const errorText = await applyRes.text()
        const errorMessage = `Échec exécution template SQL: ${errorText}`
        await updateStep(supabaseAdmin, job_id, "apply_migrations", {
          status: "failed",
          error: errorMessage,
          completed_at: new Date().toISOString(),
        })
        await updateJobStatus(supabaseAdmin, job_id, "failed", errorMessage, "apply_migrations")
        return createResponse({ error: errorMessage }, applyRes.status)
      }
      
      await updateStep(supabaseAdmin, job_id, "apply_migrations", {
        status: "completed",
        completed_at: new Date().toISOString(),
        result: { method: "full_template_execution" },
      })
    } else {
      // Exécuter par sections
      let sectionIndex = 0
      for (const section of sections) {
        const match = templateContent.match(section.pattern)
        if (match) {
          sectionIndex++
          const sectionSQL = match[0]
          
          await updateStep(
            supabaseAdmin,
            job_id,
            "apply_migrations",
            {},
            `Exécution section: ${section.name} (${sectionIndex}/${sections.length})`,
            "info"
          )
          
          const applyRes = await fetch(
            `https://api.supabase.com/v1/projects/${supabaseProjectRef}/database/query`,
            {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${supabaseAccessToken}`,
              },
              body: JSON.stringify({ query: sectionSQL }),
            }
          )
          
          if (!applyRes.ok) {
            const errorText = await applyRes.text()
            const errorMessage = `Échec section "${section.name}": ${errorText}`
            await updateStep(supabaseAdmin, job_id, "apply_migrations", {
              status: "failed",
              error: errorMessage,
              completed_at: new Date().toISOString(),
            })
            await updateJobStatus(supabaseAdmin, job_id, "failed", errorMessage, "apply_migrations")
            return createResponse({ error: errorMessage }, applyRes.status)
          }
          
          await updateStep(
            supabaseAdmin,
            job_id,
            "apply_migrations",
            {},
            `✅ Section "${section.name}" exécutée avec succès`,
            "success"
          )
        }
      }
      
      await updateStep(supabaseAdmin, job_id, "apply_migrations", {
        status: "completed",
        completed_at: new Date().toISOString(),
        result: { method: "section_by_section", sections_executed: sectionIndex },
      })
    }
    
    // Le template SQL a été appliqué avec succès par sections
    // Continuer avec les étapes suivantes...

    // ─── ÉTAPE 6: Créer les buckets Storage ──────────────────────────────────────
    await updateStep(supabaseAdmin, job_id, "create_storage", {
      status: "in_progress",
      started_at: new Date().toISOString(),
    })

    for (const bucket of projectTemplate.storage_buckets || []) {
      const createBucketRes = await fetch(
        `https://api.supabase.com/v1/projects/${supabaseProjectRef}/storage/buckets`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${supabaseAccessToken}`,
          },
          body: JSON.stringify({
            name: bucket.name,
            public: bucket.public,
            file_size_limit: bucket.file_size_limit || null,
            allowed_mime_types: bucket.allowed_mime_types || null,
          }),
        }
      )

      if (!createBucketRes.ok && createBucketRes.status !== 409) {
        const errorText = await createBucketRes.text()
        await updateStep(supabaseAdmin, job_id, "create_storage", {
          status: "failed",
          error: `Bucket ${bucket.name}: ${errorText}`,
          completed_at: new Date().toISOString(),
        })
        await updateJobStatus(
          supabaseAdmin,
          job_id,
          "failed",
          `Échec création bucket ${bucket.name}: ${errorText}`,
          "create_storage"
        )
        return createResponse({ error: `Échec création bucket ${bucket.name}: ${errorText}` }, createBucketRes.status)
      }
    }

    await updateStep(supabaseAdmin, job_id, "create_storage", {
      status: "completed",
      completed_at: new Date().toISOString(),
      result: { buckets: projectTemplate.storage_buckets?.length || 0 },
    })

    // ─── ÉTAPE 7: Créer le repo GitHub depuis le template ───────────────────────
    await updateStep(
      supabaseAdmin,
      job_id,
      "create_github",
      {
        status: "in_progress",
        started_at: new Date().toISOString(),
      },
      "Vérification du template GitHub...",
      "info"
    )

    const githubRepoName = `${provisioningJob.client_slug}-${projectTemplate.github_template_repo}`
    const templateRepoUrl = `${projectTemplate.github_template_owner}/${projectTemplate.github_template_repo}`

    // Vérifier d'abord que le repo template existe et est un template
    await updateStep(
      supabaseAdmin,
      job_id,
      "create_github",
      {},
      "Vérification du template GitHub...",
      "info"
    )

    const githubRepoName = `${provisioningJob.client_slug}-${projectTemplate.github_template_repo}`
    const templateRepoUrl = `${projectTemplate.github_template_owner}/${projectTemplate.github_template_repo}`

    // Vérifier d'abord que le repo template existe et est un template
    const templateCheckRes = await fetch(
      `https://api.github.com/repos/${templateRepoUrl}`,
      {
        headers: {
          Accept: "application/vnd.github.v3+json",
          Authorization: `token ${githubToken}`,
        },
      }
    )

    if (!templateCheckRes.ok) {
      const errorText = await templateCheckRes.text()
      let errorMessage = `Template GitHub introuvable ou inaccessible: ${errorText}`
      
      if (templateCheckRes.status === 404) {
        errorMessage = `Le repository template "${templateRepoUrl}" n'existe pas ou n'est pas accessible. Vérifiez que le repository existe et que le token GitHub a les permissions nécessaires.`
      } else if (templateCheckRes.status === 403) {
        errorMessage = `Accès refusé au repository template "${templateRepoUrl}". Vérifiez que le token GitHub a les permissions nécessaires (repo scope).`
      }
      
      await updateStep(supabaseAdmin, job_id, "create_github", {
        status: "failed",
        error: errorMessage,
        completed_at: new Date().toISOString(),
      })
      await updateJobStatus(supabaseAdmin, job_id, "failed", errorMessage, "create_github")
      return createResponse({ error: errorMessage }, templateCheckRes.status)
    }

    const templateRepo = await templateCheckRes.json()
    
    if (!templateRepo.is_template) {
      const errorMessage = `Le repository "${templateRepoUrl}" n'est pas marqué comme template. Allez dans Settings → Template repository et activez cette option.`
      await updateStep(supabaseAdmin, job_id, "create_github", {
        status: "failed",
        error: errorMessage,
        completed_at: new Date().toISOString(),
      })
      await updateJobStatus(supabaseAdmin, job_id, "failed", errorMessage, "create_github")
      return createResponse({ error: errorMessage }, 422)
    }

    await updateStep(
      supabaseAdmin,
      job_id,
      "create_github",
      {},
      `Template GitHub vérifié: ${templateRepoUrl}. Création du repository...`,
      "info"
    )

    // Créer le repo depuis le template
    const createRepoRes = await fetch("https://api.github.com/repos", {
      method: "POST",
      headers: {
        Accept: "application/vnd.github.v3+json",
        Authorization: `token ${githubToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        name: githubRepoName,
        owner: projectTemplate.github_template_owner,
        description: `Repository pour ${provisioningJob.client_name}`,
        private: projectTemplate.github_repo_private || false,
        template_owner: projectTemplate.github_template_owner,
        template_repo: projectTemplate.github_template_repo,
      }),
    })

    if (!createRepoRes.ok) {
      const errorText = await createRepoRes.text()
      let errorMessage = `Échec création repo GitHub: ${errorText}`
      
      if (createRepoRes.status === 422) {
        const errorJson = JSON.parse(errorText)
        if (errorJson.errors && errorJson.errors.some((e: any) => e.message?.includes("already exists"))) {
          errorMessage = `Le repository "${githubRepoName}" existe déjà. Choisissez un autre nom ou supprimez le repository existant.`
        }
      }
      
      await updateStep(supabaseAdmin, job_id, "create_github", {
        status: "failed",
        error: errorMessage,
        completed_at: new Date().toISOString(),
      })
      await updateJobStatus(supabaseAdmin, job_id, "failed", errorMessage, "create_github")
      return createResponse({ error: errorMessage }, createRepoRes.status)
    }

    const newRepo = await createRepoRes.json()
    
    await updateStep(supabaseAdmin, job_id, "create_github", {
      status: "completed",
      completed_at: new Date().toISOString(),
      result: {
        repo_url: newRepo.html_url,
        repo_name: newRepo.name,
        repo_full_name: newRepo.full_name,
      },
    })

    // ─── ÉTAPE 8: Créer le projet Vercel ──────────────────────────────────────────
    await updateStep(
      supabaseAdmin,
      job_id,
        const char = sql[i]
        const nextChar = sql[i + 1]
        const prevChar = i > 0 ? sql[i - 1] : ''
        
        // Détecter le début d'une fonction PostgreSQL (CREATE FUNCTION ... AS $$ ... $$)
        // IMPORTANT: Vérifier AVANT de traiter les autres caractères pour éviter de séparer prématurément
        if (!inString && !inDollarQuote && !inDoBlock && !inFunction) {
          const remaining = sql.substring(i).toLowerCase()
          // Détecter CREATE FUNCTION ou CREATE OR REPLACE FUNCTION
          if (remaining.match(/^\s*create\s+(or\s+replace\s+)?function\s+/)) {
            // Chercher le bloc AS $$ ... $$ qui contient le corps de la fonction
            // On cherche "AS" suivi d'un tag dollar (peut être sur plusieurs lignes)
            const fullRemaining = sql.substring(i)
            // Chercher "AS" suivi d'espaces optionnels puis d'un tag dollar (multiline avec flag 's')
            // Pattern amélioré : AS suivi de whitespace puis d'un tag dollar (peut contenir des caractères)
            const asMatch = fullRemaining.match(/as\s+(\$[^$\s]*\$)/is)
            if (asMatch) {
              inFunction = true
              functionDollarTag = asMatch[1]
              // On va accumuler tout jusqu'au tag de fermeture
              current += char
              i++
              continue
            } else {
              // Essayer une approche alternative : chercher "AS" puis le prochain tag dollar
              // Chercher "AS" (insensible à la casse) suivi d'espaces puis d'un tag dollar
              const asIndex = fullRemaining.search(/as\s+\$/i)
              if (asIndex !== -1) {
                const afterAs = fullRemaining.substring(asIndex + 2).trim()
                const dollarMatch = afterAs.match(/^(\$[^$\s]*\$)/)
                if (dollarMatch) {
                  inFunction = true
                  functionDollarTag = dollarMatch[1]
                  current += char
                  i++
                  continue
                }
              }
            }
          }
        }
        
        // Gérer le corps d'une fonction PostgreSQL (tout le contenu entre AS $$ et $$)
        if (inFunction) {
          current += char
          
          // Vérifier si on rencontre le tag de fermeture
          if (sql.substring(i).startsWith(functionDollarTag)) {
            // Compter combien de fois on a vu ce tag dans current
            let tagCount = 0
            let searchPos = 0
            while ((searchPos = current.indexOf(functionDollarTag, searchPos)) !== -1) {
              tagCount++
              searchPos += functionDollarTag.length
            }
            
            // Si on a vu le tag au moins 2 fois (ouverture + fermeture), on a trouvé la fin du corps
            if (tagCount >= 2) {
              // Avancer jusqu'à la fin du tag de fermeture
              i += functionDollarTag.length - 1
              
              // Chercher le ; final ou le mot-clé LANGUAGE qui peut suivre
              const afterTag = sql.substring(i + 1).trim()
              
              // Si c'est LANGUAGE, on continue jusqu'au ; final
              if (afterTag.match(/^\s*language\s+/i)) {
                // Chercher le ; après LANGUAGE (peut être sur plusieurs lignes)
                const langMatch = afterTag.match(/language\s+\w+\s*;/is)
                if (langMatch) {
                  // On a trouvé LANGUAGE ... ;, la fonction est complète
                  inFunction = false
                  functionDollarTag = ""
                  i += langMatch[0].length - 1
                } else {
                  // Pas de ; après LANGUAGE, continuer à accumuler jusqu'au prochain ;
                  i++
                  continue
                }
              } else if (afterTag.startsWith(';') || afterTag.match(/^\s*;\s*$/m)) {
                // C'est le ; final, la fonction est complète
                inFunction = false
                functionDollarTag = ""
              } else {
                // Pas de ; ou LANGUAGE immédiatement après, mais on a trouvé le tag de fermeture
                // La fonction se termine ici (peut-être pas de ; final)
                inFunction = false
                functionDollarTag = ""
              }
            } else {
              // C'est le tag d'ouverture, continuer
              i++
              continue
            }
          }
          
          // Si on est dans une fonction, on ignore TOUS les ; jusqu'au tag de fermeture
          i++
          continue
        }
        
        // Détecter le début d'un bloc DO $$ ... $$
        if (!inString && !inDollarQuote && !inDoBlock && !inFunction) {
          const remaining = sql.substring(i).toLowerCase()
          if (remaining.match(/^\s*do\s+\$/)) {
            // Trouver le tag dollar (peut être $$, $tag$, etc.)
            const dollarMatch = sql.substring(i).match(/do\s+(\$[^$]*\$)/i)
            if (dollarMatch) {
              inDoBlock = true
              dollarTag = dollarMatch[1]
              current += char
              i++
              continue
            }
          }
        }
        
        // Gérer les blocs DO $$ ... $$
        if (inDoBlock) {
          current += char
          
          // Vérifier si on rencontre le tag de fermeture
          if (sql.substring(i).startsWith(dollarTag)) {
            // Vérifier que ce n'est pas le tag d'ouverture (on doit être après le début)
            if (current.length > dollarTag.length) {
              inDoBlock = false
              dollarTag = ""
              i += dollarTag.length - 1
              // Le bloc DO se termine, on continue pour trouver le ; final
            }
          }
          
          i++
          continue
        }
        
        // Gérer les dollar-quoted strings ($$...$$, $tag$...$tag$)
        if (!inString && !inDollarQuote && char === '$') {
          const remaining = sql.substring(i)
          // Détecter le tag dollar (peut être $$, $tag$, etc.)
          const dollarMatch = remaining.match(/^(\$[^$]*\$)/)
          if (dollarMatch) {
            dollarTag = dollarMatch[1]
            inDollarQuote = true
            current += char
            i++
            continue
          }
        }
        
        if (inDollarQuote) {
          current += char
          if (sql.substring(i).startsWith(dollarTag)) {
            i += dollarTag.length - 1
            inDollarQuote = false
            dollarTag = ""
          }
          i++
          continue
        }
        
        // Gérer les strings normales ('...' ou "...")
        if (!inString && (char === "'" || char === '"')) {
          inString = true
          stringChar = char
          current += char
          i++
          continue
        }
        
        if (inString) {
          current += char
          // Échapper les quotes échappées
          if (char === stringChar && sql[i - 1] === '\\') {
            i++
            continue
          }
          // Gérer les doubles quotes pour échapper ('')
          if (char === stringChar && nextChar === stringChar) {
            current += nextChar
            i += 2
            continue
          }
          if (char === stringChar) {
            inString = false
            stringChar = ""
          }
          i++
          continue
        }
        
        // Détecter la fin d'un statement (; suivi d'un saut de ligne, commentaire, ou fin de fichier)
        // MAIS PAS si on est dans une fonction ou un bloc DO (le ; à l'intérieur ne termine pas le statement)
        if (char === ';' && !inFunction && !inDoBlock) {
          // Vérifier si c'est vraiment la fin d'un statement
          // (pas dans un commentaire, pas dans une string, etc.)
          const afterSemicolon = sql.substring(i + 1).trim()
          const isEndOfStatement = 
            afterSemicolon === '' || // Fin de fichier
            afterSemicolon.startsWith('\n') || // Saut de ligne
            afterSemicolon.startsWith('--') || // Commentaire
            afterSemicolon.match(/^\s*(create|alter|drop|insert|update|delete|select|with|do)\s+/i) // Nouveau statement SQL
            
          if (isEndOfStatement) {
            current += char
            const trimmed = current.trim()
            if (trimmed.length > 0 && trimmed !== ';' && !trimmed.match(/^--/)) {
              statements.push(trimmed)
            }
            current = ""
            // Skip les espaces et sauts de ligne après le ;
            i++
            while (i < sql.length && (sql[i] === ' ' || sql[i] === '\t' || sql[i] === '\n' || sql[i] === '\r')) {
              i++
            }
            continue
          }
        }
        
        // Accumuler le caractère normalement (si on n'est pas dans une fonction, un bloc DO, une string, etc.)
        current += char
        i++
      }
      
      // Ajouter le dernier statement s'il n'y a pas de ; final
      const trimmed = current.trim()
      if (trimmed.length > 0 && trimmed !== ';' && !trimmed.match(/^--/)) {
        statements.push(trimmed)
      }
      
      return statements.filter(s => s.length > 0 && s !== ';')
    }

    // Fonction pour détecter les dépendances d'une table (foreign keys)
    function getTableDependencies(statement: string): string[] {
      const dependencies: string[] = []
      const stmt = statement
      
      // Détecter les FOREIGN KEY references (plusieurs formats possibles)
      // Format 1: REFERENCES schema.table
      // Format 2: REFERENCES table (même schéma)
      // Format 3: FOREIGN KEY (...) REFERENCES schema.table
      const fkRegex = /(?:FOREIGN\s+KEY\s*\([^)]*\)\s*)?REFERENCES\s+(?:ONLY\s+)?["']?(\w+)["']?\s*\.\s*["']?(\w+)["']?|(?:FOREIGN\s+KEY\s*\([^)]*\)\s*)?REFERENCES\s+(?:ONLY\s+)?["']?(\w+)["']?/gi
      let match
      while ((match = fkRegex.exec(stmt)) !== null) {
        if (match[1] && match[2]) {
          // Format schema.table
          dependencies.push(`${match[1]}.${match[2]}`)
        } else if (match[3]) {
          // Format table seulement (supposé dans le même schéma ou public)
          dependencies.push(match[3])
        } else if (match[4]) {
          // Format table seulement (autre capture)
          dependencies.push(match[4])
        }
      }
      
      return [...new Set(dependencies)] // Supprimer les doublons
    }

    // Fonction pour extraire le nom de la table créée
    function getTableName(statement: string): string | null {
      const createTableMatch = statement.match(/CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:["']?(\w+)["']?\s*\.\s*)?["']?(\w+)["']?/i)
      if (createTableMatch) {
        if (createTableMatch[1] && createTableMatch[2]) {
          return `${createTableMatch[1]}.${createTableMatch[2]}`
        } else if (createTableMatch[2]) {
          return createTableMatch[2]
        }
      }
      return null
    }

    // Fonction pour détecter les dépendances d'une fonction (vues, tables, fonctions utilisées)
    function getFunctionDependencies(statement: string): string[] {
      const dependencies: string[] = []
      const stmt = statement
      
      // Détecter les références à des vues/tables (FROM, JOIN, INTO)
      // Format: schema.view ou view
      // Exemples: FROM dashboard_view.daily_stats, INTO v_daily_stats from dashboard_view.daily_stats
      const viewRegex = /(?:FROM|JOIN|INTO)\s+(?:\w+\s+)?(?:FROM\s+)?(?:ONLY\s+)?["']?(\w+)["']?\s*\.\s*["']?(\w+)["']?|(?:FROM|JOIN|INTO)\s+(?:\w+\s+)?(?:FROM\s+)?(?:ONLY\s+)?["']?(\w+)["']?/gi
      let match
      while ((match = viewRegex.exec(stmt)) !== null) {
        if (match[1] && match[2]) {
          // Format schema.view
          dependencies.push(`${match[1]}.${match[2]}`)
        } else if (match[3]) {
          // Format view seulement
          dependencies.push(match[3])
        }
      }
      
      // Détecter aussi les patterns comme "into v_daily_stats from dashboard_view.daily_stats"
      const intoFromRegex = /INTO\s+\w+\s+FROM\s+["']?(\w+)["']?\s*\.\s*["']?(\w+)["']?|INTO\s+\w+\s+FROM\s+["']?(\w+)["']?/gi
      while ((match = intoFromRegex.exec(stmt)) !== null) {
        if (match[1] && match[2]) {
          dependencies.push(`${match[1]}.${match[2]}`)
        } else if (match[3]) {
          dependencies.push(match[3])
        }
      }
      
      // Détecter les appels de fonctions (function_name(...))
      // Mais on ignore les fonctions système PostgreSQL
      const funcRegex = /(\w+)\s*\(/g
      const systemFunctions = new Set(['jsonb_agg', 'jsonb_build_object', 'coalesce', 'count', 'sum', 'max', 'min', 'avg', 'now', 'current_date', 'current_timestamp', 'extract', 'date_trunc', 'to_char', 'to_date', 'cast', '::', 'array_agg', 'string_agg'])
      
      while ((match = funcRegex.exec(stmt)) !== null) {
        const funcName = match[1]
        if (!systemFunctions.has(funcName.toLowerCase())) {
          // Pour l'instant, on ne gère pas les dépendances entre fonctions
          // car c'est plus complexe (il faudrait parser le schéma)
        }
      }
      
      return [...new Set(dependencies)] // Supprimer les doublons
    }

    // Fonction pour extraire le nom d'une vue créée
    function getViewName(statement: string): string | null {
      const createViewMatch = statement.match(/CREATE\s+(?:OR\s+REPLACE\s+)?(?:MATERIALIZED\s+)?VIEW\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:["']?(\w+)["']?\s*\.\s*)?["']?(\w+)["']?/i)
      if (createViewMatch) {
        if (createViewMatch[1] && createViewMatch[2]) {
          return `${createViewMatch[1]}.${createViewMatch[2]}`
        } else if (createViewMatch[2]) {
          return createViewMatch[2]
        }
      }
      return null
    }

    // Fonction pour déterminer le type d'objet SQL et sa priorité d'exécution
    function getStatementPriority(statement: string, allStatements: string[]): { priority: number; dependencies: string[] } {
      const stmt = statement.trim().toUpperCase()
      
      // Priorité 1: Schémas
      if (stmt.match(/^CREATE\s+SCHEMA/i)) {
        return { priority: 1, dependencies: [] }
      }
      
      // Priorité 2: Types et extensions
      if (stmt.match(/^CREATE\s+(TYPE|EXTENSION)/i)) {
        return { priority: 2, dependencies: [] }
      }
      
      // Priorité 3: Tables (avec gestion des dépendances)
      if (stmt.match(/^CREATE\s+TABLE/i)) {
        const dependencies = getTableDependencies(statement)
        // Les tables sans dépendances ont priorité 3, celles avec dépendances ont priorité 3.5
        return { 
          priority: dependencies.length === 0 ? 3 : 3.5, 
          dependencies 
        }
      }
      
      // Priorité 4: Vues et materialized views (sans dépendances d'abord)
      if (stmt.match(/^CREATE\s+(OR\s+REPLACE\s+)?(MATERIALIZED\s+)?VIEW/i)) {
        // Pour l'instant, on suppose que les vues peuvent dépendre de tables
        // mais on les crée après les tables
        return { priority: 4, dependencies: [] }
      }
      
      // Priorité 5: Index
      if (stmt.match(/^CREATE\s+INDEX/i)) {
        return { priority: 5, dependencies: [] }
      }
      
      // Priorité 6: Fonctions (peuvent dépendre de vues et tables)
      if (stmt.match(/^CREATE\s+(OR\s+REPLACE\s+)?FUNCTION/i)) {
        const dependencies = getFunctionDependencies(statement)
        // Les fonctions avec dépendances ont une priorité plus élevée
        return { 
          priority: dependencies.length === 0 ? 6 : 6.5, 
          dependencies 
        }
      }
      
      // Priorité 7: Triggers
      if (stmt.match(/^CREATE\s+TRIGGER/i)) {
        return { priority: 7, dependencies: [] }
      }
      
      // Priorité 8: RLS Policies
      if (stmt.match(/ALTER\s+TABLE.*ENABLE\s+ROW\s+LEVEL\s+SECURITY/i) || 
          stmt.match(/CREATE\s+POLICY/i)) {
        return { priority: 8, dependencies: [] }
      }
      
      // Priorité 9: Grants et autres
      if (stmt.match(/^GRANT|^REVOKE/i)) {
        return { priority: 9, dependencies: [] }
      }
      
      // Priorité 10: Tout le reste (ALTER, etc.)
      return { priority: 10, dependencies: [] }
    }

    // Analyser les dépendances entre objets pour TOUS les statements
    const tableMap = new Map<string, { statement: string; dependencies: string[]; index: number; migrationName?: string }>()
    const viewMap = new Map<string, { statement: string; dependencies: string[]; index: number; migrationName?: string }>()
    const functionMap = new Map<string, { statement: string; dependencies: string[]; index: number; migrationName?: string }>()
    const otherStatements: Array<{ statement: string; priority: number; index: number; migrationName?: string }> = []
    
    // Créer un mapping statement -> migration (on a un seul template)
    const statementToMigration = new Map<string, string>()
    const templateName = sortedMigrations[0]?.name || "template-zdicqtupwckhvxhlkiuf"
    const statements = splitSQLStatements(templateContent)
    for (const stmt of statements) {
      const trimmed = stmt.trim()
      if (trimmed && !trimmed.startsWith('--')) {
        statementToMigration.set(trimmed, templateName)
      }
    }
    
    function getMigrationName(statement: string, statementIndex: number): string {
      // Chercher dans le mapping
      const trimmed = statement.trim()
      if (statementToMigration.has(trimmed)) {
        return statementToMigration.get(trimmed)!
      }
      // Sinon, utiliser le nom du template
      return templateName
    }
    
    // Séparer les objets par type pour TOUS les statements
    for (let idx = 0; idx < allSQLStatements.length; idx++) {
      const stmt = allSQLStatements[idx]
      const migrationName = getMigrationName(stmt, idx)
      const tableName = getTableName(stmt)
      const viewName = getViewName(stmt)
      const isFunction = stmt.match(/^CREATE\s+(OR\s+REPLACE\s+)?FUNCTION/i)
      
      if (tableName) {
        const deps = getTableDependencies(stmt)
        tableMap.set(tableName, { statement: stmt, dependencies: deps, index: idx, migrationName })
      } else if (viewName) {
        // Les vues peuvent dépendre de tables, mais on les crée après les tables
        viewMap.set(viewName, { statement: stmt, dependencies: [], index: idx, migrationName })
      } else if (isFunction) {
        const deps = getFunctionDependencies(stmt)
        // Utiliser un nom unique pour la fonction (basé sur l'index si nécessaire)
        const funcName = `function_${idx}`
        functionMap.set(funcName, { statement: stmt, dependencies: deps, index: idx, migrationName })
      } else {
        const priorityInfo = getStatementPriority(stmt, allSQLStatements)
        otherStatements.push({ statement: stmt, priority: priorityInfo.priority, index: idx, migrationName })
      }
    }
      
      // Fonction helper pour trouver un objet par nom (avec ou sans schéma)
      function findObjectByName(name: string, map: Map<string, any>): string | null {
        // Essayer le nom exact
        if (map.has(name)) return name
        
        // Essayer sans schéma
        const nameWithoutSchema = name.includes('.') ? name.split('.')[1] : name
        for (const [mapName] of map) {
          const mapNameWithoutSchema = mapName.includes('.') ? mapName.split('.')[1] : mapName
          if (mapNameWithoutSchema === nameWithoutSchema || mapName === name || mapName.endsWith(`.${name}`)) {
            return mapName
          }
        }
        return null
      }
    
    // Trier les tables : d'abord celles sans dépendances, puis celles avec dépendances
    const sortedTables: Array<{ statement: string; tableName: string; index: number; migrationName?: string }> = []
    const processedTables = new Set<string>()
    
    function addTableWithDependencies(tableName: string) {
      if (processedTables.has(tableName)) return
      
      const tableInfo = tableMap.get(tableName)
      if (!tableInfo) return
      
      // D'abord ajouter les tables dont cette table dépend
      for (const dep of tableInfo.dependencies) {
        const foundDep = findObjectByName(dep, tableMap)
        if (foundDep && !processedTables.has(foundDep)) {
          addTableWithDependencies(foundDep)
        }
      }
      
      sortedTables.push({
        statement: tableInfo.statement,
        tableName: tableName,
        index: tableInfo.index,
        migrationName: tableInfo.migrationName,
      })
      processedTables.add(tableName)
    }
    
    // Ajouter toutes les tables dans le bon ordre
    for (const [tableName] of tableMap) {
      addTableWithDependencies(tableName)
    }
    
    // Trier les vues (elles peuvent dépendre de tables, mais on les crée après les tables)
    const sortedViews: Array<{ statement: string; viewName: string; index: number; migrationName?: string }> = []
    
    for (const [viewName, viewInfo] of viewMap) {
      sortedViews.push({
        statement: viewInfo.statement,
        viewName: viewName,
        index: viewInfo.index,
        migrationName: viewInfo.migrationName,
      })
    }
    
    // Séparer les fonctions avec et sans dépendances de vues
    const functionsWithViewDeps: Array<{ statement: string; funcName: string; index: number; migrationName?: string }> = []
    const functionsWithoutViewDeps: Array<{ statement: string; funcName: string; index: number; migrationName?: string }> = []
    
    for (const [funcName, funcInfo] of functionMap) {
      // Vérifier si la fonction dépend d'une vue
      let dependsOnView = false
      for (const dep of funcInfo.dependencies) {
        const foundView = findObjectByName(dep, viewMap)
        if (foundView) {
          dependsOnView = true
          break
        }
      }
      
      if (dependsOnView) {
        functionsWithViewDeps.push({
          statement: funcInfo.statement,
          funcName: funcName,
          index: funcInfo.index,
          migrationName: funcInfo.migrationName,
        })
      } else {
        functionsWithoutViewDeps.push({
          statement: funcInfo.statement,
          funcName: funcName,
          index: funcInfo.index,
          migrationName: funcInfo.migrationName,
        })
      }
    }
    
    // D'abord les fonctions sans dépendances de vues, puis celles avec dépendances
    const sortedFunctions: Array<{ statement: string; funcName: string; index: number; hasViewDeps: boolean; migrationName?: string }> = [
      ...functionsWithoutViewDeps.map(f => ({ ...f, hasViewDeps: false })),
      ...functionsWithViewDeps.map(f => ({ ...f, hasViewDeps: true }))
    ]
    
    // Combiner tous les objets triés par priorité
    const allStatements = [
      ...sortedTables.map(t => ({ 
        statement: t.statement, 
        priority: 3, 
        index: t.index,
        type: 'table',
        migrationName: t.migrationName
      })),
      ...sortedViews.map(v => ({ 
        statement: v.statement, 
        priority: 4, 
        index: v.index,
        type: 'view',
        migrationName: v.migrationName
      })),
      ...sortedFunctions.map(f => ({ 
        statement: f.statement, 
        priority: f.hasViewDeps ? 6.5 : 6, // Fonctions avec dépendances de vues après les vues
        index: f.index,
        type: 'function',
        migrationName: f.migrationName
      })),
      ...otherStatements.map(s => ({ 
        statement: s.statement, 
        priority: s.priority, 
        index: s.index,
        type: 'other',
        migrationName: s.migrationName
      }))
    ].sort((a, b) => {
      // D'abord par priorité
      if (a.priority !== b.priority) {
        return a.priority - b.priority
      }
      // Ensuite par ordre original (pour maintenir l'ordre dans la même priorité)
      return a.index - b.index
    })
    
    const sortedStatements = allStatements.map(s => ({
      statement: s.statement,
      priority: s.priority,
      index: s.index,
      migrationName: s.migrationName || "unknown",
      type: s.type || "other",
    }))
    
    await updateStep(
      supabaseAdmin,
      job_id,
      "apply_migrations",
      {},
      `✅ Tri terminé. ${sortedStatements.length} statement(s) prêt(s) à être exécuté(s) dans l'ordre optimal (schémas → types → tables → vues → fonctions → triggers → policies → grants)`,
      "success"
    )

    // Exécuter chaque statement individuellement dans l'ordre optimisé
    for (let j = 0; j < sortedStatements.length; j++) {
      const statementInfo = sortedStatements[j]
      const trimmed = statementInfo.statement.trim()
      
      // Ignorer les statements vides ou les commentaires seuls
      if (!trimmed || trimmed.startsWith('--') || trimmed.length === 0) {
        continue
      }

      const tableName = getTableName(trimmed)
      const viewName = getViewName(trimmed)
      const isFunction = trimmed.match(/^CREATE\s+(OR\s+REPLACE\s+)?FUNCTION/i)
      
      let logMessage = ""
      if (tableName) {
        logMessage = `Création table ${tableName} (${j + 1}/${sortedStatements.length}) [${statementInfo.migrationName}]`
      } else if (viewName) {
        logMessage = `Création vue ${viewName} (${j + 1}/${sortedStatements.length}) [${statementInfo.migrationName}]`
      } else if (isFunction) {
        logMessage = `Création fonction (${j + 1}/${sortedStatements.length}) [${statementInfo.migrationName}]`
      } else {
        logMessage = `Statement ${j + 1}/${sortedStatements.length} (priorité ${statementInfo.priority}) [${statementInfo.migrationName}]`
      }

      await updateStep(
        supabaseAdmin,
        job_id,
        "apply_migrations",
        {},
        logMessage,
        "info"
      )

      const applyRes = await fetch(
        `https://api.supabase.com/v1/projects/${supabaseProjectRef}/database/query`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${supabaseAccessToken}`,
          },
            body: JSON.stringify({ query: trimmed }),
        }
      )

      if (!applyRes.ok) {
        const errorText = await applyRes.text()
        let errorMessage = `[${statementInfo.migrationName}] Statement ${j + 1}/${sortedStatements.length}: ${errorText}`
        
        // Améliorer le message d'erreur pour les erreurs de type/table manquants
        if (errorText.includes("does not exist")) {
          const missingMatch = errorText.match(/(?:type|table|schema|function|view|relation)\s+["']?([\w.]+)["']?\s+does not exist/i)
          if (missingMatch) {
            const missingItem = missingMatch[1]
            errorMessage = `L'objet "${missingItem}" n'existe pas encore. Ordre de création: schémas → types → tables → vues → fonctions → triggers → policies → grants. Vérifiez que l'objet est créé avant d'être utilisé. Erreur: ${errorText}`
          }
        }
        
        // Afficher le statement qui a échoué pour le débogage
        const statementPreview = trimmed.substring(0, 300) + (trimmed.length > 300 ? '...' : '')
        errorMessage += `\n\nRequête en échec:\n${statementPreview}`
        
        await updateStep(supabaseAdmin, job_id, "apply_migrations", {
          status: "failed",
          error: errorMessage,
          completed_at: new Date().toISOString(),
        })
        await updateJobStatus(
          supabaseAdmin,
          job_id,
          "failed",
          errorMessage,
          "apply_migrations"
        )
        return createResponse({ error: errorMessage }, applyRes.status)
      }
    }

    await updateStep(supabaseAdmin, job_id, "apply_migrations", {
      status: "completed",
      completed_at: new Date().toISOString(),
      result: { 
        template_file: templateFileName,
        total_statements: allSQLStatements.length,
        statements_executed: sortedStatements.length,
        tables_created: tableMap.size,
        views_created: viewMap.size,
        functions_created: functionMap.size,
      },
    })

    // ─── ÉTAPE 6: Créer les buckets Storage ──────────────────────────────────────
    await updateStep(supabaseAdmin, job_id, "create_storage", {
      status: "in_progress",
      started_at: new Date().toISOString(),
    })

    for (const bucket of projectTemplate.storage_buckets || []) {
      const createBucketRes = await fetch(
        `https://api.supabase.com/v1/projects/${supabaseProjectRef}/storage/buckets`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${supabaseAccessToken}`,
          },
          body: JSON.stringify({
            name: bucket.name,
            public: bucket.public,
            file_size_limit: bucket.file_size_limit || null,
            allowed_mime_types: bucket.allowed_mime_types || null,
          }),
        }
      )

      if (!createBucketRes.ok && createBucketRes.status !== 409) {
        const errorText = await createBucketRes.text()
        await updateStep(supabaseAdmin, job_id, "create_storage", {
          status: "failed",
          error: `Bucket ${bucket.name}: ${errorText}`,
          completed_at: new Date().toISOString(),
        })
        await updateJobStatus(
          supabaseAdmin,
          job_id,
          "failed",
          `Échec création bucket ${bucket.name}: ${errorText}`,
          "create_storage"
        )
        return createResponse({ error: `Échec création bucket ${bucket.name}: ${errorText}` }, createBucketRes.status)
      }
    }

    await updateStep(supabaseAdmin, job_id, "create_storage", {
      status: "completed",
      completed_at: new Date().toISOString(),
      result: { buckets: projectTemplate.storage_buckets?.length || 0 },
    })

    // ─── ÉTAPE 7: Créer le repo GitHub depuis le template ───────────────────────
    await updateStep(
      supabaseAdmin,
      job_id,
      "create_github",
      {
        status: "in_progress",
        started_at: new Date().toISOString(),
      },
      "Vérification du template GitHub..."
    )

    const githubRepoName = `${provisioningJob.client_slug}-${projectTemplate.github_template_repo}`
    const templateRepoUrl = `${projectTemplate.github_template_owner}/${projectTemplate.github_template_repo}`

    // Vérifier d'abord que le repo template existe et est un template
    await updateStep(
      supabaseAdmin,
      job_id,
      "create_github",
      {},
      `Vérification du template: ${templateRepoUrl}`,
      "info"
    )

    const checkTemplateRes = await fetch(
      `https://api.github.com/repos/${projectTemplate.github_template_owner}/${projectTemplate.github_template_repo}`,
      {
        headers: {
          Accept: "application/vnd.github+json",
          Authorization: `Bearer ${githubToken}`,
          "X-GitHub-Api-Version": "2022-11-28",
        },
      }
    )

    if (!checkTemplateRes.ok) {
      const errorText = await checkTemplateRes.text()
      const errorMsg = `Template GitHub introuvable (${checkTemplateRes.status}): ${templateRepoUrl}. Vérifiez que le repo existe et que le token GitHub a les permissions 'repo'. Erreur: ${errorText}`
      await updateStep(supabaseAdmin, job_id, "create_github", {
        status: "failed",
        error: errorMsg,
        completed_at: new Date().toISOString(),
      })
      await updateJobStatus(supabaseAdmin, job_id, "failed", errorMsg, "create_github")
      return createResponse({ error: errorMsg }, checkTemplateRes.status)
    }

    const templateRepo = await checkTemplateRes.json()
    
    if (!templateRepo.is_template) {
      const errorMsg = `Le repo ${templateRepoUrl} n'est pas marqué comme template sur GitHub. Allez sur https://github.com/${templateRepoUrl}/settings et activez "Template repository" dans les options.`
      await updateStep(supabaseAdmin, job_id, "create_github", {
        status: "failed",
        error: errorMsg,
        completed_at: new Date().toISOString(),
      })
      await updateJobStatus(supabaseAdmin, job_id, "failed", errorMsg, "create_github")
      return createResponse({ error: errorMsg }, 400)
    }

    await updateStep(
      supabaseAdmin,
      job_id,
      "create_github",
      {},
      `Template vérifié, création du repo: ${githubRepoName}`,
      "info"
    )

    const createRepoRes = await fetch(
      `https://api.github.com/repos/${projectTemplate.github_template_owner}/${projectTemplate.github_template_repo}/generate`,
      {
        method: "POST",
        headers: {
          Accept: "application/vnd.github+json",
          Authorization: `Bearer ${githubToken}`,
          "X-GitHub-Api-Version": "2022-11-28",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          owner: projectTemplate.github_template_owner,
          name: githubRepoName,
          description: `Application ${provisioningJob.client_name} (généré depuis ${projectTemplate.name})`,
          private: true,
        }),
      }
    )

    if (!createRepoRes.ok) {
      const errorText = await createRepoRes.text()
      let errorMsg = `Échec création repo GitHub (${createRepoRes.status}): ${errorText}`
      
      if (createRepoRes.status === 404) {
        errorMsg = `Template GitHub introuvable: ${templateRepoUrl}. Vérifiez que le repo existe, est marqué comme template, et que le token GitHub a les permissions 'repo'.`
      } else if (createRepoRes.status === 403) {
        errorMsg = `Permission refusée pour créer le repo. Vérifiez que le token GitHub a les permissions 'repo' et que vous avez accès à l'organisation ${projectTemplate.github_template_owner}.`
      } else if (createRepoRes.status === 422) {
        errorMsg = `Données invalides: ${errorText}. Vérifiez que le nom du repo est valide et n'existe pas déjà.`
      }
      
      await updateStep(supabaseAdmin, job_id, "create_github", {
        status: "failed",
        error: errorMsg,
        completed_at: new Date().toISOString(),
      })
      await updateJobStatus(supabaseAdmin, job_id, "failed", errorMsg, "create_github")
      return createResponse({ error: errorMsg }, createRepoRes.status)
    }

    const githubRepo = await createRepoRes.json()
    const githubRepoUrl = githubRepo.html_url

    await supabaseAdmin
      .from("provisioning_jobs")
      .update({ github_repo_url: githubRepoUrl })
      .eq("id", job_id)

    await updateStep(supabaseAdmin, job_id, "create_github", {
      status: "completed",
      completed_at: new Date().toISOString(),
      result: { url: githubRepoUrl },
    })

    // ─── ÉTAPE 8: Créer le projet Vercel ────────────────────────────────────────
    await updateStep(supabaseAdmin, job_id, "create_vercel", {
      status: "in_progress",
      started_at: new Date().toISOString(),
    })

    const vercelProjectName = `${provisioningJob.client_slug}-${projectTemplate.github_template_repo}`

    const createVercelRes = await fetch("https://api.vercel.com/v9/projects", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${vercelToken}`,
      },
      body: JSON.stringify({
        name: vercelProjectName,
        gitRepository: {
          type: "github",
          repo: githubRepoName,
          repoOwner: projectTemplate.github_template_owner,
        },
        framework: projectTemplate.vercel_framework || null,
        buildCommand: projectTemplate.vercel_build_command || null,
        outputDirectory: projectTemplate.vercel_output_directory || null,
      }),
    })

    if (!createVercelRes.ok) {
      const errorText = await createVercelRes.text()
      await updateStep(supabaseAdmin, job_id, "create_vercel", {
        status: "failed",
        error: errorText,
        completed_at: new Date().toISOString(),
      })
      await updateJobStatus(supabaseAdmin, job_id, "failed", `Échec création Vercel: ${errorText}`, "create_vercel")
      return createResponse({ error: `Échec création Vercel: ${errorText}` }, createVercelRes.status)
    }

    const vercelProject = await createVercelRes.json()
    // L'URL peut être dans différentes propriétés selon la réponse Vercel
    const vercelProjectUrl = vercelProject.url || vercelProject.alias?.[0] || `https://${vercelProject.name || vercelProject.id}.vercel.app`

    await supabaseAdmin
      .from("provisioning_jobs")
      .update({ vercel_project_url: vercelProjectUrl })
      .eq("id", job_id)

    await updateStep(supabaseAdmin, job_id, "create_vercel", {
      status: "completed",
      completed_at: new Date().toISOString(),
      result: { url: vercelProjectUrl },
    })

    // ─── ÉTAPE 9: Configurer les variables d'environnement Vercel ───────────────
    await updateStep(supabaseAdmin, job_id, "configure_env", {
      status: "in_progress",
      started_at: new Date().toISOString(),
    })

    const envVars: Record<string, string> = {
      NEXT_PUBLIC_SUPABASE_URL: supabaseProjectUrl,
      NEXT_PUBLIC_SUPABASE_ANON_KEY: anonKey,
      SUPABASE_SERVICE_ROLE_KEY: serviceRoleKey,
    }

    // Ajouter les variables du template
    for (const envVar of projectTemplate.env_vars_template || []) {
      if (envVar.auto) {
        // Les variables auto sont déjà gérées ci-dessus
        continue
      }
      // Pour les variables non-auto, on ne peut pas les remplir automatiquement
      // On les laisse vides pour que l'utilisateur les configure manuellement
    }

    for (const [key, value] of Object.entries(envVars)) {
      const setEnvRes = await fetch(`https://api.vercel.com/v9/projects/${vercelProject.id}/env`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${vercelToken}`,
        },
        body: JSON.stringify({
          key,
          value,
          type: "encrypted",
          target: ["production", "development", "preview"],
        }),
      })

      if (!setEnvRes.ok) {
        console.warn(`Failed to set Vercel env var ${key}: ${await setEnvRes.text()}`)
      }
    }

    await updateStep(supabaseAdmin, job_id, "configure_env", {
      status: "completed",
      completed_at: new Date().toISOString(),
    })

    // ─── ÉTAPE 10: Enregistrer le client dans le dashboard ───────────────────────
    await updateStep(supabaseAdmin, job_id, "register_client", {
      status: "in_progress",
      started_at: new Date().toISOString(),
    })

    // Chiffrer la service_role_key
    const { data: encryptedKeyData, error: encryptError } = await supabaseAdmin.rpc("encrypt_service_key", {
      p_service_role_key: serviceRoleKey,
      p_encryption_key: encryptionKey,
    })

    if (encryptError || !encryptedKeyData) {
      await updateStep(supabaseAdmin, job_id, "register_client", {
        status: "failed",
        error: `Échec chiffrement: ${encryptError?.message || "inconnu"}`,
        completed_at: new Date().toISOString(),
      })
      await updateJobStatus(
        supabaseAdmin,
        job_id,
        "failed",
        `Échec chiffrement clé: ${encryptError?.message || "inconnu"}`,
        "register_client"
      )
      return createResponse({ error: `Échec chiffrement clé: ${encryptError?.message || "inconnu"}` }, 500)
    }

    const { data: newClient, error: clientError } = await supabaseAdmin
      .from("clients")
      .insert({
        app_id: provisioningJob.app_id,
        name: provisioningJob.client_name,
        slug: provisioningJob.client_slug,
        supabase_project_ref: supabaseProjectRef,
        supabase_url: supabaseProjectUrl,
        supabase_service_role_key_encrypted: encryptedKeyData,
        supabase_plan: provisioningJob.supabase_plan as any,
        monthly_revenue: provisioningJob.monthly_revenue,
        annual_revenue: provisioningJob.monthly_revenue * 12,
        vercel_project_url: vercelProjectUrl,
        github_repo_url: githubRepoUrl,
        status: "active",
        notes: "Client provisionné automatiquement.",
      })
      .select("id")
      .single()

    if (clientError || !newClient) {
      await updateStep(supabaseAdmin, job_id, "register_client", {
        status: "failed",
        error: clientError?.message || "inconnu",
        completed_at: new Date().toISOString(),
      })
      await updateJobStatus(
        supabaseAdmin,
        job_id,
        "failed",
        `Échec enregistrement client: ${clientError?.message || "inconnu"}`,
        "register_client"
      )
      return createResponse({ error: `Échec enregistrement client: ${clientError?.message || "inconnu"}` }, 500)
    }

    await supabaseAdmin
      .from("provisioning_jobs")
      .update({ client_id: newClient.id })
      .eq("id", job_id)

    await updateStep(supabaseAdmin, job_id, "register_client", {
      status: "completed",
      completed_at: new Date().toISOString(),
      result: { clientId: newClient.id },
    })

    // ─── TERMINÉ ────────────────────────────────────────────────────────────────
    await updateJobStatus(supabaseAdmin, job_id, "completed")

    return createResponse({ success: true, client_id: newClient.id }, 200)
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error)
    const errorStack = error instanceof Error ? error.stack : undefined
    
    console.error("[FATAL PROVISIONING ERROR]", errorMessage)
    if (errorStack) {
      console.error("[FATAL PROVISIONING ERROR] Stack:", errorStack)
    }
    
    // Essayer de mettre à jour le job si on a un job_id
    if (job_id) {
      try {
        const supabaseUrl = Deno.env.get("SUPABASE_URL")
        const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
        
        if (supabaseUrl && supabaseServiceKey) {
          const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
            auth: { autoRefreshToken: false, persistSession: false },
          })
          
          await supabaseAdmin
            .from("provisioning_jobs")
            .update({
              status: "failed",
              error_message: `Erreur fatale: ${errorMessage}`,
              error_step: "fatal_error",
              completed_at: new Date().toISOString(),
            })
            .eq("id", job_id)
            .catch((updateError) => {
              console.error("[FATAL] Impossible de mettre à jour le job:", updateError)
            })
        }
      } catch (updateError) {
        console.error("[FATAL] Erreur lors de la mise à jour du job:", updateError)
      }
    }
    
    return createResponse(
      { 
        error: "Erreur interne du serveur",
        message: errorMessage,
        details: "Consultez les logs de l'Edge Function pour plus d'informations"
      },
      500
    )
  }
})
