"use server"

import { revalidatePath } from "next/cache"
import { createClient } from "@/lib/supabase/server"
import {
  updateRevenueSchema,
  updateNotesSchema,
  createExpenseSchema,
  updateExpenseSchema,
  deleteExpenseSchema,
} from "@/lib/validations/clients"
import type { Profile } from "@/types"

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

export async function updateRevenue(formData: FormData) {
  const { user, supabase } = await requireAdmin()

  const parsed = updateRevenueSchema.safeParse({
    clientId: formData.get("clientId") as string,
    monthlyRevenue: parseFloat(formData.get("monthlyRevenue") as string),
  })

  if (!parsed.success) {
    return { error: "Données invalides" }
  }

  // RLS policy "Enable update for admin users only" autorise cette opération
  const { error } = await supabase
    .from("clients")
    .update({ monthly_revenue: parsed.data.monthlyRevenue })
    .eq("id", parsed.data.clientId)

  if (error) {
    return { error: "Erreur lors de la mise à jour" }
  }

  // Audit log — RLS policy "Enable insert for all authenticated users"
  await supabase.from("audit_log").insert({
    user_id: user.id,
    action: "revenue_updated",
    target_client_id: parsed.data.clientId,
    details: { monthly_revenue: parsed.data.monthlyRevenue },
  })

  revalidatePath("/")
  revalidatePath("/costs")
  revalidatePath(`/clients/${parsed.data.clientId}`)
  return { success: true }
}

export async function updateNotes(formData: FormData) {
  const { user, supabase } = await requireAdmin()

  const parsed = updateNotesSchema.safeParse({
    clientId: formData.get("clientId") as string,
    notes: formData.get("notes") as string,
  })

  if (!parsed.success) {
    return { error: "Données invalides" }
  }

  const { error } = await supabase
    .from("clients")
    .update({ notes: parsed.data.notes })
    .eq("id", parsed.data.clientId)

  if (error) {
    return { error: "Erreur lors de la mise à jour" }
  }

  await supabase.from("audit_log").insert({
    user_id: user.id,
    action: "client_updated",
    target_client_id: parsed.data.clientId,
    details: { field: "notes" },
  })

  revalidatePath("/")
  return { success: true }
}

export async function createExpense(formData: FormData) {
  const { user, supabase } = await requireAdmin()

  const parsed = createExpenseSchema.safeParse({
    clientId: formData.get("clientId") as string,
    description: formData.get("description") as string,
    amount: parseFloat(formData.get("amount") as string),
    category: (formData.get("category") as string) || null,
    expenseDate: formData.get("expenseDate") as string,
    isRecurring: formData.get("isRecurring") === "true",
    recurringFrequency: (formData.get("recurringFrequency") as "monthly" | "yearly" | null) || null,
    notes: (formData.get("notes") as string) || null,
  })

  if (!parsed.success) {
    return { error: "Données invalides" }
  }

  const { error } = await supabase.from("expenses").insert({
    client_id: parsed.data.clientId,
    description: parsed.data.description,
    amount: parsed.data.amount,
    category: parsed.data.category,
    expense_date: parsed.data.expenseDate,
    is_recurring: parsed.data.isRecurring,
    recurring_frequency: parsed.data.recurringFrequency,
    notes: parsed.data.notes,
  })

  if (error) {
    return { error: "Erreur lors de la création de la dépense" }
  }

  await supabase.from("audit_log").insert({
    user_id: user.id,
    action: "expense_created",
    target_client_id: parsed.data.clientId,
    details: { description: parsed.data.description, amount: parsed.data.amount },
  })

  // Récupérer le slug du client pour revalidatePath
  const { data: client } = await supabase
    .from("clients")
    .select("slug")
    .eq("id", parsed.data.clientId)
    .single()

  if (client) {
    revalidatePath(`/clients/${client.slug}`)
  }
  return { success: true }
}

export async function updateExpense(formData: FormData, expenseId: string) {
  const { user, supabase } = await requireAdmin()

  const parsed = updateExpenseSchema.safeParse({
    expenseId,
    clientId: formData.get("clientId") as string,
    description: formData.get("description") as string,
    amount: parseFloat(formData.get("amount") as string),
    category: (formData.get("category") as string) || null,
    expenseDate: formData.get("expenseDate") as string,
    isRecurring: formData.get("isRecurring") === "true",
    recurringFrequency: (formData.get("recurringFrequency") as "monthly" | "yearly" | null) || null,
    notes: (formData.get("notes") as string) || null,
  })

  if (!parsed.success) {
    return { error: "Données invalides" }
  }

  const { error } = await supabase
    .from("expenses")
    .update({
      description: parsed.data.description,
      amount: parsed.data.amount,
      category: parsed.data.category,
      expense_date: parsed.data.expenseDate,
      is_recurring: parsed.data.isRecurring,
      recurring_frequency: parsed.data.recurringFrequency,
      notes: parsed.data.notes,
      updated_at: new Date().toISOString(),
    })
    .eq("id", expenseId)
    .eq("client_id", parsed.data.clientId)

  if (error) {
    return { error: "Erreur lors de la mise à jour de la dépense" }
  }

  await supabase.from("audit_log").insert({
    user_id: user.id,
    action: "expense_updated",
    target_client_id: parsed.data.clientId,
    details: { expense_id: expenseId, description: parsed.data.description },
  })

  // Récupérer le slug du client pour revalidatePath
  const { data: client } = await supabase
    .from("clients")
    .select("slug")
    .eq("id", parsed.data.clientId)
    .single()

  if (client) {
    revalidatePath(`/clients/${client.slug}`)
  }
  return { success: true }
}

export async function deleteExpense(formData: FormData) {
  const { user, supabase } = await requireAdmin()

  const parsed = deleteExpenseSchema.safeParse({
    expenseId: formData.get("expenseId") as string,
    clientId: formData.get("clientId") as string,
  })

  if (!parsed.success) {
    return { error: "Données invalides" }
  }

  const { error } = await supabase
    .from("expenses")
    .delete()
    .eq("id", parsed.data.expenseId)
    .eq("client_id", parsed.data.clientId)

  if (error) {
    return { error: "Erreur lors de la suppression de la dépense" }
  }

  await supabase.from("audit_log").insert({
    user_id: user.id,
    action: "expense_deleted",
    target_client_id: parsed.data.clientId,
    details: { expense_id: parsed.data.expenseId },
  })

  // Récupérer le slug du client pour revalidatePath
  const { data: client } = await supabase
    .from("clients")
    .select("slug")
    .eq("id", parsed.data.clientId)
    .single()

  if (client) {
    revalidatePath(`/clients/${client.slug}`)
  }
  return { success: true }
}
