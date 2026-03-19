/**
 * Upload des Edge Functions MyFidelity (fichiers .zip) vers Storage Supabase.
 *
 * Utilisé par l'Edge Function `supabase/functions/provision-client` pour déployer
 * automatiquement les fonctions dans les nouveaux projets clients.
 *
 * Upload attendu :
 *   bucket: templates
 *   object: myfidelity/<slug>.zip
 *
 * Fichiers locaux attendus :
 *   Groupe-405/templates/myfidelity/*.zip
 *
 * Variables d'environnement :
 *   - SUPABASE_URL
 *   - SUPABASE_SERVICE_KEY
 */

const fs = require("fs")
const path = require("path")

const SUPABASE_URL = process.env.SUPABASE_URL
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY

const BUCKET_NAME = "templates"
const LOCAL_ZIP_DIR = path.join(__dirname, "..", "templates", "myfidelity")

if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
  console.error("❌ Erreur: SUPABASE_URL et SUPABASE_SERVICE_KEY requis")
  console.log('Usage:')
  console.log('  $env:SUPABASE_URL="https://xxxxx.supabase.co"')
  console.log('  $env:SUPABASE_SERVICE_KEY="sbp_xxxxx"')
  console.log("  node scripts/upload-myfidelity-edge-zips-to-storage.js")
  process.exit(1)
}

async function ensureBucket() {
  // Le bucket existe déjà normalement, mais on garde ce check pour être sûr.
  const res = await fetch(`${SUPABASE_URL}/storage/v1/bucket`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${SUPABASE_SERVICE_KEY}`,
      apikey: SUPABASE_SERVICE_KEY,
    },
    body: JSON.stringify({
      name: BUCKET_NAME,
      public: false,
      file_size_limit: 104857600,
    }),
  })

  if (!res.ok && res.status !== 409) {
    const t = await res.text()
    throw new Error(`Impossible de créer le bucket ${BUCKET_NAME}: ${res.status} - ${t}`)
  }
}

async function uploadAllZips() {
  await ensureBucket()

  if (!fs.existsSync(LOCAL_ZIP_DIR)) {
    throw new Error(`Dossier introuvable: ${LOCAL_ZIP_DIR}`)
  }

  const files = fs
    .readdirSync(LOCAL_ZIP_DIR)
    .filter((f) => f.toLowerCase().endsWith(".zip"))

  if (!files.length) {
    throw new Error(`Aucun fichier .zip trouvé dans: ${LOCAL_ZIP_DIR}`)
  }

  for (const file of files) {
    const localPath = path.join(LOCAL_ZIP_DIR, file)
    const objectKey = `myfidelity/${file}`

    console.log(`\n⬆️ Upload: ${objectKey}`)
    const content = fs.readFileSync(localPath)

    const uploadRes = await fetch(
      `${SUPABASE_URL}/storage/v1/object/${BUCKET_NAME}/${objectKey}`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/zip",
          Authorization: `Bearer ${SUPABASE_SERVICE_KEY}`,
          apikey: SUPABASE_SERVICE_KEY,
          "x-upsert": "true",
        },
        body: content,
      }
    )

    if (!uploadRes.ok) {
      const errText = await uploadRes.text()
      throw new Error(`Échec upload ${objectKey}: ${uploadRes.status} - ${errText}`)
    }
  }

  console.log("\n✅ Tous les zips ont été uploadés avec succès.")
}

uploadAllZips()
  .catch((e) => {
    console.error("❌ Erreur:", e?.message || String(e))
    process.exit(1)
  })

