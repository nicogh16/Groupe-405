"use client"

import { useState } from "react"
import {
  Mail, Phone, Globe, MapPin, Copy, Check, ExternalLink,
  Download, ChevronDown, ChevronUp, BarChart3,
} from "lucide-react"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from "@/components/ui/table"
import type { ProspectLead, SearchResult } from "@/app/(dashboard)/prospection/actions"

// ───────── Stats cards ─────────

function StatsCards({ results }: { results: SearchResult }) {
  const totalEmails = new Set(results.leads.flatMap((l) => l.emails)).size
  const totalPhones = new Set(results.leads.flatMap((l) => l.phones)).size
  const avgScore = results.leads.length > 0
    ? Math.round(results.leads.reduce((s, l) => s + l.relevanceScore, 0) / results.leads.length)
    : 0

  const items = [
    { label: "Prospects trouvés", value: results.leads.length, sub: `${results.totalSearchResults} résultats analysés` },
    { label: "Emails trouvés", value: totalEmails, sub: `${results.leads.filter((l) => l.emails.length > 0).length} avec email` },
    { label: "Téléphones trouvés", value: totalPhones, sub: `${results.leads.filter((l) => l.phones.length > 0).length} avec tél.` },
    { label: "Pertinence moyenne", value: `${avgScore}%`, sub: `${results.totalScraped} pages scrapées` },
  ]

  return (
    <div className="grid gap-4 grid-cols-1 sm:grid-cols-2 lg:grid-cols-4">
      {items.map((item) => (
        <Card key={item.label} className="border border-border/50 shadow-sm">
          <CardContent className="p-5">
            <div className="flex items-center justify-between mb-3">
              <p className="text-xs font-medium text-muted-foreground uppercase tracking-wide">{item.label}</p>
            </div>
            <p className="text-2xl font-bold tracking-tight text-foreground">{item.value}</p>
            <p className="text-xs text-muted-foreground mt-1.5">{item.sub}</p>
          </CardContent>
        </Card>
      ))}
    </div>
  )
}

// ───────── Copie helper ─────────

function CopyButton({ text, className }: { text: string; className?: string }) {
  const [copied, setCopied] = useState(false)
  const copy = () => {
    navigator.clipboard.writeText(text)
    setCopied(true)
    setTimeout(() => setCopied(false), 1500)
  }
  return (
    <button onClick={copy} className={className} title="Copier">
      {copied ? <Check className="h-3 w-3 text-green-500" /> : <Copy className="h-3 w-3 opacity-40 hover:opacity-100" />}
    </button>
  )
}

// ───────── Lead Row expandable ─────────

