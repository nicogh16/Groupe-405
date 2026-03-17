"use client"

import { useEffect, useState } from "react"
import { createClient } from "@/lib/supabase/client"
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { AlertTriangle, ExternalLink, CheckCircle2, Loader2 } from "lucide-react"

export function EdgeFunctionStatus() {
  const [status, setStatus] = useState<"checking" | "deployed" | "not_deployed" | "error">("checking")
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    async function checkFunction() {
      try {
        const supabase = createClient()
        const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!

        // Tester si l'Edge Function répond
        const response = await fetch(`${supabaseUrl}/functions/v1/provision-client`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
          },
          body: JSON.stringify({ job_id: "test" }),
        })

        // Si on reçoit une erreur 400 (bad request) au lieu de 503, c'est que la fonction existe
        // 503 = fonction non déployée
        // 400 = fonction déployée mais erreur de paramètres (normal pour un test)
        if (response.status === 503 || response.status === 404) {
          setStatus("not_deployed")
        } else if (response.status === 400 || response.status === 500) {
          // 400 ou 500 signifie que la fonction existe mais a une erreur (normal pour un test)
          setStatus("deployed")
        } else {
          setStatus("deployed")
        }
      } catch (err) {
        setStatus("error")
        setError(err instanceof Error ? err.message : "Erreur inconnue")
      }
    }

    checkFunction()
  }, [])

  if (status === "checking") {
    return (
      <Alert className="border-amber-500/20 bg-amber-500/5">
        <Loader2 className="h-4 w-4 animate-spin text-amber-500" />
        <AlertTitle className="text-amber-500">Vérification de l'Edge Function...</AlertTitle>
        <AlertDescription className="text-sm text-muted-foreground">
          Vérification si la fonction &quot;provision-client&quot; est déployée.
        </AlertDescription>
      </Alert>
    )
  }

  if (status === "deployed") {
    return (
      <Alert className="border-success/20 bg-success/5">
        <CheckCircle2 className="h-4 w-4 text-success" />
        <AlertTitle className="text-success">Edge Function déployée</AlertTitle>
        <AlertDescription className="text-sm text-muted-foreground">
          La fonction &quot;provision-client&quot; est disponible. Vous pouvez lancer un provisionnement.
        </AlertDescription>
      </Alert>
    )
  }

  if (status === "not_deployed") {
    return (
      <Alert className="border-red-500/20 bg-red-500/5">
        <AlertTriangle className="h-4 w-4 text-red-500" />
        <AlertTitle className="text-red-500">Edge Function non déployée</AlertTitle>
        <AlertDescription className="text-sm text-muted-foreground space-y-3 mt-2">
          <p>
            La fonction &quot;provision-client&quot; n&apos;est pas déployée sur Supabase. Le provisionnement ne fonctionnera pas tant qu&apos;elle n&apos;est pas déployée.
          </p>
          <div className="space-y-2">
            <p className="font-medium text-foreground">Étapes pour déployer :</p>
            <ol className="list-decimal list-inside space-y-1 text-xs">
              <li>
                Va sur{" "}
                <a
                  href={`https://supabase.com/dashboard/project/${process.env.NEXT_PUBLIC_SUPABASE_URL?.replace("https://", "").replace(".supabase.co", "")}/functions`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-blue-400 hover:underline inline-flex items-center gap-1"
                >
                  Supabase Dashboard → Edge Functions
                  <ExternalLink className="h-3 w-3" />
                </a>
              </li>
              <li>Clique sur &quot;Deploy a new function&quot; ou &quot;Create function&quot;</li>
              <li>Nomme-la <code className="bg-red-500/20 px-1 rounded">provision-client</code></li>
              <li>Copie le contenu du fichier <code className="bg-red-500/20 px-1 rounded">supabase/functions/provision-client/index.ts</code></li>
              <li>Clique sur &quot;Deploy&quot;</li>
              <li>Configure les secrets (voir <code className="bg-red-500/20 px-1 rounded">DEPLOY_PROVISIONING.md</code>)</li>
            </ol>
          </div>
          <Button
            variant="outline"
            size="sm"
            className="mt-2"
            onClick={() => {
              const url = `https://supabase.com/dashboard/project/${process.env.NEXT_PUBLIC_SUPABASE_URL?.replace("https://", "").replace(".supabase.co", "")}/functions`
              window.open(url, "_blank")
            }}
          >
            <ExternalLink className="h-3.5 w-3.5 mr-2" />
            Ouvrir Supabase Dashboard
          </Button>
        </AlertDescription>
      </Alert>
    )
  }

  return (
    <Alert className="border-red-500/20 bg-red-500/5">
      <AlertTriangle className="h-4 w-4 text-red-500" />
      <AlertTitle className="text-red-500">Erreur de vérification</AlertTitle>
      <AlertDescription className="text-sm text-muted-foreground">
        {error || "Impossible de vérifier le statut de l'Edge Function."}
      </AlertDescription>
    </Alert>
  )
}
