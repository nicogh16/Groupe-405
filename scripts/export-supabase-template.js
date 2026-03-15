/**
 * Script pour exporter le schéma complet d'un projet Supabase
 * et créer un template réutilisable (Version "Sniper" - Custom Data Only)
 * * Usage: 
 * node scripts/export-supabase-template.js <PROJECT_REF>
 */

const PROJECT_REF = process.argv[2] || process.env.SOURCE_SUPABASE_PROJECT_REF || "zdicqtupwckhvxhlkiuf"
const ACCESS_TOKEN = process.env.ACCESS_TOKEN || "sbp_98fff5bba54457eb19159fec09e9c9ec1d86dd7d"

if (!ACCESS_TOKEN) {
  console.error("❌ Erreur: ACCESS_TOKEN requis")
  console.log("Définissez ACCESS_TOKEN dans votre environnement")
  process.exit(1)
}

const fs = require('fs')
const path = require('path')

console.log(`📦 Export du schéma Supabase pour le projet: ${PROJECT_REF}`)
console.log("─".repeat(80))

// ============================================================================
// LISTE NOIRE DES OBJETS SYSTÈMES SUPABASE / POSTGRESQL
// ============================================================================
const EXCLUDED_SCHEMAS = [
  'auth', 'cron', 'extensions', 'graphql', 'graphql_public', 
  'information_schema', 'net', 'pg_catalog', 'pg_toast', 
  'pgbouncer', 'pgmq', 'pgsodium', 'pgsodium_masks', 
  'realtime', 'storage', 'supabase_functions', 
  'supabase_migrations', 'vault'
]

// On génère la string pour les requêtes SQL : 'auth', 'cron', 'extensions'...
const EXCLUDED_SCHEMAS_SQL = EXCLUDED_SCHEMAS.map(s => `'${s}'`).join(', ')

// Extensions de base à ne pas exporter (elles sont gérées par Supabase)
const EXCLUDED_EXTENSIONS = [
  'plpgsql', 'pgcrypto', 'uuid-ossp', 'pgjwt', 'pg_stat_statements',
  'pg_graphql', 'pgsodium', 'supabase_vault', 'pgbouncer'
]
const EXCLUDED_EXTENSIONS_SQL = EXCLUDED_EXTENSIONS.map(e => `'${e}'`).join(', ')
// ============================================================================

async function executeQuery(query) {
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
  if (Array.isArray(result)) return result
  if (result.data && Array.isArray(result.data)) return result.data
  if (result.rows && Array.isArray(result.rows)) return result.rows
  return result
}

async function getMigrations() {
  console.log("\n📋 Récupération des migrations...")
  try {
    const migrations = await executeQuery(`
      SELECT version, name, statements
      FROM supabase_migrations.schema_migrations
      ORDER BY version ASC;
    `)
    console.log(`✅ ${migrations.length} migration(s) trouvée(s)`)
    return migrations
  } catch (error) {
    console.warn(`⚠️  Aucune migration trouvée ou erreur: ${error.message}`)
    console.log("📝 Le script va extraire le schéma directement depuis les métadonnées PostgreSQL")
    return []
  }
}

async function getExtensions() {
  console.log("\n🔌 Récupération des extensions custom...")
  const extensions = await executeQuery(`
    SELECT extname as name, extversion as version
    FROM pg_extension
    WHERE extname NOT IN (${EXCLUDED_EXTENSIONS_SQL})
    ORDER BY extname;
  `)
  console.log(`✅ ${extensions.length} extension(s) custom trouvée(s)`)
  return extensions
}

async function getSchemas() {
  console.log("\n📁 Récupération des schémas custom...")
  const schemas = await executeQuery(`
    SELECT nspname as name
    FROM pg_namespace
    WHERE nspname NOT IN (${EXCLUDED_SCHEMAS_SQL})
      AND nspname NOT LIKE 'pg_%'
    ORDER BY nspname;
  `)
  console.log(`✅ ${schemas.length} schéma(s) personnalisé(s) trouvé(s)`)
  return schemas
}

