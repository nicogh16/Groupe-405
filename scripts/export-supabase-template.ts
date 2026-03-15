/**
 * Script pour exporter le schéma complet d'un projet Supabase
 * et créer un template réutilisable
 * 
 * Usage: 
 *   deno run --allow-net --allow-env --allow-write scripts/export-supabase-template.ts <PROJECT_REF>
 * 
 * Ou avec npx tsx:
 *   npx tsx scripts/export-supabase-template.ts <PROJECT_REF>
 */

const PROJECT_REF = Deno.args[0] || process.env.SOURCE_SUPABASE_PROJECT_REF
// Token d'accès Supabase par défaut (peut être surchargé via ACCESS_TOKEN)
const ACCESS_TOKEN = Deno.env.get("ACCESS_TOKEN") || process.env.ACCESS_TOKEN || "sbp_98fff5bba54457eb19159fec09e9c9ec1d86dd7d"

if (!PROJECT_REF) {
  console.error("❌ Erreur: PROJECT_REF requis")
  console.log("Usage: deno run scripts/export-supabase-template.ts <PROJECT_REF>")
  Deno.exit(1)
}

if (!ACCESS_TOKEN) {
  console.error("❌ Erreur: ACCESS_TOKEN requis")
  console.log("Définissez ACCESS_TOKEN dans votre environnement")
  Deno.exit(1)
}

console.log(`📦 Export du schéma Supabase pour le projet: ${PROJECT_REF}`)
console.log("─".repeat(80))

// Fonction pour exécuter une requête SQL via l'API Supabase
async function executeQuery(query: string): Promise<any> {
  const res = await fetch(
    `https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${ACCESS_TOKEN}`,
      },
      body: JSON.stringify({ query }),
    }
  )

  if (!res.ok) {
    const errorText = await res.text()
    throw new Error(`API Error (${res.status}): ${errorText}`)
  }

  const result = await res.json()
  // Gérer différents formats de réponse
  if (Array.isArray(result)) {
    return result
  } else if (result.data && Array.isArray(result.data)) {
    return result.data
  } else if (result.rows && Array.isArray(result.rows)) {
    return result.rows
  }
  return result
}

// Fonction pour récupérer toutes les migrations
async function getMigrations() {
  console.log("\n📋 Récupération des migrations...")
  
  try {
    const migrations = await executeQuery(`
      SELECT 
        version,
        name,
        statements
      FROM supabase_migrations.schema_migrations
      ORDER BY version ASC;
    `)

    console.log(`✅ ${migrations.length} migration(s) trouvée(s)`)
    return migrations
  } catch (error) {
    const errorMsg = error instanceof Error ? error.message : String(error)
    console.warn(`⚠️  Aucune migration trouvée ou erreur: ${errorMsg}`)
    console.log("📝 Le script va extraire le schéma directement depuis les métadonnées PostgreSQL")
    return []
  }
}

// Fonction pour récupérer les extensions
async function getExtensions() {
  console.log("\n🔌 Récupération des extensions...")
  
  const extensions = await executeQuery(`
    SELECT 
      extname as name,
      extversion as version
    FROM pg_extension
    WHERE extname NOT IN ('plpgsql', 'pgcrypto', 'uuid-ossp', 'pgjwt')
    ORDER BY extname;
  `)

  console.log(`✅ ${extensions.length} extension(s) trouvée(s)`)
  return extensions
}

// Fonction pour récupérer les schémas personnalisés
async function getSchemas() {
  console.log("\n📁 Récupération des schémas...")
  
  const schemas = await executeQuery(`
    SELECT 
      nspname as name
    FROM pg_namespace
    WHERE nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast', 'pg_temp_1', 'pg_toast_temp_1', 'pg_temp', 'pg_toast_temp')
      AND nspname NOT LIKE 'pg_temp_%'
      AND nspname NOT LIKE 'pg_toast_temp_%'
      AND nspname NOT IN ('extensions', 'storage', 'vault', 'graphql_public', 'realtime', 'supabase_functions', 'supabase_migrations', 'auth')
    ORDER BY nspname;
  `)

  console.log(`✅ ${schemas.length} schéma(s) personnalisé(s) trouvé(s)`)
  return schemas
}

