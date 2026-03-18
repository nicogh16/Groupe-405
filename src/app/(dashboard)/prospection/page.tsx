"use client"

import { useState } from "react"
import { Radar, Sparkles, Info } from "lucide-react"
import { ProspectionSearchForm } from "@/components/prospection/search-form"
import { ProspectionResults } from "@/components/prospection/results-table"
import { searchProspects } from "./actions"
import type { SearchResult } from "./actions"
import { Card } from "@/components/ui/card"

export default function ProspectionPage() {
  const [isLoading, setIsLoading] = useState(false)
  const [results, setResults] = useState<SearchResult | null>(null)
  const [searchParams, setSearchParams] = useState({
    location: "",
    sector: "",
    keywords: "",
    specificTarget: "",
  })

  const handleSearch = async (params: typeof searchParams) => {
    setIsLoading(true)
    setSearchParams(params)
    setResults(null)

    try {
      const data = await searchProspects(params)
      setResults(data)
    } catch (error) {
      console.error("Erreur de recherche:", error)
      setResults({
        leads: [],
        totalScraped: 0,
        errors: ["Une erreur est survenue lors de la recherche. Veuillez réessayer."],
      })
    } finally {
      setIsLoading(false)
    }
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="space-y-1">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
            <Radar className="h-5 w-5 text-primary" />
          </div>
          <div>
            <h1 className="text-2xl font-bold tracking-tight">Prospection</h1>
            <p className="text-sm text-muted-foreground">
              Trouvez de nouveaux clients potentiels en recherchant des commerces et contacts
            </p>
          </div>
        </div>
      </div>

      {/* Info card */}
      <Card className="p-4 bg-primary/5 border-primary/20">
        <div className="flex items-start gap-3">
          <Info className="h-5 w-5 text-primary shrink-0 mt-0.5" />
          <div className="text-sm text-muted-foreground space-y-1">
            <p className="font-medium text-foreground">Comment ça fonctionne ?</p>
            <p>
              Entrez une <strong>localisation</strong> (ex: Montréal), un{" "}
              <strong>secteur</strong> (ex: université) et une <strong>cible spécifique</strong>{" "}
              (ex: cafétéria). L&apos;outil va chercher sur le web les commerces correspondants et
              extraire automatiquement les emails, numéros de téléphone et adresses trouvés sur
              leurs sites web.
            </p>
            <p>
              <Sparkles className="h-3.5 w-3.5 inline mr-1" />
              Cliquez sur un contact pour le copier. Vous pouvez aussi exporter tous les
              résultats en CSV.
            </p>
          </div>
        </div>
      </Card>

      {/* Formulaire de recherche */}
      <ProspectionSearchForm onSearch={handleSearch} isLoading={isLoading} />

      {/* État de chargement */}
      {isLoading && (
        <Card className="p-8">
          <div className="flex flex-col items-center justify-center gap-4">
            <div className="relative">
              <div className="h-12 w-12 rounded-full border-4 border-primary/20 border-t-primary animate-spin" />
            </div>
            <div className="text-center space-y-1">
              <p className="text-sm font-medium">Recherche en cours...</p>
              <p className="text-xs text-muted-foreground">
                Analyse des pages web et extraction des contacts. Cela peut prendre 15-30 secondes.
              </p>
            </div>
          </div>
        </Card>
      )}

      {/* Résultats */}
      {results && !isLoading && (
        <ProspectionResults results={results} searchParams={searchParams} />
      )}
    </div>
  )
}
