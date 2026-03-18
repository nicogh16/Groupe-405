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
}

export interface SearchResult {
  leads: ProspectLead[]
  totalScraped: number
  errors: string[]
}

// =====================================================
// Helpers
// =====================================================

const EMAIL_REGEX = /[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/g
const PHONE_REGEX = /(?:\+?1[-.\s]?)?(?:\(?\d{3}\)?[-.\s]?)?\d{3}[-.\s]?\d{4}/g

// Emails à ignorer (génériques, images, etc.)
const IGNORED_EMAIL_DOMAINS = [
  "example.com",
  "sentry.io",
  "wixpress.com",
  "w3.org",
  "schema.org",
  "googleapis.com",
  "googleusercontent.com",
  "gstatic.com",
]

const IGNORED_EMAIL_PATTERNS = [
  /\.png$/i,
  /\.jpg$/i,
  /\.gif$/i,
  /\.svg$/i,
  /\.webp$/i,
  /^noreply@/i,
  /^no-reply@/i,
  /^postmaster@/i,
  /^mailer-daemon@/i,
]

function cleanEmails(emails: string[]): string[] {
  const seen = new Set<string>()
  return emails.filter((email) => {
    const lower = email.toLowerCase()
    if (seen.has(lower)) return false
    seen.add(lower)
    // Filtrer les domaines ignorés
    if (IGNORED_EMAIL_DOMAINS.some((d) => lower.endsWith(`@${d}`) || lower.includes(d))) return false
    // Filtrer les patterns ignorés
    if (IGNORED_EMAIL_PATTERNS.some((p) => p.test(lower))) return false
    // Filtrer les emails trop courts ou trop longs
    if (lower.length < 6 || lower.length > 80) return false
    return true
  })
}

function cleanPhones(phones: string[]): string[] {
  const seen = new Set<string>()
  return phones.filter((phone) => {
    // Normaliser le numéro
    const digits = phone.replace(/\D/g, "")
    // Doit avoir entre 7 et 11 chiffres
    if (digits.length < 7 || digits.length > 11) return false
    if (seen.has(digits)) return false
    seen.add(digits)
    return true
  })
}

function formatPhone(phone: string): string {
  const digits = phone.replace(/\D/g, "")
  if (digits.length === 10) {
    return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`
  }
  if (digits.length === 11 && digits.startsWith("1")) {
    return `+1 (${digits.slice(1, 4)}) ${digits.slice(4, 7)}-${digits.slice(7)}`
  }
  return phone
}

// User agent pour les requêtes
const USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

async function fetchWithTimeout(url: string, timeoutMs: number = 8000): Promise<string | null> {
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
    const contentType = response.headers.get("content-type") || ""
    if (!contentType.includes("text/html") && !contentType.includes("text/plain") && !contentType.includes("application/xhtml")) {
      return null
    }
    return await response.text()
  } catch {
    return null
  }
}

// =====================================================
// Recherche via DuckDuckGo HTML
// =====================================================

async function searchDuckDuckGo(query: string): Promise<Array<{ title: string; url: string; snippet: string }>> {
  const results: Array<{ title: string; url: string; snippet: string }> = []
  
  try {
    const encodedQuery = encodeURIComponent(query)
    const searchUrl = `https://html.duckduckgo.com/html/?q=${encodedQuery}`
    
    const html = await fetchWithTimeout(searchUrl, 10000)
    if (!html) return results

    const $ = cheerio.load(html)
    
    $(".result").each((_, el) => {
      const titleEl = $(el).find(".result__title a, .result__a")
      const snippetEl = $(el).find(".result__snippet")
      const title = titleEl.text().trim()
      let url = titleEl.attr("href") || ""
      const snippet = snippetEl.text().trim()

      // DuckDuckGo utilise des URLs de redirection, extraire l'URL réelle
      if (url.includes("uddg=")) {
        try {
          const urlObj = new URL(url, "https://duckduckgo.com")
          url = decodeURIComponent(urlObj.searchParams.get("uddg") || url)
        } catch {
          // garder l'URL telle quelle
        }
      }

      if (title && url && url.startsWith("http")) {
        results.push({ title, url, snippet })
      }
    })
  } catch (error) {
    console.error("Erreur recherche DuckDuckGo:", error)
  }

  return results
}

// =====================================================
// Recherche via Bing
// =====================================================

async function searchBing(query: string): Promise<Array<{ title: string; url: string; snippet: string }>> {
  const results: Array<{ title: string; url: string; snippet: string }> = []

  try {
    const encodedQuery = encodeURIComponent(query)
    const searchUrl = `https://www.bing.com/search?q=${encodedQuery}&count=20`

    const html = await fetchWithTimeout(searchUrl, 10000)
    if (!html) return results

    const $ = cheerio.load(html)

    $(".b_algo").each((_, el) => {
      const titleEl = $(el).find("h2 a")
      const snippetEl = $(el).find(".b_caption p, .b_lineclamp2")
      const title = titleEl.text().trim()
      const url = titleEl.attr("href") || ""
      const snippet = snippetEl.text().trim()

      if (title && url && url.startsWith("http")) {
        results.push({ title, url, snippet })
      }
    })
  } catch (error) {
    console.error("Erreur recherche Bing:", error)
  }

  return results
}

// =====================================================
// Extraction de contacts depuis une page
// =====================================================

async function extractContactsFromPage(
  url: string
): Promise<{ emails: string[]; phones: string[]; address: string | null }> {
  const result = { emails: [] as string[], phones: [] as string[], address: null as string | null }

  try {
    const html = await fetchWithTimeout(url)
    if (!html) return result

    const $ = cheerio.load(html)

    // Supprimer les scripts et styles pour éviter les faux positifs
    $("script, style, noscript").remove()

    const bodyText = $("body").text()

    // Extraire les emails
    const emailMatches = bodyText.match(EMAIL_REGEX) || []
    result.emails = cleanEmails(emailMatches)

    // Chercher aussi dans les liens mailto:
    $('a[href^="mailto:"]').each((_, el) => {
      const href = $(el).attr("href") || ""
      const email = href.replace("mailto:", "").split("?")[0].trim()
      if (email && EMAIL_REGEX.test(email)) {
        result.emails.push(email)
      }
    })
    result.emails = cleanEmails(result.emails)

    // Extraire les téléphones
    const phoneMatches = bodyText.match(PHONE_REGEX) || []
    result.phones = cleanPhones(phoneMatches).map(formatPhone)

    // Chercher aussi dans les liens tel:
    $('a[href^="tel:"]').each((_, el) => {
      const href = $(el).attr("href") || ""
      const phone = href.replace("tel:", "").trim()
      if (phone) {
        const formatted = formatPhone(phone)
        if (!result.phones.includes(formatted)) {
          result.phones.push(formatted)
        }
      }
    })

    // Essayer d'extraire une adresse (balise address ou schéma)
    const addressEl = $("address").first().text().trim()
    if (addressEl && addressEl.length > 10 && addressEl.length < 200) {
      result.address = addressEl.replace(/\s+/g, " ")
    }

    // Chercher dans les données structurées (JSON-LD)
    $('script[type="application/ld+json"]').each((_, el) => {
      try {
        const jsonText = $(el).html()
        if (!jsonText) return
        const data = JSON.parse(jsonText)
        
        const extractFromSchema = (obj: Record<string, unknown>) => {
          if (obj.email && typeof obj.email === "string") {
            const email = obj.email.replace("mailto:", "")
            if (EMAIL_REGEX.test(email)) result.emails.push(email)
          }
          if (obj.telephone && typeof obj.telephone === "string") {
            result.phones.push(formatPhone(obj.telephone))
          }
          if (obj.address && typeof obj.address === "object") {
            const addr = obj.address as Record<string, string>
            const parts = [addr.streetAddress, addr.addressLocality, addr.addressRegion, addr.postalCode].filter(Boolean)
            if (parts.length > 1) {
              result.address = parts.join(", ")
            }
          }
        }

        if (Array.isArray(data)) {
          data.forEach((item: Record<string, unknown>) => extractFromSchema(item))
        } else {
          extractFromSchema(data)
        }
      } catch {
        // JSON invalide, ignorer
      }
    })

    // Dédupliquer après toutes les extractions
    result.emails = cleanEmails(result.emails)
    result.phones = [...new Set(result.phones)]
  } catch {
    // Erreur de fetch, retourner résultat vide
  }

  return result
}

// =====================================================
// Chercher les pages contact/about d'un site
// =====================================================

async function findContactPages(baseUrl: string, html: string): Promise<string[]> {
  const contactPages: string[] = []
  
  try {
    const $ = cheerio.load(html)
    const baseUrlObj = new URL(baseUrl)
    
    const contactKeywords = [
      "contact", "nous-joindre", "nous-contacter", "about", "a-propos",
      "coordonnees", "coordonnées", "join", "reach", "info"
    ]

    $("a[href]").each((_, el) => {
      const href = $(el).attr("href") || ""
      const text = $(el).text().toLowerCase().trim()
      
      const hrefLower = href.toLowerCase()
      const isContactLink = contactKeywords.some(
        (kw) => hrefLower.includes(kw) || text.includes(kw)
      )

      if (isContactLink) {
        try {
          const fullUrl = new URL(href, baseUrl)
          // Ne suivre que les liens du même domaine
          if (fullUrl.hostname === baseUrlObj.hostname) {
            contactPages.push(fullUrl.toString())
          }
        } catch {
          // URL invalide
        }
      }
    })
  } catch {
    // Erreur, retourner vide
  }

  return [...new Set(contactPages)].slice(0, 3) // Max 3 pages de contact
}

// =====================================================
// Action principale de recherche
// =====================================================

export async function searchProspects(formData: {
  location: string
  sector: string
  keywords: string
  specificTarget: string
}): Promise<SearchResult> {
  const { location, sector, keywords, specificTarget } = formData
  const errors: string[] = []

  // Construire la requête de recherche
  const queryParts = []
  if (specificTarget) queryParts.push(specificTarget)
  if (sector) queryParts.push(sector)
  if (location) queryParts.push(location)
  if (keywords) queryParts.push(keywords)
  queryParts.push("contact email téléphone")

  const searchQuery = queryParts.join(" ")

  // Aussi faire une recherche plus ciblée
  const directoryQuery = `${specificTarget || sector} ${location} annuaire coordonnées`

  // Rechercher via plusieurs moteurs en parallèle
  const [duckResults, bingResults, duckDirectoryResults] = await Promise.all([
    searchDuckDuckGo(searchQuery),
    searchBing(searchQuery),
    searchDuckDuckGo(directoryQuery),
  ])

  // Combiner et dédupliquer les résultats de recherche
  const allSearchResults = new Map<string, { title: string; url: string; snippet: string }>()
  
  for (const result of [...duckResults, ...bingResults, ...duckDirectoryResults]) {
    try {
      const urlObj = new URL(result.url)
      const key = urlObj.hostname + urlObj.pathname
      if (!allSearchResults.has(key)) {
        allSearchResults.set(key, result)
      }
    } catch {
      // URL invalide, ignorer
    }
  }

  const uniqueResults = Array.from(allSearchResults.values()).slice(0, 15) // Max 15 résultats

  if (uniqueResults.length === 0) {
    errors.push("Aucun résultat trouvé. Essayez d'autres mots-clés.")
    return { leads: [], totalScraped: 0, errors }
  }

  // Scraper chaque résultat pour extraire les contacts
  const leads: ProspectLead[] = []

  const scrapePromises = uniqueResults.map(async (searchResult) => {
    try {
      // Récupérer la page principale
      const html = await fetchWithTimeout(searchResult.url)
      if (!html) return null

      // Extraire les contacts de la page principale
      const mainContacts = await extractContactsFromPage(searchResult.url)

      // Si pas assez de contacts, chercher les pages contact/à propos
      if (mainContacts.emails.length === 0 && mainContacts.phones.length === 0) {
        const contactPages = await findContactPages(searchResult.url, html)
        
        for (const pageUrl of contactPages) {
          const pageContacts = await extractContactsFromPage(pageUrl)
          mainContacts.emails.push(...pageContacts.emails)
          mainContacts.phones.push(...pageContacts.phones)
          if (!mainContacts.address && pageContacts.address) {
            mainContacts.address = pageContacts.address
          }
        }

        // Dédupliquer
        mainContacts.emails = cleanEmails(mainContacts.emails)
        mainContacts.phones = [...new Set(mainContacts.phones)]
      }

      // Ne retourner que les résultats avec au moins un contact
      if (mainContacts.emails.length > 0 || mainContacts.phones.length > 0) {
        return {
          name: searchResult.title,
          url: searchResult.url,
          description: searchResult.snippet,
          emails: mainContacts.emails.slice(0, 5), // Max 5 emails par lead
          phones: mainContacts.phones.slice(0, 5), // Max 5 phones par lead
          address: mainContacts.address,
          source: new URL(searchResult.url).hostname,
        } satisfies ProspectLead
      }

      return null
    } catch {
      return null
    }
  })

  const results = await Promise.all(scrapePromises)
  
  for (const lead of results) {
    if (lead) {
      leads.push(lead)
    }
  }

  if (leads.length === 0 && uniqueResults.length > 0) {
    errors.push(
      "Des résultats de recherche ont été trouvés, mais aucun contact n'a pu être extrait. Essayez des termes plus spécifiques."
    )
  }

  return {
    leads,
    totalScraped: uniqueResults.length,
    errors,
  }
}
