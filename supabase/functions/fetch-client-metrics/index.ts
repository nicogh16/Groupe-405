import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "jsr:@supabase/supabase-js@2"

interface ClientInfo {
  client_id: string
  client_name: string
  supabase_url: string
  supabase_project_ref: string
  supabase_plan: string
  monthly_revenue: number
  decrypted_service_key: string
}

interface MetricsResult {
  registeredUsersCount: number
  databaseSizeBytes: number
  storageSizeBytes: number
  apiRequestsCount: number   // total 7 derniers jours (API publique Supabase)
  monthlyActiveUsers: number
  edgeFunctionInvocations: number  // toujours 0 — API publique indisponible
  realtimeMessages: number         // toujours 0 — API publique indisponible
  estimatedMonthlyCost: number
  storageUsagePercent: number
  mauUsagePercent: number
  databaseUsagePercent: number
  edgeFunctionUsagePercent: number
  realtimeUsagePercent: number
}

const PLAN_LIMITS: Record<string, any> = {
  free: {
    databaseSizeBytes: 500 * 1024 * 1024,
    storageSizeBytes: 1 * 1024 * 1024 * 1024,
    monthlyActiveUsers: 50_000,
    edgeFunctionInvocations: 500_000,
    realtimeMessages: 2_000_000,
    monthlyCostBase: 0,
  },
  pro: {
    databaseSizeBytes: 8 * 1024 * 1024 * 1024,
    storageSizeBytes: 100 * 1024 * 1024 * 1024,
    monthlyActiveUsers: 100_000,
    edgeFunctionInvocations: 2_000_000,
    realtimeMessages: 5_000_000,
    monthlyCostBase: 25,
  },
  team: {
    databaseSizeBytes: 8 * 1024 * 1024 * 1024,
    storageSizeBytes: 100 * 1024 * 1024 * 1024,
    monthlyActiveUsers: 100_000,
    edgeFunctionInvocations: 2_000_000,
    realtimeMessages: 5_000_000,
    monthlyCostBase: 599,
  },
  enterprise: {
    databaseSizeBytes: 100 * 1024 * 1024 * 1024,
    storageSizeBytes: 1024 * 1024 * 1024 * 1024,
    monthlyActiveUsers: 1_000_000,
    edgeFunctionInvocations: 10_000_000,
    realtimeMessages: 50_000_000,
    monthlyCostBase: 0,
  },
}

function usagePercent(used: number, limit: number): number {
  if (limit <= 0) return 0
  return Math.min(Math.round((used / limit) * 10000) / 100, 100)
}

async function verifyUserAuth(req: Request, supabaseUrl: string, supabaseServiceKey: string): Promise<boolean> {
  const authHeader = req.headers.get("Authorization")
  if (!authHeader || !authHeader.startsWith("Bearer ")) return false
  const token = authHeader.replace("Bearer ", "")
  const adminClient = createClient(supabaseUrl, supabaseServiceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })
  const { data: { user }, error } = await adminClient.auth.getUser(token)
  return !error && !!user
}

/**
 * Résout la bonne clé service_role pour un client.
 * Si la clé déchiffrée de la DB est un JWT legacy (eyJ...) et qu'un secret
 * ASAP_ROLE_KEY existe, on utilise ce dernier et on re-chiffre en DB.
 */
async function resolveServiceKey(
  client: ClientInfo,
  adminClient: any,
  encryptionKey: string
): Promise<string> {
  const dbKey = client.decrypted_service_key

  // Si la clé est au nouveau format, elle fonctionne directement
  if (dbKey && !dbKey.startsWith("eyJ")) {
    console.log(`[resolveKey] DB key is new format (${dbKey.substring(0, 15)}...) — using it`)
    return dbKey
  }

  // Clé legacy détectée — chercher un override dans les secrets
  console.log(`[resolveKey] DB key is legacy JWT — checking for override secret`)
  const overrideKey = Deno.env.get("ASAP_ROLE_KEY")

  if (overrideKey && overrideKey.length > 10) {
    console.log(`[resolveKey] Found ASAP_ROLE_KEY secret (${overrideKey.substring(0, 15)}...) — using it`)

    // Re-chiffrer la bonne clé dans la DB pour les prochaines fois
    try {
      const { error } = await adminClient.rpc("update_client_service_key", {
        p_client_id: client.client_id,
        p_new_key: overrideKey,
        p_encryption_key: encryptionKey,
      })
      if (error) {
        console.error(`[resolveKey] Failed to re-encrypt key in DB: ${error.message}`)
      } else {
        console.log(`[resolveKey] Successfully re-encrypted new key in DB for client ${client.client_name}`)
      }
    } catch (err) {
      console.error(`[resolveKey] Re-encrypt exception:`, err)
    }

    return overrideKey
  }

  // Pas d'override, on utilise quand même la clé legacy (ça échouera probablement)
  console.warn(`[resolveKey] No override found, using legacy JWT key — Auth/Storage calls will likely fail`)
  return dbKey
}