// Fonction pour récupérer les buckets Storage
async function getStorageBuckets() {
  console.log("\n🗄️  Récupération des buckets Storage...")
  
  try {
    const buckets = await executeQuery(`
      SELECT 
        name,
        public,
        file_size_limit,
        allowed_mime_types
      FROM storage.buckets
      ORDER BY name;
    `)

    console.log(`✅ ${buckets.length} bucket(s) trouvé(s)`)
    return buckets
  } catch (error) {
    console.warn(`⚠️  Impossible de récupérer les buckets: ${error}`)
    return []
  }
}

// Fonction pour extraire le schéma complet depuis les métadonnées PostgreSQL
async function getSchemaFromMetadata() {
  console.log("\n🔍 Extraction du schéma depuis les métadonnées PostgreSQL...")
  
  const schemaObjects = {
    tables: [] as any[],
    views: [] as any[],
    functions: [] as any[],
    types: [] as any[],
    triggers: [] as any[],
    policies: [] as any[]
  }

  try {
    // Tables avec leurs colonnes
    console.log("  → Extraction des tables...")
    const tables = await executeQuery(`
      SELECT 
        t.table_schema,
        t.table_name,
        c.column_name,
        c.data_type,
        c.character_maximum_length,
        c.is_nullable,
        c.column_default,
        c.ordinal_position
      FROM information_schema.tables t
      JOIN information_schema.columns c ON t.table_schema = c.table_schema AND t.table_name = c.table_name
      WHERE t.table_schema NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
        AND t.table_schema NOT LIKE 'pg_temp_%'
        AND t.table_type = 'BASE TABLE'
        AND t.table_schema NOT IN ('extensions', 'storage', 'vault', 'graphql_public', 'realtime', 'supabase_functions', 'supabase_migrations', 'auth')
      ORDER BY t.table_schema, t.table_name, c.ordinal_position;
    `)
    
    // Grouper par table
    const tablesMap = new Map<string, any>()
    for (const row of tables) {
      const key = `${row.table_schema}.${row.table_name}`
      if (!tablesMap.has(key)) {
        tablesMap.set(key, {
          schema: row.table_schema,
          name: row.table_name,
          columns: []
        })
      }
      tablesMap.get(key)!.columns.push(row)
    }
    
    schemaObjects.tables = Array.from(tablesMap.values())
    console.log(`    ✅ ${schemaObjects.tables.length} table(s) trouvée(s)`)

    // Vues
    console.log("  → Extraction des vues...")
    const views = await executeQuery(`
      SELECT 
        schemaname,
        viewname,
        definition
      FROM pg_views
      WHERE schemaname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
        AND schemaname NOT LIKE 'pg_temp_%'
        AND schemaname NOT IN ('extensions', 'storage', 'vault', 'graphql_public', 'realtime', 'supabase_functions', 'supabase_migrations', 'auth')
      ORDER BY schemaname, viewname;
    `)
    schemaObjects.views = views
    console.log(`    ✅ ${schemaObjects.views.length} vue(s) trouvée(s)`)

    // Fonctions
    console.log("  → Extraction des fonctions...")
    const functions = await executeQuery(`
      SELECT 
        n.nspname as schema_name,
        p.proname as function_name,
        pg_get_function_arguments(p.oid) as arguments,
        pg_get_function_result(p.oid) as return_type,
        l.lanname as language,
        pg_get_functiondef(p.oid) as definition
      FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
      JOIN pg_language l ON p.prolang = l.oid
      WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
        AND n.nspname NOT LIKE 'pg_temp_%'
        AND n.nspname NOT IN ('extensions', 'storage', 'vault', 'graphql_public', 'realtime', 'supabase_functions', 'supabase_migrations', 'auth')
        AND p.prokind = 'f'
      ORDER BY n.nspname, p.proname;
    `)
    schemaObjects.functions = functions
    console.log(`    ✅ ${schemaObjects.functions.length} fonction(s) trouvée(s)`)

    // Types personnalisés
    console.log("  → Extraction des types...")
    const typesRaw = await executeQuery(`
      SELECT 
        n.nspname as schema_name,
        t.typname as type_name,
        t.typtype as type_type,
        array_agg(e.enumlabel ORDER BY e.enumsortorder) as enum_values
      FROM pg_type t
      JOIN pg_namespace n ON t.typnamespace = n.oid
      LEFT JOIN pg_enum e ON t.oid = e.enumtypid
      WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
        AND n.nspname NOT LIKE 'pg_temp_%'
        AND n.nspname NOT IN ('extensions', 'storage', 'vault', 'graphql_public', 'realtime', 'supabase_functions', 'supabase_migrations', 'auth')
        AND t.typtype IN ('e', 'c')
      GROUP BY n.nspname, t.typname, t.typtype
      ORDER BY n.nspname, t.typname;
    `)
    
    // Normaliser enum_values (peut être retourné comme tableau ou chaîne selon l'API)
    const types = typesRaw.map((type: any) => {
      if (type.enum_values && !Array.isArray(type.enum_values)) {
        // Si c'est une chaîne, essayer de la convertir en tableau
        if (typeof type.enum_values === 'string') {
          try {
            // Essayer de parser comme JSON
            const parsed = JSON.parse(type.enum_values)
            if (Array.isArray(parsed)) {
              type.enum_values = parsed
            }
          } catch {
            // Si ce n'est pas du JSON valide, créer un tableau avec la valeur
            type.enum_values = [type.enum_values]
          }
        } else {
          // Si ce n'est ni un tableau ni une chaîne, créer un tableau vide
          type.enum_values = []
        }
      }
      return type
    })
    
    schemaObjects.types = types
    console.log(`    ✅ ${schemaObjects.types.length} type(s) trouvé(s)`)

  } catch (error) {
    console.warn(`⚠️  Erreur lors de l'extraction: ${error}`)
  }

  return schemaObjects
}