async function getStorageBuckets() {
  console.log("\n🗄️  Récupération des buckets Storage...")
  try {
    const buckets = await executeQuery(`
      SELECT name, public, file_size_limit, allowed_mime_types
      FROM storage.buckets
      ORDER BY name;
    `)
    console.log(`✅ ${buckets.length} bucket(s) trouvé(s)`)
    return buckets
  } catch (error) {
    console.warn(`⚠️  Impossible de récupérer les buckets: ${error.message}`)
    return []
  }
}

async function getSchemaFromMetadata() {
  console.log("\n🔍 Extraction du schéma métier depuis les métadonnées...")
  
  const schemaObjects = { tables: [], views: [], functions: [], types: [], triggers: [], policies: [] }

  try {
    // Tables
    console.log("  → Extraction des tables...")
    const tables = await executeQuery(`
      SELECT t.table_schema, t.table_name, c.column_name, c.data_type, 
             c.character_maximum_length, c.is_nullable, c.column_default, c.ordinal_position
      FROM information_schema.tables t
      JOIN information_schema.columns c ON t.table_schema = c.table_schema AND t.table_name = c.table_name
      WHERE t.table_schema NOT IN (${EXCLUDED_SCHEMAS_SQL})
        AND t.table_schema NOT LIKE 'pg_%'
        AND t.table_type = 'BASE TABLE'
      ORDER BY t.table_schema, t.table_name, c.ordinal_position;
    `)
    
    const tablesMap = new Map()
    for (const row of tables) {
      const key = `${row.table_schema}.${row.table_name}`
      if (!tablesMap.has(key)) tablesMap.set(key, { schema: row.table_schema, name: row.table_name, columns: [] })
      tablesMap.get(key).columns.push(row)
    }
    schemaObjects.tables = Array.from(tablesMap.values())
    console.log(`    ✅ ${schemaObjects.tables.length} table(s) custom trouvée(s)`)

    // Vues
    console.log("  → Extraction des vues...")
    const views = await executeQuery(`
      SELECT schemaname, viewname, definition
      FROM pg_views
      WHERE schemaname NOT IN (${EXCLUDED_SCHEMAS_SQL})
        AND schemaname NOT LIKE 'pg_%'
      ORDER BY schemaname, viewname;
    `)
    schemaObjects.views = views
    console.log(`    ✅ ${schemaObjects.views.length} vue(s) custom trouvée(s)`)

    // Fonctions
    console.log("  → Extraction des fonctions...")
    const functions = await executeQuery(`
      SELECT n.nspname as schema_name, p.proname as function_name,
             pg_get_function_arguments(p.oid) as arguments,
             pg_get_function_result(p.oid) as return_type,
             l.lanname as language, pg_get_functiondef(p.oid) as definition
      FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
      JOIN pg_language l ON p.prolang = l.oid
      WHERE n.nspname NOT IN (${EXCLUDED_SCHEMAS_SQL})
        AND n.nspname NOT LIKE 'pg_%'
        AND p.prokind = 'f'
      ORDER BY n.nspname, p.proname;
    `)
    schemaObjects.functions = functions
    console.log(`    ✅ ${schemaObjects.functions.length} fonction(s) custom trouvée(s)`)

    // Types personnalisés (ENUMs, etc.)
    console.log("  → Extraction des types...")
    const typesRaw = await executeQuery(`
      SELECT n.nspname as schema_name, t.typname as type_name, t.typtype as type_type,
             array_agg(e.enumlabel ORDER BY e.enumsortorder) as enum_values
      FROM pg_type t
      JOIN pg_namespace n ON t.typnamespace = n.oid
      LEFT JOIN pg_enum e ON t.oid = e.enumtypid
      WHERE n.nspname NOT IN (${EXCLUDED_SCHEMAS_SQL})
        AND n.nspname NOT LIKE 'pg_%'
        AND t.typtype IN ('e', 'c')
      GROUP BY n.nspname, t.typname, t.typtype
      ORDER BY n.nspname, t.typname;
    `)
    
    const types = typesRaw.map(type => {
      if (type.enum_values && !Array.isArray(type.enum_values)) {
        if (typeof type.enum_values === 'string') {
          try {
            const parsed = JSON.parse(type.enum_values)
            type.enum_values = Array.isArray(parsed) ? parsed : [type.enum_values]
          } catch {
            type.enum_values = [type.enum_values]
          }
        } else {
          type.enum_values = []
        }
      }
      return type
    })
    
    schemaObjects.types = types
    console.log(`    ✅ ${schemaObjects.types.length} type(s) custom trouvé(s)`)

  } catch (error) {
    console.warn(`⚠️  Erreur lors de l'extraction: ${error.message}`)
  }

  return schemaObjects
}

