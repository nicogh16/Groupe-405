"use client"

import { useState } from "react"
import {
  Mail,
  Phone,
  Globe,
  MapPin,
  Copy,
  Check,
  ExternalLink,
  Download,
  ChevronDown,
  ChevronUp,
} from "lucide-react"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import type { ProspectLead, SearchResult } from "@/app/(dashboard)/prospection/actions"

interface ResultsTableProps {
  results: SearchResult
  searchParams: {
    location: string
    sector: string
    keywords: string
    specificTarget: string
  }
}

function LeadCard({ lead, index }: { lead: ProspectLead; index: number }) {
  const [expanded, setExpanded] = useState(false)
  const [copiedField, setCopiedField] = useState<string | null>(null)

  const copyToClipboard = (text: string, field: string) => {
    navigator.clipboard.writeText(text)
    setCopiedField(field)
    setTimeout(() => setCopiedField(null), 2000)
  }

  return (
    <Card className="p-4 hover:shadow-md transition-shadow">
      <div className="flex items-start justify-between gap-4">
        <div className="flex-1 min-w-0">
          {/* Header */}
          <div className="flex items-start gap-3">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary text-sm font-bold">
              {index + 1}
            </div>
            <div className="flex-1 min-w-0">
              <h3 className="font-semibold text-sm leading-tight line-clamp-2">{lead.name}</h3>
              <a
                href={lead.url}
                target="_blank"
                rel="noopener noreferrer"
                className="text-xs text-muted-foreground hover:text-primary flex items-center gap-1 mt-0.5"
              >
                <Globe className="h-3 w-3 shrink-0" />
                <span className="truncate">{lead.source}</span>
                <ExternalLink className="h-3 w-3 shrink-0" />
              </a>
            </div>
          </div>

          {/* Description */}
          {lead.description && (
            <p className="text-xs text-muted-foreground mt-2 line-clamp-2">{lead.description}</p>
          )}

          {/* Contacts rapides */}
          <div className="mt-3 flex flex-wrap gap-2">
            {lead.emails.slice(0, expanded ? undefined : 2).map((email) => (
              <button
                key={email}
                onClick={() => copyToClipboard(email, email)}
                className="inline-flex items-center gap-1.5 rounded-md bg-blue-500/10 px-2 py-1 text-xs font-medium text-blue-700 dark:text-blue-400 hover:bg-blue-500/20 transition-colors"
              >
                <Mail className="h-3 w-3" />
                <span className="max-w-[200px] truncate">{email}</span>
                {copiedField === email ? (
                  <Check className="h-3 w-3 text-green-500" />
                ) : (
                  <Copy className="h-3 w-3 opacity-50" />
                )}
              </button>
            ))}
            {lead.phones.slice(0, expanded ? undefined : 2).map((phone) => (
              <button
                key={phone}
                onClick={() => copyToClipboard(phone, phone)}
                className="inline-flex items-center gap-1.5 rounded-md bg-green-500/10 px-2 py-1 text-xs font-medium text-green-700 dark:text-green-400 hover:bg-green-500/20 transition-colors"
              >
                <Phone className="h-3 w-3" />
                {phone}
                {copiedField === phone ? (
                  <Check className="h-3 w-3 text-green-500" />
                ) : (
                  <Copy className="h-3 w-3 opacity-50" />
                )}
              </button>
            ))}
            {lead.address && (
              <button
                onClick={() => copyToClipboard(lead.address!, "address")}
                className="inline-flex items-center gap-1.5 rounded-md bg-orange-500/10 px-2 py-1 text-xs font-medium text-orange-700 dark:text-orange-400 hover:bg-orange-500/20 transition-colors"
              >
                <MapPin className="h-3 w-3" />
                <span className="max-w-[200px] truncate">{lead.address}</span>
                {copiedField === "address" ? (
                  <Check className="h-3 w-3 text-green-500" />
                ) : (
                  <Copy className="h-3 w-3 opacity-50" />
                )}
              </button>
            )}
          </div>

          {/* Voir plus */}
          {(lead.emails.length > 2 || lead.phones.length > 2) && (
            <button
              onClick={() => setExpanded(!expanded)}
              className="mt-2 text-xs text-muted-foreground hover:text-foreground flex items-center gap-1"
            >
              {expanded ? (
                <>
                  <ChevronUp className="h-3 w-3" /> Moins de détails
                </>
              ) : (
                <>
                  <ChevronDown className="h-3 w-3" /> +{" "}
                  {lead.emails.length - 2 + lead.phones.length - 2} contact(s)
                </>
              )}
            </button>
          )}
        </div>

        {/* Badges */}
        <div className="flex flex-col items-end gap-1 shrink-0">
          {lead.emails.length > 0 && (
            <Badge variant="secondary" className="text-[10px]">
              {lead.emails.length} email{lead.emails.length > 1 ? "s" : ""}
            </Badge>
          )}
          {lead.phones.length > 0 && (
            <Badge variant="secondary" className="text-[10px]">
              {lead.phones.length} tél.
            </Badge>
          )}
        </div>
      </div>
    </Card>
  )
}

