# Export du schéma Supabase en template

Ce script permet d'exporter le schéma complet d'un projet Supabase (migrations, extensions, schémas, buckets) et de créer un template SQL réutilisable.

## Utilisation

### Avec Node.js (recommandé)

```bash
# Le token est déjà configuré par défaut dans le script
# Vous pouvez le surcharger si nécessaire :
# $env:ACCESS_TOKEN="sbp_votre_token_ici"

# Exporter le schéma d'un projet
node scripts/export-supabase-template.js <PROJECT_REF>
```

### Avec Deno

```bash
# Le token est déjà configuré par défaut dans le script
# Vous pouvez le surcharger si nécessaire :
# $env:ACCESS_TOKEN="sbp_votre_token_ici"

# Exporter le schéma d'un projet
deno run --allow-net --allow-env --allow-write scripts/export-supabase-template.ts <PROJECT_REF>
```

## Exemple

```bash
# Exporter le schéma du projet ASAP Fidélité
node scripts/export-supabase-template.js abcdefghijklmnop
```

Le script va :
1. ✅ Récupérer toutes les migrations depuis `supabase_migrations.schema_migrations` (si disponibles)
2. ✅ **Si pas de migrations** : Extraire directement le schéma depuis les métadonnées PostgreSQL
3. ✅ Récupérer les extensions installées
4. ✅ Récupérer les schémas personnalisés
5. ✅ Récupérer les buckets Storage
6. ✅ Générer un fichier SQL complet dans `templates/supabase-template-<PROJECT_REF>.sql`

## Fichier généré

Le fichier SQL généré contient (dans l'ordre d'exécution) :
- **Extensions** : Toutes les extensions PostgreSQL installées
- **Schémas** : Tous les schémas personnalisés (ex: `private`, `dashboard_view`)
- **Types personnalisés** : Tous les types ENUM et composites (depuis les métadonnées)
- **Tables** : Toutes les tables avec leurs colonnes et contraintes (depuis les métadonnées)
- **Vues** : Toutes les vues avec leurs définitions (depuis les métadonnées)
- **Fonctions** : Toutes les fonctions PostgreSQL (depuis les métadonnées)
- **Migrations** : Toutes les migrations dans l'ordre chronologique (si disponibles)
- **Buckets Storage** : Tous les buckets de stockage configurés

**Important** : Même si vous n'avez pas créé de migrations lors de vos modifications, le script extrait tout le schéma directement depuis les métadonnées PostgreSQL (`information_schema`, `pg_catalog`). Vous obtiendrez un template complet avec toutes vos tables, vues et fonctions !

## Utilisation du template

### Option 1 : Exécution manuelle

1. Créez un nouveau projet Supabase
2. Ouvrez le SQL Editor
3. Copiez-collez le contenu du fichier `templates/supabase-template-<PROJECT_REF>.sql`
4. Exécutez le script

### Option 2 : Utilisation dans l'Edge Function

Le template peut être utilisé directement dans l'Edge Function `provision-client` en remplaçant la récupération des migrations par la lecture de ce fichier.

## Avantages

✅ **Complet** : Exporte tout le schéma (migrations, extensions, schémas, buckets, tables, vues, fonctions)  
✅ **Fonctionne sans migrations** : Extrait directement depuis les métadonnées PostgreSQL si pas de migrations  
✅ **Ordre garanti** : Les objets sont créés dans le bon ordre (extensions → schémas → types → tables → vues → fonctions)  
✅ **Réutilisable** : Un seul fichier SQL pour recréer tout le schéma  
✅ **Versionné** : Peut être commité dans Git pour traçabilité  
✅ **Tables créées en premier** : Les tables sont créées avant les migrations, donc pas de problème d'ordre  

## Notes

- Le script nécessite un token Supabase avec les permissions de lecture sur le projet source
- Les données des tables ne sont **pas** exportées (schéma uniquement)
- Les Edge Functions ne sont **pas** exportées (utilisez `supabase functions deploy` pour cela)
