import { z } from "zod"

export const provisionClientSchema = z.object({
  templateId: z.string().uuid("ID template invalide"),
  clientName: z
    .string()
    .min(2, "Le nom doit contenir au moins 2 caractères")
    .max(100, "Nom trop long")
    .trim(),
  clientSlug: z
    .string()
    .min(2, "Le slug doit contenir au moins 2 caractères")
    .max(50, "Slug trop long")
    .regex(
      /^[a-z0-9-]+$/,
      "Le slug ne peut contenir que des lettres minuscules, chiffres et tirets"
    )
    .trim(),
  supabasePlan: z.enum(["free", "pro", "team", "enterprise"]).default("free"),
  supabaseRegion: z.string().default("ca-central-1"),
  monthlyRevenue: z.number().min(0, "Le revenu ne peut pas être négatif").default(0),
  githubRepoName: z
    .string()
    .min(2, "Le nom du repo doit contenir au moins 2 caractères")
    .max(100, "Nom du repo trop long")
    .regex(
      /^[a-zA-Z0-9._-]+$/,
      "Le nom du repo ne peut contenir que des lettres, chiffres, points, tirets et underscores"
    )
    .optional(),
  vercelProjectName: z
    .string()
    .min(2, "Le nom du projet Vercel doit contenir au moins 2 caractères")
    .max(100, "Nom trop long")
    .regex(
      /^[a-z0-9-]+$/,
      "Le nom du projet Vercel ne peut contenir que des lettres minuscules, chiffres et tirets"
    )
    .optional(),
})

export const updateTemplateSchema = z.object({
  templateId: z.string().uuid("ID template invalide"),
  githubTemplateOwner: z.string().min(1).optional(),
  githubTemplateRepo: z.string().min(1).optional(),
  defaultSupabasePlan: z.enum(["free", "pro", "team", "enterprise"]).optional(),
  defaultSupabaseRegion: z.string().optional(),
  description: z.string().max(500).optional(),
})

export type ProvisionClientData = z.infer<typeof provisionClientSchema>
export type UpdateTemplateData = z.infer<typeof updateTemplateSchema>

// Regions Supabase disponibles
export const SUPABASE_REGIONS = [
  { value: "ca-central-1", label: "Canada (Montréal)" },
  { value: "us-east-1", label: "États-Unis (Virginie)" },
  { value: "us-west-1", label: "États-Unis (Californie)" },
  { value: "eu-west-1", label: "Europe (Irlande)" },
  { value: "eu-west-2", label: "Europe (Londres)" },
  { value: "eu-central-1", label: "Europe (Francfort)" },
  { value: "ap-southeast-1", label: "Asie (Singapour)" },
  { value: "ap-northeast-1", label: "Asie (Tokyo)" },
  { value: "ap-south-1", label: "Asie (Mumbai)" },
  { value: "sa-east-1", label: "Amérique du Sud (São Paulo)" },
] as const

// Étapes du provisionnement (pour l'UI)
// Le workflow actuel: Edge Function => migrations SQL,
// puis worker Next.js => déploiement des Edge Functions + création du client.
export const PROVISIONING_STEPS = [
  { id: "create_supabase", label: "Création du projet Supabase" },
  { id: "wait_supabase", label: "Attente de l'initialisation Supabase" },
  { id: "fetch_migrations", label: "Récupération des migrations SQL" },
  { id: "apply_migrations", label: "Application du schéma SQL" },
  { id: "deploy_edge_functions", label: "Installation des Edge Functions" },
  { id: "register_client", label: "Création du client dans le dashboard" },
] as const