function LeadRow({ lead, index }: { lead: ProspectLead; index: number }) {
  const [expanded, setExpanded] = useState(false)
  const hasMore = lead.emails.length > 1 || lead.phones.length > 1

  return (
    <>
      <TableRow className="group cursor-pointer hover:bg-muted/50" onClick={() => hasMore && setExpanded(!expanded)}>
        <TableCell className="w-10 text-center font-medium text-muted-foreground text-xs">
          {index + 1}
        </TableCell>
        <TableCell>
          <div className="min-w-0">
            <p className="font-medium text-sm truncate max-w-[280px]">{lead.name}</p>
            <a
              href={lead.url}
              target="_blank"
              rel="noopener noreferrer"
              onClick={(e) => e.stopPropagation()}
              className="text-xs text-muted-foreground hover:text-primary inline-flex items-center gap-1 mt-0.5"
            >
              <Globe className="h-3 w-3 shrink-0" />
              <span className="truncate max-w-[200px]">{lead.source}</span>
              <ExternalLink className="h-3 w-3 shrink-0" />
            </a>
          </div>
        </TableCell>
        <TableCell>
          {lead.emails.length > 0 ? (
            <div className="flex items-center gap-1.5">
              <span className="text-sm truncate max-w-[220px]">{lead.emails[0]}</span>
              <CopyButton text={lead.emails[0]} />
              {lead.emails.length > 1 && (
                <Badge variant="secondary" className="text-[10px] px-1.5 py-0">+{lead.emails.length - 1}</Badge>
              )}
            </div>
          ) : (
            <span className="text-xs text-muted-foreground">—</span>
          )}
        </TableCell>
        <TableCell>
          {lead.phones.length > 0 ? (
            <div className="flex items-center gap-1.5">
              <span className="text-sm whitespace-nowrap">{lead.phones[0]}</span>
              <CopyButton text={lead.phones[0]} />
              {lead.phones.length > 1 && (
                <Badge variant="secondary" className="text-[10px] px-1.5 py-0">+{lead.phones.length - 1}</Badge>
              )}
            </div>
          ) : (
            <span className="text-xs text-muted-foreground">—</span>
          )}
        </TableCell>
        <TableCell className="hidden lg:table-cell">
          {lead.address ? (
            <div className="flex items-center gap-1.5">
              <MapPin className="h-3 w-3 text-muted-foreground shrink-0" />
              <span className="text-xs truncate max-w-[180px]">{lead.address}</span>
              <CopyButton text={lead.address} />
            </div>
          ) : (
            <span className="text-xs text-muted-foreground">—</span>
          )}
        </TableCell>
        <TableCell className="w-16 text-center">
          <div className="flex items-center justify-center gap-1">
            <div className="w-8 h-1.5 rounded-full bg-muted overflow-hidden">
              <div
                className="h-full rounded-full bg-primary transition-all"
                style={{ width: `${lead.relevanceScore}%` }}
              />
            </div>
            <span className="text-[10px] text-muted-foreground w-7">{lead.relevanceScore}%</span>
          </div>
        </TableCell>
        <TableCell className="w-8">
          {hasMore && (
            <button onClick={(e) => { e.stopPropagation(); setExpanded(!expanded) }}>
              {expanded ? <ChevronUp className="h-4 w-4 text-muted-foreground" /> : <ChevronDown className="h-4 w-4 text-muted-foreground" />}
            </button>
          )}
        </TableCell>
      </TableRow>

      {expanded && (
        <TableRow className="bg-muted/30">
          <TableCell />
          <TableCell colSpan={6}>
            <div className="py-2 space-y-2">
              {lead.description && (
                <p className="text-xs text-muted-foreground">{lead.description}</p>
              )}
              <div className="flex flex-wrap gap-2">
                {lead.emails.map((email) => (
                  <span key={email} className="inline-flex items-center gap-1.5 rounded-md bg-blue-500/10 px-2.5 py-1 text-xs font-medium text-blue-700 dark:text-blue-400">
                    <Mail className="h-3 w-3" />
                    {email}
                    <CopyButton text={email} />
                  </span>
                ))}
                {lead.phones.map((phone) => (
                  <span key={phone} className="inline-flex items-center gap-1.5 rounded-md bg-green-500/10 px-2.5 py-1 text-xs font-medium text-green-700 dark:text-green-400">
                    <Phone className="h-3 w-3" />
                    {phone}
                    <CopyButton text={phone} />
                  </span>
                ))}
                {lead.address && (
                  <span className="inline-flex items-center gap-1.5 rounded-md bg-orange-500/10 px-2.5 py-1 text-xs font-medium text-orange-700 dark:text-orange-400">
                    <MapPin className="h-3 w-3" />
                    {lead.address}
                    <CopyButton text={lead.address} />
                  </span>
                )}
              </div>
            </div>
          </TableCell>
        </TableRow>
      )}
    </>
  )
}

// ───────── Composant principal ─────────

interface ResultsTableProps {
  results: SearchResult
  searchParams: {
    location: string
    sector: string
    keywords: string
    specificTarget: string
  }
}

