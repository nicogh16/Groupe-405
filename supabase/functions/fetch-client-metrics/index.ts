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

  interface ClientStatsResult {
    source: string
    kpi: Record<string, unknown>
  user_kpi: Record<string, unknown>
    charts: Record<string, Record<string, unknown>[]>
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

  async function fetchClientStats(
    clientUrl: string,
    clientServiceKey: string,
    appSlug?: string
  ): Promise<ClientStatsResult> {
    const clientDb = createClient(clientUrl, clientServiceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    const callStatsRpc = async (
      fnName: string,
      args?: Record<string, unknown>
    ): Promise<Record<string, unknown>[]> => {
      const { data: rpcRows, error: rpcRowsError } = await clientDb
        .schema("stats")
        .rpc(fnName, args)
      if (rpcRowsError) {
        console.warn(`[stats] RPC ${fnName} failed: ${rpcRowsError.message}`)
        return []
      }
      if (!rpcRows) return []
      return Array.isArray(rpcRows) ? (rpcRows as Record<string, unknown>[]) : [rpcRows as Record<string, unknown>]
    }

    const callStatsView = async (
      viewName: string,
      limit = 500
    ): Promise<Record<string, unknown>[]> => {
      const { data: viewRows, error: viewError } = await clientDb
        .schema("stats")
        .from(viewName)
        .select("*")
        .limit(limit)

      if (viewError) {
        console.warn(`[stats] View ${viewName} failed: ${viewError.message}`)
        return []
      }
      return (viewRows ?? []) as Record<string, unknown>[]
    }

  const callStatsSingleView = async (
    viewName: string
  ): Promise<Record<string, unknown> | null> => {
    const { data: row, error: rowError } = await clientDb
      .schema("stats")
      .from(viewName)
      .select("*")
      .limit(1)
      .maybeSingle()

    if (rowError) {
      console.warn(`[stats] Single view ${viewName} failed: ${rowError.message}`)
      return null
    }
    return (row ?? null) as Record<string, unknown> | null
  }

    const normalizeSeriesByDate = (
      rows: Record<string, unknown>[],
      dateField = "date"
    ): Record<string, unknown>[] =>
      [...rows].sort((a, b) =>
        String(a[dateField] ?? "").localeCompare(String(b[dateField] ?? ""))
      )

    const fetchPublicTransactionsAnalysis = async () => {
    const now = new Date()
    const thirtyDaysAgo = new Date(now)
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30)
    const oneYearAgo = new Date(now)
    oneYearAgo.setFullYear(oneYearAgo.getFullYear() - 1)
    const fromDate = oneYearAgo.toISOString()

    const fetchTransactionsRows = async () => {
      const baseSelect = "date, points, status, restaurant_id, items"

      // Priorite: table publique si elle existe.
      const publicRes = await clientDb
        .from("transactions")
        .select(baseSelect)
        .gte("date", fromDate)
        .order("date", { ascending: true })
        .limit(100_000)

      if (!publicRes.error) {
        return {
          data: publicRes.data ?? [],
          source: "public.transactions",
          error: null as string | null,
        }
      }

      // Fallback: de nombreux templates stockent les transactions dans private.transactions.
      const privateRes = await clientDb
        .schema("private")
        .from("transactions")
        .select(baseSelect)
        .gte("date", fromDate)
        .order("date", { ascending: true })
        .limit(100_000)

      if (!privateRes.error) {
        return {
          data: privateRes.data ?? [],
          source: "private.transactions",
          error: null as string | null,
        }
      }

      return {
        data: [] as Record<string, unknown>[],
        source: "none",
        error: `public="${publicRes.error.message}" private="${privateRes.error.message}"`,
      }
    }

    const txFetch = await fetchTransactionsRows()
    const txRows = txFetch.data
    const txError = txFetch.error

      if (txError) {
      console.warn(`[stats] transactions table not available: ${txError}`)
        return {
          transaction_daily_public: [] as Record<string, unknown>[],
          transaction_heatmap_public: [] as Record<string, unknown>[],
          transaction_peak_hours_public: [] as Record<string, unknown>[],
          transaction_meta_public: [] as Record<string, unknown>[],
          transaction_item_daily_heatmap_public: [] as Record<string, unknown>[],
          transaction_top_items_public: [] as Record<string, unknown>[],
        transaction_hourly_heatmap_year_public: [] as Record<string, unknown>[],
        }
      }
    console.log(`[stats] transactions analysis source: ${txFetch.source}, rows=${txRows.length}`)

    const allRows = (txRows ?? []).filter((row: any) => {
        // On exclut uniquement les statuts explicitement "annulés/échoués".
        if (!row?.status) return true
        const status = String(row.status).toLowerCase().trim()
        return !["cancelled", "canceled", "annule", "annulee", "failed", "refused", "rejected"].includes(status)
      }) as Array<{ date: string; points: number | null; restaurant_id?: string | null }>

    const rows = allRows.filter((row) => {
      const dateObj = new Date(row.date)
      return !Number.isNaN(dateObj.getTime()) && dateObj >= thirtyDaysAgo
    })

      const dailyMap = new Map<string, { transactions: number; points_distributed: number }>()
      const heatmapMap = new Map<string, { day_of_week: number; hour_of_day: number; count: number }>()
      const hourMap = new Map<number, number>()
    const yearHourMap = new Map<string, { month_of_year: number; month_label: string; hour_of_day: number; count: number }>()
      const itemTotalsMap = new Map<string, number>()
      const itemDayMap = new Map<string, { item_name: string; date: string; day_of_month: number; order_count: number }>()
      let totalPoints = 0

    const extractItemCounters = (items: unknown): Array<{ name: string; qty: number }> => {
        if (!Array.isArray(items)) return []
        const counters: Array<{ name: string; qty: number }> = []
      const articleCounters: Array<{ name: string; qty: number }> = []

        for (const rawItem of items) {
          if (!rawItem) continue

          if (typeof rawItem === "string") {
            const name = rawItem.trim()
            if (!name) continue
            counters.push({ name, qty: 1 })
            continue
          }

          if (typeof rawItem === "object") {
            const itemObj = rawItem as Record<string, unknown>
          const itemType = String(itemObj.type ?? "").toLowerCase().trim()
            const name =
              String(
                itemObj.name ??
                itemObj.item_name ??
                itemObj.product_name ??
                itemObj.title ??
                itemObj.label ??
              itemObj.id ??
                itemObj.nom ??
                ""
              ).trim()
            if (!name) continue
            const qtyRaw = Number(
              itemObj.quantity ??
              itemObj.qty ??
              itemObj.count ??
              itemObj.qte ??
              1
            )
            const qty = Number.isFinite(qtyRaw) && qtyRaw > 0 ? Math.round(qtyRaw) : 1
          const itemCounter = { name, qty }
          counters.push(itemCounter)
          if (itemType === "article") {
            articleCounters.push(itemCounter)
          }
          }
        }

      // Si des "articles" existent, on priorise ce sous-ensemble pour la heatmap produits.
      return articleCounters.length > 0 ? articleCounters : counters
      }

    const monthLabels = [
      "Jan", "Fev", "Mar", "Avr", "Mai", "Jun",
      "Jul", "Aou", "Sep", "Oct", "Nov", "Dec",
    ]

    for (const row of allRows) {
      if (!row.date) continue
      const dateObj = new Date(row.date)
      if (Number.isNaN(dateObj.getTime())) continue
      const monthIndex = dateObj.getUTCMonth()
      const hour = dateObj.getUTCHours()
      const yearHourKey = `${monthIndex + 1}-${hour}`
      const existing = yearHourMap.get(yearHourKey) ?? {
        month_of_year: monthIndex + 1,
        month_label: monthLabels[monthIndex] ?? String(monthIndex + 1),
        hour_of_day: hour,
        count: 0,
      }
      existing.count += 1
      yearHourMap.set(yearHourKey, existing)
    }

      for (const row of rows) {
        if (!row.date) continue
        const dateObj = new Date(row.date)
        if (Number.isNaN(dateObj.getTime())) continue

        const dateKey = dateObj.toISOString().slice(0, 10)
        const dayOfMonth = dateObj.getUTCDate()
        const points = typeof row.points === "number" ? row.points : Number(row.points ?? 0)

        const daily = dailyMap.get(dateKey) ?? { transactions: 0, points_distributed: 0 }
        daily.transactions += 1
        daily.points_distributed += Number.isFinite(points) ? points : 0
        dailyMap.set(dateKey, daily)

        const dow = dateObj.getUTCDay()
        const hour = dateObj.getUTCHours()
        const heatKey = `${dow}-${hour}`
        const heat = heatmapMap.get(heatKey) ?? { day_of_week: dow, hour_of_day: hour, count: 0 }
        heat.count += 1
        heatmapMap.set(heatKey, heat)

        hourMap.set(hour, (hourMap.get(hour) ?? 0) + 1)
        totalPoints += Number.isFinite(points) ? points : 0

        const itemCounters = extractItemCounters((row as unknown as Record<string, unknown>).items)
        for (const item of itemCounters) {
          itemTotalsMap.set(item.name, (itemTotalsMap.get(item.name) ?? 0) + item.qty)
          const itemDayKey = `${item.name}__${dateKey}`
          const existing = itemDayMap.get(itemDayKey) ?? {
            item_name: item.name,
            date: dateKey,
            day_of_month: dayOfMonth,
            order_count: 0,
          }
          existing.order_count += item.qty
          itemDayMap.set(itemDayKey, existing)
        }
      }

      const dayNames = ["Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"]

      const dailySeries = Array.from(dailyMap.entries())
        .sort((a, b) => a[0].localeCompare(b[0]))
        .map(([date, values]) => ({
          date,
          transactions: values.transactions,
          points_distributed: values.points_distributed,
        }))

      const heatmapSeries = Array.from(heatmapMap.values())
        .sort((a, b) => (a.day_of_week - b.day_of_week) || (a.hour_of_day - b.hour_of_day))
        .map((item) => ({
          ...item,
          day_name: dayNames[item.day_of_week] ?? String(item.day_of_week),
        }))

      const peakHours = Array.from(hourMap.entries())
        .sort((a, b) => b[1] - a[1])
        .slice(0, 6)
        .map(([hour_of_day, transaction_count]) => ({
          hour_of_day,
          transaction_count,
        }))

      const topItems = Array.from(itemTotalsMap.entries())
        .sort((a, b) => b[1] - a[1])
        .slice(0, 20)
        .map(([item_name, order_count]) => ({
          item_name,
          order_count,
        }))

      const topItemNames = new Set(topItems.slice(0, 10).map((item) => item.item_name))
      const itemDailyHeatmap = Array.from(itemDayMap.values())
        .filter((row) => topItemNames.has(row.item_name))
        .sort((a, b) => {
          if (a.item_name !== b.item_name) return a.item_name.localeCompare(b.item_name)
          return a.date.localeCompare(b.date)
        })

      const topHour = peakHours[0]?.hour_of_day
      const avgPoints = rows.length > 0 ? totalPoints / rows.length : 0
      const meta = [
        {
          total_transactions_30d: rows.length,
          avg_points_per_transaction_30d: Math.round(avgPoints * 100) / 100,
          peak_hour_utc: topHour ?? null,
          peak_hour_label_utc: topHour !== undefined ? `${String(topHour).padStart(2, "0")}:00` : null,
        },
      ]

    const yearHourlyHeatmap = Array.from(yearHourMap.values())
      .sort((a, b) => (a.month_of_year - b.month_of_year) || (a.hour_of_day - b.hour_of_day))

      return {
        transaction_daily_public: dailySeries,
        transaction_heatmap_public: heatmapSeries,
        transaction_peak_hours_public: peakHours,
        transaction_meta_public: meta,
        transaction_item_daily_heatmap_public: itemDailyHeatmap,
        transaction_top_items_public: topItems,
      transaction_hourly_heatmap_year_public: yearHourlyHeatmap,
      }
    }

    const deriveWeeklyActivityFromDaily = (
      dailyRows: Record<string, unknown>[]
    ): Record<string, unknown>[] => {
      if (!dailyRows || dailyRows.length === 0) return []

      const dayNames = ["Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"]
      const weeklyMap = new Map<number, number>()

      for (const row of dailyRows) {
        const rawDate = row.date
        if (!rawDate) continue
        const dateObj = new Date(String(rawDate))
        if (Number.isNaN(dateObj.getTime())) continue
        const dow = dateObj.getUTCDay()
        const accessLikeCount = Number(row.transactions ?? row.new_users ?? 0) || 0
        weeklyMap.set(dow, (weeklyMap.get(dow) ?? 0) + accessLikeCount)
      }

      return Array.from(weeklyMap.entries())
        .sort((a, b) => a[0] - b[0])
        .map(([day_of_week, access_count]) => ({
          day_of_week,
          day_name: dayNames[day_of_week] ?? String(day_of_week),
          access_count,
          // Fallback: la vue daily ne donne pas l'unique users par jour.
          unique_users: 0,
        }))
    }

    const deriveWeeklyActivityFromWeeklyTrends = (
      weeklyRows: Record<string, unknown>[]
    ): Record<string, unknown>[] => {
      if (!weeklyRows || weeklyRows.length === 0) return []

      const dayNames = ["Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"]
      return weeklyRows
        .map((row) => {
          const raw = row.week_start
          const dateObj = new Date(String(raw ?? ""))
          const dayOfWeek = Number.isNaN(dateObj.getTime()) ? 1 : dateObj.getUTCDay()
          return {
            day_of_week: dayOfWeek,
            day_name: dayNames[dayOfWeek] ?? String(dayOfWeek),
            access_count: Number(row.transactions ?? row.active_users ?? row.app_access_count ?? row.new_users ?? 0) || 0,
            unique_users: Number(row.active_users ?? 0) || 0,
          }
        })
        .slice(0, 8)
    }

  const fetchStartupUserKpi = async (): Promise<Record<string, unknown>> => {
    const startupKpiView = await callStatsSingleView("startup_kpi_dashboard")
    if (startupKpiView) return startupKpiView

    const { data: startupKpiRpc, error: startupKpiRpcError } = await clientDb
      .schema("stats")
      .rpc("get_startup_kpi_admin")
    if (startupKpiRpcError) {
      console.warn(`[stats] get_startup_kpi_admin failed: ${startupKpiRpcError.message}`)
      return {}
    }
    return (startupKpiRpc ?? {}) as Record<string, unknown>
  }

    const fidelityCharts = async () => {
      const [
        dailyTrendsRpc,
        dailyTrendsView,
        weeklyTrendsView,
        monthlyTrendsView,
        weeklyActivity,
        hourlyDistribution,
        topRestaurantsRpc,
        topRestaurantsView,
        userSegments,
        paretoAnalysis,
        accessCorrelation,
        publicTransactionsAnalysis,
      startupDailyTrends,
      startupWeeklyTrends,
      startupMonthlyTrends,
      ] = await Promise.all([
        callStatsRpc("get_fidelity_daily_trends_admin"),
        callStatsView("fidelity_daily_trends"),
        callStatsView("fidelity_weekly_trends", 20),
        callStatsView("fidelity_monthly_trends", 24),
        callStatsRpc("get_weekly_activity_admin"),
        callStatsRpc("get_transaction_hourly_distribution_admin"),
        callStatsRpc("get_top_restaurants_admin", { limit_count: 10 }),
        callStatsView("fidelity_top_restaurants", 20),
        callStatsRpc("get_user_segments_analysis_admin"),
        callStatsRpc("get_pareto_analysis_admin"),
        callStatsRpc("get_access_transaction_correlation_admin"),
        fetchPublicTransactionsAnalysis(),
      callStatsView("startup_daily_growth"),
      callStatsView("startup_weekly_growth", 20),
      callStatsView("startup_monthly_growth", 24),
      ])

      const dailyTrendsRaw = dailyTrendsRpc.length > 0 ? dailyTrendsRpc : dailyTrendsView
      const dailyTrends = normalizeSeriesByDate(dailyTrendsRaw, "date")
      const weeklyTrends = normalizeSeriesByDate(weeklyTrendsView, "week_start")
      const monthlyTrends = normalizeSeriesByDate(monthlyTrendsView, "month_start")
      const weeklyActivityFallback = deriveWeeklyActivityFromDaily(dailyTrends)
      const weeklyActivityFromWeeklyTrends = deriveWeeklyActivityFromWeeklyTrends(weeklyTrends)
      const topRestaurants = topRestaurantsRpc.length > 0 ? topRestaurantsRpc : topRestaurantsView

      return {
        daily_trends: dailyTrends,
        weekly_activity:
          weeklyActivity.length > 0
            ? weeklyActivity
            : weeklyActivityFromWeeklyTrends.length > 0
              ? weeklyActivityFromWeeklyTrends
              : weeklyActivityFallback,
        weekly_trends: weeklyTrends,
        monthly_trends: monthlyTrends,
        hourly_distribution: hourlyDistribution,
        top_restaurants: topRestaurants,
        user_segments: userSegments,
        pareto_analysis: paretoAnalysis,
        access_correlation: accessCorrelation,
      user_daily_trends: normalizeSeriesByDate(startupDailyTrends, "date"),
      user_weekly_trends: normalizeSeriesByDate(startupWeeklyTrends, "week_start"),
      user_monthly_trends: normalizeSeriesByDate(startupMonthlyTrends, "month_start"),
        ...publicTransactionsAnalysis,
      }
    }

    const startupCharts = async () => {
      const [
        dailyTrendsRpc,
        dailyTrendsView,
        weeklyTrendsView,
        monthlyTrendsView,
        weeklyActivity,
        timeToValue,
        accessCorrelation,
      ] = await Promise.all([
        callStatsRpc("get_startup_daily_trends_admin"),
        callStatsView("startup_daily_growth"),
        callStatsView("startup_weekly_growth", 20),
        callStatsView("startup_monthly_growth", 24),
        callStatsRpc("get_weekly_activity_admin"),
        callStatsRpc("get_time_to_value_analysis_admin"),
        callStatsRpc("get_access_transaction_correlation_admin"),
      ])
      const dailyTrendsRaw = dailyTrendsRpc.length > 0 ? dailyTrendsRpc : dailyTrendsView
      const dailyTrends = normalizeSeriesByDate(dailyTrendsRaw, "date")
      const weeklyTrends = normalizeSeriesByDate(weeklyTrendsView, "week_start")
      const monthlyTrends = normalizeSeriesByDate(monthlyTrendsView, "month_start")
      const weeklyActivityFallback = deriveWeeklyActivityFromDaily(dailyTrends)
      const weeklyActivityFromWeeklyTrends = deriveWeeklyActivityFromWeeklyTrends(weeklyTrends)

      return {
        daily_trends: dailyTrends,
        weekly_activity:
          weeklyActivity.length > 0
            ? weeklyActivity
            : weeklyActivityFromWeeklyTrends.length > 0
              ? weeklyActivityFromWeeklyTrends
              : weeklyActivityFallback,
        weekly_trends: weeklyTrends,
        monthly_trends: monthlyTrends,
        time_to_value: timeToValue,
        access_correlation: accessCorrelation,
      }
    }

    const kpiView = appSlug === "studioconnect"
      ? "startup_kpi_dashboard"
      : "fidelity_kpi_dashboard"

    const { data, error } = await clientDb
      .schema("stats")
      .from(kpiView)
      .select("*")
      .limit(1)
      .maybeSingle()

    const charts = appSlug === "studioconnect"
      ? await startupCharts()
      : await fidelityCharts()
    const startupUserKpi = await fetchStartupUserKpi()

    if (!error && data) {
      return {
        source: `stats.${kpiView}`,
        kpi: data as Record<string, unknown>,
        user_kpi: startupUserKpi,
        charts,
      }
    }

    // Fallback: certaines instances exposent la fonction admin mais pas la vue.
    const rpcFn = appSlug === "studioconnect"
      ? "get_startup_kpi_admin"
      : "get_fidelity_kpi_admin"
    const { data: rpcData, error: rpcError } = await clientDb
      .schema("stats")
      .rpc(rpcFn)

    if (rpcError) {
      const viewErr = error?.message ?? "Unknown view error"
      throw new Error(
        `Failed to fetch stats (view=${kpiView}, rpc=${rpcFn}). view_error="${viewErr}" rpc_error="${rpcError.message}"`
      )
    }

    return {
      source: `stats.${rpcFn}()`,
      kpi: (rpcData ?? {}) as Record<string, unknown>,
      user_kpi: startupUserKpi,
      charts,
    }
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
      let stats: ClientStatsResult | null = null
      let statsErrorMessage: string | null = null
      try {
        // Les clients MyFidelity partagent le même schéma `stats.*`.
        stats = await fetchClientStats(
          client.supabase_url,
          resolvedKey,
          (client as any).app_slug
        )
      } catch (statsErr) {
        const message = statsErr instanceof Error ? statsErr.message : "Unknown stats error"
        statsErrorMessage = message
        console.error("[STATS] Failed to load client stats:", message)
      }

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
        JSON.stringify({ success: true, metrics, stats, stats_error: statsErrorMessage }),
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
