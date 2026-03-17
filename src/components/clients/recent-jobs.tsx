"use client"

import { useState } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { ChevronRight, Clock, CheckCircle2, XCircle, Loader2 } from "lucide-react"
import { ProvisioningProgress } from "./provisioning-progress"
import type { ProvisioningJob, ProvisioningJobStatus } from "@/types"

interface RecentJobsProps {
  jobs: ProvisioningJob[]
}

function JobStatusIcon({ status }: { status: ProvisioningJobStatus }) {
  switch (status) {
    case "completed":
      return <CheckCircle2 className="h-4 w-4 text-success" />
    case "running":
      return <Loader2 className="h-4 w-4 text-blue-500 animate-spin" />
    case "failed":
      return <XCircle className="h-4 w-4 text-red-500" />
    default:
      return <Clock className="h-4 w-4 text-muted-foreground" />
  }
}

function jobStatusLabel(status: ProvisioningJobStatus): { text: string; variant: "default" | "secondary" | "destructive" | "outline" } {
  switch (status) {
    case "pending":
      return { text: "En attente", variant: "secondary" }
    case "running":
      return { text: "En cours", variant: "default" }
    case "completed":
      return { text: "Terminé", variant: "default" }
    case "failed":
      return { text: "Échec", variant: "destructive" }
    case "cancelled":
      return { text: "Annulé", variant: "outline" }
  }
}

export function RecentJobs({ jobs }: RecentJobsProps) {
  const [selectedJobId, setSelectedJobId] = useState<string | null>(null)

  if (jobs.length === 0) return null

  return (
    <>
      <Card className="border-border/50">
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-medium">
            Provisionnements récents
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-2">
            {jobs.map((job) => {
              const statusInfo = jobStatusLabel(job.status)
              return (
                <button
                  key={job.id}
                  onClick={() => setSelectedJobId(job.id)}
                  className="w-full flex items-center gap-3 p-3 rounded-lg hover:bg-muted/50 transition text-left"
                >
                  <JobStatusIcon status={job.status} />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium truncate">{job.client_name}</p>
                    <p className="text-xs text-muted-foreground">
                      {new Date(job.created_at).toLocaleDateString("fr-CA", {
                        day: "numeric",
                        month: "short",
                        year: "numeric",
                        hour: "2-digit",
                        minute: "2-digit",
                      })}
                    </p>
                  </div>
                  <Badge variant={statusInfo.variant} className="text-[11px]">
                    {statusInfo.text}
                  </Badge>
                  <ChevronRight className="h-4 w-4 text-muted-foreground" />
                </button>
              )
            })}
          </div>
        </CardContent>
      </Card>

      {/* Dialog pour voir les détails d'un job */}
      <Dialog open={!!selectedJobId} onOpenChange={() => setSelectedJobId(null)}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Détails du provisionnement</DialogTitle>
          </DialogHeader>
          {selectedJobId && (
            <ProvisioningProgress jobId={selectedJobId} />
          )}
        </DialogContent>
      </Dialog>
    </>
  )
}
