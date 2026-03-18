"use server"

import * as cheerio from "cheerio"

// =====================================================
// Types
// =====================================================

export interface ProspectLead {
  name: string
  url: string
  description: string
  emails: string[]
  phones: string[]
  address: string | null
  source: string
  relevanceScore: number
}

export interface SearchResult {
  leads: ProspectLead[]
  totalScraped: number
  totalSearchResults: number
  errors: string[]
  searchQueries: string[]
}

// =====================================================
// Helpers
// =====================================================

const EMAIL_REGEX = /[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/g
const PHONE_REGEX = /(?:\+?1[-.\s]?)?(?:\(?\d{3}\)?[-.\s]?)?\d{3}[-.\s]?\d{4}/g

const IGNORED_EMAIL_DOMAINS = [
  "example.com", "sentry.io", "wixpress.com", "w3.org", "schema.org",
  "googleapis.com", "googleusercontent.com", "gstatic.com", "facebook.com",
  "twitter.com", "instagram.com", "linkedin.com", "youtube.com",
  "apple.com", "microsoft.com", "google.com", "amazon.com",
  "cloudflare.com", "wordpress.org", "jquery.com", "bootstrapcdn.com",
]

const IGNORED_EMAIL_PATTERNS = [
  /\.png$/i, /\.jpg$/i, /\.gif$/i, /\.svg$/i, /\.webp$/i, /\.css$/i, /\.js$/i,
  /^noreply@/i, /^no-reply@/i, /^postmaster@/i, /^mailer-daemon@/i,
  /^admin@/i, /^webmaster@/i, /^support@wordpress/i, /^changeme@/i,
  /^email@/i, /^test@/i, /^info@example/i, /^user@/i,
]

function cleanEmails(emails: string[]): string[] {
  const seen = new Set<string>()
  return emails.filter((email) => {
    const lower = email.toLowerCase()
    if (seen.has(lower)) return false
    seen.add(lower)
    if (IGNORED_EMAIL_DOMAINS.some((d) => lower.endsWith(`@${d}`) || lower.includes(d))) return false
    if (IGNORED_EMAIL_PATTERNS.some((p) => p.test(lower))) return false
    if (lower.length < 6 || lower.length > 80) return false
    return true
  })
}

function cleanPhones(phones: string[]): string[] {
  const seen = new Set<string>()
  return phones.filter((phone) => {
    const digits = phone.replace(/\D/g, "")
    if (digits.length < 7 || digits.length > 11) return false
    // Ignorer les numéros qui sont clairement des dates ou codes
    if (/^(19|20)\d{6}$/.test(digits)) return false
    if (seen.has(digits)) return false
    seen.add(digits)
    return true
  })
}

function formatPhone(phone: string): string {
  const digits = phone.replace(/\D/g, "")
  if (digits.length === 10) return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`
  if (digits.length === 11 && digits.startsWith("1")) return `+1 (${digits.slice(1, 4)}) ${digits.slice(4, 7)}-${digits.slice(7)}`
  return phone
}

const USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

async function fetchPage(url: string, timeoutMs = 10000): Promise<string | null> {
  try {
    const controller = new AbortController()
    const timeout = setTimeout(() => controller.abort(), timeoutMs)
    const response = await fetch(url, {
      headers: {
        "User-Agent": USER_AGENT,
        Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "fr-CA,fr;q=0.9,en;q=0.8",
      },
      signal: controller.signal,
      redirect: "follow",
    })
    clearTimeout(timeout)
    if (!response.ok) return null
    const ct = response.headers.get("content-type") || ""
    if (!ct.includes("text/html") && !ct.includes("text/plain") && !ct.includes("xhtml")) return null
    return await response.text()
  } catch {
    return null
  }
}

// =====================================================
// Moteurs de recherche
// =====================================================

interface RawSearchResult {
  title: string
  url: string
  snippet: string
}

async function searchDuckDuckGo(query: string): Promise<RawSearchResult[]> {
  const results: RawSearchResult[] = []
  try {
    const html = await fetchPage(`https://html.duckduckgo.com/html/?q=${encodeURIComponent(query)}`, 12000)
    if (!html) return results
    const $ = cheerio.load(html)
    $(".result").each((_, el) => {
      const titleEl = $(el).find(".result__title a, .result__a")
      const snippetEl = $(el).find(".result__snippet")
      const title = titleEl.text().trim()
      let url = titleEl.attr("href") || ""
      const snippet = snippetEl.text().trim()
      if (url.includes("uddg=")) {
        try {
          url = decodeURIComponent(new URL(url, "https://duckduckgo.com").searchParams.get("uddg") || url)
        } catch { /* keep url */ }
      }
      if (title && url && url.startsWith("http")) results.push({ title, url, snippet })
    })
  } catch { /* ignore */ }
  return results
}

