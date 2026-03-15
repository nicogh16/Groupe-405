import Link from "next/link"
import { Button } from "@/components/ui/button"

export default function NotFound() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center space-y-4">
      <h1 className="text-6xl font-bold tracking-tight">404</h1>
      <p className="text-muted-foreground">Page introuvable.</p>
      <Button asChild variant="outline">
        <Link href="/">Retour au dashboard</Link>
      </Button>
    </div>
  )
}