// ——— Fetch users from CLIENT's Auth API ———
async function fetchUsers(clientUrl: string, clientServiceKey: string) {
  console.log(`[fetchUsers] Calling Auth API on: ${clientUrl}`)
  console.log(`[fetchUsers] Key format: ${clientServiceKey.startsWith('eyJ') ? 'JWT (legacy)' : clientServiceKey.startsWith('sb_') ? 'sb_secret' : 'other'}`)

  let allUsers: any[] = []
  let page = 1
  const perPage = 1000

  while (true) {
    try {
      const res = await fetch(
        `${clientUrl}/auth/v1/admin/users?page=${page}&per_page=${perPage}`,
        {
          headers: {
            Authorization: `Bearer ${clientServiceKey}`,
            apikey: clientServiceKey,
          },
        }
      )

      if (!res.ok) {
        const errText = await res.text()
        console.error(`[fetchUsers] ERROR page ${page}: HTTP ${res.status} - ${errText}`)
        break
      }

      const data = await res.json()
      const users = data.users || []
      console.log(`[fetchUsers] Page ${page}: got ${users.length} users`)
      allUsers = [...allUsers, ...users]

      if (users.length < perPage) break
      page++
    } catch (err) {
      console.error("[fetchUsers] Exception:", err)
      break
    }
  }

  const thirtyDaysAgo = new Date()
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30)
  const mau = allUsers.filter((u: any) => {
    if (!u.last_sign_in_at) return false
    return new Date(u.last_sign_in_at) >= thirtyDaysAgo
  }).length

  console.log(`[fetchUsers] Total: ${allUsers.length} users, MAU: ${mau}`)
  return { total: allUsers.length, mau }
}

