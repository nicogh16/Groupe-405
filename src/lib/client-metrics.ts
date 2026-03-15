import { createClient } from "@/lib/supabase/server"
import type { Client, ClientMetrics } from "@/types"

/**
 * Récupère les métriques d'un client via l'Edge Function Supabase.
 *
 * Architecture sécurisée :
 * - Le service_role_key du client est déchiffré DANS Supabase (jamais dans Next.js)
 * - Les appels aux APIs externes se font depuis l'Edge Function interne
 * - Aucune clé sensible ne transite par le code Next.js
 */
export async function fetchClientMetrics(
  clientId: string,
  saveSnapshot = false
): Promise<ClientMetrics | null> {
  try {
    const supabase = await createClient()

    const { data, error } = await supabase.functions.invoke(
      "fetch-client-metrics",
      {
        body: {
          client_id: clientId,
          save_snapshot: saveSnapshot,
        },
      }
    )

    if (error) {
      console.error(`Edge Function error for client ${clientId}:`, error.message)
      return null
    }

    if (!data?.success || !data?.metrics) {
      console.error(`No metrics returned for client ${clientId}:`, data?.error)
      return null
    }

    return data.metrics as ClientMetrics
  } catch (err) {
    console.error(`Failed to fetch metrics for client ${clientId}:`, err)
    return null
  }
}
