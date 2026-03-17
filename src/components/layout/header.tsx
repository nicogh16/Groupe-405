import { ThemeToggle } from "./theme-toggle"
import { UserNav } from "./user-nav"
import { Logo } from "./logo"
import type { Profile } from "@/types"

export function Header({ profile }: { profile: Profile | null }) {
  return (
    <header className="flex h-16 items-center justify-between border-b border-border bg-background px-6">
      <div className="md:hidden">
        <Logo />
      </div>
      <div className="hidden md:block" />
      <div className="flex items-center gap-2">
        <ThemeToggle />
        <UserNav profile={profile} />
      </div>
    </header>
  )
}
