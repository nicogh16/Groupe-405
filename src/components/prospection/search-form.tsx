"use client"

import { useState } from "react"
import { Search, MapPin, Building2, Tag, Target, Loader2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"

interface SearchFormProps {
  onSearch: (data: {
    location: string
    sector: string
    keywords: string
    specificTarget: string
    maxResults: number
  }) => void
  isLoading: boolean
}

const QUICK_SEARCHES = [
  { label: "🍽️ Cafétérias universitaires", location: "Montréal", sector: "université", keywords: "", specificTarget: "cafétéria" },
  { label: "🍕 Restaurants", location: "Montréal", sector: "restaurant", keywords: "menu fidélité", specificTarget: "restaurant" },
  { label: "✂️ Salons coiffure", location: "Montréal", sector: "salon coiffure", keywords: "", specificTarget: "salon beauté" },
  { label: "☕ Cafés", location: "Montréal", sector: "café coffee shop", keywords: "", specificTarget: "café" },
  { label: "💪 Gyms & Fitness", location: "Montréal", sector: "gym fitness", keywords: "abonnement", specificTarget: "centre sportif" },
  { label: "🥖 Boulangeries", location: "Montréal", sector: "boulangerie pâtisserie", keywords: "", specificTarget: "boulangerie" },
  { label: "🧁 Pâtisseries", location: "Québec", sector: "pâtisserie", keywords: "", specificTarget: "pâtisserie" },
  { label: "🏨 Hôtels", location: "Montréal", sector: "hôtel hébergement", keywords: "", specificTarget: "hôtel" },
]

export function ProspectionSearchForm({ onSearch, isLoading }: SearchFormProps) {
  const [location, setLocation] = useState("")
  const [sector, setSector] = useState("")
  const [keywords, setKeywords] = useState("")
  const [specificTarget, setSpecificTarget] = useState("")
  const [maxResults, setMaxResults] = useState("15")

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    onSearch({ location, sector, keywords, specificTarget, maxResults: parseInt(maxResults) })
  }

  const handleQuickSearch = (qs: (typeof QUICK_SEARCHES)[0]) => {
    setLocation(qs.location)
    setSector(qs.sector)
    setKeywords(qs.keywords)
    setSpecificTarget(qs.specificTarget)
    onSearch({
      location: qs.location,
      sector: qs.sector,
      keywords: qs.keywords,
      specificTarget: qs.specificTarget,
      maxResults: parseInt(maxResults),
    })
  }

  const canSearch = !isLoading && (location || sector || specificTarget)

  return (
    <div className="space-y-4">
      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <div className="space-y-1.5">
            <Label htmlFor="location" className="text-xs font-medium text-muted-foreground uppercase tracking-wide flex items-center gap-1.5">
              <MapPin className="h-3.5 w-3.5" />
              Localisation
            </Label>
            <Input
              id="location"
              placeholder="Montréal, Québec, Laval..."
              value={location}
              onChange={(e) => setLocation(e.target.value)}
              className="h-10"
            />
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="sector" className="text-xs font-medium text-muted-foreground uppercase tracking-wide flex items-center gap-1.5">
              <Building2 className="h-3.5 w-3.5" />
              Secteur / Industrie
            </Label>
            <Input
              id="sector"
              placeholder="université, restaurant, hôtel..."
              value={sector}
              onChange={(e) => setSector(e.target.value)}
              className="h-10"
            />
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="specificTarget" className="text-xs font-medium text-muted-foreground uppercase tracking-wide flex items-center gap-1.5">
              <Target className="h-3.5 w-3.5" />
              Cible spécifique
            </Label>
            <Input
              id="specificTarget"
              placeholder="cafétéria, food court, cantine..."
              value={specificTarget}
              onChange={(e) => setSpecificTarget(e.target.value)}
              className="h-10"
            />
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="keywords" className="text-xs font-medium text-muted-foreground uppercase tracking-wide flex items-center gap-1.5">
              <Tag className="h-3.5 w-3.5" />
              Mots-clés (optionnel)
            </Label>
            <Input
              id="keywords"
              placeholder="fidélité, menu, abonnement..."
              value={keywords}
              onChange={(e) => setKeywords(e.target.value)}
              className="h-10"
            />
          </div>

          <div className="space-y-1.5">
            <Label className="text-xs font-medium text-muted-foreground uppercase tracking-wide flex items-center gap-1.5">
              <Search className="h-3.5 w-3.5" />
              Nombre de résultats
            </Label>
            <Select value={maxResults} onValueChange={setMaxResults}>
              <SelectTrigger className="h-10">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="5">5 prospects</SelectItem>
                <SelectItem value="10">10 prospects</SelectItem>
                <SelectItem value="15">15 prospects</SelectItem>
                <SelectItem value="25">25 prospects</SelectItem>
                <SelectItem value="35">35 prospects</SelectItem>
                <SelectItem value="50">50 prospects</SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div className="flex items-end">
            <Button type="submit" disabled={!canSearch} className="w-full h-10">
              {isLoading ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  Recherche...
                </>
              ) : (
                <>
                  <Search className="mr-2 h-4 w-4" />
                  Rechercher
                </>
              )}
            </Button>
          </div>
        </div>
      </form>

      {/* Recherches rapides */}
      <div className="flex flex-wrap gap-1.5">
        <span className="text-xs text-muted-foreground self-center mr-1">Rapide :</span>
        {QUICK_SEARCHES.map((qs) => (
          <button
            key={qs.label}
            onClick={() => handleQuickSearch(qs)}
            disabled={isLoading}
            className="inline-flex items-center rounded-md border border-border/50 bg-card px-2.5 py-1 text-xs text-muted-foreground hover:text-foreground hover:bg-muted transition-colors disabled:opacity-50"
          >
            {qs.label}
          </button>
        ))}
      </div>
    </div>
  )
}
