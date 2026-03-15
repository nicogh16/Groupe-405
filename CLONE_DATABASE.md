# Guide: Cloner une base de données Supabase avec pg_dump

Ce guide explique comment utiliser `pg_dump` pour cloner votre base de données Supabase.

## Prérequis

1. **PostgreSQL installé** (pour avoir `pg_dump` et `psql`)
   - Téléchargement: https://www.postgresql.org/download/windows/
   - Assurez-vous que `pg_dump` et `psql` sont dans votre PATH

2. **Informations de connexion Supabase**
   - Allez dans votre Dashboard Supabase
   - **Settings** → **Database** → **Connection string**
   - Copiez la connection string (format: `postgresql://postgres:Maniju16052002&@db.zdicqtupwckhvxhlkiuf.supabase.co:5432/postgres`)

## Méthode 1: Utiliser le script PowerShell (Recommandé)

### Étape 1: Configurer les variables d'environnement

Ouvrez PowerShell et définissez votre connection string:

```powershell
$env:SUPABASE_DB_CONNECTION_STRING = 'postgresql://postgres:Maniju16052002&@db.zdicqtupwckhvxhlkiuf.supabase.co:5432/postgres'
```

**⚠️ Alternative:** Vous pouvez aussi utiliser des paramètres individuels:

```powershell
$env:SUPABASE_DB_HOST = "db.zdicqtupwckhvxhlkiuf.supabase.co"
$env:SUPABASE_DB_PORT = "5432"
$env:SUPABASE_DB_NAME = "postgres"
$env:SUPABASE_DB_USER = "postgres"
$env:SUPABASE_DB_PASSWORD = "Maniju16052002&"
```

### Étape 2: Cloner la base de données

```powershell
# Clone complet (schéma + données)
.\scripts\clone-database.ps1

# Clone du schéma uniquement (sans données)
.\scripts\clone-database.ps1 -SchemaOnly

# Clone des données uniquement (sans schéma)
.\scripts\clone-database.ps1 -DataOnly

# Spécifier un nom de fichier de sortie
.\scripts\clone-database.ps1 -OutputFile "ma-sauvegarde.sql"
```

Le fichier SQL sera créé dans le répertoire courant avec un nom par défaut comme `database-backup-2026-02-22-143022.sql`.

### Étape 3: Restaurer la base de données (optionnel)

Pour restaurer la sauvegarde dans une autre base de données:

```powershell
# Configurer la connection string de la base de destination
$env:SUPABASE_DB_CONNECTION_STRING = 'postgresql://postgres:Maniju16052002&@db.zdicqtupwckhvxhlkiuf.supabase.co:5432/postgres'

# Restaurer
.\scripts\restore-database.ps1 -InputFile "database-backup-2026-02-22-143022.sql"
```

## Méthode 2: Utiliser pg_dump directement

### Cloner la base de données

```powershell
# Avec connection string
pg_dump 'postgresql://postgres:Maniju16052002&@db.zdicqtupwckhvxhlkiuf.supabase.co:5432/postgres' -f backup.sql

# Avec paramètres individuels
$env:PGPASSWORD = "Maniju16052002&"
pg_dump -h db.zdicqtupwckhvxhlkiuf.supabase.co -p 5432 -U postgres -d postgres -f backup.sql
```

### Options utiles de pg_dump

```powershell
# Schéma uniquement (pas de données)
pg_dump --schema-only 'postgresql://postgres:Maniju16052002&@db.zdicqtupwckhvxhlkiuf.supabase.co:5432/postgres' -f schema.sql

# Données uniquement (pas de schéma)
pg_dump --data-only 'postgresql://postgres:Maniju16052002&@db.zdicqtupwckhvxhlkiuf.supabase.co:5432/postgres' -f data.sql

# Exclure certaines tables
pg_dump --exclude-table=table1 --exclude-table=table2 'postgresql://postgres:Maniju16052002&@db.zdicqtupwckhvxhlkiuf.supabase.co:5432/postgres' -f backup.sql

# Inclure seulement certaines tables
pg_dump --table=table1 --table=table2 'postgresql://postgres:Maniju16052002&@db.zdicqtupwckhvxhlkiuf.supabase.co:5432/postgres' -f backup.sql

# Format personnalisé (compressé, plus rapide à restaurer)
pg_dump -Fc 'postgresql://postgres:Maniju16052002&@db.zdicqtupwckhvxhlkiuf.supabase.co:5432/postgres' -f backup.dump
```

### Restaurer avec psql

```powershell
# Restaurer depuis un fichier SQL
psql 'postgresql://postgres:Maniju16052002&@db.zdicqtupwckhvxhlkiuf.supabase.co:5432/postgres' -f backup.sql

# Ou avec paramètres individuels
$env:PGPASSWORD = "Maniju16052002&"
psql -h db.zdicqtupwckhvxhlkiuf.supabase.co -p 5432 -U postgres -d postgres -f backup.sql
```

## Où trouver les informations de connexion

1. **Dashboard Supabase** → Votre projet
2. **Settings** → **Database**
3. **Connection string** → Copiez la string complète
   - Format: `postgresql://postgres:Maniju16052002&@db.zdicqtupwckhvxhlkiuf.supabase.co:5432/postgres`

## Notes importantes

- ⚠️ **Sécurité**: Ne commitez jamais vos mots de passe ou connection strings dans Git
- ⚠️ **Taille**: Les bases de données volumineuses peuvent prendre du temps à exporter
- ⚠️ **RLS**: Les politiques RLS (Row Level Security) sont incluses dans l'export
- ⚠️ **Extensions**: Certaines extensions Supabase peuvent nécessiter des permissions spéciales

## Dépannage

### Erreur: "pg_dump n'est pas reconnu"
- Installez PostgreSQL Client Tools
- Vérifiez que PostgreSQL est dans votre PATH

### Erreur: "password authentication failed"
- Vérifiez votre mot de passe dans le Dashboard Supabase
- Assurez-vous que vous utilisez le mot de passe de la base de données, pas l'API key

### Erreur: "connection timeout"
- Vérifiez que votre IP est autorisée dans les paramètres de connexion Supabase
- Vérifiez votre connexion internet
