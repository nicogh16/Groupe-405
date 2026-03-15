# Configuration des Secrets pour l'Edge Function `provision-client`

Une fois l'Edge Function déployée, configurez ces secrets dans **Supabase Dashboard** → **Edge Functions** → **provision-client** → **Settings** → **Secrets** :

## Secrets à configurer

**IMPORTANT** : Les noms des secrets ont été simplifiés pour éviter les problèmes avec le Dashboard Supabase.

| Secret | Valeur | Où le trouver |
|--------|-------|---------------|
| `ACCESS_TOKEN` | `sbp_98fff5bba54457eb19159fec09e9c9ec1d86dd7d` | ✅ Déjà fourni (anciennement `SUPABASE_ACCESS_TOKEN`) |
| `ORG_ID` | `nwbtiyytbspogtztglum` | ✅ Trouvé dans la liste des projets (anciennement `SUPABASE_ORG_ID`) |
| `SOURCE_SUPABASE_PROJECT_REF` | Le project ref d'ASAP Fidélité | Le project ref du projet Supabase ASAP Fidélité (ex: `abcdefghijklmnop`) - visible dans l'URL du dashboard |
| `GITHUB_TOKEN` | À créer | GitHub → Settings → Developer settings → Personal access tokens → Generate new token (permissions: `repo`) |
| `VERCEL_TOKEN` | À créer | Vercel Dashboard → Settings → Tokens → Create Token |
| `ENCRYPTION_KEY` | À récupérer | La même clé que dans votre `.env.local` (variable `ENCRYPTION_KEY`) |

## Instructions détaillées

### 1. GitHub Token

1. Va sur https://github.com/settings/tokens
2. Clique sur **"Generate new token"** → **"Generate new token (classic)"**
3. Donne-lui un nom (ex: "Provisioning Client")
4. Sélectionne la permission : **`repo`** (accès complet aux repositories)
5. Clique sur **"Generate token"**
6. **Copie le token immédiatement** (il ne sera plus visible après)

### 2. Vercel Token

1. Va sur https://vercel.com/account/tokens
2. Clique sur **"Create Token"**
3. Donne-lui un nom (ex: "Provisioning Client")
4. Sélectionne la portée : **Full Account** ou **Specific Projects**
5. Clique sur **"Create"**
6. **Copie le token immédiatement** (il ne sera plus visible après)

### 3. SOURCE_SUPABASE_PROJECT_REF

Le project ref du projet Supabase ASAP Fidélité depuis lequel les migrations seront copiées :

1. Va sur le dashboard du projet ASAP Fidélité : https://supabase.com/dashboard/project/[PROJECT_REF]
2. Le project ref est visible dans l'URL (ex: `https://supabase.com/dashboard/project/abcdefghijklmnop`)
3. Copie le project ref (la partie après `/project/`)
4. Ajoute-le comme secret `SOURCE_SUPABASE_PROJECT_REF`

**Exemple** : Si l'URL est `https://supabase.com/dashboard/project/abcdefghijklmnop`, le project ref est `abcdefghijklmnop`

### 4. ENCRYPTION_KEY

Cette clé doit être la même que celle utilisée dans votre application Next.js. Elle se trouve dans votre fichier `.env.local` :

```
ENCRYPTION_KEY=votre_cle_ici
```

**Important** : Si vous n'avez pas encore cette clé, générez-en une nouvelle (32 caractères minimum) et utilisez-la à la fois dans `.env.local` et dans les secrets de l'Edge Function.

## Vérification

Une fois tous les secrets configurés :

1. Testez en créant un nouveau job de provisionnement depuis l'interface
2. Vérifiez les logs dans **Edge Functions** → **provision-client** → **Logs**
3. Le statut devrait passer de "pending" à "running" puis progresser étape par étape

## Dépannage

Si vous voyez une erreur "Secrets manquants" dans les logs :
- Vérifiez que tous les secrets sont bien configurés (sans espaces avant/après)
- Vérifiez que les noms des secrets sont exactement comme indiqué (sensible à la casse)
- Vérifiez que les tokens GitHub et Vercel ont les bonnes permissions
