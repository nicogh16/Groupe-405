"use client"

import { useState, useTransition } from "react"
import { useRouter } from "next/navigation"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Separator } from "@/components/ui/separator"
import { Textarea } from "@/components/ui/textarea"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import {
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger,
} from "@/components/ui/tabs"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import {
  GitBranch,
  Database,
  Globe,
  HardDrive,
  CheckCircle2,
  XCircle,
  Save,
  Loader2,
  Plus,
  Trash2,
  Server,
  Key,
  Settings,
  Eye,
  EyeOff,
  ExternalLink,
  Smartphone,
  Monitor,
  ChevronDown,
  ChevronUp,
  FunctionSquare,
  TableIcon,
  Layers,
  Code2,
  Palette,
} from "lucide-react"
import { toast } from "sonner"
import {
  updateTemplate,
  updateTemplateBuckets,
  updateTemplateEnvVars,
} from "@/app/(dashboard)/settings/actions"
import { SUPABASE_REGIONS } from "@/lib/validations/provisioning"
import type {
  ProjectTemplateWithApp,
  StorageBucketConfig,
  EnvVarTemplate,
  SchemaSnapshot,
} from "@/types"

interface TemplatesManagerProps {
  templates: ProjectTemplateWithApp[]
}

// ─── Sous-composant : Header App ────────────────────────────────────────────

function AppHeader({ template }: { template: ProjectTemplateWithApp }) {
  const app = template.app
  return (
    <div className="flex items-start gap-4 p-4 rounded-lg bg-muted/30 border">
      {/* Logo/Couleur */}
      <div
        className="w-14 h-14 rounded-xl flex items-center justify-center text-white font-bold text-xl shrink-0 shadow-sm"
        style={{ backgroundColor: app?.color ?? "#3B82F6" }}
      >
        {app?.logo_url ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={app.logo_url} alt={app.name} className="w-10 h-10 object-contain" />
        ) : (
          app?.name?.charAt(0) ?? "?"
        )}
      </div>

      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 mb-1">
          <h3 className="text-base font-semibold">{app?.name}</h3>
          <Badge variant="outline" className="text-[10px]">{app?.slug}</Badge>
          {template.is_active ? (
            <Badge variant="default" className="text-[10px] gap-1">
              <CheckCircle2 className="h-2.5 w-2.5" /> Actif
            </Badge>
          ) : (
            <Badge variant="secondary" className="text-[10px] gap-1">
              <XCircle className="h-2.5 w-2.5" /> Inactif
            </Badge>
          )}
        </div>
        <p className="text-sm text-muted-foreground mb-2">
          {app?.description ?? "Aucune description"}
        </p>

        {/* Tech Stack */}
        {app?.tech_stack && app.tech_stack.length > 0 && (
          <div className="flex flex-wrap gap-1 mb-2">
            {app.tech_stack.map((tech) => (
              <Badge key={tech} variant="secondary" className="text-[10px] font-mono">
                {tech}
              </Badge>
            ))}
          </div>
        )}

        {/* Repos & URLs */}
        <div className="flex flex-wrap gap-3 text-xs text-muted-foreground">
          {app?.github_dashboard_repo && (
            <a
              href={app.github_dashboard_repo}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-1 hover:text-foreground transition"
            >
              <Monitor className="h-3 w-3" />
              Dashboard repo
              <ExternalLink className="h-2.5 w-2.5" />
            </a>
          )}
          {app?.github_mobile_repo && (
            <a
              href={app.github_mobile_repo}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-1 hover:text-foreground transition"
            >
              <Smartphone className="h-3 w-3" />
              Mobile repo
              <ExternalLink className="h-2.5 w-2.5" />
            </a>
          )}
          {app?.vercel_dashboard_url && (
            <a
              href={app.vercel_dashboard_url}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-1 hover:text-foreground transition"
            >
              <Globe className="h-3 w-3" />
              Vercel
              <ExternalLink className="h-2.5 w-2.5" />
            </a>
          )}
        </div>
      </div>

      <div className="text-right shrink-0 text-xs text-muted-foreground space-y-0.5">
        <p>Template v{template.version}</p>
        <p>Créé le {new Date(template.created_at).toLocaleDateString("fr-CA")}</p>
      </div>
    </div>
  )
}

// ─── Sous-composant : Général ───────────────────────────────────────────────

