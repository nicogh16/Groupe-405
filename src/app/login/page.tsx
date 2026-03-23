import { LoginForm } from "@/components/auth/login-form"
import { Logo } from "@/components/layout/logo"

export default function LoginPage() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-background px-4">
      <div className="w-full max-w-md space-y-8">
        <div className="text-center space-y-3">
          <div className="flex justify-center mb-6">
            <Logo showText={false} />
          </div>
          <h1 className="text-2xl font-semibold text-foreground">Connexion</h1>
          <p className="text-sm text-muted-foreground">
            Connectez-vous pour accéder au panel
          </p>
        </div>
        <LoginForm />
      </div>
    </div>
  )
}
