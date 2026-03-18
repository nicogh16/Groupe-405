"use client"

import { useState, useEffect } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Progress } from "@/components/ui/progress"
import {
  CheckCircle2,
  ChevronRight,
  ChevronLeft,
  Database,
  FileCode,
  Play,
  Loader2,
  Sparkles,
  Table,
  FunctionSquare,
  Eye,
  Layers,
} from "lucide-react"

interface DatabaseStep {
  id: number
  title: string
  description: string
  sqlFile: "init" | "table" | "view-mv" | "function" | null
  sqlPreview: string
  icon: React.ReactNode
  status: "pending" | "running" | "completed" | "error"
}

const steps: DatabaseStep[] = [
  {
    id: 1,
    title: "Initialisation des schémas",
    description: "Création des schémas de base de données (audit, dashboard_view, mv)",
    sqlFile: "init",
    sqlPreview: `CREATE SCHEMA audit;
CREATE SCHEMA dashboard_view;
CREATE SCHEMA mv;

-- Configuration des extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";`,
    icon: <Layers className="h-5 w-5" />,
    status: "pending",
  },
  {
    id: 2,
    title: "Création des tables",
    description: "Installation de toutes les tables de l'application",
    sqlFile: "table",
    sqlPreview: `CREATE TABLE public.users (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  email text UNIQUE NOT NULL,
  name text,
  points integer DEFAULT 0,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.transactions (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid REFERENCES public.users(id),
  total numeric(10,2),
  points integer,
  created_at timestamp with time zone DEFAULT now()
);`,
    icon: <Table className="h-5 w-5" />,
    status: "pending",
  },
  {
    id: 3,
    title: "Création des vues et materialized views",
    description: "Installation des vues pour le dashboard et les statistiques",
    sqlFile: "view-mv",
    sqlPreview: `CREATE VIEW dashboard_view.user_stats AS
SELECT 
  u.id,
  u.email,
  u.points,
  COUNT(t.id) as transaction_count,
  SUM(t.total) as total_spent
FROM public.users u
LEFT JOIN public.transactions t ON t.user_id = u.id
GROUP BY u.id, u.email, u.points;

CREATE MATERIALIZED VIEW mv.restaurant_stats AS
SELECT 
  r.id,
  r.name,
  COUNT(t.id) as order_count
FROM public.restaurants r
LEFT JOIN public.transactions t ON t.restaurant_id = r.id
GROUP BY r.id, r.name;`,
    icon: <Eye className="h-5 w-5" />,
    status: "pending",
  },
  {
    id: 4,
    title: "Installation des fonctions PostgreSQL",
    description: "Création des fonctions avec DECLARE et logique métier",
    sqlFile: "function",
    sqlPreview: `CREATE FUNCTION audit.detect_anomaly_trigger() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id uuid;
    v_user_role text;
    v_anomaly_type text;
BEGIN
    -- Logique de détection d'anomalies
    v_user_id := auth.uid();
    -- ... reste de la fonction
    RETURN NEW;
END;
$$;`,
    icon: <FunctionSquare className="h-5 w-5" />,
    status: "pending",
  },
]

