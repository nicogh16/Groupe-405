"use client"

import { usePathname } from "next/navigation"
import { LayoutDashboard, Users, Settings, DollarSign } from "lucide-react"
import { cn } from "@/lib/utils"
import { Logo } from "./logo"
import Link from "next/link"

const navItems = [
  { label: "Dashboard", href: "/", icon: LayoutDashboard },
  { label: "Clients", href: "/clients", icon: Users },
  { label: "Coûts & Marges", href: "/costs", icon: DollarSign },
  { label: "Paramètres", href: "/settings", icon: Settings },
]

export function Sidebar() {
  const pathname = usePathname()

  return (
    <aside className="hidden md:flex md:w-64 md:flex-col md:border-r border-sidebar-border bg-sidebar">
      <div className="flex h-16 items-center border-b border-sidebar-border px-6">
        <Logo variant="compact" />
      </div>
      <nav className="flex-1 space-y-0.5 p-3">
        {navItems.map((item) => {
          const isActive =
            item.href === "/" ? pathname === "/" : pathname.startsWith(item.href)
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                "relative flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors",
                isActive
                  ? "text-foreground bg-sidebar-accent"
                  : "text-muted-foreground hover:text-foreground hover:bg-sidebar-accent/50"
              )}
            >
              {isActive && (
                <div className="absolute left-0 top-1/2 -translate-y-1/2 w-1 h-5 bg-primary rounded-r-full" />
              )}
              <item.icon className={cn("h-4 w-4", isActive ? "text-primary" : "")} />
              {item.label}
            </Link>
          )
        })}
      </nav>
    </aside>
  )
}
