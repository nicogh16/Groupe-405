"use client"

import { useState, useCallback } from "react"
import { Loader2 } from "lucide-react"
import { ProspectionSearchForm } from "@/components/prospection/search-form"
import { ProspectionResults } from "@/components/prospection/results-table"
import { searchProspects } from "./actions"
import type { SearchResult } from "./actions"
import { Card, CardContent } from "@/components/ui/card"

export default function ProspectionPage() {
  const [isLoading, setIsLoading] = useState(false)
  const [results, setResults] = useState<SearchResult | null>(null)
  const [searchParams, setSearchParams] = useState({
    location: "",
    sector: "",
    keywords: "",
    specificTarget: "",
  })
  const [progress, setProgress] = useState("")

  const handleSearch = useCallback(async (params: {
    location: string
    sector: string
    keywords: string
    specificTarget: string
    maxResults: number
  }) => {
    setIsLoading(true)
    setSearchParams(params)
    setResults(null)
    setProgress("Lancement des recherches...")

    try {
      // Simuler progression (le server action ne peut pas streamer)
      const progressTimer = setInterval(() => {
        setProgress((prev) => {
          if (prev.includes("Extraction")) return "Analyse des pages et extraction des contacts..."
          if (prev.includes("pages")) return "Extraction des emails et téléphones..."
          if (prev.includes("Recherche")) return "Analyse des pages web trouvées..."
          return "Recherche en cours sur plusieurs moteurs..."
        })
      }, 4000)

      const data = await searchProspects(params)
      clearInterval(progressTimer)
      setResults(data)
    } catch (error) {
      console.error("Erreur:", error)
      setResults({
        leads: [],
        totalScraped: 0,
        totalSearchResults: 0,
        errors: ["Une erreur est survenue. Veuillez réessayer."],
        searchQueries: [],
      })
    } finally {
      setIsLoading(false)
      setProgress("")
    }
  }, [])

  return (
    <div className="space-y-6">
      {/* Header — même style que les autres pages */}
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Prospection</h1>
        <p className="text-sm text-muted-foreground mt-1">
          Trouvez de nouveaux clients en recherchant des commerces et leurs coordonnées
        </p>
      </div>

      {/* Formulaire */}
      <ProspectionSearchForm onSearch={handleSearch} isLoading={isLoading} />

      {/* Chargement */}
      {isLoading && (
        <Card className="border border-border/50">
          <CardContent className="py-12">
            <div className="flex flex-col items-center justify-center gap-3">
              <Loader2 className="h-8 w-8 text-primary animate-spin" />
              <div className="text-center">
                <p className="text-sm font-medium">{progress || "Recherche en cours..."}</p>
                <p className="text-xs text-muted-foreground mt-1">
                  Cela peut prendre 30 à 60 secondes selon le nombre de résultats demandés.
                </p>
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Résultats */}
      {results && !isLoading && (
        <ProspectionResults results={results} searchParams={searchParams} />
      )}
    </div>
  )
}
