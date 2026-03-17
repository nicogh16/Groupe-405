import { cn } from "@/lib/utils"
import { AlertTriangle } from "lucide-react"
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip"

interface UsageProgressProps {
  label: string
  value: number // percentage 0-100
  className?: string
}

export function UsageProgress({ label, value, className }: UsageProgressProps) {
  const color =
    value >= 90
      ? "bg-red-500"
      : value >= 70
        ? "bg-amber-500"
        : "bg-success"

  const isWarning = value >= 70
  const isCritical = value >= 90

  return (
    <div className={cn("space-y-2", className)}>
      <div className="flex items-center justify-between text-sm">
        <div className="flex items-center gap-2">
          <span className="text-muted-foreground">{label}</span>
          {isCritical && (
            <TooltipProvider>
              <Tooltip>
                <TooltipTrigger asChild>
                  <AlertTriangle className="h-3.5 w-3.5 text-red-500" />
                </TooltipTrigger>
                <TooltipContent>
                  <p>Limite critique atteinte - Risque de dépassement</p>
                </TooltipContent>
              </Tooltip>
            </TooltipProvider>
          )}
          {isWarning && !isCritical && (
            <TooltipProvider>
              <Tooltip>
                <TooltipTrigger asChild>
                  <AlertTriangle className="h-3.5 w-3.5 text-amber-500" />
                </TooltipTrigger>
                <TooltipContent>
                  <p>Approche de la limite - Surveiller l&apos;utilisation</p>
                </TooltipContent>
              </Tooltip>
            </TooltipProvider>
          )}
        </div>
        <span
          className={cn(
            "font-medium text-foreground",
            isCritical && "text-red-600",
            isWarning && !isCritical && "text-amber-600"
          )}
        >
          {value}%
        </span>
      </div>
      <div className="h-1.5 w-full rounded-full bg-muted">
        <div
          className={cn("h-full rounded-full transition-all", color)}
          style={{ width: `${Math.min(value, 100)}%` }}
        />
      </div>
    </div>
  )
}
