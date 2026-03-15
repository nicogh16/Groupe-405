"use client"

import { useState, useTransition } from "react"
import { createMember, deleteMember, updateMemberRole } from "@/app/(dashboard)/settings/actions"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Separator } from "@/components/ui/separator"
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
  DialogTrigger,
} from "@/components/ui/dialog"
import { toast } from "sonner"
import { UserPlus, Trash2, Loader2, ShieldAlert } from "lucide-react"
import type { Profile } from "@/types"

interface TeamManagerProps {
  teamMembers: Profile[]
  currentUserId: string
}

export function TeamManager({ teamMembers, currentUserId }: TeamManagerProps) {
  const [isPending, startTransition] = useTransition()
  const [createOpen, setCreateOpen] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<Profile | null>(null)

  // Formulaire de création
  const [email, setEmail] = useState("")
  const [password, setPassword] = useState("")
  const [fullName, setFullName] = useState("")
  const [role, setRole] = useState<"admin" | "viewer">("viewer")

  function handleCreate(e: React.FormEvent) {
    e.preventDefault()
    const formData = new FormData()
    formData.set("email", email)
    formData.set("password", password)
    formData.set("full_name", fullName)
    formData.set("role", role)

    startTransition(async () => {
      const result = await createMember(formData)
      if (result.error) {
        toast.error(result.error)
      } else {
        toast.success(result.message ?? "Membre créé avec succès")
        setCreateOpen(false)
        setEmail("")
        setPassword("")
        setFullName("")
        setRole("viewer")
      }
    })
  }

  function handleDelete(member: Profile) {
    const formData = new FormData()
    formData.set("user_id", member.id)

    startTransition(async () => {
      const result = await deleteMember(formData)
      if (result.error) {
        toast.error(result.error)
      } else {
        toast.success(result.message ?? "Membre supprimé")
        setDeleteTarget(null)
      }
    })
  }

  function handleRoleChange(userId: string, newRole: string) {
    const formData = new FormData()
    formData.set("user_id", userId)
    formData.set("role", newRole)

    startTransition(async () => {
      const result = await updateMemberRole(formData)
      if (result.error) {
        toast.error(result.error)
      } else {
        toast.success(result.message ?? "Rôle mis à jour")
      }
    })
  }

  return (
    <div className="space-y-4">
      {/* Liste des membres */}
      <div className="space-y-3">
        {teamMembers.map((member, index) => (
          <div key={member.id}>
            {index > 0 && <Separator className="mb-3" />}
            <div className="flex items-center justify-between gap-3">
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium truncate">{member.full_name}</p>
                <p className="text-xs text-muted-foreground">
                  Depuis {new Date(member.created_at).toLocaleDateString("fr-CA")}
                </p>
              </div>

              <div className="flex items-center gap-2">
                {/* Sélecteur de rôle */}
                {member.id !== currentUserId ? (
                  <Select
                    defaultValue={member.role}
                    onValueChange={(val) => handleRoleChange(member.id, val)}
                    disabled={isPending}
                  >
                    <SelectTrigger className="h-7 w-24 text-xs">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="admin">admin</SelectItem>
                      <SelectItem value="viewer">viewer</SelectItem>
                    </SelectContent>
                  </Select>
                ) : (
                  <Badge variant={member.role === "admin" ? "default" : "secondary"}>
                    {member.role} (moi)
                  </Badge>
                )}

                {/* Bouton supprimer */}
                {member.id !== currentUserId && (
                  <Dialog
                    open={deleteTarget?.id === member.id}
                    onOpenChange={(open) => !open && setDeleteTarget(null)}
                  >
                    <DialogTrigger asChild>
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-7 w-7 text-muted-foreground hover:text-destructive"
                        onClick={() => setDeleteTarget(member)}
                        disabled={isPending}
                      >
                        <Trash2 className="h-3.5 w-3.5" />
                      </Button>
                    </DialogTrigger>
                    <DialogContent>
                      <DialogHeader>
                        <DialogTitle className="flex items-center gap-2">
                          <ShieldAlert className="h-5 w-5 text-destructive" />
                          Supprimer un membre
                        </DialogTitle>
                        <DialogDescription>
                          Voulez-vous vraiment supprimer{" "}
                          <strong>{member.full_name}</strong> ? Cette action est irréversible.
                          Le compte et l&apos;accès seront définitivement supprimés.
                        </DialogDescription>
                      </DialogHeader>
                      <DialogFooter>
                        <Button variant="outline" onClick={() => setDeleteTarget(null)}>
                          Annuler
                        </Button>
                        <Button
                          variant="destructive"
                          onClick={() => handleDelete(member)}
                          disabled={isPending}
                        >
                          {isPending ? (
                            <Loader2 className="h-4 w-4 animate-spin" />
                          ) : (
                            "Supprimer"
                          )}
                        </Button>
                      </DialogFooter>
                    </DialogContent>
                  </Dialog>
                )}
              </div>
            </div>
          </div>
        ))}
      </div>

      <Separator />

      {/* Bouton créer un membre */}
      <Dialog open={createOpen} onOpenChange={setCreateOpen}>
        <DialogTrigger asChild>
          <Button variant="outline" size="sm" className="gap-2">
            <UserPlus className="h-4 w-4" />
            Ajouter un membre
          </Button>
        </DialogTrigger>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Ajouter un membre</DialogTitle>
            <DialogDescription>
              Créez un compte pour un nouveau membre de l&apos;équipe. Il pourra se connecter
              immédiatement avec les identifiants fournis.
            </DialogDescription>
          </DialogHeader>
          <form onSubmit={handleCreate} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="full_name">Nom complet</Label>
              <Input
                id="full_name"
                value={fullName}
                onChange={(e) => setFullName(e.target.value)}
                placeholder="Jean Dupont"
                required
                minLength={2}
                disabled={isPending}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="jean@groupe405.com"
                required
                disabled={isPending}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="password">Mot de passe temporaire</Label>
              <Input
                id="password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Min. 8 caractères"
                required
                minLength={8}
                disabled={isPending}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="role">Rôle</Label>
              <Select
                value={role}
                onValueChange={(val) => setRole(val as "admin" | "viewer")}
                disabled={isPending}
              >
                <SelectTrigger id="role">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="viewer">
                    <div>
                      <p className="font-medium">Viewer</p>
                      <p className="text-xs text-muted-foreground">Lecture seule</p>
                    </div>
                  </SelectItem>
                  <SelectItem value="admin">
                    <div>
                      <p className="font-medium">Admin</p>
                      <p className="text-xs text-muted-foreground">Accès complet</p>
                    </div>
                  </SelectItem>
                </SelectContent>
              </Select>
            </div>
            <DialogFooter>
              <Button
                type="button"
                variant="outline"
                onClick={() => setCreateOpen(false)}
                disabled={isPending}
              >
                Annuler
              </Button>
              <Button type="submit" disabled={isPending}>
                {isPending ? (
                  <>
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                    Création...
                  </>
                ) : (
                  "Créer le compte"
                )}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  )
}