export function ProspectionResults({ results, searchParams }: ResultsTableProps) {
  const [copiedAll, setCopiedAll] = useState(false)

  const exportCSV = () => {
    const headers = ["Nom", "URL", "Emails", "Téléphones", "Adresse", "Description", "Source"]
    const rows = results.leads.map((lead) => [
      `"${lead.name.replace(/"/g, '""')}"`,
      lead.url,
      `"${lead.emails.join("; ")}"`,
      `"${lead.phones.join("; ")}"`,
      `"${(lead.address || "").replace(/"/g, '""')}"`,
      `"${lead.description.replace(/"/g, '""')}"`,
      lead.source,
    ])

    const csv = [headers.join(","), ...rows.map((r) => r.join(","))].join("\n")
    const blob = new Blob(["\uFEFF" + csv], { type: "text/csv;charset=utf-8;" })
    const url = URL.createObjectURL(blob)
    const link = document.createElement("a")
    link.href = url
    const filename = `prospection_${searchParams.location || "all"}_${searchParams.sector || "all"}_${new Date().toISOString().split("T")[0]}.csv`
    link.download = filename.replace(/\s+/g, "_")
    link.click()
    URL.revokeObjectURL(url)
  }

  const copyAllEmails = () => {
    const allEmails = [...new Set(results.leads.flatMap((l) => l.emails))]
    navigator.clipboard.writeText(allEmails.join("\n"))
    setCopiedAll(true)
    setTimeout(() => setCopiedAll(false), 2000)
  }

  if (results.leads.length === 0 && results.errors.length > 0) {
    return (
      <Card className="p-8 text-center">
        <div className="mx-auto w-12 h-12 rounded-full bg-orange-500/10 flex items-center justify-center mb-4">
          <Globe className="h-6 w-6 text-orange-500" />
        </div>
        {results.errors.map((error, i) => (
          <p key={i} className="text-sm text-muted-foreground">
            {error}
          </p>
        ))}
      </Card>
    )
  }

  const totalEmails = new Set(results.leads.flatMap((l) => l.emails)).size
  const totalPhones = new Set(results.leads.flatMap((l) => l.phones)).size

  return (
    <div className="space-y-4">
      {/* Stats */}
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div className="flex flex-wrap items-center gap-3">
          <Badge variant="outline" className="py-1">
            {results.leads.length} prospect{results.leads.length > 1 ? "s" : ""} trouvé
            {results.leads.length > 1 ? "s" : ""}
          </Badge>
          <Badge variant="outline" className="py-1 text-blue-600 border-blue-200 bg-blue-50 dark:bg-blue-950 dark:border-blue-800">
            <Mail className="h-3 w-3 mr-1" />
            {totalEmails} email{totalEmails > 1 ? "s" : ""}
          </Badge>
          <Badge variant="outline" className="py-1 text-green-600 border-green-200 bg-green-50 dark:bg-green-950 dark:border-green-800">
            <Phone className="h-3 w-3 mr-1" />
            {totalPhones} téléphone{totalPhones > 1 ? "s" : ""}
          </Badge>
          <span className="text-xs text-muted-foreground">
            ({results.totalScraped} page{results.totalScraped > 1 ? "s" : ""} analysée
            {results.totalScraped > 1 ? "s" : ""})
          </span>
        </div>

        <div className="flex items-center gap-2">
          <Button variant="outline" size="sm" onClick={copyAllEmails}>
            {copiedAll ? (
              <>
                <Check className="mr-1 h-3 w-3 text-green-500" />
                Copié !
              </>
            ) : (
              <>
                <Copy className="mr-1 h-3 w-3" />
                Copier tous les emails
              </>
            )}
          </Button>
          <Button variant="outline" size="sm" onClick={exportCSV}>
            <Download className="mr-1 h-3 w-3" />
            Exporter CSV
          </Button>
        </div>
      </div>

      {/* Erreurs éventuelles */}
      {results.errors.length > 0 && (
        <div className="rounded-md bg-orange-50 dark:bg-orange-950/20 p-3 border border-orange-200 dark:border-orange-800">
          {results.errors.map((error, i) => (
            <p key={i} className="text-sm text-orange-700 dark:text-orange-400">
              ⚠️ {error}
            </p>
          ))}
        </div>
      )}

      {/* Liste des leads */}
      <div className="grid gap-3">
        {results.leads.map((lead, index) => (
          <LeadCard key={`${lead.url}-${index}`} lead={lead} index={index} />
        ))}
      </div>
    </div>
  )
}
