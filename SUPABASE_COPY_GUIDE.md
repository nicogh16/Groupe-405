# Guide : Copier proprement un projet Supabase

## Méthode actuelle (implémentée)

Notre Edge Function `provision-client` utilise déjà une méthode propre pour copier un projet Supabase :

### ✅ Avantages de la méthode actuelle

1. **Copie uniquement le schéma** (pas les données)
   - Récupère les migrations depuis `supabase_migrations.schema_migrations`
   - Applique les migrations dans le bon ordre de dépendances

2. **Gestion automatique des dépendances**
   - Crée d'abord les schémas
   - Puis les types et extensions
   - Ensuite les tables (sans dépendances d'abord, puis avec dépendances)
   - Puis les vues
   - Enfin les fonctions (sans dépendances de vues d'abord, puis avec dépendances)
   - Et enfin les triggers, RLS policies, et grants

3. **Parser SQL robuste**
   - Gère les blocs `DO $$ ... $$`
   - Gère les fonctions PostgreSQL `CREATE FUNCTION ... AS $$ ... $$`
   - Gère les dollar-quoted strings
   - Gère les strings normales avec échappement

## Méthode alternative : pg_dump (si vous avez accès direct à PostgreSQL)

Si vous avez un accès direct à la base de données PostgreSQL (via connection string), vous pouvez utiliser `pg_dump` :

```bash
# Dump du schéma uniquement (sans données)
pg_dump -h db.[PROJECT_REF].supabase.co \
  -U postgres \
  -p 5432 \
  -d postgres \
  --schema-only \
  --no-owner \
  --no-privileges \
  -f schema.sql

# Appliquer le schéma sur le nouveau projet
psql -h db.[NEW_PROJECT_REF].supabase.co \
  -U postgres \
  -p 5432 \
  -d postgres \
  -f schema.sql
```

**⚠️ Limitations :**
- Nécessite un accès direct à PostgreSQL (connection string)
- Nécessite `pg_dump` et `psql` installés localement
- Les migrations Supabase ne seront pas copiées (seulement le schéma actuel)

## Méthode recommandée : Utiliser les migrations Supabase (notre méthode actuelle)

### ✅ Pourquoi cette méthode est meilleure

1. **Respecte l'historique des migrations**
   - Conserve l'ordre chronologique des migrations
   - Permet de suivre l'évolution du schéma
   - Compatible avec le système de migrations Supabase

2. **Gestion automatique des dépendances**
   - Notre parser SQL détecte et respecte les dépendances
   - Crée les objets dans le bon ordre automatiquement

3. **Pas besoin d'accès direct à PostgreSQL**
   - Utilise uniquement l'API Supabase Management
   - Fonctionne via l'Edge Function

### 📋 Configuration actuelle

Notre Edge Function utilise :
- **Source** : `SOURCE_SUPABASE_PROJECT_REF` (le projet à copier)
- **Destination** : Le nouveau projet créé automatiquement
- **Méthode** : Récupération des migrations depuis `supabase_migrations.schema_migrations`

## Améliorations possibles

### Option 1 : Utiliser pg_dump via l'API Supabase (si disponible)

Si Supabase expose un endpoint pour exécuter `pg_dump`, on pourrait l'utiliser :

```typescript
// Exemple (si l'API le supporte)
const dumpRes = await fetch(
  `https://api.supabase.com/v1/projects/${sourceProjectRef}/database/dump`,
  {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      schema_only: true,
      format: "sql"
    })
  }
)
```

**⚠️ Note** : Cette API n'existe peut-être pas encore dans Supabase.

### Option 2 : Améliorer la récupération des migrations

Notre méthode actuelle récupère les migrations depuis `supabase_migrations.schema_migrations`. C'est déjà optimal car :
- ✅ Conserve l'historique complet
- ✅ Respecte l'ordre chronologique
- ✅ Inclut tous les objets (tables, vues, fonctions, triggers, etc.)

### Option 3 : Ajouter la copie des données (optionnel)

Si vous voulez aussi copier les données (pas seulement le schéma) :

```sql
-- Pour chaque table, exporter les données
COPY table_name TO STDOUT WITH CSV HEADER;

-- Puis importer dans le nouveau projet
COPY table_name FROM STDIN WITH CSV HEADER;
```

**⚠️ Attention** : Copier les données peut être long et coûteux. Généralement, on copie seulement le schéma pour créer un nouveau projet "propre".

## Conclusion

**Notre méthode actuelle est déjà optimale** pour copier proprement un projet Supabase :

✅ Copie uniquement le schéma (pas les données)  
✅ Respecte l'ordre des dépendances  
✅ Gère tous les types d'objets SQL  
✅ Utilise les migrations Supabase (historique complet)  
✅ Fonctionne via l'API Supabase (pas besoin d'accès direct)  

La seule amélioration possible serait d'utiliser `pg_dump` si Supabase expose cette fonctionnalité via l'API, mais pour l'instant, notre méthode est la meilleure approche disponible.
