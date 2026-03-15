import { z } from "zod"

export const updateRevenueSchema = z.object({
  clientId: z.string().uuid("ID client invalide"),
  monthlyRevenue: z
    .number()
    .min(0, "Le revenu ne peut pas être négatif")
    .max(1_000_000, "Valeur trop élevée"),
})

export const updateNotesSchema = z.object({
  clientId: z.string().uuid("ID client invalide"),
  notes: z.string().max(5000, "Notes trop longues"),
})

export const createClientSchema = z.object({
  appId: z.string().uuid("ID app invalide"),
  name: z
    .string()
    .min(2, "Le nom doit contenir au moins 2 caractères")
    .max(100, "Nom trop long"),
  slug: z
    .string()
    .min(2, "Le slug doit contenir au moins 2 caractères")
    .max(50, "Slug trop long")
    .regex(/^[a-z0-9-]+$/, "Le slug ne peut contenir que des lettres minuscules, chiffres et tirets"),
  supabaseProjectRef: z.string().optional(),
  supabaseUrl: z.string().url("URL invalide").optional().or(z.literal("")),
  supabaseServiceRoleKey: z.string().optional(),
  supabasePlan: z.enum(["free", "pro", "team", "enterprise"]).default("free"),
  monthlyRevenue: z.number().min(0).default(0),
  vercelProjectUrl: z.string().url("URL invalide").optional().or(z.literal("")),
  githubRepoUrl: z.string().url("URL invalide").optional().or(z.literal("")),
})

export const createExpenseSchema = z.object({
  clientId: z.string().uuid("ID client invalide"),
  description: z.string().min(1, "La description est requise").max(200, "Description trop longue"),
  amount: z.number().min(0.01, "Le montant doit être supérieur à 0"),
  category: z.string().max(50, "Catégorie trop longue").nullable(),
  expenseDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Date invalide"),
  isRecurring: z.boolean().default(false),
  recurringFrequency: z.enum(["monthly", "yearly"]).nullable(),
  notes: z.string().max(1000, "Notes trop longues").nullable(),
})

export const updateExpenseSchema = createExpenseSchema.extend({
  expenseId: z.string().uuid("ID dépense invalide"),
})

export const deleteExpenseSchema = z.object({
  expenseId: z.string().uuid("ID dépense invalide"),
  clientId: z.string().uuid("ID client invalide"),
})

export type UpdateRevenueData = z.infer<typeof updateRevenueSchema>
export type UpdateNotesData = z.infer<typeof updateNotesSchema>
export type CreateClientData = z.infer<typeof createClientSchema>
export type CreateExpenseData = z.infer<typeof createExpenseSchema>
export type UpdateExpenseData = z.infer<typeof updateExpenseSchema>
export type DeleteExpenseData = z.infer<typeof deleteExpenseSchema>
