/**
 * Script pour uploader le fichier supabase_new_project.sql dans un bucket Storage Supabase
 * pour être utilisé automatiquement lors du provisioning de nouveaux clients MyFidelity
 * 
 * Usage:
 *   node scripts/upload-myfidelity-template.js
 * 
 * Variables d'environnement requises:
 *   - SUPABASE_URL: URL de votre projet Supabase (ex: https://xxxxx.supabase.co)
 *   - SUPABASE_SERVICE_KEY: Service role key (pas l'anon key!)
 */

const fs = require('fs')
const path = require('path')

const SUPABASE_URL = process.env.SUPABASE_URL
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY
const TEMPLATE_FILE = path.join(__dirname, '..', 'supabase_new_project.sql')
const BUCKET_NAME = 'templates'
const FILE_NAME = 'supabase_new_project.sql'

if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
  console.error('❌ Erreur: SUPABASE_URL et SUPABASE_SERVICE_KEY requis')
  console.log('Usage:')
  console.log('  $env:SUPABASE_URL="https://xxxxx.supabase.co"')
  console.log('  $env:SUPABASE_SERVICE_KEY="sbp_xxxxx"')
  console.log('  node scripts/upload-myfidelity-template.js')
  process.exit(1)
}

if (!fs.existsSync(TEMPLATE_FILE)) {
  console.error(`❌ Erreur: Fichier template introuvable: ${TEMPLATE_FILE}`)
  console.log('Assurez-vous que le fichier supabase_new_project.sql existe à la racine du projet')
  process.exit(1)
}

async function uploadTemplate() {
  try {
    console.log('📦 Upload du template SQL MyFidelity vers Storage Supabase...')
    console.log(`   Fichier: ${TEMPLATE_FILE}`)
    console.log(`   Bucket: ${BUCKET_NAME}`)
    console.log(`   Nom: ${FILE_NAME}`)
    console.log('─'.repeat(80))

    // Lire le fichier
    const fileContent = fs.readFileSync(TEMPLATE_FILE, 'utf8')
    const fileSize = (fileContent.length / 1024 / 1024).toFixed(2)
    console.log(`✅ Fichier lu (${fileSize} MB)`)

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
          file_size_limit: 104857600, // 100 MB (augmenté pour les gros fichiers)
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
    console.log(`   (Cela peut prendre quelques minutes pour un gros fichier...)`)
    
    const uploadRes = await fetch(
      `${SUPABASE_URL}/storage/v1/object/${BUCKET_NAME}/${FILE_NAME}`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'text/plain',
          'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
          'apikey': SUPABASE_SERVICE_KEY,
          'x-upsert': 'true', // Remplacer si existe déjà
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
    console.log(`   - Taille: ${fileSize} MB`)
    console.log(`\n💡 Le fichier est maintenant accessible depuis l'Edge Function provision-client`)
    console.log(`   Lors de la création d'un nouveau client MyFidelity, le système utilisera automatiquement ce fichier!`)

  } catch (error) {
    console.error(`\n❌ Erreur lors de l'upload:`, error.message)
    process.exit(1)
  }
}

uploadTemplate()