async function searchBing(query: string, count = 30): Promise<RawSearchResult[]> {
  const results: RawSearchResult[] = []
  try {
    const html = await fetchPage(`https://www.bing.com/search?q=${encodeURIComponent(query)}&count=${count}`, 12000)
    if (!html) return results
    const $ = cheerio.load(html)
    $(".b_algo").each((_, el) => {
      const titleEl = $(el).find("h2 a")
      const snippetEl = $(el).find(".b_caption p, .b_lineclamp2")
      const title = titleEl.text().trim()
      const url = titleEl.attr("href") || ""
      const snippet = snippetEl.text().trim()
      if (title && url && url.startsWith("http")) results.push({ title, url, snippet })
    })
  } catch { /* ignore */ }
  return results
}

// =====================================================
// Extraction de contacts
// =====================================================

function extractContactsFromHTML(html: string, url: string): {
  emails: string[]; phones: string[]; address: string | null
} {
  const result = { emails: [] as string[], phones: [] as string[], address: null as string | null }
  try {
    const $ = cheerio.load(html)
    $("script, style, noscript, svg, path").remove()
    const bodyText = $("body").text()

    // Emails depuis le texte
    result.emails.push(...(bodyText.match(EMAIL_REGEX) || []))

    // Emails depuis les liens mailto
    $('a[href^="mailto:"]').each((_, el) => {
      const email = ($(el).attr("href") || "").replace("mailto:", "").split("?")[0].trim()
      if (email && EMAIL_REGEX.test(email)) result.emails.push(email)
    })

    // Téléphones depuis le texte
    result.phones.push(...(bodyText.match(PHONE_REGEX) || []))

    // Téléphones depuis les liens tel
    $('a[href^="tel:"]').each((_, el) => {
      const phone = ($(el).attr("href") || "").replace("tel:", "").trim()
      if (phone) result.phones.push(phone)
    })

    // Adresse depuis balise <address>
    const addressEl = $("address").first().text().trim()
    if (addressEl && addressEl.length > 10 && addressEl.length < 300) {
      result.address = addressEl.replace(/\s+/g, " ")
    }

    // Données structurées JSON-LD
    $('script[type="application/ld+json"]').each((_, el) => {
      try {
        const data = JSON.parse($(el).html() || "")
        const items = Array.isArray(data) ? data : [data]
        for (const obj of items) {
          if (obj.email) {
            const e = String(obj.email).replace("mailto:", "")
            if (EMAIL_REGEX.test(e)) result.emails.push(e)
          }
          if (obj.telephone) result.phones.push(String(obj.telephone))
          if (obj.address && typeof obj.address === "object") {
            const a = obj.address
            const parts = [a.streetAddress, a.addressLocality, a.addressRegion, a.postalCode].filter(Boolean)
            if (parts.length > 1) result.address = parts.join(", ")
          }
          // Chercher aussi dans contactPoint
          if (obj.contactPoint) {
            const contacts = Array.isArray(obj.contactPoint) ? obj.contactPoint : [obj.contactPoint]
            for (const cp of contacts) {
              if (cp.email) result.emails.push(String(cp.email).replace("mailto:", ""))
              if (cp.telephone) result.phones.push(String(cp.telephone))
            }
          }
        }
      } catch { /* bad json */ }
    })

    // Chercher aussi dans les meta tags
    const ogEmail = $('meta[property="og:email"]').attr("content")
    if (ogEmail) result.emails.push(ogEmail)

    // Nettoyer
    result.emails = cleanEmails(result.emails)
    result.phones = [...new Set(cleanPhones(result.phones).map(formatPhone))]
  } catch { /* ignore */ }
  return result
}

