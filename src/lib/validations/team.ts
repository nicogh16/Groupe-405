import { z } from "zod"

export const inviteUserSchema = z.object({
  email: z
    .string()
    .min(1, "L'email est requis")
    .email("Format d'email invalide"),
  fullName: z
    .string()
    .min(2, "Le nom doit contenir au moins 2 caractères")
    .max(100, "Nom trop long"),
  role: z.enum(["admin", "viewer"]),
})

export const updateMemberRoleSchema = z.object({
  userId: z.string().uuid("ID utilisateur invalide"),
  role: z.enum(["admin", "viewer"]),
})

export type InviteUserData = z.infer<typeof inviteUserSchema>
export type UpdateMemberRoleData = z.infer<typeof updateMemberRoleSchema>
