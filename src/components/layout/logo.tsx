"use client"

import Link from "next/link"
import { cn } from "@/lib/utils"

interface LogoProps {
  className?: string
  showText?: boolean
  variant?: "default" | "compact"
}

export function Logo({ className, showText = true, variant = "default" }: LogoProps) {
  // Version compacte : icône carrée avec G + texte
  if (variant === "compact") {
    return (
      <Link href="/" className={cn("flex items-center gap-2.5", className)}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src="/logo.png"
          alt="G Groupe 405"
          width={32}
          height={32}
          border-radius={50}
          className="object-contain h-8 w-8"
        />
        {showText && (
          <span className="font-bold text-base text-foreground">Groupe 405</span>
        )}
      </Link>
    )
  }

  // Version sans texte
  if (!showText) {
    return (
      <Link href="/" className={cn("flex items-center", className)}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src="/logo.png"
          alt="G Groupe 405"
          width={32}
          height={32}
          border-radius={50}
          className="object-contain h-8 w-8"
        />
      </Link>
    )
  }

  // Version par défaut : logo complet avec texte
  return (
    <Link href="/" className={cn("flex items-center", className)}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src="/logo-large.png"
        alt="G Groupe 405"
        width={160}
        height={40}
        border-radius={50}
        className="object-contain h-10"
      />
    </Link>
  )
}