function findContactPageUrls(baseUrl: string, html: string): string[] {
  const urls: string[] = []
  try {
    const $ = cheerio.load(html)
    const baseHost = new URL(baseUrl).hostname
    const keywords = [
      "contact", "nous-joindre", "nous-contacter", "about", "a-propos",
      "coordonnees", "coordonnées", "join", "reach", "info",
      "about-us", "qui-sommes-nous", "equipe", "team",
    ]
    $("a[href]").each((_, el) => {
      const href = $(el).attr("href") || ""
      const text = $(el).text().toLowerCase().trim()
      const hrefLower = href.toLowerCase()
      if (keywords.some((kw) => hrefLower.includes(kw) || text.includes(kw))) {
        try {
          const full = new URL(href, baseUrl)
          if (full.hostname === baseHost) urls.push(full.toString())
        } catch { /* bad url */ }
      }
    })
  } catch { /* ignore */ }
  return [...new Set(urls)].slice(0, 3)
}

// =====================================================
// Score de pertinence
// =====================================================

function computeRelevance(
  lead: { name: string; description: string; emails: string[]; phones: string[]; address: string | null },
  keywords: string[]
): number {
  let score = 0
  const text = `${lead.name} ${lead.description}`.toLowerCase()

  // Points pour contacts trouvés
  score += Math.min(lead.emails.length, 3) * 20
  score += Math.min(lead.phones.length, 3) * 15
  if (lead.address) score += 10

  // Points pour mots-clés trouvés dans le texte
  for (const kw of keywords) {
    if (kw.length < 2) continue
    if (text.includes(kw.toLowerCase())) score += 15
  }

  return Math.min(score, 100)
}

// =====================================================
// Générateur de requêtes de recherche variées
// =====================================================

function buildSearchQueries(params: {
  location: string; sector: string; keywords: string; specificTarget: string
}): string[] {
  const { location, sector, keywords, specificTarget } = params
  const queries: string[] = []

  // Requête principale ciblée
  const mainParts = [specificTarget, sector, location].filter(Boolean)
  if (mainParts.length > 0) {
    queries.push(`${mainParts.join(" ")} contact email téléphone`)
  }

  // Requête avec "annuaire" / "répertoire"
  if (location && (sector || specificTarget)) {
    queries.push(`${specificTarget || sector} ${location} annuaire répertoire`)
  }

  // Requête ciblée sur les coordonnées
  if (specificTarget && location) {
    queries.push(`"${specificTarget}" "${location}" coordonnées`)
  }

  // Requête avec mots-clés supplémentaires
  if (keywords && location) {
    queries.push(`${keywords} ${specificTarget || sector} ${location}`)
  }

  // Requête pages jaunes / annuaire
  if (specificTarget || sector) {
    queries.push(`${specificTarget || sector} ${location} site:pagesjaunes.ca OR site:yellowpages.ca OR site:canada411.ca`)
  }

  // Requête Google Maps style
  if (specificTarget && location) {
    queries.push(`${specificTarget} near ${location} phone email`)
  }

  // Requête francophone ciblée
  if (location && (specificTarget || sector)) {
    queries.push(`liste ${specificTarget || sector} ${location} courriel téléphone`)
  }

  // Requête en anglais aussi
  if (specificTarget && location) {
    queries.push(`${specificTarget} ${location} contact information email phone`)
  }

  return [...new Set(queries)].slice(0, 8) // Max 8 requêtes variées
}

// =====================================================
// Action principale
// =====================================================

