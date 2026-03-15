"use server"

import { revalidatePath } from "next/cache"
import { createClient } from "@/lib/supabase/server"
import { z } from "zod"
import type { Profile, StorageBucketConfig, EnvVarTemplate } from "@/types"

// ─── Schémas de validation ──────────────────────────────────────────────────

const createMemberSchema = z.object({
  email: z.string().email("Format d'email invalide"),
  password: z.string().min(8, "Le mot de passe doit contenir au moins 8 caractères"),
  full_name: z.string().min(2, "Le nom doit contenir au moins 2 caractères").max(100),
  role: z.enum(["admin", "viewer"]),
})

const deleteMemberSchema = z.object({
  user_id: z.string().uuid("ID utilisateur invalide"),
})

const updateRoleSchema = z.object({
  user_id: z.string().uuid("ID utilisateur invalide"),
  role: z.enum(["admin", "viewer"]),
})

// ─── Helper : récupérer le token de session courant ─────────────────────────

async function getSessionToken(): Promise<string | null> {
  const supabase = await createClient()
  const { data: { session } } = await supabase.auth.getSession()
  return session?.access_token ?? null
}

// ─── Helper : appeler l'Edge Function manage-team ───────────────────────────

async function callManageTeam(
  token: string,
  body: Record<string, unknown>
): Promise<{ success?: boolean; message?: string; error?: string }> {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!

  const res = await fetch(`${supabaseUrl}/functions/v1/manage-team`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
      apikey: supabaseAnonKey,
    },
    body: JSON.stringify(body),
  })

  return res.json()
}

// ─── Action : Créer un membre ────────────────────────────────────────────────

export async function createMember(formData: FormData) {
  const parsed = createMemberSchema.safeParse({
    email: formData.get("email"),
    password: formData.get("password"),
    full_name: formData.get("full_name"),
    role: formData.get("role"),
  })

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Données invalides" }
  }

  const token = await getSessionToken()
  if (!token) return { error: "Non authentifié" }

  const result = await callManageTeam(token, {
    action: "create_member",
    ...parsed.data,
  })

  if (result.error) return { error: result.error }

  revalidatePath("/settings")
  return { success: true, message: result.message }
}

// ─── Action : Supprimer un membre ───────────────────────────────────────────

export async function deleteMember(formData: FormData) {
  const parsed = deleteMemberSchema.safeParse({
    user_id: formData.get("user_id"),
  })

  if (!parsed.success) return { error: "ID invalide" }

  const token = await getSessionToken()
  if (!token) return { error: "Non authentifié" }

  const result = await callManageTeam(token, {
    action: "delete_member",
    user_id: parsed.data.user_id,
  })

  if (result.error) return { error: result.error }

  revalidatePath("/settings")
  return { success: true, message: result.message }
}

// ─── Action : Changer le rôle d'un membre ───────────────────────────────────

export async function updateMemberRole(formData: FormData) {
  const parsed = updateRoleSchema.safeParse({
    user_id: formData.get("user_id"),
    role: formData.get("role"),
  })

  if (!parsed.success) return { error: "Données invalides" }

  const token = await getSessionToken()
  if (!token) return { error: "Non authentifié" }

  const result = await callManageTeam(token, {
    action: "update_role",
    user_id: parsed.data.user_id,
    role: parsed.data.role,
  })

  if (result.error) return { error: result.error }

  revalidatePath("/settings")
  return { success: true, message: result.message }
}

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

// ─── Action : Mettre à jour un template (champs généraux) ───────────────────

export async function updateTemplate(data: {
  templateId: string
  name?: string
  description?: string
  github_template_owner?: string
  github_template_repo?: string
  github_migrations_path?: string
  default_supabase_plan?: string
  default_supabase_region?: string
  vercel_framework?: string
  vercel_build_command?: string | null
  vercel_output_directory?: string | null
  is_active?: boolean
}) {
  const { supabase } = await requireAdmin()

  const { templateId, ...updateData } = data

  // Filtrer les undefined
  const cleanData = Object.fromEntries(
    Object.entries(updateData).filter(([, v]) => v !== undefined)
  )

  if (Object.keys(cleanData).length === 0) {
    return { error: "Aucune modification" }
  }

  const { error } = await supabase
    .from("project_templates")
    .update(cleanData)
    .eq("id", templateId)

  if (error) {
    console.error("Error updating template:", error.message)
    return { error: error.message }
  }

  revalidatePath("/settings")
  return { success: true }
}

// ─── Action : Mettre à jour les storage buckets d'un template ───────────────

export async function updateTemplateBuckets(
  templateId: string,
  buckets: StorageBucketConfig[]
) {
  const { supabase } = await requireAdmin()

  const { error } = await supabase
    .from("project_templates")
    .update({ storage_buckets: buckets })
    .eq("id", templateId)

  if (error) {
    console.error("Error updating buckets:", error.message)
    return { error: error.message }
  }

  revalidatePath("/settings")
  return { success: true }
}

// ─── Action : Mettre à jour les env vars template ───────────────────────────

export async function updateTemplateEnvVars(
  templateId: string,
  envVars: EnvVarTemplate[]
) {
  const { supabase } = await requireAdmin()

  const { error } = await supabase
    .from("project_templates")
    .update({ env_vars_template: envVars })
    .eq("id", templateId)

  if (error) {
    console.error("Error updating env vars:", error.message)
    return { error: error.message }
  }

  revalidatePath("/settings")
  return { success: true }
}