export function ProspectionResults({ results, searchParams }: ResultsTableProps) {
  const [copiedAll, setCopiedAll] = useState(false)

  const exportCSV = () => {
    const headers = ["#", "Nom", "URL", "Emails", "Téléphones", "Adresse", "Description", "Source", "Pertinence"]
    const rows = results.leads.map((lead, i) => [
      i + 1,
      `"${lead.name.replace(/"/g, '""')}"`,
      lead.url,
      `"${lead.emails.join("; ")}"`,
      `"${lead.phones.join("; ")}"`,
      `"${(lead.address || "").replace(/"/g, '""')}"`,
      `"${lead.description.replace(/"/g, '""')}"`,
      lead.source,
      `${lead.relevanceScore}%`,
    ])
    const csv = [headers.join(","), ...rows.map((r) => r.join(","))].join("\n")
    const blob = new Blob(["\uFEFF" + csv], { type: "text/csv;charset=utf-8;" })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = `prospection_${searchParams.location || "all"}_${new Date().toISOString().split("T")[0]}.csv`.replace(/\s+/g, "_")
    a.click()
    URL.revokeObjectURL(url)
  }

  const copyAllEmails = () => {
    const all = [...new Set(results.leads.flatMap((l) => l.emails))]
    navigator.clipboard.writeText(all.join("\n"))
    setCopiedAll(true)
    setTimeout(() => setCopiedAll(false), 2000)
  }

  if (results.leads.length === 0) {
    return (
      <Card className="border border-border/50">
        <CardContent className="py-12 text-center">
          <BarChart3 className="h-10 w-10 text-muted-foreground/40 mx-auto mb-3" />
          <p className="text-sm font-medium">Aucun prospect avec contacts trouvé</p>
          {results.errors.map((err, i) => (
            <p key={i} className="text-xs text-muted-foreground mt-1">{err}</p>
          ))}
          <p className="text-xs text-muted-foreground mt-2">
            Essayez des termes plus spécifiques ou une autre localisation.
          </p>
        </CardContent>
      </Card>
    )
  }

  return (
    <div className="space-y-6">
      {/* Stats */}
      <StatsCards results={results} />

      {/* Erreurs */}
      {results.errors.length > 0 && (
        <div className="rounded-md bg-orange-50 dark:bg-orange-950/20 px-4 py-3 border border-orange-200 dark:border-orange-800">
          {results.errors.map((err, i) => (
            <p key={i} className="text-xs text-orange-700 dark:text-orange-400">⚠️ {err}</p>
          ))}
        </div>
      )}

      {/* Actions */}
      <Card className="border border-border/50">
        <CardHeader className="pb-3 flex flex-row items-center justify-between space-y-0">
          <CardTitle className="text-sm font-medium">
            Résultats ({results.leads.length})
          </CardTitle>
          <div className="flex items-center gap-2">
            <Button variant="outline" size="sm" onClick={copyAllEmails} className="h-8 text-xs">
              {copiedAll ? (
                <><Check className="mr-1.5 h-3 w-3 text-green-500" />Copié !</>
              ) : (
                <><Copy className="mr-1.5 h-3 w-3" />Copier tous les emails</>
              )}
            </Button>
            <Button variant="outline" size="sm" onClick={exportCSV} className="h-8 text-xs">
              <Download className="mr-1.5 h-3 w-3" />
              Exporter CSV
            </Button>
          </div>
        </CardHeader>
        <CardContent className="p-0">
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead className="w-10 text-center">#</TableHead>
                  <TableHead>Prospect</TableHead>
                  <TableHead>Email</TableHead>
                  <TableHead>Téléphone</TableHead>
                  <TableHead className="hidden lg:table-cell">Adresse</TableHead>
                  <TableHead className="w-20 text-center">Score</TableHead>
                  <TableHead className="w-8" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {results.leads.map((lead, index) => (
                  <LeadRow key={`${lead.url}-${index}`} lead={lead} index={index} />
                ))}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