export function DatabaseInstallGuide() {
  const [currentStep, setCurrentStep] = useState(0)
  const [isRunning, setIsRunning] = useState(false)
  const [stepsState, setStepsState] = useState<DatabaseStep[]>(steps)
  const [typedSQL, setTypedSQL] = useState("")
  const [showSQL, setShowSQL] = useState(false)

  const currentStepData = stepsState[currentStep]
  const progress = ((currentStep + 1) / steps.length) * 100

  // Animation de frappe pour le SQL
  useEffect(() => {
    if (showSQL && currentStepData.sqlPreview) {
      setTypedSQL("")
      let index = 0
      const interval = setInterval(() => {
        if (index < currentStepData.sqlPreview.length) {
          setTypedSQL(currentStepData.sqlPreview.slice(0, index + 1))
          index++
        } else {
          clearInterval(interval)
        }
      }, 10) // Vitesse de frappe

      return () => clearInterval(interval)
    }
  }, [showSQL, currentStep])

  const handleNext = () => {
    if (currentStep < steps.length - 1) {
      setCurrentStep(currentStep + 1)
      setShowSQL(false)
      setTypedSQL("")
    }
  }

  const handlePrevious = () => {
    if (currentStep > 0) {
      setCurrentStep(currentStep - 1)
      setShowSQL(false)
      setTypedSQL("")
    }
  }

  const handleRunStep = () => {
    setIsRunning(true)
    setShowSQL(true)

    // Mettre à jour le statut de l'étape actuelle
    setStepsState((prev) =>
      prev.map((step, idx) => {
        if (idx === currentStep) {
          return { ...step, status: "running" }
        }
        return step
      })
    )

    // Simuler l'exécution (3 secondes)
    setTimeout(() => {
      setStepsState((prev) =>
        prev.map((step, idx) => {
          if (idx === currentStep) {
            return { ...step, status: "completed" }
          }
          return step
        })
      )
      setIsRunning(false)
    }, 3000)
  }

  const handleRunAll = () => {
    setIsRunning(true)
    setShowSQL(true)
    let stepIndex = 0

    const runNextStep = () => {
      if (stepIndex < steps.length) {
        setCurrentStep(stepIndex)
        setStepsState((prev) =>
          prev.map((step, idx) => {
            if (idx === stepIndex) {
              return { ...step, status: "running" }
            }
            return step
          })
        )

        setTimeout(() => {
          setStepsState((prev) =>
            prev.map((step, idx) => {
              if (idx === stepIndex) {
                return { ...step, status: "completed" }
              }
              return step
            })
          )

          stepIndex++
          if (stepIndex < steps.length) {
            setTimeout(runNextStep, 500)
          } else {
            setIsRunning(false)
          }
        }, 2000)
      }
    }

    runNextStep()
  }

  const getStatusIcon = (status: DatabaseStep["status"]) => {
    switch (status) {
      case "completed":
        return <CheckCircle2 className="h-5 w-5 text-green-500" />
      case "running":
        return <Loader2 className="h-5 w-5 text-blue-500 animate-spin" />
      case "error":
        return <CheckCircle2 className="h-5 w-5 text-red-500" />
      default:
        return <div className="h-5 w-5 rounded-full border-2 border-gray-300" />
    }
  }

  const getStatusBadge = (status: DatabaseStep["status"]) => {
    switch (status) {
      case "completed":
        return (
          <Badge className="bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300">
            ✓ Terminé
          </Badge>
        )
      case "running":
        return (
          <Badge className="bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300">
            <Loader2 className="h-3 w-3 mr-1 animate-spin" />
            En cours...
          </Badge>
        )
      case "error":
        return (
          <Badge className="bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-300">
            ✗ Erreur
          </Badge>
        )
      default:
        return (
          <Badge variant="outline" className="bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300">
            En attente
          </Badge>
        )
    }
  }

  const completedSteps = stepsState.filter((s) => s.status === "completed").length

  return (
    <div className="space-y-6">
      {/* En-tête avec progression */}
      <Card className="border-2 border-blue-200 dark:border-blue-800 bg-gradient-to-br from-blue-50/50 to-indigo-50/50 dark:from-blue-950/20 dark:to-indigo-950/20">
        <CardHeader>
          <div className="flex items-center justify-between mb-4">
            <CardTitle className="text-2xl font-bold bg-gradient-to-r from-blue-600 to-indigo-600 bg-clip-text text-transparent flex items-center gap-2">
              <Database className="h-7 w-7 text-blue-600" />
              Installation de la base de données MyFidelity
            </CardTitle>
            <Badge variant="outline" className="text-lg px-3 py-1">
              {completedSteps}/{steps.length} étapes
            </Badge>
          </div>
          <Progress value={progress} className="h-2" />
          <p className="text-sm text-muted-foreground mt-2">
            Suivez les étapes pour installer la base de données avec tous les scripts SQL
          </p>
        </CardHeader>
      </Card>

      {/* Étape actuelle */}
      <Card className="border-2 border-blue-300 dark:border-blue-700">
        <CardHeader>
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="flex items-center justify-center w-12 h-12 rounded-full bg-blue-100 dark:bg-blue-900 text-blue-600 dark:text-blue-400">
                {currentStepData.icon}
              </div>
              <div>
                <CardTitle className="text-xl">
                  Étape {currentStep + 1} : {currentStepData.title}
                </CardTitle>
                <p className="text-sm text-muted-foreground mt-1">{currentStepData.description}</p>
              </div>
            </div>
            {getStatusBadge(currentStepData.status)}
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          {/* Fichier SQL */}
          {currentStepData.sqlFile && (
            <div className="space-y-2">
              <div className="flex items-center gap-2 text-sm font-medium">
                <FileCode className="h-4 w-4" />
                Fichier : <code className="bg-muted px-2 py-1 rounded">{currentStepData.sqlFile}.sql</code>
              </div>

              {/* Aperçu SQL avec animation */}
              <div className="relative">
                <div className="bg-gray-900 dark:bg-gray-950 rounded-lg p-4 border border-gray-700 overflow-hidden">
                  <div className="flex items-center gap-2 mb-3">
                    <div className="flex gap-1.5">
                      <div className="w-3 h-3 rounded-full bg-red-500" />
                      <div className="w-3 h-3 rounded-full bg-yellow-500" />
                      <div className="w-3 h-3 rounded-full bg-green-500" />
                    </div>
                    <span className="text-xs text-gray-400 ml-2 font-mono">
                      {currentStepData.sqlFile}.sql
                    </span>
                  </div>
                  <pre className="text-xs font-mono text-green-400 overflow-x-auto">
                    <code>{showSQL ? typedSQL : "Cliquez sur 'Exécuter cette étape' pour voir le SQL..."}</code>
                  </pre>
                  {isRunning && currentStepData.status === "running" && (
                    <div className="absolute inset-0 bg-gray-900/80 flex items-center justify-center">
                      <div className="flex flex-col items-center gap-2">
                        <Loader2 className="h-8 w-8 text-blue-400 animate-spin" />
                        <span className="text-sm text-blue-400">Exécution en cours...</span>
                      </div>
                    </div>
                  )}
                </div>
              </div>
            </div>
          )}

          {/* Actions */}
          <div className="flex items-center justify-between pt-4 border-t">
            <div className="flex gap-2">
              <Button
                variant="outline"
                onClick={handlePrevious}
                disabled={currentStep === 0 || isRunning}
              >
                <ChevronLeft className="h-4 w-4 mr-2" />
                Précédent
              </Button>
              <Button
                variant="default"
                onClick={handleRunStep}
                disabled={isRunning || currentStepData.status === "completed"}
                className="bg-blue-600 hover:bg-blue-700"
              >
                {currentStepData.status === "running" ? (
                  <>
                    <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                    Exécution...
                  </>
                ) : currentStepData.status === "completed" ? (
                  <>
                    <CheckCircle2 className="h-4 w-4 mr-2" />
                    Terminé
                  </>
                ) : (
                  <>
                    <Play className="h-4 w-4 mr-2" />
                    Exécuter cette étape
                  </>
                )}
              </Button>
            </div>
            <Button
              variant="outline"
              onClick={handleNext}
              disabled={currentStep === steps.length - 1 || isRunning}
            >
              Suivant
              <ChevronRight className="h-4 w-4 ml-2" />
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Liste de toutes les étapes */}
      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Toutes les étapes</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-3">
            {stepsState.map((step, index) => (
              <div
                key={step.id}
                className={`flex items-center gap-4 p-3 rounded-lg border-2 transition-all cursor-pointer ${
                  index === currentStep
                    ? "border-blue-500 bg-blue-50 dark:bg-blue-950/20"
                    : "border-gray-200 dark:border-gray-700 hover:border-gray-300 dark:hover:border-gray-600"
                }`}
                onClick={() => {
                  if (!isRunning) {
                    setCurrentStep(index)
                    setShowSQL(false)
                    setTypedSQL("")
                  }
                }}
              >
                <div className="flex items-center justify-center w-10 h-10 rounded-full bg-gray-100 dark:bg-gray-800 shrink-0">
                  {getStatusIcon(step.status)}
                </div>
                <div className="flex-1">
                  <div className="flex items-center gap-2">
                    <span className="font-semibold">{step.title}</span>
                    {getStatusBadge(step.status)}
                  </div>
                  <p className="text-xs text-muted-foreground mt-0.5">{step.description}</p>
                </div>
                {step.sqlFile && (
                  <Badge variant="outline" className="shrink-0">
                    <FileCode className="h-3 w-3 mr-1" />
                    {step.sqlFile}.sql
                  </Badge>
                )}
              </div>
            ))}
          </div>

          {/* Bouton exécuter tout */}
          {completedSteps < steps.length && (
            <div className="mt-6 pt-4 border-t">
              <Button
                onClick={handleRunAll}
                disabled={isRunning}
                className="w-full bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-700 hover:to-indigo-700"
                size="lg"
              >
                {isRunning ? (
                  <>
                    <Loader2 className="h-5 w-5 mr-2 animate-spin" />
                    Installation en cours...
                  </>
                ) : (
                  <>
                    <Sparkles className="h-5 w-5 mr-2" />
                    Exécuter toutes les étapes automatiquement
                  </>
                )}
              </Button>
            </div>
          )}

          {/* Message de succès */}
          {completedSteps === steps.length && (
            <div className="mt-6 p-4 bg-green-50 dark:bg-green-950/20 border border-green-200 dark:border-green-800 rounded-lg">
              <div className="flex items-center gap-2 text-green-700 dark:text-green-300">
                <CheckCircle2 className="h-5 w-5" />
                <span className="font-semibold">Installation terminée avec succès !</span>
              </div>
              <p className="text-sm text-green-600 dark:text-green-400 mt-2">
                Tous les scripts SQL ont été exécutés. La base de données MyFidelity est maintenant prête.
              </p>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
