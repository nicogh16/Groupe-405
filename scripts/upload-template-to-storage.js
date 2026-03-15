/**
 * Script pour uploader le fichier template SQL dans un bucket Storage Supabase
 * 
 * Usage:
 *   node scripts/upload-template-to-storage.js
 * 
 * Variables d'environnement requises:
 *   - SUPABASE_URL: URL de votre projet Supabase (ex: https://xxxxx.supabase.co)
 *   - SUPABASE_SERVICE_KEY: Service role key (pas l'anon key!)
 */

const fs = require('fs')
const path = require('path')

const SUPABASE_URL = process.env.SUPABASE_URL
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY
const TEMPLATE_FILE = path.join(__dirname, '..', 'templates', 'supabase-template-zdicqtupwckhvxhlkiuf.sql')
const BUCKET_NAME = 'templates'
const FILE_NAME = 'supabase-template-zdicqtupwckhvxhlkiuf.sql'

if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
  console.error('❌ Erreur: SUPABASE_URL et SUPABASE_SERVICE_KEY requis')
  console.log('Usage:')
  console.log('  $env:SUPABASE_URL="https://xxxxx.supabase.co"')
  console.log('  $env:SUPABASE_SERVICE_KEY="sbp_xxxxx"')
  console.log('  node scripts/upload-template-to-storage.js')
  process.exit(1)
}

if (!fs.existsSync(TEMPLATE_FILE)) {
  console.error(`❌ Erreur: Fichier template introuvable: ${TEMPLATE_FILE}`)
  console.log('Exécutez d\'abord: node scripts/export-supabase-template.js')
  process.exit(1)
}

async function uploadTemplate() {
  try {
    console.log('📦 Upload du template SQL vers Storage Supabase...')
    console.log(`   Fichier: ${TEMPLATE_FILE}`)
    console.log(`   Bucket: ${BUCKET_NAME}`)
    console.log(`   Nom: ${FILE_NAME}`)
    console.log('─'.repeat(80))

    // Lire le fichier
    const fileContent = fs.readFileSync(TEMPLATE_FILE, 'utf8')
    const fileSize = (fileContent.length / 1024).toFixed(2)
    console.log(`✅ Fichier lu (${fileSize} KB)`)

    // Créer le bucket s'il n'existe pas
    console.log(`\n📁 Vérification du bucket "${BUCKET_NAME}"...`)
    const createBucketRes = await fetch(
      `${SUPABASE_URL}/storage/v1/bucket`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
          'apikey': SUPABASE_SERVICE_KEY,
        },
        body: JSON.stringify({
          name: BUCKET_NAME,
          public: false, // Bucket privé
          file_size_limit: 10485760, // 10 MB
        }),
      }
    )

    if (createBucketRes.ok) {
      console.log(`✅ Bucket "${BUCKET_NAME}" créé`)
    } else if (createBucketRes.status === 409) {
      console.log(`✅ Bucket "${BUCKET_NAME}" existe déjà`)
    } else {
      const errorText = await createBucketRes.text()
      console.warn(`⚠️  Impossible de créer le bucket: ${errorText}`)
    }

    // Uploader le fichier
    console.log(`\n⬆️  Upload du fichier "${FILE_NAME}"...`)
    const uploadRes = await fetch(
      `${SUPABASE_URL}/storage/v1/object/${BUCKET_NAME}/${FILE_NAME}`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'text/plain',
          'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
          'apikey': SUPABASE_SERVICE_KEY,
        },
        body: fileContent,
      }
    )

    if (!uploadRes.ok) {
      const errorText = await uploadRes.text()
      throw new Error(`Échec upload: ${uploadRes.status} - ${errorText}`)
    }

    console.log(`✅ Fichier uploadé avec succès!`)
    console.log(`\n📊 Résumé:`)
    console.log(`   - Bucket: ${BUCKET_NAME}`)
    console.log(`   - Fichier: ${FILE_NAME}`)
    console.log(`   - Taille: ${fileSize} KB`)
    console.log(`\n💡 Le fichier est maintenant accessible depuis l'Edge Function provision-client`)

  } catch (error) {
    console.error(`\n❌ Erreur lors de l'upload:`, error.message)
    process.exit(1)
  }
}

uploadTemplate()
