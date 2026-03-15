import { ThemeToggle } from "./theme-toggle"
import { UserNav } from "./user-nav"
import type { Profile } from "@/types"

export function Header({ profile }: { profile: Profile | null }) {
  return (
    <header className="flex h-14 items-center justify-between border-b border-border bg-card px-4 md:px-6">
      <div className="flex items-center gap-2 md:hidden">
        <div className="flex h-7 w-7 items-center justify-center rounded-md bg-primary text-primary-foreground text-xs font-bold">
          G4
        </div>
        <span className="text-sm font-semibold tracking-tight">Groupe 405</span>
      </div>
      <div className="hidden md:block" />
      <div className="flex items-center gap-2">
        <ThemeToggle />
        <UserNav profile={profile} />
      </div>
    </header>
  )
}