// ——— Fetch storage from CLIENT's Storage API ———
async function fetchStorage(clientUrl: string, clientServiceKey: string): Promise<number> {
  console.log(`[fetchStorage] Calling Storage API on: ${clientUrl}`)
  let totalBytes = 0

  try {
    const bucketsRes = await fetch(`${clientUrl}/storage/v1/bucket`, {
      headers: {
        Authorization: `Bearer ${clientServiceKey}`,
        apikey: clientServiceKey,
      },
    })

    if (!bucketsRes.ok) {
      const errText = await bucketsRes.text()
      console.error(`[fetchStorage] Buckets ERROR: HTTP ${bucketsRes.status} - ${errText}`)
      return 0
    }

    const buckets = await bucketsRes.json()
    console.log(`[fetchStorage] Found ${buckets.length} buckets`)

    for (const bucket of buckets) {
      let offset = 0
      const limit = 1000

      while (true) {
        const filesRes = await fetch(
          `${clientUrl}/storage/v1/object/list/${bucket.name}`,
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${clientServiceKey}`,
              apikey: clientServiceKey,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({ prefix: "", limit, offset }),
          }
        )

        if (!filesRes.ok) {
          console.error(`[fetchStorage] Files list error for bucket ${bucket.name}: ${filesRes.status}`)
          break
        }

        const files = await filesRes.json()
        if (!Array.isArray(files) || files.length === 0) break

        for (const file of files) {
          if (file.metadata?.size) {
            totalBytes += typeof file.metadata.size === "number"
              ? file.metadata.size
              : parseInt(String(file.metadata.size || "0"), 10)
          }
        }

        if (files.length < limit) break
        offset += limit
      }
    }
  } catch (err) {
    console.error("[fetchStorage] Exception:", err)
  }

  console.log(`[fetchStorage] Total: ${totalBytes} bytes`)
  return totalBytes
}

// ——— Fetch billing metrics from Management API (same source as Supabase dashboard) ———
async function fetchManagementMetrics(projectRef: string, accessToken: string) {
  console.log(`[fetchMgmt] Fetching billing metrics for project: ${projectRef}`)
  let apiRequestsCount = 0
  let edgeFunctionInvocations = 0
  let realtimeMessages = 0

  const mgmtHeaders = {
    Authorization: `Bearer ${accessToken}`,
    "Content-Type": "application/json",
  }

  // Helper: parse a usages array (org billing format)
  function parseUsages(usages: any[]) {
    for (const item of usages) {
      const metric = (item.metric || item.name || "").toUpperCase()
      // usage peut être dans différents champs selon l'endpoint
      const usage = item.usage ?? item.capped_usage ?? item.available_in_plan ?? item.value ?? 0
      console.log(`[billing] metric="${metric}" usage=${usage}`)

      if (metric.includes("EDGE_FUNCTION")) {
        edgeFunctionInvocations = typeof usage === "number" ? usage : parseInt(String(usage), 10)
      }
      if (metric.includes("REALTIME") && (metric.includes("MESSAGE") || metric.includes("MSG") || metric.includes("COUNT"))) {
        realtimeMessages = typeof usage === "number" ? usage : parseInt(String(usage), 10)
      }
      if (metric === "API_REQUESTS" || metric === "REST_REQUESTS" || metric === "TOTAL_REQUESTS") {
        apiRequestsCount = typeof usage === "number" ? usage : parseInt(String(usage), 10)
      }
    }
  }

  // ——— ÉTAPE 1 : endpoint de facturation organisation (même données que le dashboard Supabase) ———
  try {
    // Récupérer les infos du projet pour avoir l'org
    const projRes = await fetch(`https://api.supabase.com/v1/projects/${projectRef}`, { headers: mgmtHeaders })
    if (!projRes.ok) {
      console.error(`[fetchMgmt] project info error: ${projRes.status}`)
    } else {
      const projData = await projRes.json()
      const orgId = projData.organization_id
      console.log(`[fetchMgmt] org_id: ${orgId}`)

      if (orgId) {
        const orgsRes = await fetch(`https://api.supabase.com/v1/organizations`, { headers: mgmtHeaders })
        if (orgsRes.ok) {
          const orgs = await orgsRes.json()
          const org = orgs.find((o: any) => o.id === orgId)
          if (org) {
            console.log(`[fetchMgmt] org slug: ${org.slug}`)

            // ——— Org billing/usage (source principale = dashboard Supabase) ———
            const billingRes = await fetch(
              `https://api.supabase.com/v1/organizations/${org.slug}/billing/usage`,
              { headers: mgmtHeaders }
            )
            if (billingRes.ok) {
              const billingData = await billingRes.json()
              console.log(`[billing] RAW: ${JSON.stringify(billingData).substring(0, 2000)}`)

              // Essayer les différentes structures de réponse possibles
              const usageList =
                billingData.usages ??
                billingData.usage_items ??
                billingData.lineItems ??
                (Array.isArray(billingData) ? billingData : null)

              if (Array.isArray(usageList) && usageList.length > 0) {
                parseUsages(usageList)
              } else if (typeof billingData === "object") {
                // Format clé/valeur directe
                for (const [key, val] of Object.entries(billingData)) {
                  const k = key.toUpperCase()
                  const v = typeof val === "number" ? val : 0
                  console.log(`[billing] key="${k}" val=${v}`)
                  if (k.includes("EDGE_FUNCTION")) edgeFunctionInvocations = v
                  if (k.includes("REALTIME") && (k.includes("MESSAGE") || k.includes("COUNT"))) realtimeMessages = v
                }
              }
            } else {
              const errText = await billingRes.text()
              console.error(`[billing] error: ${billingRes.status} - ${errText.substring(0, 200)}`)
            }
          }
        }
      }
    }
  } catch (err) {
    console.error("[fetchMgmt] billing exception:", err)
  }

  // ——— ÉTAPE 2 : fallback analytics endpoint (pour API counts si toujours 0) ———
  if (apiRequestsCount === 0) {
    try {
      const now = new Date()
      const startDate = new Date(now.getFullYear(), now.getMonth(), 1).toISOString().split("T")[0]
      const endDate = new Date(now.getFullYear(), now.getMonth() + 1, 0).toISOString().split("T")[0]

      const countsRes = await fetch(
        `https://api.supabase.com/v1/projects/${projectRef}/analytics/endpoints/usage.api-counts?start_date=${startDate}&end_date=${endDate}`,
        { headers: mgmtHeaders }
      )
      if (countsRes.ok) {
        const data = await countsRes.json()
        console.log(`[analytics] api-counts: ${JSON.stringify(data).substring(0, 300)}`)
        if (Array.isArray(data?.result)) {
          for (const entry of data.result) {
            apiRequestsCount += (entry.total_rest_requests || 0)
              + (entry.total_auth_requests || 0)
              + (entry.total_storage_requests || 0)
              + (entry.total_realtime_requests || 0)
          }
        }
      }
    } catch (_) {}
  }

  console.log(`[fetchMgmt] FINAL: api=${apiRequestsCount}, edge=${edgeFunctionInvocations}, realtime=${realtimeMessages}`)
  return { dbSizeBytes: 0, apiRequestsCount, edgeFunctionInvocations, realtimeMessages }
}

// ——— Core: fetch all metrics for one client ———
async function fetchMetricsForClient(
  client: ClientInfo,
  accessToken: string,
  serviceKeyOverride: string
): Promise<MetricsResult> {
  const plan = PLAN_LIMITS[client.supabase_plan] || PLAN_LIMITS.free
  const key = serviceKeyOverride

  console.log(`\n========== FETCHING METRICS FOR: ${client.client_name} ==========`)
  console.log(`Client URL: ${client.supabase_url}`)
  console.log(`Client project ref: ${client.supabase_project_ref}`)
  console.log(`Using key format: ${key.startsWith('eyJ') ? 'JWT' : key.startsWith('sb_') ? 'sb_secret' : 'other'} (${key.length} chars)`)

  const [usersResult, storageBytes, mgmtMetrics] = await Promise.all([
    fetchUsers(client.supabase_url, key),
    fetchStorage(client.supabase_url, key),
    client.supabase_project_ref
      ? fetchManagementMetrics(client.supabase_project_ref, accessToken)
      : Promise.resolve({ dbSizeBytes: 0, apiRequestsCount: 0, edgeFunctionInvocations: 0, realtimeMessages: 0 }),
  ])

  const result: MetricsResult = {
    registeredUsersCount: usersResult.total,
    monthlyActiveUsers: usersResult.mau,
    storageSizeBytes: storageBytes,
    databaseSizeBytes: 0, // Always 0 - removed from display
    apiRequestsCount: mgmtMetrics.apiRequestsCount,
    edgeFunctionInvocations: mgmtMetrics.edgeFunctionInvocations,
    realtimeMessages: mgmtMetrics.realtimeMessages,
    estimatedMonthlyCost: plan.monthlyCostBase,
    storageUsagePercent: usagePercent(storageBytes, plan.storageSizeBytes),
    mauUsagePercent: usagePercent(usersResult.mau, plan.monthlyActiveUsers),
    databaseUsagePercent: 0, // Always 0 - removed from display
    edgeFunctionUsagePercent: usagePercent(mgmtMetrics.edgeFunctionInvocations, plan.edgeFunctionInvocations),
    realtimeUsagePercent: usagePercent(mgmtMetrics.realtimeMessages, plan.realtimeMessages),
  }

  console.log(`[RESULT] users=${result.registeredUsersCount}, mau=${result.monthlyActiveUsers}, storage=${result.storageSizeBytes}, api=${result.apiRequestsCount}, edge=${result.edgeFunctionInvocations}`)
  return result
}

// ——— Main handler ———
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

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    const encryptionKey = Deno.env.get("ENCRYPTION_KEY")!
    const accessToken = Deno.env.get("ACCESS_TOKEN")!

    console.log(`[INIT] Dashboard URL: ${supabaseUrl}`)

    const body = await req.json()
    const { client_id, mode, save_snapshot, cron_secret } = body
    console.log(`[INIT] Mode: ${mode || 'single'}, client_id: ${client_id}`)

    const adminClient = createClient(supabaseUrl, supabaseServiceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    // ——— MODE CRON ———
    if (mode === "cron") {
      const expectedSecret = Deno.env.get("CRON_SECRET")
      if (!cron_secret || cron_secret !== expectedSecret) {
        return new Response(
          JSON.stringify({ error: "Invalid cron secret" }),
          { status: 401, headers: { "Content-Type": "application/json" } }
        )
      }

      const { data: clients, error: clientsError } = await adminClient.rpc(
        "get_all_active_clients_for_metrics",
        { p_encryption_key: encryptionKey }
      )

      if (clientsError || !clients || clients.length === 0) {
        return new Response(
          JSON.stringify({ error: "No active clients", details: clientsError?.message }),
          { status: 200, headers: { "Content-Type": "application/json" } }
        )
      }

      const today = new Date().toISOString().split("T")[0]
      const results: { client_id: string; success: boolean; error?: string }[] = []

      for (const client of clients as ClientInfo[]) {
        try {
          const resolvedKey = await resolveServiceKey(client, adminClient, encryptionKey)
          const metrics = await fetchMetricsForClient(client, accessToken, resolvedKey)
          const { error: saveError } = await adminClient.rpc("save_usage_snapshot", {
            p_client_id: client.client_id,
            p_snapshot_date: today,
            p_registered_users: metrics.registeredUsersCount,
            p_database_size: 0, // Always 0 - removed from display
            p_storage_size: metrics.storageSizeBytes,
            p_api_requests: metrics.apiRequestsCount,
            p_mau: metrics.monthlyActiveUsers,
            p_edge_invocations: metrics.edgeFunctionInvocations,
            p_realtime_messages: metrics.realtimeMessages,
            p_monthly_cost: metrics.estimatedMonthlyCost,
          })
          results.push({ client_id: client.client_id, success: !saveError, error: saveError?.message })
        } catch (err) {
          results.push({ client_id: client.client_id, success: false, error: err instanceof Error ? err.message : "Unknown" })
        }
      }

      return new Response(
        JSON.stringify({ message: `Processed ${results.length} clients`, results }),
        { headers: { "Content-Type": "application/json" } }
      )
    }

    // ——— MODE SINGLE CLIENT ———
    const isAuthenticated = await verifyUserAuth(req, supabaseUrl, supabaseServiceKey)
    if (!isAuthenticated) {
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      )
    }

    if (!client_id) {
      return new Response(
        JSON.stringify({ error: "client_id is required" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      )
    }

    const { data: clientRows, error: clientError } = await adminClient.rpc(
      "get_client_for_metrics",
      { p_client_id: client_id, p_encryption_key: encryptionKey }
    )

    if (clientError) {
      console.error(`[RPC] Error: ${clientError.message}`)
      return new Response(
        JSON.stringify({ error: "RPC failed", details: clientError.message }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      )
    }

    if (!clientRows || clientRows.length === 0) {
      return new Response(
        JSON.stringify({ error: "Client not found" }),
        { status: 404, headers: { "Content-Type": "application/json" } }
      )
    }

    const client = clientRows[0] as ClientInfo
    
    // Résoudre la bonne clé (auto-corrige les legacy JWT)
    const resolvedKey = await resolveServiceKey(client, adminClient, encryptionKey)
    const metrics = await fetchMetricsForClient(client, accessToken, resolvedKey)

    if (save_snapshot) {
      const today = new Date().toISOString().split("T")[0]
      const { error: saveErr } = await adminClient.rpc("save_usage_snapshot", {
        p_client_id: client.client_id,
        p_snapshot_date: today,
        p_registered_users: metrics.registeredUsersCount,
        p_database_size: 0, // Always 0 - removed from display
        p_storage_size: metrics.storageSizeBytes,
        p_api_requests: metrics.apiRequestsCount,
        p_mau: metrics.monthlyActiveUsers,
        p_edge_invocations: metrics.edgeFunctionInvocations,
        p_realtime_messages: metrics.realtimeMessages,
        p_monthly_cost: metrics.estimatedMonthlyCost,
      })
      if (saveErr) console.error("[SAVE] error:", saveErr.message)
      else console.log("[SAVE] Snapshot saved successfully")
    }

    return new Response(
      JSON.stringify({ success: true, metrics }),
      { headers: { "Content-Type": "application/json" } }
    )
  } catch (error) {
    console.error("[FATAL]", error)
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : "Internal error" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    )
  }
})
