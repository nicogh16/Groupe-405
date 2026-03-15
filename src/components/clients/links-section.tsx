import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { ExternalLink, Database, Triangle, Github } from "lucide-react"

interface LinksSectionProps {
  supabaseProjectRef: string | null
  vercelProjectUrl: string | null
  githubRepoUrl: string | null
}

function LinkItem({
  label,
  url,
  icon: Icon,
}: {
  label: string
  url: string
  icon: React.ComponentType<{ className?: string }>
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
  supabaseProjectRef,
  vercelProjectUrl,
  githubRepoUrl,
}: LinksSectionProps) {
  const links = [
    supabaseProjectRef && {
      label: "Supabase Dashboard",
      url: `https://supabase.com/dashboard/project/${supabaseProjectRef}`,
      icon: Database,
    },
    vercelProjectUrl && {
      label: "Vercel",
      url: vercelProjectUrl,
      icon: Triangle,
    },
    githubRepoUrl && {
      label: "GitHub",
      url: githubRepoUrl,
      icon: Github,
    },
  ].filter(Boolean) as { label: string; url: string; icon: React.ComponentType<{ className?: string }> }[]

  if (links.length === 0) return null

  return (
    <Card className="border-border/50">
      <CardHeader className="pb-3">
        <CardTitle className="text-sm font-medium">Liens externes</CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">
        {links.map((link) => (
          <LinkItem key={link.label} {...link} />
        ))}
      </CardContent>
    </Card>
  )
}
