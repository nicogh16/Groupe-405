"use client"

import { useState } from "react"
import { updateRevenue } from "@/app/(dashboard)/clients/[slug]/actions"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { Loader2, Save, Edit2, X } from "lucide-react"
import { formatCurrency, formatNumber, getStatusColor } from "@/lib/utils"
import { APP_CONFIG, SUPABASE_PLAN_LIMITS } from "@/lib/constants"
import { toast } from "sonner"
import Link from "next/link"
import type { Client, App, UsageSnapshot } from "@/types"

interface CostsTableProps {
  clients: (Client & { app: App })[]
  snapshots: Record<string, UsageSnapshot | null>
  isAdmin: boolean
}

export function CostsTable({ clients, snapshots, isAdmin }: CostsTableProps) {
  const [editingClientId, setEditingClientId] = useState<string | null>(null)
  const [revenueValues, setRevenueValues] = useState<Record<string, string>>({})
  const [isSaving, setIsSaving] = useState<string | null>(null)

  function handleEdit(clientId: string, currentRevenue: number) {
    setEditingClientId(clientId)
    setRevenueValues((prev) => ({
      ...prev,
      [clientId]: currentRevenue.toString(),
    }))
  }

  function handleCancel(clientId: string) {
    setEditingClientId(null)
    setRevenueValues((prev) => {
      const newValues = { ...prev }
      delete newValues[clientId]
      return newValues
    })
  }

  async function handleSave(clientId: string) {
    const revenue = revenueValues[clientId]
    if (!revenue) return

    setIsSaving(clientId)

    const formData = new FormData()
    formData.set("clientId", clientId)
    formData.set("monthlyRevenue", revenue)

    try {
      const result = await updateRevenue(formData)
      if (result?.error) {
        toast.error(result.error)
      } else {
        toast.success("Revenu mis à jour")
        setEditingClientId(null)
        window.location.reload()
      }
    } catch (error) {
      toast.error("Erreur lors de la mise à jour")
    } finally {
      setIsSaving(null)
    }
  }

  return (
    <div className="rounded-md border border-border/50">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Client</TableHead>
            <TableHead>Plan</TableHead>
            <TableHead className="text-right">Coût Mensuel</TableHead>
            <TableHead className="text-right">Coût Annuel</TableHead>
            <TableHead className="text-right">Revenu Mensuel</TableHead>
            <TableHead className="text-right">Revenu Annuel</TableHead>
            <TableHead className="text-right">Marge Mensuelle</TableHead>
            <TableHead className="text-right">Marge Annuelle</TableHead>
            <TableHead className="text-right">Marge %</TableHead>
            {isAdmin && <TableHead className="text-right">Actions</TableHead>}
          </TableRow>
        </TableHeader>
        <TableBody>
          {clients.map((client) => {
            const snapshot = snapshots[client.id]
            const planLimits = SUPABASE_PLAN_LIMITS[client.supabase_plan]
            const monthlyCost = snapshot
              ? snapshot.estimated_monthly_cost
              : planLimits?.monthlyCostBase ?? 0
            const annualCost = monthlyCost * 12

            const isEditing = editingClientId === client.id
            const currentRevenue = client.monthly_revenue ?? 0
            const displayRevenue = isEditing
              ? revenueValues[client.id] ?? currentRevenue.toString()
              : currentRevenue

            const monthlyRevenue = parseFloat(displayRevenue) || 0
            const annualRevenue = monthlyRevenue * 12
            const monthlyMargin = monthlyRevenue - monthlyCost
            const annualMargin = annualRevenue - annualCost
            const marginPercent =
              monthlyRevenue > 0 ? ((monthlyMargin / monthlyRevenue) * 100).toFixed(1) : "0.0"

            const appConfig = APP_CONFIG[client.app.slug as keyof typeof APP_CONFIG]

            return (
              <TableRow key={client.id}>
                <TableCell>
                  <Link
                    href={`/clients/${client.slug}`}
                    className="hover:underline flex items-center gap-2"
                  >
                    <div className={`h-2 w-2 rounded-full ${getStatusColor(client.status)}`} />
                    <span className="font-medium">{client.name}</span>
                  </Link>
                  <Badge
                    variant={appConfig?.badgeVariant ?? "default"}
                    className="text-[10px] px-1.5 py-0 mt-1"
                  >
                    {appConfig?.label ?? client.app.name}
                  </Badge>
                </TableCell>
                <TableCell>
                  <span className="text-sm">{planLimits?.label ?? client.supabase_plan}</span>
                </TableCell>
                <TableCell className="text-right font-medium">
                  {formatCurrency(monthlyCost)}
                </TableCell>
                <TableCell className="text-right font-medium">
                  {formatCurrency(annualCost)}
                </TableCell>
                <TableCell className="text-right">
                  {isEditing ? (
                    <div className="flex items-center justify-end gap-2">
                      <Input
                        type="number"
                        step="0.01"
                        min="0"
                        value={displayRevenue}
                        onChange={(e) =>
                          setRevenueValues((prev) => ({
                            ...prev,
                            [client.id]: e.target.value,
                          }))
                        }
                        className="w-32 h-8 text-right"
                        disabled={isSaving === client.id}
                      />
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => handleSave(client.id)}
                        disabled={isSaving === client.id}
                      >
                        {isSaving === client.id ? (
                          <Loader2 className="h-4 w-4 animate-spin" />
                        ) : (
                          <Save className="h-4 w-4" />
                        )}
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => handleCancel(client.id)}
                        disabled={isSaving === client.id}
                      >
                        <X className="h-4 w-4" />
                      </Button>
                    </div>
                  ) : (
                    <span className="font-medium text-emerald-600 dark:text-emerald-400">
                      {formatCurrency(monthlyRevenue)}
                    </span>
                  )}
                </TableCell>
                <TableCell className="text-right font-medium text-emerald-600 dark:text-emerald-400">
                  {formatCurrency(annualRevenue)}
                </TableCell>
                <TableCell
                  className={`text-right font-medium ${
                    monthlyMargin >= 0
                      ? "text-emerald-600 dark:text-emerald-400"
                      : "text-red-600 dark:text-red-400"
                  }`}
                >
                  {formatCurrency(monthlyMargin)}
                </TableCell>
                <TableCell
                  className={`text-right font-medium ${
                    annualMargin >= 0
                      ? "text-emerald-600 dark:text-emerald-400"
                      : "text-red-600 dark:text-red-400"
                  }`}
                >
                  {formatCurrency(annualMargin)}
                </TableCell>
                <TableCell
                  className={`text-right font-medium ${
                    parseFloat(marginPercent) >= 0
                      ? "text-emerald-600 dark:text-emerald-400"
                      : "text-red-600 dark:text-red-400"
                  }`}
                >
                  {marginPercent}%
                </TableCell>
                {isAdmin && (
                  <TableCell className="text-right">
                    {!isEditing && (
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => handleEdit(client.id, currentRevenue)}
                      >
                        <Edit2 className="h-4 w-4" />
                      </Button>
                    )}
                  </TableCell>
                )}
              </TableRow>
            )
          })}
        </TableBody>
      </Table>
    </div>
  )
}
