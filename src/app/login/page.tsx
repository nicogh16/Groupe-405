import { LoginForm } from "@/components/auth/login-form"

export default function LoginPage() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-background px-4">
      <div className="w-full max-w-sm space-y-8">
        <div className="text-center space-y-2">
          <h1 className="text-3xl font-bold tracking-tight">Groupe 405</h1>
          <p className="text-sm text-muted-foreground">
            Connectez-vous pour accéder au panel
          </p>
        </div>
        <LoginForm />
      </div>
    </div>
  )
}