function GeneralSection({
  template,
  isPending,
  onSave,
}: {
  template: ProjectTemplateWithApp
  isPending: boolean
  onSave: (data: Record<string, unknown>) => Promise<void>
}) {
  const [name, setName] = useState(template.name)
  const [description, setDescription] = useState(template.description ?? "")
  const [isActive, setIsActive] = useState(template.is_active)

  const hasChanges =
    name !== template.name ||
    description !== (template.description ?? "") ||
    isActive !== template.is_active

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-4">
        <div className="space-y-2">
          <Label>Nom du template</Label>
          <Input value={name} onChange={(e) => setName(e.target.value)} disabled={isPending} />
        </div>
        <div className="space-y-2">
          <Label>Statut</Label>
          <Button
            variant={isActive ? "default" : "secondary"}
            className="w-full gap-2"
            onClick={() => setIsActive(!isActive)}
            disabled={isPending}
          >
            {isActive ? (
              <><CheckCircle2 className="h-3.5 w-3.5" /> Actif</>
            ) : (
              <><XCircle className="h-3.5 w-3.5" /> Inactif</>
            )}
          </Button>
          <p className="text-xs text-muted-foreground">
            Les templates inactifs ne sont pas proposés lors du provisionnement.
          </p>
        </div>
      </div>

      <div className="space-y-2">
        <Label>Description</Label>
        <Textarea
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          disabled={isPending}
          rows={3}
          placeholder="Description du template..."
        />
      </div>

      {hasChanges && (
        <Button
          size="sm"
          className="gap-2"
          disabled={isPending}
          onClick={() => onSave({ name, description: description || null, is_active: isActive })}
        >
          {isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Save className="h-3.5 w-3.5" />}
          Enregistrer
        </Button>
      )}
    </div>
  )
}

// ─── Sous-composant : GitHub ────────────────────────────────────────────────

function GitHubSection({
  template,
  isPending,
  onSave,
}: {
  template: ProjectTemplateWithApp
  isPending: boolean
  onSave: (data: Record<string, unknown>) => Promise<void>
}) {
  const [owner, setOwner] = useState(template.github_template_owner)
  const [repo, setRepo] = useState(template.github_template_repo)
  const [migrationsPath, setMigrationsPath] = useState(template.github_migrations_path)

  const hasChanges =
    owner !== template.github_template_owner ||
    repo !== template.github_template_repo ||
    migrationsPath !== template.github_migrations_path

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-4">
        <div className="space-y-2">
          <Label>Propriétaire GitHub</Label>
          <Input
            value={owner}
            onChange={(e) => setOwner(e.target.value)}
            disabled={isPending}
            className="font-mono text-sm"
          />
        </div>
        <div className="space-y-2">
          <Label>Repo template</Label>
          <Input
            value={repo}
            onChange={(e) => setRepo(e.target.value)}
            disabled={isPending}
            className="font-mono text-sm"
          />
        </div>
      </div>

      <div className="space-y-2">
        <Label>Chemin des migrations SQL</Label>
        <Input
          value={migrationsPath}
          onChange={(e) => setMigrationsPath(e.target.value)}
          disabled={isPending}
          className="font-mono text-sm"
        />
        <p className="text-xs text-muted-foreground">
          Chemin relatif vers les fichiers .sql de migration dans le repo.
        </p>
      </div>

      <div className="p-3 rounded-md bg-muted/50 border flex items-center gap-3">
        <GitBranch className="h-4 w-4 text-muted-foreground shrink-0" />
        <div className="text-xs text-muted-foreground">
          <p>
            Le repo complet :{" "}
            <a
              href={`https://github.com/${owner}/${repo}`}
              target="_blank"
              rel="noopener noreferrer"
              className="font-mono text-foreground hover:underline inline-flex items-center gap-1"
            >
              {owner}/{repo}
              <ExternalLink className="h-2.5 w-2.5" />
            </a>
          </p>
          <p className="mt-1">
            Lors du provisionnement, un nouveau repo sera créé via GitHub &quot;Use this template&quot;.
          </p>
        </div>
      </div>

      {hasChanges && (
        <Button
          size="sm"
          className="gap-2"
          disabled={isPending}
          onClick={() =>
            onSave({
              github_template_owner: owner,
              github_template_repo: repo,
              github_migrations_path: migrationsPath,
            })
          }
        >
          {isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Save className="h-3.5 w-3.5" />}
          Enregistrer
        </Button>
      )}
    </div>
  )
}

// ─── Sous-composant : Supabase ──────────────────────────────────────────────

