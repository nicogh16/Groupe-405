"use client"

import { useState } from "react"
import { Search, MapPin, Building2, Tag, Target, Loader2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Card } from "@/components/ui/card"

interface SearchFormProps {
  onSearch: (data: {
    location: string
    sector: string
    keywords: string
    specificTarget: string
  }) => void
  isLoading: boolean
}

const QUICK_SEARCHES = [
  { label: "Cafétérias universitaires", location: "Montréal", sector: "université", keywords: "", specificTarget: "cafétéria" },
  { label: "Restaurants", location: "Montréal", sector: "restaurant", keywords: "menu fidélité", specificTarget: "restaurant" },
  { label: "Salons de coiffure", location: "Montréal", sector: "salon coiffure", keywords: "", specificTarget: "salon beauté" },
  { label: "Cafés", location: "Montréal", sector: "café coffee shop", keywords: "", specificTarget: "café" },
  { label: "Gyms & Fitness", location: "Montréal", sector: "gym fitness", keywords: "abonnement", specificTarget: "centre sportif" },
  { label: "Boulangeries", location: "Montréal", sector: "boulangerie pâtisserie", keywords: "", specificTarget: "boulangerie" },
]

export function ProspectionSearchForm({ onSearch, isLoading }: SearchFormProps) {
  const [location, setLocation] = useState("")
  const [sector, setSector] = useState("")
  const [keywords, setKeywords] = useState("")
  const [specificTarget, setSpecificTarget] = useState("")

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    onSearch({ location, sector, keywords, specificTarget })
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
    })
  }

  return (
    <Card className="p-6">
      <form onSubmit={handleSubmit} className="space-y-6">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {/* Localisation */}
          <div className="space-y-2">
            <Label htmlFor="location" className="flex items-center gap-2">
              <MapPin className="h-4 w-4 text-primary" />
              Localisation
            </Label>
            <Input
              id="location"
              placeholder="ex: Montréal, Québec, Laval..."
              value={location}
              onChange={(e) => setLocation(e.target.value)}
            />
          </div>

          {/* Secteur / Industrie */}
          <div className="space-y-2">
            <Label htmlFor="sector" className="flex items-center gap-2">
              <Building2 className="h-4 w-4 text-primary" />
              Secteur / Industrie
            </Label>
            <Input
              id="sector"
              placeholder="ex: université, restaurant, hôtel..."
              value={sector}
              onChange={(e) => setSector(e.target.value)}
            />
          </div>

          {/* Cible spécifique */}
          <div className="space-y-2">
            <Label htmlFor="specificTarget" className="flex items-center gap-2">
              <Target className="h-4 w-4 text-primary" />
              Cible spécifique
            </Label>
            <Input
              id="specificTarget"
              placeholder="ex: cafétéria, food court, cantine..."
              value={specificTarget}
              onChange={(e) => setSpecificTarget(e.target.value)}
            />
            <p className="text-xs text-muted-foreground">
              Le type de commerce ou service précis que vous cherchez
            </p>
          </div>

          {/* Mots-clés supplémentaires */}
          <div className="space-y-2">
            <Label htmlFor="keywords" className="flex items-center gap-2">
              <Tag className="h-4 w-4 text-primary" />
              Mots-clés (optionnel)
            </Label>
            <Input
              id="keywords"
              placeholder="ex: fidélité, menu, abonnement..."
              value={keywords}
              onChange={(e) => setKeywords(e.target.value)}
            />
            <p className="text-xs text-muted-foreground">
              Mots-clés supplémentaires pour affiner la recherche
            </p>
          </div>
        </div>

        <div className="flex items-center gap-3">
          <Button type="submit" disabled={isLoading || (!location && !sector && !specificTarget)}>
            {isLoading ? (
              <>
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                Recherche en cours...
              </>
            ) : (
              <>
                <Search className="mr-2 h-4 w-4" />
                Rechercher des prospects
              </>
            )}
          </Button>
        </div>
      </form>

      {/* Recherches rapides */}
      <div className="mt-6 pt-4 border-t">
        <p className="text-sm font-medium text-muted-foreground mb-3">Recherches rapides :</p>
        <div className="flex flex-wrap gap-2">
          {QUICK_SEARCHES.map((qs) => (
            <Button
              key={qs.label}
              variant="outline"
              size="sm"
              onClick={() => handleQuickSearch(qs)}
              disabled={isLoading}
              className="text-xs"
            >
              {qs.label}
            </Button>
          ))}
        </div>
      </div>
    </Card>
  )
}
