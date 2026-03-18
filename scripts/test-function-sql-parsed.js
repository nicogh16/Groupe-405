/**
 * Script de test manuel pour exécuter function.sql avec parsing
 * Usage: node scripts/test-function-sql-parsed.js
 */

const { Client } = require('pg');
const fs = require('fs').promises;
const path = require('path');

// Configuration - MODIFIEZ CES VALEURS
const PROJECT_REF = 'medpkzuculodumzlmbrk';
const DB_PASSWORD = '6lOMIvti9cXPHbs0';

// Connection string avec pooler (port 6543)
const connectionString = `postgresql://postgres:${encodeURIComponent(DB_PASSWORD)}@db.${PROJECT_REF}.supabase.co:6543/postgres`;

// Parser SQL simplifié (basé sur celui du code)
function parseSQLStatements(sql) {
  const statements = [];
  let current = '';
  let inString = false;
  let inDollarQuote = false;
  let inDoBlock = false;
  let inFunction = false;
  let stringChar = '';
  let dollarTag = '';
  let functionDollarTag = '';

  for (let i = 0; i < sql.length; i++) {
    const char = sql[i];
    const nextChar = sql[i + 1];
    const prevChar = i > 0 ? sql[i - 1] : '';

    // Détecter le début d'une fonction PostgreSQL
    if (!inString && !inDollarQuote && !inDoBlock && !inFunction) {
      const remaining = sql.substring(i).toLowerCase();
      if (remaining.match(/^\s*create\s+(or\s+replace\s+)?function\s+/i)) {
        const fullRemaining = sql.substring(i);
        const asMatch = fullRemaining.match(/as\s+(\$[^$\s]*\$)/i);
        if (asMatch) {
          inFunction = true;
          functionDollarTag = asMatch[1];
          current += char;
          i++;
          continue;
        }
      }
    }

    // Gérer les dollar quotes dans les fonctions
    if (inFunction) {
      if (!inDollarQuote && char === '$' && sql.substring(i).startsWith(functionDollarTag)) {
        inDollarQuote = true;
        dollarTag = functionDollarTag;
        current += char;
        continue;
      } else if (inDollarQuote && sql.substring(i).startsWith(dollarTag)) {
        if (sql.substring(i + dollarTag.length).startsWith(';')) {
          inDollarQuote = false;
          current += sql.substring(i, i + dollarTag.length);
          i += dollarTag.length - 1;
          dollarTag = '';
          continue;
        } else if (sql.substring(i + dollarTag.length).match(/^\s*$/)) {
          inDollarQuote = false;
          inFunction = false;
          current += sql.substring(i, i + dollarTag.length);
          i += dollarTag.length - 1;
          dollarTag = '';
          functionDollarTag = '';
          continue;
        }
      }
    }

    // Gérer les strings normales
    if (!inDollarQuote && !inFunction) {
      if (!inString && (char === "'" || char === '"')) {
        inString = true;
        stringChar = char;
        current += char;
        continue;
      } else if (inString && char === stringChar && prevChar !== '\\') {
        inString = false;
        stringChar = '';
        current += char;
        continue;
      }
    }

    current += char;

    // Fin de statement (hors des strings et dollar quotes)
    if (!inString && !inDollarQuote && !inFunction && char === ';') {
      const trimmed = current.trim();
      if (trimmed && !trimmed.match(/^\s*--/)) {
        statements.push(trimmed);
      }
      current = '';
    }
  }

  // Ajouter le dernier statement s'il y en a un
  const trimmed = current.trim();
  if (trimmed && !trimmed.match(/^\s*--/)) {
    statements.push(trimmed);
  }

  return statements;
}

async function testFunctionSQL() {
  const client = new Client({
    connectionString,
    statement_timeout: 0,
    query_timeout: 0,
  });

  try {
    console.log('🔌 Connexion à la base de données...');
    await client.connect();
    console.log('✅ Connecté avec succès\n');

    // Lire le fichier function.sql
    const sqlFilePath = path.join(__dirname, '..', 'templates', 'myfidelity', 'function.sql');
    console.log(`📖 Lecture du fichier: ${sqlFilePath}`);
    
    const sqlContent = await fs.readFile(sqlFilePath, 'utf8');
    console.log(`📄 Fichier lu: ${sqlContent.length} caractères\n`);

    // Parser le SQL en statements
    console.log('🔧 Parsing du SQL en statements individuels...');
    const statements = parseSQLStatements(sqlContent);
    console.log(`📋 ${statements.length} statement(s) trouvé(s)\n`);

    // Exécuter chaque statement
    console.log('⚙️  Exécution des statements (cela peut prendre plusieurs minutes)...\n');
    const startTime = Date.now();
    let successCount = 0;
    let errorCount = 0;
    const errors = [];

    for (let i = 0; i < statements.length; i++) {
      const statement = statements[i];
      const statementPreview = statement.substring(0, 80).replace(/\s+/g, ' ');
      
      try {
        await client.query(statement);
        successCount++;
        
        if ((i + 1) % 10 === 0) {
          process.stdout.write(`\r✅ ${i + 1}/${statements.length} statements exécutés...`);
        }
      } catch (error) {
        errorCount++;
        errors.push({
          index: i + 1,
          statement: statementPreview,
          error: error.message,
        });
        
        // Afficher les premières erreurs
        if (errors.length <= 5) {
          console.log(`\n❌ Erreur au statement ${i + 1}: ${error.message}`);
          console.log(`   Statement: ${statementPreview}...`);
        }
      }
    }

    const duration = ((Date.now() - startTime) / 1000).toFixed(2);
    console.log(`\n\n✅ Exécution terminée en ${duration} secondes`);
    console.log(`📊 Résultats: ${successCount} succès, ${errorCount} erreur(s)`);

    if (errors.length > 5) {
      console.log(`\n⚠️  ${errors.length - 5} autre(s) erreur(s) non affichée(s)`);
    }

    // Vérifier que les fonctions ont été créées
    console.log('\n🔍 Vérification des fonctions créées...');
    const functionsQuery = `
      SELECT 
        n.nspname as schema_name,
        COUNT(*) as function_count
      FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
      WHERE n.nspname IN ('audit', 'mv', 'postgre_rpc', 'private', 'public')
      GROUP BY n.nspname
      ORDER BY n.nspname;
    `;
    
    const functionsResult = await client.query(functionsQuery);
    console.log('\n📋 Fonctions par schéma:');
    functionsResult.rows.forEach(row => {
      console.log(`   - ${row.schema_name}: ${row.function_count} fonction(s)`);
    });

    const totalFunctions = functionsResult.rows.reduce((sum, row) => sum + parseInt(row.function_count), 0);
    console.log(`\n✅ Total: ${totalFunctions} fonction(s) créée(s)`);

    if (errorCount > 0) {
      console.log(`\n⚠️  Attention: ${errorCount} erreur(s) détectée(s) lors de l'exécution`);
      process.exit(1);
    }

  } catch (error) {
    console.error('\n❌ Erreur:', error.message);
    if (error.position) {
      console.error(`   Position de l'erreur: ${error.position}`);
    }
    process.exit(1);
  } finally {
    await client.end();
    console.log('\n🔌 Connexion fermée');
  }
}

// Exécuter le test
testFunctionSQL().catch(console.error);
