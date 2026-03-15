# Guide : Restaurer votre base de données dans un nouveau projet Supabase

Ce guide vous explique comment préparer et restaurer votre dump SQL dans un nouveau projet Supabase.

## 📋 Prérequis

1. **PostgreSQL installé** avec `psql` et `pg_dump` dans le PATH
   - Téléchargement : https://www.postgresql.org/download/windows/
   - Ou utilisez les chemins complets dans les scripts

2. **Un dump SQL** de votre base de données actuelle (`full_dump.sql`)

## 🚀 Étapes

### Étape 1 : Préparer le dump

Le script `prepare-dump-for-new-project.ps1` nettoie le dump en retirant les éléments spécifiques à Supabase (schémas système, extensions, etc.) et garde uniquement vos schémas personnalisés.

```powershell
.\scripts\prepare-dump-for-new-project.ps1 -InputFile "full_dump.sql" -OutputFile "supabase_new_project.sql"
```

**Ce que fait le script :**
- ✅ Retire les lignes `\restrict` et `\unrestrict` (spécifiques à Supabase)
- ✅ Retire les CREATE SCHEMA pour les schémas système (auth, storage, realtime, etc.)
- ✅ Retire les CREATE EXTENSION pour les extensions système
- ✅ Retire les event triggers et publications Supabase
- ✅ Garde vos schémas personnalisés (public, private, audit, mv, etc.)
- ✅ Ajoute un en-tête avec instructions

**Résultat :** Un fichier `supabase_new_project.sql` prêt à être restauré.

### Étape 2 : Créer un nouveau projet Supabase

1. Allez sur https://supabase.com/dashboard
2. Cliquez sur "New Project"
3. Remplissez les informations :
   - **Name** : Nom de votre projet
   - **Database Password** : Choisissez un mot de passe fort
   - **Region** : Choisissez la région la plus proche
4. Attendez que le projet soit créé (2-3 minutes)

### Étape 3 : Obtenir la connection string

1. Dans le dashboard Supabase, allez dans **Settings** → **Database**
2. Trouvez la section **Connection string**
3. Sélectionnez **URI** ou **Connection pooling**
4. Copiez la connection string, elle ressemble à :
   ```
   postgresql://postgres:[YOUR-PASSWORD]@db.[PROJECT-REF].supabase.co:5432/postgres
   ```
5. Remplacez `[YOUR-PASSWORD]` par votre mot de passe

### Étape 4 : Restaurer le dump

Utilisez le script de restauration :

```powershell
.\scripts\restore-to-new-project.ps1 -ConnectionString "postgresql://postgres:VOTRE_MOT_DE_PASSE@db.VOTRE_PROJET.supabase.co:5432/postgres"
```

**Ou manuellement avec psql :**

```powershell
$env:PGPASSWORD = "VOTRE_MOT_DE_PASSE"
psql "postgresql://postgres:VOTRE_MOT_DE_PASSE@db.VOTRE_PROJET.supabase.co:5432/postgres" -f supabase_new_project.sql
```

**Ou avec le chemin complet de psql :**

```powershell
$env:PGPASSWORD = "VOTRE_MOT_DE_PASSE"
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" "postgresql://postgres:VOTRE_MOT_DE_PASSE@db.VOTRE_PROJET.supabase.co:5432/postgres" -f supabase_new_project.sql
```

### Étape 5 : Vérifier la restauration

1. Allez dans **Table Editor** du dashboard Supabase
2. Vérifiez que toutes vos tables sont présentes
3. Vérifiez quelques lignes de données pour confirmer

### Étape 6 : Mettre à jour votre application

1. **Récupérez les nouvelles clés API** :
   - Allez dans **Settings** → **API**
   - Copiez :
     - `Project URL` → `NEXT_PUBLIC_SUPABASE_URL`
     - `anon public` key → `NEXT_PUBLIC_SUPABASE_ANON_KEY`
     - `service_role` key → `SUPABASE_SERVICE_ROLE_KEY`

2. **Mettez à jour `.env.local`** :
   ```env
   NEXT_PUBLIC_SUPABASE_URL=https://VOTRE_PROJET.supabase.co
   NEXT_PUBLIC_SUPABASE_ANON_KEY=sb_publishable_...
   SUPABASE_SERVICE_ROLE_KEY=sb_secret_...
   ```

3. **Configurez les politiques RLS** si nécessaire :
   - Allez dans **Authentication** → **Policies**
   - Vérifiez que vos politiques sont bien configurées

## ⚠️ Notes importantes

- **Les schémas système Supabase** (auth, storage, realtime, etc.) sont déjà créés dans un nouveau projet. Le dump préparé ne les inclut pas.

- **Les extensions Supabase** (pg_graphql, supabase_vault, etc.) sont déjà installées. Le dump préparé ne les réinstalle pas.

- **Certaines erreurs peuvent être normales** :
  - `relation already exists` : Si certaines tables existent déjà
  - `extension already exists` : Si certaines extensions sont déjà installées
  - Ces erreurs sont généralement sans impact

- **Temps de restauration** : Selon la taille de votre base, cela peut prendre de quelques secondes à plusieurs minutes.

## 🔧 Dépannage

### Erreur : "psql n'est pas reconnu"
- Installez PostgreSQL ou utilisez le chemin complet : `C:\Program Files\PostgreSQL\18\bin\psql.exe`

### Erreur : "connection refused" ou "timeout"
- Vérifiez votre connection string
- Vérifiez que le projet Supabase est bien créé et actif
- Vérifiez votre connexion internet

### Erreur : "permission denied"
- Vérifiez que vous utilisez le bon mot de passe
- Vérifiez que la connection string est correcte

### Certaines tables manquent après la restauration
- Vérifiez les erreurs dans la sortie de psql
- Certaines tables peuvent nécessiter des dépendances spécifiques
- Vérifiez les politiques RLS si vous ne voyez pas les données

## 📝 Scripts disponibles

- `scripts/prepare-dump-for-new-project.ps1` : Prépare le dump pour un nouveau projet
- `scripts/restore-to-new-project.ps1` : Restaure le dump dans un nouveau projet
- `scripts/dump-database.ps1` : Crée un dump de la base actuelle
- `scripts/restore-database.ps1` : Restaure un dump dans la base actuelle

## 🎯 Exemple complet

```powershell
# 1. Préparer le dump
.\scripts\prepare-dump-for-new-project.ps1 -InputFile "full_dump.sql"

# 2. Créer un nouveau projet sur https://supabase.com/dashboard

# 3. Restaurer dans le nouveau projet
.\scripts\restore-to-new-project.ps1 -ConnectionString "postgresql://postgres:MON_MOT_DE_PASSE@db.monprojet.supabase.co:5432/postgres"

# 4. Mettre à jour .env.local avec les nouvelles clés API
```

---

**Besoin d'aide ?** Consultez la documentation Supabase : https://supabase.com/docs