function SupabaseSection({
  template,
  isPending,
  onSave,
}: {
  template: ProjectTemplateWithApp
  isPending: boolean
  onSave: (data: Record<string, unknown>) => Promise<void>
}) {
  const [plan, setPlan] = useState<string>(template.default_supabase_plan)
  const [region, setRegion] = useState<string>(template.default_supabase_region)

  const hasChanges =
    plan !== template.default_supabase_plan || region !== template.default_supabase_region

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-4">
        <div className="space-y-2">
          <Label>Plan par défaut</Label>
          <Select value={plan} onValueChange={setPlan} disabled={isPending}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="free">Free (0$/mois)</SelectItem>
              <SelectItem value="pro">Pro (25$/mois)</SelectItem>
              <SelectItem value="team">Team (599$/mois)</SelectItem>
              <SelectItem value="enterprise">Enterprise</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-2">
          <Label>Région par défaut</Label>
          <Select value={region} onValueChange={setRegion} disabled={isPending}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              {SUPABASE_REGIONS.map((r) => (
                <SelectItem key={r.value} value={r.value}>{r.label}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </div>

      <div className="p-3 rounded-md bg-muted/50 border">
        <p className="text-xs text-muted-foreground">
          <Database className="h-3.5 w-3.5 inline mr-1" />
          Ces valeurs sont les défauts proposés lors du provisionnement. Modifiables pour chaque nouveau client.
        </p>
      </div>

      {hasChanges && (
        <Button
          size="sm"
          className="gap-2"
          disabled={isPending}
          onClick={() => onSave({ default_supabase_plan: plan, default_supabase_region: region })}
        >
          {isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Save className="h-3.5 w-3.5" />}
          Enregistrer
        </Button>
      )}
    </div>
  )
}

// ─── Sous-composant : Storage ───────────────────────────────────────────────

function StorageSection({
  template,
  isPending,
  startTransition,
  router,
}: {
  template: ProjectTemplateWithApp
  isPending: boolean
  startTransition: (fn: () => Promise<void>) => void
  router: ReturnType<typeof useRouter>
}) {
  const [buckets, setBuckets] = useState<StorageBucketConfig[]>(template.storage_buckets ?? [])
  const [showAdd, setShowAdd] = useState(false)
  const [newName, setNewName] = useState("")
  const [newPublic, setNewPublic] = useState(true)
  const [newSizeLimit, setNewSizeLimit] = useState("")
  const [newMime, setNewMime] = useState("")

  const hasChanges = JSON.stringify(template.storage_buckets ?? []) !== JSON.stringify(buckets)

  function handleAdd() {
    if (!newName.trim()) return
    setBuckets([
      ...buckets,
      {
        name: newName.trim().toLowerCase().replace(/\s+/g, "-"),
        public: newPublic,
        file_size_limit: newSizeLimit ? parseInt(newSizeLimit) : null,
        allowed_mime_types: newMime ? newMime.split(",").map((t) => t.trim()).filter(Boolean) : null,
      },
    ])
    setShowAdd(false)
    setNewName("")
    setNewSizeLimit("")
    setNewMime("")
  }

  function handleSave() {
    startTransition(async () => {
      const result = await updateTemplateBuckets(template.id, buckets)
      if (result.success) { toast.success("Buckets mis à jour"); router.refresh() }
      else toast.error(result.error || "Erreur")
    })
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <p className="text-sm text-muted-foreground">
          {buckets.length} bucket{buckets.length > 1 ? "s" : ""} configuré{buckets.length > 1 ? "s" : ""}
        </p>
        <Button variant="outline" size="sm" className="gap-2" onClick={() => setShowAdd(true)} disabled={isPending}>
          <Plus className="h-3.5 w-3.5" /> Ajouter
        </Button>
      </div>

      {buckets.length > 0 ? (
        <div className="space-y-2">
          {buckets.map((b, i) => (
            <div key={`${b.name}-${i}`} className="flex items-center gap-3 p-3 rounded-lg border bg-card">
              <HardDrive className="h-4 w-4 text-muted-foreground shrink-0" />
              <div className="flex-1 min-w-0">
                <p className="text-sm font-mono font-medium">{b.name}</p>
                <div className="flex items-center gap-2 mt-0.5">
                  <button
                    onClick={() => {
                      const u = [...buckets]; u[i] = { ...u[i], public: !u[i].public }; setBuckets(u)
                    }}
                    disabled={isPending}
                    className="text-xs text-muted-foreground hover:text-foreground transition flex items-center gap-1"
                  >
                    {b.public ? <><Eye className="h-3 w-3" /> Public</> : <><EyeOff className="h-3 w-3" /> Privé</>}
                  </button>
                  {b.file_size_limit && (
                    <span className="text-xs text-muted-foreground">· Max: {(b.file_size_limit / 1024 / 1024).toFixed(0)} MB</span>
                  )}
                  {b.allowed_mime_types && b.allowed_mime_types.length > 0 && (
                    <span className="text-xs text-muted-foreground">· {b.allowed_mime_types.join(", ")}</span>
                  )}
                </div>
              </div>
              <Button
                variant="ghost" size="icon" className="h-7 w-7 text-destructive hover:bg-destructive/10 shrink-0"
                onClick={() => setBuckets(buckets.filter((_, idx) => idx !== i))} disabled={isPending}
              >
                <Trash2 className="h-3.5 w-3.5" />
              </Button>
            </div>
          ))}
        </div>
      ) : (
        <p className="text-center py-6 text-xs text-muted-foreground">Aucun bucket configuré.</p>
      )}

      {hasChanges && (
        <Button size="sm" className="gap-2" disabled={isPending} onClick={handleSave}>
          {isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Save className="h-3.5 w-3.5" />}
          Enregistrer les buckets
        </Button>
      )}

      <Dialog open={showAdd} onOpenChange={setShowAdd}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Ajouter un bucket Storage</DialogTitle>
            <DialogDescription>Ce bucket sera créé lors du provisionnement de nouveaux clients.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label>Nom</Label>
              <Input value={newName} onChange={(e) => setNewName(e.target.value)} placeholder="avatars, uploads..." className="font-mono" />
            </div>
            <div className="flex items-center justify-between">
              <Label>Public</Label>
              <Button variant={newPublic ? "default" : "secondary"} size="sm" onClick={() => setNewPublic(!newPublic)}>
                {newPublic ? "Public" : "Privé"}
              </Button>
            </div>
            <div className="space-y-2">
              <Label>Taille max par fichier (octets)</Label>
              <Input value={newSizeLimit} onChange={(e) => setNewSizeLimit(e.target.value)} placeholder="5242880 (= 5 MB)" type="number" />
            </div>
            <div className="space-y-2">
              <Label>Types MIME autorisés</Label>
              <Input value={newMime} onChange={(e) => setNewMime(e.target.value)} placeholder="image/jpeg, image/png, image/webp" className="font-mono text-sm" />
              <p className="text-xs text-muted-foreground">Séparés par des virgules. Vide = tout accepter.</p>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowAdd(false)}>Annuler</Button>
            <Button onClick={handleAdd} disabled={!newName.trim()}>Ajouter</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

// ─── Sous-composant : Vercel + Env Vars ─────────────────────────────────────

function VercelSection({
  template,
  isPending,
  onSave,
  startTransition,
  router,
}: {
  template: ProjectTemplateWithApp
  isPending: boolean
  onSave: (data: Record<string, unknown>) => Promise<void>
  startTransition: (fn: () => Promise<void>) => void
  router: ReturnType<typeof useRouter>
}) {
  const [framework, setFramework] = useState<string>(template.vercel_framework || "other")
  const [buildCmd, setBuildCmd] = useState(template.vercel_build_command ?? "")
  const [outDir, setOutDir] = useState(template.vercel_output_directory ?? "")

  const [envVars, setEnvVars] = useState<EnvVarTemplate[]>(template.env_vars_template ?? [])
  const [showAddEnv, setShowAddEnv] = useState(false)
  const [newKey, setNewKey] = useState("")
  const [newDesc, setNewDesc] = useState("")
  const [newAuto, setNewAuto] = useState(false)
  const [newSecret, setNewSecret] = useState(false)

  const normalizedFramework = framework === "other" ? "" : framework
  const normalizedTemplateFramework = template.vercel_framework || ""
  const hasVercelChanges =
    normalizedFramework !== normalizedTemplateFramework ||
    buildCmd !== (template.vercel_build_command ?? "") ||
    outDir !== (template.vercel_output_directory ?? "")

  const hasEnvChanges = JSON.stringify(template.env_vars_template ?? []) !== JSON.stringify(envVars)

  function handleAddEnv() {
    if (!newKey.trim()) return
    setEnvVars([...envVars, { key: newKey.trim(), description: newDesc.trim(), auto: newAuto, secret: newSecret }])
    setShowAddEnv(false)
    setNewKey(""); setNewDesc(""); setNewAuto(false); setNewSecret(false)
  }

  function handleSaveEnv() {
    startTransition(async () => {
      const result = await updateTemplateEnvVars(template.id, envVars)
      if (result.success) { toast.success("Variables mises à jour"); router.refresh() }
      else toast.error(result.error || "Erreur")
    })
  }

  return (
    <div className="space-y-6">
      {/* Vercel Config */}
      <div className="space-y-4">
        <h4 className="text-sm font-medium flex items-center gap-2"><Server className="h-4 w-4" /> Configuration Vercel</h4>
        <div className="space-y-2">
          <Label>Framework</Label>
          <Select value={framework} onValueChange={setFramework} disabled={isPending}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="nextjs">Next.js</SelectItem>
              <SelectItem value="react">React (Vite)</SelectItem>
              <SelectItem value="nuxtjs">Nuxt.js</SelectItem>
              <SelectItem value="svelte">SvelteKit</SelectItem>
              <SelectItem value="astro">Astro</SelectItem>
              <SelectItem value="other">Autre</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div className="grid grid-cols-2 gap-4">
          <div className="space-y-2">
            <Label>Build command</Label>
            <Input value={buildCmd} onChange={(e) => setBuildCmd(e.target.value)} disabled={isPending} placeholder="Détection auto" className="font-mono text-sm" />
          </div>
          <div className="space-y-2">
            <Label>Output directory</Label>
            <Input value={outDir} onChange={(e) => setOutDir(e.target.value)} disabled={isPending} placeholder="Détection auto" className="font-mono text-sm" />
          </div>
        </div>
        {hasVercelChanges && (
          <Button size="sm" className="gap-2" disabled={isPending}
            onClick={() => onSave({ vercel_framework: framework === "other" ? "" : framework, vercel_build_command: buildCmd || null, vercel_output_directory: outDir || null })}
          >
            {isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Save className="h-3.5 w-3.5" />}
            Enregistrer
          </Button>
        )}
      </div>

      <Separator />

      {/* Env Vars */}
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <h4 className="text-sm font-medium flex items-center gap-2">
            <Key className="h-4 w-4" /> Variables d&apos;environnement ({envVars.length})
          </h4>
          <Button variant="outline" size="sm" className="gap-2" onClick={() => setShowAddEnv(true)} disabled={isPending}>
            <Plus className="h-3.5 w-3.5" /> Ajouter
          </Button>
        </div>

        {envVars.length > 0 ? (
          <div className="space-y-2">
            {envVars.map((ev, i) => (
              <div key={`${ev.key}-${i}`} className="flex items-center gap-3 p-3 rounded-lg border bg-card">
                <Key className="h-4 w-4 text-muted-foreground shrink-0" />
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-mono font-medium">{ev.key}</p>
                  {ev.description && <p className="text-xs text-muted-foreground">{ev.description}</p>}
                </div>
                <div className="flex items-center gap-1.5 shrink-0">
                  {ev.auto && <Badge variant="outline" className="text-[10px]">Auto</Badge>}
                  {ev.secret && <Badge variant="secondary" className="text-[10px]">Secret</Badge>}
                </div>
                <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive hover:bg-destructive/10 shrink-0"
                  onClick={() => setEnvVars(envVars.filter((_, idx) => idx !== i))} disabled={isPending}
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </Button>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-center py-4 text-xs text-muted-foreground">Aucune variable configurée.</p>
        )}

        <div className="p-3 rounded-md bg-muted/50 border text-xs text-muted-foreground">
          <strong>Auto</strong> = valeur remplie automatiquement (URL Supabase, clés API…). <strong>Secret</strong> = chiffré sur Vercel.
        </div>

        {hasEnvChanges && (
          <Button size="sm" className="gap-2" disabled={isPending} onClick={handleSaveEnv}>
            {isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Save className="h-3.5 w-3.5" />}
            Enregistrer les variables
          </Button>
        )}

        <Dialog open={showAddEnv} onOpenChange={setShowAddEnv}>
          <DialogContent className="sm:max-w-md">
            <DialogHeader>
              <DialogTitle>Ajouter une variable d&apos;environnement</DialogTitle>
              <DialogDescription>Configurée sur Vercel pour chaque nouveau client.</DialogDescription>
            </DialogHeader>
            <div className="space-y-4 py-4">
              <div className="space-y-2">
                <Label>Clé</Label>
                <Input value={newKey} onChange={(e) => setNewKey(e.target.value)} placeholder="NEXT_PUBLIC_MY_VAR" className="font-mono" />
              </div>
              <div className="space-y-2">
                <Label>Description</Label>
                <Input value={newDesc} onChange={(e) => setNewDesc(e.target.value)} placeholder="Description" />
              </div>
              <div className="flex items-center justify-between">
                <div><Label>Auto-remplissage</Label><p className="text-xs text-muted-foreground">Valeur auto lors du provisionnement</p></div>
                <Button variant={newAuto ? "default" : "outline"} size="sm" onClick={() => setNewAuto(!newAuto)}>{newAuto ? "Auto" : "Manuel"}</Button>
              </div>
              <div className="flex items-center justify-between">
                <div><Label>Secret</Label><p className="text-xs text-muted-foreground">Chiffré sur Vercel</p></div>
                <Button variant={newSecret ? "default" : "outline"} size="sm" onClick={() => setNewSecret(!newSecret)}>{newSecret ? "Secret" : "Plain"}</Button>
              </div>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setShowAddEnv(false)}>Annuler</Button>
              <Button onClick={handleAddEnv} disabled={!newKey.trim()}>Ajouter</Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>
    </div>
  )
}

// ─── Sous-composant : Schema (Tables, Fonctions, Views, Types) ──────────────

function SchemaSection({ snapshot }: { snapshot: SchemaSnapshot | null }) {
  const [expandedSection, setExpandedSection] = useState<string | null>(null)

  if (!snapshot) {
    return (
      <div className="text-center py-8 text-sm text-muted-foreground">
        <Database className="h-8 w-8 mx-auto mb-2 opacity-50" />
        <p>Aucun snapshot de schéma disponible.</p>
        <p className="text-xs mt-1">Le schema sera importé lors de la prochaine analyse.</p>
      </div>
    )
  }

  // Statistiques
  const totalTables = Object.values(snapshot.tables ?? {}).flat().length
  const totalFunctions = Object.values(snapshot.functions ?? {}).flat().length
  const totalViews = Object.values(snapshot.views ?? {}).flat().length
  const totalTypes = snapshot.custom_types?.length ?? 0

  const toggle = (key: string) => setExpandedSection(expandedSection === key ? null : key)

  return (
    <div className="space-y-4">
      {/* Résumé */}
      <div className="grid grid-cols-4 gap-3">
        {[
          { label: "Tables", count: totalTables, icon: TableIcon, color: "text-blue-500" },
          { label: "Fonctions", count: totalFunctions, icon: FunctionSquare, color: "text-success" },
          { label: "Views", count: totalViews, icon: Layers, color: "text-purple-500" },
          { label: "Types", count: totalTypes, icon: Code2, color: "text-primary" },
        ].map(({ label, count, icon: Icon, color }) => (
          <div key={label} className="text-center p-3 rounded-lg border bg-card">
            <Icon className={`h-5 w-5 mx-auto mb-1 ${color}`} />
            <p className="text-lg font-bold">{count}</p>
            <p className="text-xs text-muted-foreground">{label}</p>
          </div>
        ))}
      </div>

      {/* Schemas utilisés */}
      <div className="flex items-center gap-2 text-xs text-muted-foreground">
        <span>Schemas :</span>
        {(snapshot.schemas ?? []).map((s) => (
          <Badge key={s} variant="outline" className="text-[10px] font-mono">{s}</Badge>
        ))}
      </div>

      {/* Tables par schema */}
      {Object.entries(snapshot.tables ?? {}).map(([schema, tables]) => (
        <div key={`tables-${schema}`} className="border rounded-lg overflow-hidden">
          <button
            onClick={() => toggle(`tables-${schema}`)}
            className="w-full flex items-center justify-between p-3 bg-muted/30 hover:bg-muted/50 transition"
          >
            <div className="flex items-center gap-2">
              <TableIcon className="h-4 w-4 text-blue-500" />
              <span className="text-sm font-medium">Tables</span>
              <Badge variant="outline" className="text-[10px] font-mono">{schema}</Badge>
              <span className="text-xs text-muted-foreground">({tables.length})</span>
            </div>
            {expandedSection === `tables-${schema}` ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
          </button>
          {expandedSection === `tables-${schema}` && (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-[200px]">Table</TableHead>
                  <TableHead className="w-[80px] text-center">Colonnes</TableHead>
                  <TableHead>Description</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {tables.map((t) => (
                  <TableRow key={t.name}>
                    <TableCell className="font-mono text-sm font-medium">{t.name}</TableCell>
                    <TableCell className="text-center">
                      <Badge variant="secondary" className="text-[10px]">{t.columns}</Badge>
                    </TableCell>
                    <TableCell className="text-sm text-muted-foreground">{t.description}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </div>
      ))}

      {/* Fonctions par schema */}
      {Object.entries(snapshot.functions ?? {}).map(([schema, fns]) => (
        <div key={`fns-${schema}`} className="border rounded-lg overflow-hidden">
          <button
            onClick={() => toggle(`fns-${schema}`)}
            className="w-full flex items-center justify-between p-3 bg-muted/30 hover:bg-muted/50 transition"
          >
            <div className="flex items-center gap-2">
              <FunctionSquare className="h-4 w-4 text-success" />
              <span className="text-sm font-medium">Fonctions</span>
              <Badge variant="outline" className="text-[10px] font-mono">{schema}</Badge>
              <span className="text-xs text-muted-foreground">({fns.length})</span>
            </div>
            {expandedSection === `fns-${schema}` ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
          </button>
          {expandedSection === `fns-${schema}` && (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-[280px]">Fonction</TableHead>
                  <TableHead>Description</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {fns.map((f) => (
                  <TableRow key={f.name}>
                    <TableCell className="font-mono text-sm font-medium">{f.name}</TableCell>
                    <TableCell className="text-sm text-muted-foreground">{f.description}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </div>
      ))}

      {/* Views par schema */}
      {Object.entries(snapshot.views ?? {}).map(([schema, views]) => (
        <div key={`views-${schema}`} className="border rounded-lg overflow-hidden">
          <button
            onClick={() => toggle(`views-${schema}`)}
            className="w-full flex items-center justify-between p-3 bg-muted/30 hover:bg-muted/50 transition"
          >
            <div className="flex items-center gap-2">
              <Layers className="h-4 w-4 text-purple-500" />
              <span className="text-sm font-medium">Views</span>
              <Badge variant="outline" className="text-[10px] font-mono">{schema}</Badge>
              <span className="text-xs text-muted-foreground">({views.length})</span>
            </div>
            {expandedSection === `views-${schema}` ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
          </button>
          {expandedSection === `views-${schema}` && (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-[280px]">View</TableHead>
                  <TableHead>Description</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {views.map((v) => (
                  <TableRow key={v.name}>
                    <TableCell className="font-mono text-sm font-medium">{v.name}</TableCell>
                    <TableCell className="text-sm text-muted-foreground">{v.description}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </div>
      ))}

      {/* Types custom */}
      {snapshot.custom_types && snapshot.custom_types.length > 0 && (
        <div className="border rounded-lg overflow-hidden">
          <button
            onClick={() => toggle("types")}
            className="w-full flex items-center justify-between p-3 bg-muted/30 hover:bg-muted/50 transition"
          >
            <div className="flex items-center gap-2">
              <Code2 className="h-4 w-4 text-primary" />
              <span className="text-sm font-medium">Types personnalisés</span>
              <span className="text-xs text-muted-foreground">({snapshot.custom_types.length})</span>
            </div>
            {expandedSection === "types" ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
          </button>
          {expandedSection === "types" && (
            <div className="p-4 space-y-3">
              {snapshot.custom_types.map((ct) => (
                <div key={ct.name} className="p-3 rounded-lg border bg-card">
                  <div className="flex items-center gap-2 mb-1">
                    <p className="font-mono text-sm font-medium">{ct.name}</p>
                    <Badge variant="outline" className="text-[10px]">{ct.type}</Badge>
                  </div>
                  <div className="flex flex-wrap gap-1">
                    {ct.values.map((v) => (
                      <Badge key={v} variant="secondary" className="text-[10px] font-mono">{v}</Badge>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  )
}

// ─── Composant Principal ────────────────────────────────────────────────────

export function TemplatesManager({ templates }: TemplatesManagerProps) {
  const [expandedId, setExpandedId] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()
  const router = useRouter()

  async function handleSaveGeneral(templateId: string, data: Record<string, unknown>) {
    startTransition(async () => {
      const result = await updateTemplate({ templateId, ...data })
      if (result.success) { toast.success("Template mis à jour"); router.refresh() }
      else toast.error(result.error || "Erreur")
    })
  }

  return (
    <Card className="border-border/50">
      <CardHeader className="pb-3">
        <CardTitle className="text-sm font-medium">
          Templates de projet ({templates.length})
        </CardTitle>
      </CardHeader>
      <CardContent>
        <div className="space-y-4">
          {templates.map((template, index) => {
            const isExpanded = expandedId === template.id
            const app = template.app

            return (
              <div key={template.id}>
                {index > 0 && <Separator className="mb-4" />}

                {/* Header cliquable */}
                <button
                  onClick={() => setExpandedId(isExpanded ? null : template.id)}
                  className="w-full flex items-center gap-4 p-3 rounded-lg hover:bg-muted/50 transition text-left"
                >
                  {/* Mini logo */}
                  <div
                    className="w-10 h-10 rounded-lg flex items-center justify-center text-white font-bold text-sm shrink-0"
                    style={{ backgroundColor: app?.color ?? "#3B82F6" }}
                  >
                    {app?.name?.charAt(0) ?? "?"}
                  </div>

                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <p className="text-sm font-medium">{template.name}</p>
                      {template.is_active ? (
                        <Badge variant="default" className="text-[10px] gap-1"><CheckCircle2 className="h-2.5 w-2.5" /> Actif</Badge>
                      ) : (
                        <Badge variant="secondary" className="text-[10px] gap-1"><XCircle className="h-2.5 w-2.5" /> Inactif</Badge>
                      )}
                    </div>
                    <div className="flex items-center gap-3 mt-1 text-xs text-muted-foreground">
                      <span className="flex items-center gap-1"><Globe className="h-3 w-3" />{app?.name ?? "—"}</span>
                      <span className="flex items-center gap-1"><GitBranch className="h-3 w-3" />{template.github_template_owner}/{template.github_template_repo}</span>
                      <span className="flex items-center gap-1"><Database className="h-3 w-3" />{template.default_supabase_plan}</span>
                      <span className="flex items-center gap-1"><HardDrive className="h-3 w-3" />{template.storage_buckets?.length ?? 0} bucket(s)</span>
                      {template.schema_snapshot?.tables && (
                        <span className="flex items-center gap-1">
                          <TableIcon className="h-3 w-3" />
                          {Object.values(template.schema_snapshot.tables).flat().length} tables
                        </span>
                      )}
                    </div>
                  </div>

                  {isExpanded ? <ChevronUp className="h-5 w-5 text-muted-foreground shrink-0" /> : <ChevronDown className="h-5 w-5 text-muted-foreground shrink-0" />}
                </button>

                {/* Contenu détaillé */}
                {isExpanded && (
                  <div className="mt-3 space-y-4">
                    {/* Header App complet */}
                    <AppHeader template={template} />

                    {/* Tabs */}
                    <Tabs defaultValue="schema" className="w-full">
                      <TabsList className="grid w-full grid-cols-6">
                        <TabsTrigger value="schema" className="gap-1.5 text-xs">
                          <Database className="h-3.5 w-3.5" /> Schema
                        </TabsTrigger>
                        <TabsTrigger value="general" className="gap-1.5 text-xs">
                          <Settings className="h-3.5 w-3.5" /> Général
                        </TabsTrigger>
                        <TabsTrigger value="github" className="gap-1.5 text-xs">
                          <GitBranch className="h-3.5 w-3.5" /> GitHub
                        </TabsTrigger>
                        <TabsTrigger value="supabase" className="gap-1.5 text-xs">
                          <Palette className="h-3.5 w-3.5" /> Supabase
                        </TabsTrigger>
                        <TabsTrigger value="storage" className="gap-1.5 text-xs">
                          <HardDrive className="h-3.5 w-3.5" /> Storage
                        </TabsTrigger>
                        <TabsTrigger value="vercel" className="gap-1.5 text-xs">
                          <Server className="h-3.5 w-3.5" /> Vercel
                        </TabsTrigger>
                      </TabsList>

                      <TabsContent value="schema" className="mt-4">
                        <SchemaSection snapshot={template.schema_snapshot} />
                      </TabsContent>
                      <TabsContent value="general" className="mt-4">
                        <GeneralSection template={template} isPending={isPending} onSave={(data) => handleSaveGeneral(template.id, data)} />
                      </TabsContent>
                      <TabsContent value="github" className="mt-4">
                        <GitHubSection template={template} isPending={isPending} onSave={(data) => handleSaveGeneral(template.id, data)} />
                      </TabsContent>
                      <TabsContent value="supabase" className="mt-4">
                        <SupabaseSection template={template} isPending={isPending} onSave={(data) => handleSaveGeneral(template.id, data)} />
                      </TabsContent>
                      <TabsContent value="storage" className="mt-4">
                        <StorageSection template={template} isPending={isPending} startTransition={startTransition} router={router} />
                      </TabsContent>
                      <TabsContent value="vercel" className="mt-4">
                        <VercelSection template={template} isPending={isPending} onSave={(data) => handleSaveGeneral(template.id, data)} startTransition={startTransition} router={router} />
                      </TabsContent>
                    </Tabs>
                  </div>
                )}
              </div>
            )
          })}

          {templates.length === 0 && (
            <p className="text-xs text-muted-foreground text-center py-4">Aucun template configuré.</p>
          )}
        </div>
      </CardContent>
    </Card>
  )
}