export async function searchProspects(formData: {
  location: string
  sector: string
  keywords: string
  specificTarget: string
  maxResults: number
}): Promise<SearchResult> {
  const { location, sector, keywords, specificTarget, maxResults } = formData
  const errors: string[] = []
  const targetCount = Math.min(Math.max(maxResults || 10, 5), 50)

  // Générer plusieurs requêtes de recherche variées
  const searchQueries = buildSearchQueries({ location, sector, keywords, specificTarget })

  if (searchQueries.length === 0) {
    return { leads: [], totalScraped: 0, totalSearchResults: 0, errors: ["Veuillez entrer au moins un critère de recherche."], searchQueries: [] }
  }

  // Exécuter toutes les recherches en parallèle (DDG + Bing pour chaque requête)
  const searchPromises: Promise<RawSearchResult[]>[] = []
  for (const q of searchQueries) {
    searchPromises.push(searchDuckDuckGo(q))
    searchPromises.push(searchBing(q, 30))
  }
  const allRawResults = await Promise.all(searchPromises)

  // Combiner et dédupliquer
  const uniqueMap = new Map<string, RawSearchResult>()
  for (const batch of allRawResults) {
    for (const r of batch) {
      try {
        const u = new URL(r.url)
        // Ignorer les moteurs de recherche, réseaux sociaux, etc.
        const skipDomains = ["google.", "bing.", "duckduckgo.", "yahoo.", "facebook.com", "twitter.com", "instagram.com", "linkedin.com", "youtube.com", "wikipedia.org", "reddit.com", "tiktok.com"]
        if (skipDomains.some(d => u.hostname.includes(d))) continue
        const key = u.hostname + u.pathname.replace(/\/+$/, "")
        if (!uniqueMap.has(key)) uniqueMap.set(key, r)
      } catch { /* bad url */ }
    }
  }

  const totalSearchResults = uniqueMap.size
  // Prendre plus de résultats que nécessaire pour compenser ceux sans contacts
  const candidates = Array.from(uniqueMap.values()).slice(0, Math.min(targetCount * 4, 80))

  if (candidates.length === 0) {
    return { leads: [], totalScraped: 0, totalSearchResults: 0, errors: ["Aucun résultat trouvé. Essayez d'autres mots-clés."], searchQueries }
  }

  // Scraper par lots de 6 en parallèle pour ne pas surcharger
  const leads: ProspectLead[] = []
  const allKeywords = [specificTarget, sector, ...keywords.split(/\s+/), location].filter(Boolean)
  const batchSize = 6

  for (let i = 0; i < candidates.length && leads.length < targetCount; i += batchSize) {
    const batch = candidates.slice(i, i + batchSize)

    const batchResults = await Promise.all(batch.map(async (sr) => {
      try {
        const html = await fetchPage(sr.url)
        if (!html) return null

        let contacts = extractContactsFromHTML(html, sr.url)

        // Si pas de contacts, chercher les pages contact/à propos
        if (contacts.emails.length === 0 && contacts.phones.length === 0) {
          const contactPages = findContactPageUrls(sr.url, html)
          for (const pageUrl of contactPages) {
            const pageHtml = await fetchPage(pageUrl)
            if (!pageHtml) continue
            const pageContacts = extractContactsFromHTML(pageHtml, pageUrl)
            contacts.emails.push(...pageContacts.emails)
            contacts.phones.push(...pageContacts.phones)
            if (!contacts.address && pageContacts.address) contacts.address = pageContacts.address
          }
          contacts.emails = cleanEmails(contacts.emails)
          contacts.phones = [...new Set(contacts.phones)]
        }

        if (contacts.emails.length === 0 && contacts.phones.length === 0) return null

        const lead: ProspectLead = {
          name: sr.title,
          url: sr.url,
          description: sr.snippet,
          emails: contacts.emails.slice(0, 8),
          phones: contacts.phones.slice(0, 8),
          address: contacts.address,
          source: new URL(sr.url).hostname,
          relevanceScore: 0,
        }
        lead.relevanceScore = computeRelevance(lead, allKeywords)
        return lead
      } catch { return null }
    }))

    for (const lead of batchResults) {
      if (lead && leads.length < targetCount) leads.push(lead)
    }
  }

  // Trier par score de pertinence
  leads.sort((a, b) => b.relevanceScore - a.relevanceScore)

  if (leads.length === 0 && candidates.length > 0) {
    errors.push("Des résultats de recherche ont été trouvés, mais aucun contact n'a pu être extrait. Essayez des termes plus spécifiques ou un secteur différent.")
  }

  return {
    leads,
    totalScraped: Math.min(candidates.length, leads.length > 0 ? candidates.length : candidates.length),
    totalSearchResults,
    errors,
    searchQueries,
  }
}