// Fonction pour générer les CREATE TABLE depuis les métadonnées
function generateCreateTableSQL(table: any): string {
  let sql = `CREATE TABLE IF NOT EXISTS "${table.schema}"."${table.name}" (\n`
  
  const columns = []
  for (const col of table.columns) {
    let colDef = `  "${col.column_name}" ${col.data_type}`
    
    if (col.character_maximum_length) {
      colDef += `(${col.character_maximum_length})`
    }
    
    if (col.is_nullable === 'NO') {
      colDef += ' NOT NULL'
    }
    
    if (col.column_default) {
      colDef += ` DEFAULT ${col.column_default}`
    }
    
    columns.push(colDef)
  }
  
  sql += columns.join(',\n')
  sql += '\n);'
  
  return sql
}

// Fonction pour générer le template SQL
async function generateTemplateSQL(migrations: any[], extensions: any[], schemas: any[], buckets: any[], schemaMetadata: any = null): Promise<string> {
  const hasMetadata = schemaMetadata && (schemaMetadata.tables.length > 0 || schemaMetadata.views.length > 0 || schemaMetadata.functions.length > 0)
  
  let template = `-- Template SQL généré depuis le projet Supabase: ${PROJECT_REF}
-- Date: ${new Date().toISOString()}
-- 
-- Ce template contient:
-- - ${migrations.length} migration(s)${migrations.length === 0 ? ' (schéma extrait depuis les métadonnées)' : ''}
-- - ${extensions.length} extension(s)
-- - ${schemas.length} schéma(s) personnalisé(s)
${hasMetadata ? `-- - ${schemaMetadata.tables.length} table(s) (depuis les métadonnées)\n-- - ${schemaMetadata.views.length} vue(s) (depuis les métadonnées)\n-- - ${schemaMetadata.functions.length} fonction(s) (depuis les métadonnées)\n-- - ${schemaMetadata.types.length} type(s) (depuis les métadonnées)` : ''}
-- - ${buckets.length} bucket(s) Storage
--
-- Pour utiliser ce template:
-- 1. Créez un nouveau projet Supabase
-- 2. Exécutez ce script SQL dans l'ordre suivant:
--    a) Extensions
--    b) Schémas
--    c) Types personnalisés
--    d) Tables (depuis les métadonnées)
--    e) Vues (depuis les métadonnées)
--    f) Fonctions (depuis les métadonnées)
--    g) Migrations (si disponibles)
--    h) Buckets Storage

-- ============================================================================
-- EXTENSIONS
-- ============================================================================

`

  // Extensions
  for (const ext of extensions) {
    template += `CREATE EXTENSION IF NOT EXISTS "${ext.name}";\n`
  }

  template += `\n-- ============================================================================
-- SCHÉMAS
-- ============================================================================

`

  // Schémas
  for (const schema of schemas) {
    template += `CREATE SCHEMA IF NOT EXISTS "${schema.name}";\n`
  }

  template += `\n-- ============================================================================
-- TYPES PERSONNALISÉS
-- ============================================================================

`

  // Types depuis les métadonnées
  if (schemaMetadata && schemaMetadata.types && schemaMetadata.types.length > 0) {
    for (const type of schemaMetadata.types) {
      if (type.type_type === 'e') {
        // Gérer enum_values qui peut être un tableau ou une chaîne
        let enumValues: string[] = []
        if (Array.isArray(type.enum_values)) {
          enumValues = type.enum_values
        } else if (type.enum_values && typeof type.enum_values === 'string') {
          // Si c'est une chaîne, essayer de la parser
          try {
            enumValues = JSON.parse(type.enum_values)
          } catch {
            // Si ce n'est pas du JSON, traiter comme une seule valeur
            enumValues = [type.enum_values]
          }
        }
        
        if (enumValues.length > 0) {
          template += `CREATE TYPE "${type.schema_name}"."${type.type_name}" AS ENUM (\n`
          template += enumValues.map((v: string) => `  '${v}'`).join(',\n')
          template += `\n);\n\n`
        }
      }
    }
  }

  template += `\n-- ============================================================================
-- TABLES (créées depuis les métadonnées PostgreSQL)
-- ============================================================================

`

  // Tables depuis les métadonnées
  if (schemaMetadata && schemaMetadata.tables && schemaMetadata.tables.length > 0) {
    for (const table of schemaMetadata.tables) {
      template += `-- Table: ${table.schema}.${table.name}\n`
      template += generateCreateTableSQL(table) + "\n\n"
    }
  }

  template += `\n-- ============================================================================
-- VUES
-- ============================================================================

`

  // Vues depuis les métadonnées
  if (schemaMetadata && schemaMetadata.views && schemaMetadata.views.length > 0) {
    for (const view of schemaMetadata.views) {
      template += `CREATE OR REPLACE VIEW "${view.schemaname}"."${view.viewname}" AS\n`
      template += view.definition + ";\n\n"
    }
  }

  template += `\n-- ============================================================================
-- FONCTIONS
-- ============================================================================

`

  // Fonctions depuis les métadonnées
  if (schemaMetadata && schemaMetadata.functions && schemaMetadata.functions.length > 0) {
    for (const func of schemaMetadata.functions) {
      template += `-- Function: ${func.schema_name}.${func.function_name}(${func.arguments})\n`
      template += func.definition + "\n\n"
    }
  }

  template += `\n-- ============================================================================
-- MIGRATIONS (si disponibles, dans l'ordre chronologique)
-- ============================================================================

`

  // Migrations (si disponibles)
  if (migrations && migrations.length > 0) {
    for (const migration of migrations) {
      template += `-- Migration: ${migration.name || migration.version}\n`
      template += `-- Version: ${migration.version}\n\n`
      
      if (migration.statements && Array.isArray(migration.statements)) {
        template += migration.statements.join("\n\n") + "\n\n"
      } else if (migration.statement) {
        template += migration.statement + "\n\n"
      }
      
      template += "-- " + "─".repeat(70) + "\n\n"
    }
  } else {
    template += `-- Aucune migration trouvée dans supabase_migrations.schema_migrations\n`
    template += `-- Le schéma a été extrait directement depuis les métadonnées PostgreSQL\n\n`
  }

  template += `-- ============================================================================
-- STORAGE BUCKETS
-- ============================================================================

`

  // Buckets
  for (const bucket of buckets) {
    template += `INSERT INTO storage.buckets (name, public, file_size_limit, allowed_mime_types)\n`
    template += `VALUES (\n`
    template += `  '${bucket.name}',\n`
    template += `  ${bucket.public},\n`
    template += `  ${bucket.file_size_limit ? bucket.file_size_limit : 'NULL'},\n`
    template += `  ${bucket.allowed_mime_types ? `ARRAY[${bucket.allowed_mime_types.map((m: string) => `'${m}'`).join(', ')}]` : 'NULL'}\n`
    template += `)\n`
    template += `ON CONFLICT (name) DO NOTHING;\n\n`
  }

  return template
}

