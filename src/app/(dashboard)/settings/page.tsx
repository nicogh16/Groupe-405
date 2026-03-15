import { createClient } from "@/lib/supabase/server"
import { redirect } from "next/navigation"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { TeamManager } from "@/components/settings/team-manager"
import { TemplatesManager } from "@/components/settings/templates-manager"
import type { Profile, ProjectTemplateWithApp } from "@/types"

export default async function SettingsPage() {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) redirect("/login")

  // Vérifier si admin pour voir la liste des membres
  const { data: currentProfile } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", user.id)
    .single()

  const profile = currentProfile as Profile | null
  const isAdmin = profile?.role === "admin"

  // Si admin, charger tous les profils
  let teamMembers: Profile[] = []
  let templates: ProjectTemplateWithApp[] = []
  if (isAdmin) {
    const { data } = await supabase.from("profiles").select("*").order("created_at")
    teamMembers = (data ?? []) as Profile[]

    const { data: templatesRaw } = await supabase
      .from("project_templates")
      .select("*, app:apps(*)")
      .order("name")
    templates = (templatesRaw ?? []) as unknown as ProjectTemplateWithApp[]
  }

  return (
    <div className="space-y-6 max-w-4xl">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Paramètres</h1>
        <p className="text-sm text-muted-foreground mt-1">
          Gérez votre profil, votre équipe et vos templates.
        </p>
      </div>

      {/* Mon profil */}
      <Card className="border-border/50">
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-medium">Mon profil</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="grid grid-cols-2 gap-4 text-sm">
            <div>
              <p className="text-muted-foreground text-xs">Nom</p>
              <p className="font-medium">{profile?.full_name ?? "—"}</p>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">Email</p>
              <p className="font-medium">{user.email}</p>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">Rôle</p>
              <Badge variant={profile?.role === "admin" ? "default" : "secondary"}>
                {profile?.role ?? "viewer"}
              </Badge>
            </div>
            <div>
              <p className="text-muted-foreground text-xs">Membre depuis</p>
              <p className="font-medium">
                {new Date(user.created_at).toLocaleDateString("fr-CA")}
              </p>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Gestion d'équipe (admin seulement) */}
      {isAdmin && (
        <Card className="border-border/50">
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-medium">
              Équipe ({teamMembers.length} membre{teamMembers.length > 1 ? "s" : ""})
            </CardTitle>
          </CardHeader>
          <CardContent>
            <TeamManager
              teamMembers={teamMembers}
              currentUserId={user.id}
            />
          </CardContent>
        </Card>
      )}

      {/* Gestion des templates (admin seulement) */}
      {isAdmin && <TemplatesManager templates={templates} />}
    </div>
  )
}
