"use client"

import { useState, useTransition } from "react"
import type { ComponentType } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { toast } from "sonner"
import {
  ExternalLink,
  Database,
  Triangle,
  Github,
  Pencil,
  Save,
  Loader2,
  Globe,
} from "lucide-react"
import { updateClientLinks } from "@/app/(dashboard)/clients/[slug]/actions"

interface LinksSectionProps {
  clientId: string
  supabaseProjectRef: string | null
  supabaseUrl: string | null
  vercelProjectUrl: string | null
  githubRepoUrl: string | null
  isAdmin: boolean
}

function LinkItem({
  label,
  url,
  icon: Icon,
}: {
  label: string
  url: string
  icon: ComponentType<{ className?: string }>
}) {
  return (
    <a
      href={url}
      target="_blank"
      rel="noopener noreferrer"
      className="flex items-center gap-3 rounded-md border border-border/50 px-3 py-2.5 text-sm transition-colors hover:bg-accent"
    >
      <Icon className="h-4 w-4 text-muted-foreground" />
      <span className="flex-1">{label}</span>
      <ExternalLink className="h-3 w-3 text-muted-foreground" />
    </a>
  )
}

export function LinksSection({
  clientId,
  supabaseProjectRef,
  supabaseUrl,
  vercelProjectUrl,
  githubRepoUrl,
  isAdmin,
}: LinksSectionProps) {
  const [isEditing, setIsEditing] = useState(false)
  const [isPending, startTransition] = useTransition()

  const [ref, setRef] = useState(supabaseProjectRef ?? "")
  const [vercel, setVercel] = useState(vercelProjectUrl ?? "")
  const [github, setGithub] = useState(githubRepoUrl ?? "")

  const links = [
    supabaseProjectRef
      ? {
          label: "Supabase Dashboard",
          url: `https://supabase.com/dashboard/project/${supabaseProjectRef}`,
          icon: Database,
        }
      : null,
    vercelProjectUrl
      ? { label: "Site web", url: vercelProjectUrl, icon: Triangle }
      : null,
    githubRepoUrl ? { label: "GitHub", url: githubRepoUrl, icon: Github } : null,
  ].filter(Boolean) as { label: string; url: string; icon: ComponentType<{ className?: string }> }[]

  return (
    <Card className="border-border/50">
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between gap-3">
          <CardTitle className="text-sm font-medium">Liens externes</CardTitle>
          {isAdmin && (
            <Button
              type="button"
              size="sm"
              variant="outline"
              className="h-8"
              onClick={() => setIsEditing((v) => !v)}
              disabled={isPending}
            >
              <Pencil className="mr-2 h-4 w-4" />
              {isEditing ? "Fermer" : "Modifier"}
            </Button>
          )}
        </div>
      </CardHeader>

      <CardContent className="space-y-3">
        {isEditing && isAdmin ? (
          <form
            onSubmit={(e) => {
              e.preventDefault()
              const formData = new FormData()
              formData.set("clientId", clientId)
              formData.set("supabaseProjectRef", ref)
              formData.set("vercelProjectUrl", vercel)
              formData.set("githubRepoUrl", github)

              startTransition(async () => {
                const result = await updateClientLinks(formData)
                if (result?.error) {
                  toast.error(result.error)
                } else {
                  toast.success("Liens mis à jour")
                  setIsEditing(false)
                }
              })
            }}
            className="space-y-4"
          >
            <div className="grid gap-3">
              <div className="space-y-2">
                <Label htmlFor="supabaseProjectRef">Supabase project ref</Label>
                <Input
                  id="supabaseProjectRef"
                  value={ref}
                  onChange={(e) => setRef(e.target.value)}
                  placeholder="medpkzuculodumzlmbrk"
                  disabled={isPending}
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="vercelProjectUrl">Site web (Vercel URL)</Label>
                <Input
                  id="vercelProjectUrl"
                  value={vercel}
                  onChange={(e) => setVercel(e.target.value)}
                  placeholder="https://vercel.com/..."
                  disabled={isPending}
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="githubRepoUrl">GitHub repo URL</Label>
                <Input
                  id="githubRepoUrl"
                  value={github}
                  onChange={(e) => setGithub(e.target.value)}
                  placeholder="https://github.com/..."
                  disabled={isPending}
                />
              </div>
            </div>

            <Button type="submit" size="sm" variant="outline" disabled={isPending}>
              {isPending ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Save className="mr-2 h-4 w-4" />}
              Sauvegarder
            </Button>
          </form>
        ) : (
          <>
            {links.length > 0 ? (
              <div className="space-y-2">
                {links.map((link) => (
                  <LinkItem key={link.label} {...link} />
                ))}
              </div>
            ) : (
              <p className="text-sm text-muted-foreground">Aucun lien configuré.</p>
            )}
          </>
        )}
      </CardContent>
    </Card>
  )
}

