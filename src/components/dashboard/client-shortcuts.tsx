"use client"

import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip"
import { Database, Globe, Github, ExternalLink } from "lucide-react"

interface ClientShortcutsProps {
  supabaseProjectRef: string | null
  supabaseUrl: string | null
  vercelProjectUrl: string | null
  githubRepoUrl: string | null
}

export function ClientShortcuts({
  supabaseProjectRef,
  supabaseUrl,
  vercelProjectUrl,
  githubRepoUrl,
}: ClientShortcutsProps) {
  const supabaseDashboard = supabaseProjectRef
    ? `https://supabase.com/dashboard/project/${supabaseProjectRef}`
    : null

  const shortcuts = [
    { href: supabaseDashboard, icon: Database, label: "Supabase", color: "hover:text-emerald-500" },
    { href: githubRepoUrl, icon: Github, label: "GitHub", color: "hover:text-foreground" },
    // Le "site web" correspond ici au déploiement Vercel
    { href: vercelProjectUrl, icon: ExternalLink, label: "Site web", color: "hover:text-foreground" },
  ].filter((s) => s.href)

  if (shortcuts.length === 0) return null

  return (
    <TooltipProvider delayDuration={200}>
      <div className="flex items-center gap-1">
        {shortcuts.map((shortcut) => (
          <Tooltip key={shortcut.label}>
            <TooltipTrigger asChild>
              <a
                href={shortcut.href!}
                target="_blank"
                rel="noopener noreferrer"
                onClick={(e) => e.stopPropagation()}
                className={`inline-flex items-center justify-center h-8 w-8 rounded-md text-muted-foreground ${shortcut.color} hover:bg-accent transition-colors`}
              >
                <shortcut.icon className="h-4 w-4" />
              </a>
            </TooltipTrigger>
            <TooltipContent side="bottom" className="text-xs">
              {shortcut.label}
            </TooltipContent>
          </Tooltip>
        ))}
      </div>
    </TooltipProvider>
  )
}
