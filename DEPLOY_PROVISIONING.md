# Guide de déploiement de l'Edge Function `provision-client`

## 1. Déployer l'Edge Function

### Option A : Via Supabase Dashboard (Recommandé)

1. Va sur https://supabase.com/dashboard/project/[TON_PROJECT_ID]/functions
2. Clique sur **"Deploy a new function"** ou **"Create function"**
3. Nomme-la `provision-client`
4. Copie-colle le contenu de `supabase/functions/provision-client/index.ts`
5. Clique sur **Deploy**

### Option B : Via CLI Supabase

**Étape 1 : Obtenir un Access Token**

1. Va sur https://supabase.com/dashboard/account/tokens
2. Clique sur **"Generate new token"**
3. Donne-lui un nom (ex: "CLI Deployment")
4. Copie le token (format `sbp_...`)

**Étape 2 : Déployer avec le token**

```bash
# Option A : Utiliser le token directement
npx supabase functions deploy provision-client --token sbp_votre_token_ici

# Option B : Définir la variable d'environnement (PowerShell)
$env:SUPABASE_ACCESS_TOKEN = "sbp_votre_token_ici"
npx supabase functions deploy provision-client

# Option C : Définir la variable d'environnement (bash/Linux/Mac)
export SUPABASE_ACCESS_TOKEN="sbp_votre_token_ici"
npx supabase functions deploy provision-client
```

**Étape 3 : Lier le projet (si pas déjà fait)**

```bash
npx supabase link --project-ref [TON_PROJECT_REF] --token sbp_votre_token_ici
```

> **Note** : Le `--token` est nécessaire si vous n'avez pas fait `supabase login` dans un terminal interactif.

## 2. Configurer les Secrets

Une fois la fonction déployée, va dans **Settings** → **Secrets** de la fonction `provision-client` et ajoute :

| Secret | Description | Où le trouver |
|--------|-------------|---------------|
| `ACCESS_TOKEN` | Token Management API Supabase | Format: `sbp_...` (dans ton compte Supabase) |
| `GITHUB_TOKEN` | Personal Access Token GitHub | GitHub → Settings → Developer settings → Personal access tokens → Generate new token (permissions: `repo`) |
| `VERCEL_TOKEN` | Token Vercel | Vercel Dashboard → Settings → Tokens → Create Token |
| `ORG_ID` | ID de ton organisation Supabase | Dans l'URL du dashboard Supabase ou via l'API |
| `ENCRYPTION_KEY` | Clé de chiffrement | La même que celle dans `.env.local` (variable `ENCRYPTION_KEY`) |

## 3. Vérifier le déploiement

Une fois déployée, teste en créant un nouveau job de provisionnement depuis l'interface. Le statut devrait passer de "pending" à "running" puis progresser étape par étape.

## 4. Dépannage

Si le job reste bloqué à "pending" :

1. Vérifie les logs de l'Edge Function dans Supabase Dashboard → Edge Functions → provision-client → Logs
2. Vérifie que tous les secrets sont bien configurés
3. Vérifie que l'Edge Function est bien déployée (doit apparaître dans la liste)
4. Vérifie les logs du serveur Next.js pour voir si l'appel à `supabase.functions.invoke` échoue