async function getTableConstraints(schema, tableName) {
  try {
    const constraints = await executeQuery(`
      SELECT tc.constraint_name, tc.constraint_type, kcu.column_name,
             ccu.table_schema AS foreign_table_schema, ccu.table_name AS foreign_table_name,
             ccu.column_name AS foreign_column_name
      FROM information_schema.table_constraints tc
      LEFT JOIN information_schema.key_column_usage kcu 
        ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
      LEFT JOIN information_schema.constraint_column_usage ccu 
        ON ccu.constraint_name = tc.constraint_name
      WHERE tc.table_schema = '${schema}' AND tc.table_name = '${tableName}'
      ORDER BY tc.constraint_type, tc.constraint_name;
    `)
    return constraints
  } catch (error) {
    console.warn(`⚠️  Impossible de récupérer les contraintes pour ${schema}.${tableName}: ${error.message}`)
    return []
  }
}

async function generateCreateTableSQL(table) {
  let sql = `CREATE TABLE IF NOT EXISTS "${table.schema}"."${table.name}" (\n`
  const columns = []
  
  for (const col of table.columns) {
    let colDef = `  "${col.column_name}" ${col.data_type}`
    if (col.character_maximum_length) colDef += `(${col.character_maximum_length})`
    if (col.is_nullable === 'NO') colDef += ' NOT NULL'
    if (col.column_default) colDef += ` DEFAULT ${col.column_default}`
    columns.push(colDef)
  }
  
  const constraints = await getTableConstraints(table.schema, table.name)
  const primaryKeys = constraints.filter(c => c.constraint_type === 'PRIMARY KEY')
  const foreignKeys = constraints.filter(c => c.constraint_type === 'FOREIGN KEY')
  const uniqueKeys = constraints.filter(c => c.constraint_type === 'UNIQUE')
  
  if (primaryKeys.length > 0) {
    const pkColumns = primaryKeys.map(c => `"${c.column_name}"`).join(', ')
    columns.push(`  PRIMARY KEY (${pkColumns})`)
  }
  
  for (const fk of foreignKeys) {
    if (fk.foreign_table_schema && fk.foreign_table_name && fk.foreign_column_name) {
      columns.push(`  CONSTRAINT "${fk.constraint_name}" FOREIGN KEY ("${fk.column_name}") REFERENCES "${fk.foreign_table_schema}"."${fk.foreign_table_name}"("${fk.foreign_column_name}")`)
    }
  }
  
  for (const uk of uniqueKeys) {
    columns.push(`  CONSTRAINT "${uk.constraint_name}" UNIQUE ("${uk.column_name}")`)
  }
  
  sql += columns.join(',\n') + '\n);'
  return sql
}

