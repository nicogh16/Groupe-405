/**
 * Script de test manuel pour exécuter function.sql
 * Usage: node scripts/test-function-sql.js
 */

const { Client } = require('pg');
const fs = require('fs').promises;
const path = require('path');

// Configuration - MODIFIEZ CES VALEURS
const PROJECT_REF = 'medpkzuculodumzlmbrk'; // Votre project ref
const DB_PASSWORD = '6lOMIvti9cXPHbs0'; // Votre mot de passe

// Connection string avec pooler (port 6543)
const connectionString = `postgresql://postgres:${encodeURIComponent(DB_PASSWORD)}@db.${PROJECT_REF}.supabase.co:6543/postgres`;

async function testFunctionSQL() {
  const client = new Client({
    connectionString,
    statement_timeout: 0, // Pas de timeout
    query_timeout: 0,
  });

  try {
    console.log('🔌 Connexion à la base de données...');
    await client.connect();
    console.log('✅ Connecté avec succès');

    // Lire le fichier function.sql
    const sqlFilePath = path.join(__dirname, '..', 'templates', 'myfidelity', 'function.sql');
    console.log(`📖 Lecture du fichier: ${sqlFilePath}`);
    
    const sqlContent = await fs.readFile(sqlFilePath, 'utf8');
    console.log(`📄 Fichier lu: ${sqlContent.length} caractères`);

    // Exécuter le SQL
    console.log('⚙️  Exécution du SQL (cela peut prendre plusieurs minutes)...');
    const startTime = Date.now();
    
    const result = await client.query(sqlContent);
    
    const duration = ((Date.now() - startTime) / 1000).toFixed(2);
    console.log(`✅ Exécution terminée en ${duration} secondes`);
    console.log(`📊 Résultat:`, result.command, result.rowCount !== null ? `${result.rowCount} lignes affectées` : '');

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

  } catch (error) {
    console.error('❌ Erreur:', error.message);
    if (error.position) {
      console.error(`   Position de l'erreur: ${error.position}`);
    }
    if (error.hint) {
      console.error(`   Indice: ${error.hint}`);
    }
    process.exit(1);
  } finally {
    await client.end();
    console.log('\n🔌 Connexion fermée');
  }
}

// Exécuter le test
testFunctionSQL().catch(console.error);
