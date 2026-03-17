"use server"

import { revalidatePath } from "next/cache"
import { createClient } from "@/lib/supabase/server"
import { provisionClientSchema } from "@/lib/validations/provisioning"
import { PROVISIONING_STEPS } from "@/lib/validations/provisioning"
import type { Profile } from "@/types"

// ─── Helper : vérifier admin ────────────────────────────────────────────────

async function requireAdmin() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) throw new Error("Non authentifié")

  const { data: profile } = await supabase
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .single()

  if ((profile as Profile | null)?.role !== "admin") {
    throw new Error("Accès refusé")
  }

  return { user, supabase }
}

// ─── Helper : récupérer le token de session ─────────────────────────────────

async function getSessionToken(): Promise<string | null> {
  const supabase = await createClient()
  const {
    data: { session },
  } = await supabase.auth.getSession()
  return session?.access_token ?? null
}

// ─── Action : Lancer le provisionnement d'un nouveau client ─────────────────

export async function startProvisioning(formData: FormData) {
  const { user, supabase } = await requireAdmin()

  const parsed = provisionClientSchema.safeParse({
    templateId: formData.get("templateId"),
    clientName: formData.get("clientName"),
    clientSlug: formData.get("clientSlug"),
    supabasePlan: formData.get("supabasePlan") || "free",
    supabaseRegion: formData.get("supabaseRegion") || "ca-central-1",
    monthlyRevenue: parseFloat(formData.get("monthlyRevenue") as string) || 0,
    githubRepoName: formData.get("githubRepoName") || undefined,
    vercelProjectName: formData.get("vercelProjectName") || undefined,
  })

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Données invalides",
    }
  }

  // Vérifier que le slug n'est pas déjà pris
  const { data: existingClient } = await supabase
    .from("clients")
    .select("id")
    .eq("slug", parsed.data.clientSlug)
    .maybeSingle()

  if (existingClient) {
    return { error: "Ce slug est déjà utilisé par un autre client" }
  }

  // Vérifier que le template existe
  const { data: template } = await supabase
    .from("project_templates")
    .select("id, app_id")
    .eq("id", parsed.data.templateId)
    .single()

  if (!template) {
    return { error: "Template introuvable" }
  }

  // Créer le job avec les steps initiales
  const initialSteps = PROVISIONING_STEPS.map((s) => ({
    id: s.id,
    label: s.label,
    status: "pending" as const,
  }))

  const { data: job, error: jobError } = await supabase
    .from("provisioning_jobs")
    .insert({
      client_name: parsed.data.clientName,
      client_slug: parsed.data.clientSlug,
      app_id: template.app_id,
      template_id: parsed.data.templateId,
      supabase_plan: parsed.data.supabasePlan,
      supabase_region: parsed.data.supabaseRegion,
      monthly_revenue: parsed.data.monthlyRevenue,
      status: "pending",
      steps: initialSteps,
      created_by: user.id,
    })
    .select("id")
    .single()

  if (jobError || !job) {
    console.error("Error creating provisioning job:", jobError?.message)
    return {
      error: jobError?.message || "Erreur lors de la création du job",
    }
  }

  // Lancer l'Edge Function en arrière-plan (fire-and-forget)
  // Utiliser fetch directement avec le token pour garantir l'authentification
  const sessionToken = await getSessionToken()
  if (!sessionToken) {
    return { error: "Non authentifié" }
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!

  fetch(`${supabaseUrl}/functions/v1/provision-client`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${sessionToken}`,
      apikey: supabaseAnonKey,
    },
    body: JSON.stringify({ job_id: job.id }),
  })
    .then(async (res) => {
      if (!res.ok) {
        let errorText = ""
        try {
          const errorData = await res.json()
          errorText = errorData.error || errorData.message || JSON.stringify(errorData)
        } catch {
          errorText = await res.text().catch(() => res.statusText)
        }
        
        let errorMessage = `Erreur ${res.status}: ${errorText}`
        
        if (res.status === 401) {
          errorMessage = "Erreur d'authentification (401). Vérifiez que vous êtes bien connecté."
        } else if (res.status === 503) {
          errorMessage = "Edge Function non disponible (503). Vérifiez que la fonction 'provision-client' est déployée et que tous les secrets sont configurés."
        } else if (res.status === 404) {
          // Ne pas mettre à jour le job si c'est juste un 404 de l'appel initial
          // L'Edge Function peut retourner 404 pour d'autres raisons (job introuvable, etc.)
          if (errorText.includes("job_id") || errorText.includes("Job introuvable")) {
            errorMessage = `Job introuvable: ${errorText}`
          } else {
            errorMessage = "Edge Function introuvable (404). La fonction 'provision-client' n'est pas déployée."
          }
        }
        
        console.error("Error invoking provision-client:", res.status, errorMessage)
        
        // Mettre à jour le job avec l'erreur seulement si ce n'est pas un 404 de l'Edge Function elle-même
        // (car si l'Edge Function n'est pas déployée, on ne peut pas mettre à jour le job)
        if (res.status !== 404 || errorText.includes("job_id") || errorText.includes("Job introuvable")) {
          try {
            await supabase
              .from("provisioning_jobs")
              .update({
                status: "failed",
                error_message: errorMessage,
                error_step: "edge_function_invoke",
                completed_at: new Date().toISOString(),
              })
              .eq("id", job.id)
          } catch (err) {
            console.error("Erreur lors de la mise à jour du job:", err)
          }
        }
      } else {
        const data = await res.json().catch(() => ({}))
        console.log("Provision-client invoqué avec succès:", data)
        // Ne pas mettre à jour le job ici car l'Edge Function le fait elle-même
      }
    })
    .catch(async (err) => {
      console.error("Failed to trigger provision-client:", err)
      
      let errorMessage = "Impossible de lancer l'Edge Function"
      const errMessage = err?.message || String(err)
      
      // Détecter les erreurs réseau ou de connexion
      if (errMessage.includes("Failed to fetch") || errMessage.includes("NetworkError") || errMessage.includes("fetch")) {
        errorMessage = "Erreur de connexion à l'Edge Function. Vérifiez que la fonction 'provision-client' est déployée et accessible."
      } else if (errMessage.includes("503") || errMessage.includes("Service Unavailable")) {
        errorMessage = "Edge Function non disponible (503). Vérifiez que la fonction 'provision-client' est déployée et que tous les secrets sont configurés."
      } else if (errMessage.includes("404") || errMessage.includes("Not Found")) {
        errorMessage = "Edge Function introuvable (404). La fonction 'provision-client' n'est pas déployée."
      } else if (errMessage) {
        errorMessage = `Erreur: ${errMessage}`
      }
      
      // Mettre à jour le job avec l'erreur
      try {
        await supabase
          .from("provisioning_jobs")
          .update({
            status: "failed",
            error_message: errorMessage,
            error_step: "edge_function_invoke",
            completed_at: new Date().toISOString(),
          })
          .eq("id", job.id)
      } catch (updateErr) {
        console.error("Erreur lors de la mise à jour du job:", updateErr)
      }
    })

  // Audit log
  await supabase.from("audit_log").insert({
    user_id: user.id,
    action: "provisioning_started",
    details: {
      job_id: job.id,
      client_name: parsed.data.clientName,
      client_slug: parsed.data.clientSlug,
      template_id: parsed.data.templateId,
    },
  })

  revalidatePath("/clients")
  return { success: true, jobId: job.id }
}

// ─── Action : Restaurer un projet Supabase directement (sans Edge Function) ───

export async function restoreProjectDirectly(formData: FormData) {
  const { user, supabase } = await requireAdmin()

  const projectRef = formData.get("projectRef") as string
  const dbPassword = formData.get("dbPassword") as string
  const useMyFidelityTemplate = formData.get("useMyFidelityTemplate") === "true"

  if (!projectRef) {
    return { error: "Project ref requis" }
  }

  if (!dbPassword) {
    return { error: "Mot de passe de la base de données requis" }
  }

  try {
    // Lire le fichier SQL template
    const templateFileName = useMyFidelityTemplate 
      ? "supabase_new_project.sql"
      : "supabase-template-zdicqtupwckhvxhlkiuf.sql"

    // Lire depuis Storage Supabase avec service role key
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
    const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY

    if (!supabaseUrl || !supabaseServiceKey) {
      return { 
        error: "SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY doivent être configurés dans les variables d'environnement" 
      }
    }

    // Créer un client avec service role key pour accéder au Storage
    const { createClient: createSupabaseClient } = await import("@supabase/supabase-js")
    const storageClient = createSupabaseClient(supabaseUrl, supabaseServiceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    const { data: fileData, error: storageError } = await storageClient
      .storage
      .from("templates")
      .download(templateFileName)

    if (storageError || !fileData) {
      return { 
        error: `Fichier template introuvable dans Storage: ${templateFileName}. ${storageError?.message || ""}. Assurez-vous que le fichier est uploadé dans le bucket "templates".` 
      }
    }

    // Convertir le Blob en texte
    const templateSQL = await fileData.text()

    // Construire la connection string
    const connectionString = `postgresql://postgres:${encodeURIComponent(dbPassword)}@db.${projectRef}.supabase.co:5432/postgres`

    return await executeRestore(projectRef, connectionString, templateSQL, supabase)
  } catch (error) {
    console.error("Erreur lors de la restauration:", error)
    return { 
      error: error instanceof Error ? error.message : "Erreur inconnue lors de la restauration" 
    }
  }
}

