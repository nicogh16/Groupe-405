import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function formatBytes(bytes: number, decimals = 1): string {
  if (bytes === 0) return "0 B"
  const k = 1024
  const sizes = ["B", "KB", "MB", "GB", "TB"]
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(decimals))} ${sizes[i]}`
}

export function formatCurrency(amount: number, currency = "CAD"): string {
  return new Intl.NumberFormat("fr-CA", {
    style: "currency",
    currency,
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  }).format(amount)
}

export function formatNumber(num: number): string {
  return new Intl.NumberFormat("fr-CA").format(num)
}

export function getUsagePercentage(used: number, limit: number): number {
  if (limit === 0) return 0
  return Math.min(Math.round((used / limit) * 100), 100)
}

export function getStatusColor(status: string): string {
  switch (status) {
    case "active":
      return "bg-green-500"
    case "paused":
      return "bg-amber-500"
    case "inactive":
      return "bg-red-500"
    default:
      return "bg-neutral-400"
  }
}