async function generateTemplateSQL(migrations, extensions, schemas, buckets, schemaMetadata = null) {
  const hasMetadata = schemaMetadata && (schemaMetadata.tables.length > 0 || schemaMetadata.views.length > 0 || schemaMetadata.functions.length > 0)
  
  let template = `-- Template SQL généré depuis le projet Supabase: ${PROJECT_REF}
-- Ne contient QUE le schéma custom métier (nettoyé des objets systèmes Supabase)
-- Date: ${new Date().toISOString()}

-- ============================================================================
-- EXTENSIONS CUSTOM
-- ============================================================================
`
  for (const ext of extensions) template += `CREATE EXTENSION IF NOT EXISTS "${ext.name}";\n`

  template += `\n-- ============================================================================
-- SCHÉMAS CUSTOM
-- ============================================================================
`
  for (const schema of schemas) template += `CREATE SCHEMA IF NOT EXISTS "${schema.name}";\n`

  template += `\n-- ============================================================================
-- TYPES PERSONNALISÉS
-- ============================================================================
`
  if (schemaMetadata && schemaMetadata.types) {
    for (const type of schemaMetadata.types) {
      if (type.type_type === 'e') {
        let enumValues = Array.isArray(type.enum_values) ? type.enum_values : []
        if (enumValues.length > 0) {
          template += `CREATE TYPE "${type.schema_name}"."${type.type_name}" AS ENUM (\n`
          template += enumValues.map(v => `  '${v}'`).join(',\n')
          template += `\n);\n\n`
        }
      }
    }
  }

  template += `\n-- ============================================================================
-- TABLES MÉTIER
-- ============================================================================
`
  if (schemaMetadata && schemaMetadata.tables) {
    for (const table of schemaMetadata.tables) {
      template += `-- Table: ${table.schema}.${table.name}\n`
      const tableSQL = await generateCreateTableSQL(table)
      template += tableSQL + "\n\n"
    }
  }

  template += `\n-- ============================================================================
-- VUES MÉTIER
-- ============================================================================
`
  if (schemaMetadata && schemaMetadata.views) {
    for (const view of schemaMetadata.views) {
      template += `CREATE OR REPLACE VIEW "${view.schemaname}"."${view.viewname}" AS\n${view.definition};\n\n`
    }
  }

  template += `\n-- ============================================================================
-- FONCTIONS MÉTIER
-- ============================================================================
`
  if (schemaMetadata && schemaMetadata.functions) {
    for (const func of schemaMetadata.functions) {
      template += `-- Function: ${func.schema_name}.${func.function_name}(${func.arguments})\n${func.definition}\n\n`
    }
  }

  template += `\n-- ============================================================================
-- STORAGE BUCKETS
-- ============================================================================
`
  for (const bucket of buckets) {
    template += `INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)\nVALUES (\n`
    template += `  '${bucket.name}', '${bucket.name}', ${bucket.public}, `
    template += `${bucket.file_size_limit ? bucket.file_size_limit : 'NULL'}, `
    template += `${bucket.allowed_mime_types ? `ARRAY[${bucket.allowed_mime_types.map(m => `'${m}'`).join(', ')}]` : 'NULL'}\n)\n`
    template += `ON CONFLICT (id) DO NOTHING;\n\n`
  }

  return template
}

async function main() {
  try {
    const [migrations, extensions, schemas, buckets] = await Promise.all([
      getMigrations(), getExtensions(), getSchemas(), getStorageBuckets(),
    ])

    let schemaMetadata = null
    console.log("\n⚠️  Extraction complète du schéma métier depuis les métadonnées...")
    try {
      schemaMetadata = await getSchemaFromMetadata()
    } catch (error) {
      console.warn(`⚠️  Impossible d'extraire les métadonnées: ${error.message}`)
    }

    const templateSQL = await generateTemplateSQL(migrations, extensions, schemas, buckets, schemaMetadata)

    const outputDir = path.join(process.cwd(), 'templates')
    if (!fs.existsSync(outputDir)) fs.mkdirSync(outputDir, { recursive: true })

    const outputPath = path.join(outputDir, `supabase-template-${PROJECT_REF}.sql`)
    fs.writeFileSync(outputPath, templateSQL, 'utf8')

    console.log("\n" + "=".repeat(80))
    console.log("✅ Template généré avec succès ! (100% Custom)")
    console.log("=".repeat(80))
    console.log(`📄 Fichier: ${outputPath}`)
    
  } catch (error) {
    console.error("\n❌ Erreur lors de l'export:", error.message)
    process.exit(1)
  }
}

main()