// Parser SQL identique à celui de l'Edge Function pour diviser en statements
function parseSQLStatements(sql: string): string[] {
  const statements: string[] = []
  let current = ""
  let inString = false
  let inDollarQuote = false
  let inDoBlock = false
  let inFunction = false
  let stringChar = ""
  let dollarTag = ""
  let functionDollarTag = ""

  for (let i = 0; i < sql.length; i++) {
    const char = sql[i]
    const nextChar = sql[i + 1]
    const prevChar = i > 0 ? sql[i - 1] : ''

    // Détecter le début d'une fonction PostgreSQL (CREATE FUNCTION ... AS $$ ... $$)
    if (!inString && !inDollarQuote && !inDoBlock && !inFunction) {
      const remaining = sql.substring(i).toLowerCase()
      if (remaining.match(/^\s*create\s+(or\s+replace\s+)?function\s+/)) {
        const fullRemaining = sql.substring(i)
        const asMatch = fullRemaining.match(/as\s+(\$[^$\s]*\$)/is)
        if (asMatch) {
          inFunction = true
          functionDollarTag = asMatch[1]
          current += char
          i++
          continue
        } else {
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

    // Gérer le corps d'une fonction PostgreSQL
    if (inFunction) {
      current += char

      if (sql.substring(i).startsWith(functionDollarTag)) {
        let tagCount = 0
        let searchPos = 0
        while ((searchPos = current.indexOf(functionDollarTag, searchPos)) !== -1) {
          tagCount++
          searchPos += functionDollarTag.length
        }

        if (tagCount >= 2) {
          i += functionDollarTag.length - 1
          const afterTag = sql.substring(i + 1).trim()

          if (afterTag.match(/^\s*language\s+/i)) {
            const langMatch = afterTag.match(/language\s+\w+\s*;/is)
            if (langMatch) {
              inFunction = false
              functionDollarTag = ""
              i += langMatch[0].length - 1
            } else {
              i++
              continue
            }
          } else if (afterTag.startsWith(';') || afterTag.match(/^\s*;\s*$/m)) {
            inFunction = false
            functionDollarTag = ""
          } else {
            inFunction = false
            functionDollarTag = ""
          }
        } else {
          i++
          continue
        }
      }

      i++
      continue
    }

    // Détecter le début d'un bloc DO $$ ... $$
    if (!inString && !inDollarQuote && !inDoBlock && !inFunction) {
      const remaining = sql.substring(i).toLowerCase()
      if (remaining.match(/^\s*do\s+\$/)) {
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

      if (sql.substring(i).startsWith(dollarTag)) {
        if (current.length > dollarTag.length) {
          inDoBlock = false
          dollarTag = ""
          i += dollarTag.length - 1
        }
      }

      i++
      continue
    }

    // Gérer les dollar-quoted strings ($$...$$, $tag$...$tag$)
    if (!inString && !inDollarQuote && char === '$') {
      const remaining = sql.substring(i)
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
      if (char === stringChar && sql[i - 1] === '\\') {
        i++
        continue
      }
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

    // Détecter la fin d'un statement
    if (char === ';' && !inFunction && !inDoBlock) {
      const afterSemicolon = sql.substring(i + 1).trim()
      const isEndOfStatement =
        afterSemicolon === '' ||
        afterSemicolon.startsWith('\n') ||
        afterSemicolon.startsWith('--') ||
        afterSemicolon.match(/^\s*(create|alter|drop|insert|update|delete|select|with|do)\s+/i)

      if (isEndOfStatement) {
        current += char
        const trimmed = current.trim()
        if (trimmed.length > 0 && trimmed !== ';' && !trimmed.match(/^--/)) {
          statements.push(trimmed)
        }
        current = ""
        i++
        while (i < sql.length && (sql[i] === ' ' || sql[i] === '\t' || sql[i] === '\n' || sql[i] === '\r')) {
          i++
        }
        continue
      }
    }

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

async function executeRestore(
  projectRef: string | null,
  connectionString: string | null,
  templateSQL: string,
  supabase: any
) {
  if (!connectionString) {
    return { error: "Connection string requise" }
  }

  try {
    // Utiliser pg (node-postgres) pour exécuter le SQL directement
    // Comme psql -f, on divise en statements et on les exécute un par un
    const { Client } = await import("pg")
    
    const client = new Client({
      connectionString: connectionString,
    })

    await client.connect()
    console.log(`[RESTORE] Connecté à la base de données ${projectRef}`)

    // Parser le SQL en statements (comme psql -f le fait)
    const statements = parseSQLStatements(templateSQL)
    console.log(`[RESTORE] ${statements.length} statements à exécuter`)

    // Exécuter chaque statement un par un
    let executed = 0
    for (let i = 0; i < statements.length; i++) {
      const statement = statements[i]
      if (!statement.trim()) continue

      try {
        // Afficher la progression tous les 100 statements
        if (i % 100 === 0) {
          console.log(`[RESTORE] Exécution du statement ${i + 1}/${statements.length}...`)
        }

        await client.query(statement)
        executed++
      } catch (stmtError) {
        const errorMsg = stmtError instanceof Error ? stmtError.message : String(stmtError)
        console.error(`[RESTORE] Erreur au statement ${i + 1}/${statements.length}:`, errorMsg)
        console.error(`[RESTORE] Statement problématique (premiers 200 caractères):`, statement.substring(0, 200))
        
        await client.end()
        return {
          error: `Erreur au statement ${i + 1}/${statements.length}: ${errorMsg}`
        }
      }
    }

    await client.end()
    console.log(`[RESTORE] Restauration terminée avec succès (${executed} statements exécutés)`)

    return {
      success: true,
      message: `Restauration terminée avec succès ! (${executed} statements exécutés)`
    }
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error)
    console.error(`[RESTORE] Erreur:`, errorMessage)
    return {
      error: `Erreur lors de la restauration: ${errorMessage}`
    }
  }
}

// ─── Action : Récupérer le status d'un job ──────────────────────────────────

export async function getProvisioningJobStatus(jobId: string) {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) return { error: "Non authentifié" }

  const { data: job, error } = await supabase
    .from("provisioning_jobs")
    .select("*")
    .eq("id", jobId)
    .single()

  if (error || !job) {
    return { error: "Job introuvable" }
  }

  return { job }
}

// ─── Action : Lister les templates actifs ───────────────────────────────────

export async function getActiveTemplates() {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) return { error: "Non authentifié", templates: [] }

  const { data: templates, error } = await supabase
    .from("project_templates")
    .select("*, app:apps(*)")
    .eq("is_active", true)
    .order("name")

  if (error) {
    return { error: error.message, templates: [] }
  }

  return { templates: templates ?? [] }
}

// ─── Action : Annuler/Supprimer un job de provisionnement ────────────────────

export async function cancelProvisioningJob(jobId: string) {
  const { user, supabase } = await requireAdmin()

  // Vérifier que le job existe et récupérer le supabase_project_ref
  const { data: job, error: jobError } = await supabase
    .from("provisioning_jobs")
    .select("id, status, client_id, supabase_project_ref")
    .eq("id", jobId)
    .single()

  if (jobError || !job) {
    return { error: "Job introuvable" }
  }

  // Si le job est terminé et a créé un client, on ne peut pas le supprimer
  if (job.status === "completed" && job.client_id) {
    return { error: "Impossible de supprimer un job terminé qui a créé un client" }
  }

  // Si le job est en cours, on le marque comme annulé et on supprime le projet Supabase s'il existe
  if (job.status === "running") {
    // Supprimer le projet Supabase s'il existe
    if (job.supabase_project_ref) {
      try {
        const accessToken = process.env.ACCESS_TOKEN
        
        if (accessToken) {
          const deleteProjectRes = await fetch(
            `https://api.supabase.com/v1/projects/${job.supabase_project_ref}`,
            {
              method: "DELETE",
              headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${accessToken}`,
              },
            }
          )

          if (deleteProjectRes.ok) {
            console.log(`✅ Projet Supabase ${job.supabase_project_ref} supprimé avec succès`)
          } else {
            const errorText = await deleteProjectRes.text()
            console.warn(`⚠️ Échec suppression projet Supabase ${job.supabase_project_ref}: ${deleteProjectRes.status} - ${errorText}`)
          }
        } else {
          console.warn(`⚠️ Token Supabase (ACCESS_TOKEN) non configuré, impossible de supprimer le projet Supabase ${job.supabase_project_ref}`)
        }
      } catch (error) {
        console.error(`❌ Erreur lors de la suppression du projet Supabase ${job.supabase_project_ref}:`, error)
      }
    }

    const { error: updateError } = await supabase
      .from("provisioning_jobs")
      .update({
        status: "cancelled",
        error_message: "Annulé par l'utilisateur",
        completed_at: new Date().toISOString(),
      })
      .eq("id", jobId)

    if (updateError) {
      return { error: updateError.message }
    }

    // Audit log
    await supabase.from("audit_log").insert({
      user_id: user.id,
      action: "provisioning_job_cancelled",
      details: { 
        job_id: jobId,
        supabase_project_ref: job.supabase_project_ref || null,
      },
    })

    revalidatePath("/clients")
    return { success: true, message: "Job annulé" }
  }

  // Avant de supprimer le job, supprimer le projet Supabase s'il existe
  if (job.supabase_project_ref) {
    try {
      // Récupérer le token d'accès Supabase depuis les variables d'environnement
      // Note: On utilise le même token que celui utilisé par l'Edge Function (ACCESS_TOKEN)
      // Cette variable doit être dans .env.local côté serveur Next.js
      const accessToken = process.env.ACCESS_TOKEN
      
      if (!accessToken) {
        console.warn(`⚠️ Token Supabase (ACCESS_TOKEN) non configuré dans .env.local, impossible de supprimer le projet Supabase ${job.supabase_project_ref}`)
        // On continue quand même la suppression du job
      } else {
        // Supprimer le projet Supabase via l'API Management
        const deleteProjectRes = await fetch(
          `https://api.supabase.com/v1/projects/${job.supabase_project_ref}`,
          {
            method: "DELETE",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${accessToken}`,
            },
          }
        )

        if (deleteProjectRes.ok) {
          console.log(`✅ Projet Supabase ${job.supabase_project_ref} supprimé avec succès`)
        } else {
          const errorText = await deleteProjectRes.text()
          console.warn(`⚠️ Échec suppression projet Supabase ${job.supabase_project_ref}: ${deleteProjectRes.status} - ${errorText}`)
          // On continue quand même la suppression du job même si la suppression du projet a échoué
        }
      }
    } catch (error) {
      console.error(`❌ Erreur lors de la suppression du projet Supabase ${job.supabase_project_ref}:`, error)
      // On continue quand même la suppression du job même si la suppression du projet a échoué
    }
  }

  // Supprimer le job complètement
  const { error: deleteError } = await supabase.from("provisioning_jobs").delete().eq("id", jobId)

  if (deleteError) {
    return { error: deleteError.message }
  }

  // Audit log
  await supabase.from("audit_log").insert({
    user_id: user.id,
    action: "provisioning_job_deleted",
    details: { 
      job_id: jobId,
      supabase_project_ref: job.supabase_project_ref || null,
    },
  })

  revalidatePath("/clients")
  return { success: true, message: "Job supprimé" }
}

// ─── Action : Relancer un job bloqué ──────────────────────────────────────────

export async function retryProvisioningJob(jobId: string) {
  const { user, supabase } = await requireAdmin()

  // Vérifier que le job existe et est en pending ou failed
  const { data: job, error: jobError } = await supabase
    .from("provisioning_jobs")
    .select("id, status, client_id")
    .eq("id", jobId)
    .single()

  if (jobError || !job) {
    return { error: "Job introuvable" }
  }

  if (job.status === "running") {
    return { error: "Le job est déjà en cours" }
  }

  if (job.status === "completed" && job.client_id) {
    return { error: "Le job est déjà terminé avec succès" }
  }

  // Relancer l'Edge Function
  supabase.functions
    .invoke("provision-client", {
      body: { job_id: jobId },
    })
    .then((result) => {
      if (result.error) {
        console.error("Error invoking provision-client:", result.error)
        supabase
          .from("provisioning_jobs")
          .update({
            status: "failed",
            error_message: result.error.message || "Erreur lors du relancement",
            completed_at: new Date().toISOString(),
          })
          .eq("id", jobId)
      } else {
        console.log("Provision-client relancé avec succès")
      }
    })
    .catch((err) => {
      console.error("Failed to retry provision-client:", err)
      supabase
        .from("provisioning_jobs")
        .update({
          status: "failed",
          error_message: err.message || "Impossible de relancer l'Edge Function",
          completed_at: new Date().toISOString(),
        })
        .eq("id", jobId)
    })

  // Audit log
  await supabase.from("audit_log").insert({
    user_id: user.id,
    action: "provisioning_job_retried",
    details: { job_id: jobId },
  })

  revalidatePath("/clients")
  return { success: true, message: "Relance du job en cours..." }
}