// Fonction principale
async function main() {
  try {
    // Récupérer toutes les données
    const [migrations, extensions, schemas, buckets] = await Promise.all([
      getMigrations(),
      getExtensions(),
      getSchemas(),
      getStorageBuckets(),
    ])

    // Extraire le schéma depuis les métadonnées (même si pas de migrations)
    let schemaMetadata = null
    if (migrations.length === 0) {
      console.log("\n⚠️  Aucune migration trouvée, extraction complète du schéma depuis les métadonnées...")
      schemaMetadata = await getSchemaFromMetadata()
    } else {
      // Essayer quand même d'extraire les métadonnées pour avoir les tables/vues/fonctions actuelles
      try {
        schemaMetadata = await getSchemaFromMetadata()
      } catch (error) {
        console.warn(`⚠️  Impossible d'extraire les métadonnées: ${error}`)
      }
    }

    // Générer le template SQL
    const templateSQL = await generateTemplateSQL(migrations, extensions, schemas, buckets, schemaMetadata)

    // Sauvegarder dans un fichier
    const outputPath = `templates/supabase-template-${PROJECT_REF}.sql`
    
    // Créer le dossier templates s'il n'existe pas
    try {
      await Deno.mkdir("templates", { recursive: true })
    } catch {
      // Le dossier existe déjà
    }

    await Deno.writeTextFile(outputPath, templateSQL)

    console.log("\n" + "=".repeat(80))
    console.log("✅ Template généré avec succès !")
    console.log("=".repeat(80))
    console.log(`📄 Fichier: ${outputPath}`)
    console.log(`📊 Statistiques:`)
    console.log(`   - Migrations: ${migrations.length}`)
    console.log(`   - Extensions: ${extensions.length}`)
    console.log(`   - Schémas: ${schemas.length}`)
    if (schemaMetadata) {
      console.log(`   - Tables: ${schemaMetadata.tables.length}`)
      console.log(`   - Vues: ${schemaMetadata.views.length}`)
      console.log(`   - Fonctions: ${schemaMetadata.functions.length}`)
      console.log(`   - Types: ${schemaMetadata.types.length}`)
    }
    console.log(`   - Buckets: ${buckets.length}`)
    console.log("\n💡 Pour utiliser ce template:")
    console.log("   1. Créez un nouveau projet Supabase")
    console.log(`   2. Exécutez le fichier SQL: ${outputPath}`)
    console.log("   3. Ou utilisez-le dans votre Edge Function de provisionnement")
  } catch (error) {
    console.error("\n❌ Erreur lors de l'export:", error)
    Deno.exit(1)
  }
}

// Exécuter
if (import.meta.main) {
  main()
}
