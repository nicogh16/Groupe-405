/**
 * Script pour uploader les fichiers MyFidelity splités vers le bucket Storage "templates"
 *
 * Utilisé par l'Edge Function `supabase/functions/provision-client` pour appliquer les templates SQL
 * lors de la création de nouveaux clients MyFidelity.
 *
 * Fichiers attendus localement:
 *   Groupe-405/templates/myfidelity/{init.sql,table.sql,view-mv.sql,function.sql}
 *
 * Clés Storage (objets) qui seront uploadés:
 *   templates/myfidelity/init.sql
 *   templates/myfidelity/table.sql
 *   templates/myfidelity/view-mv.sql
 *   templates/myfidelity/function.sql
 *
 * Variables d'environnement requises:
 *   - SUPABASE_URL
 *   - SUPABASE_SERVICE_KEY
 */

const fs = require("fs")
const path = require("path")

const SUPABASE_URL = process.env.SUPABASE_URL
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY

const BUCKET_NAME = "templates"
const FILES_IN_ORDER = ["init.sql", "table.sql", "view-mv.sql", "function.sql"]

if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
  console.error("❌ Erreur: SUPABASE_URL et SUPABASE_SERVICE_KEY requis")
  console.log("Usage:")
  console.log('  $env:SUPABASE_URL="https://xxxxx.supabase.co"')
  console.log('  $env:SUPABASE_SERVICE_KEY="sbp_xxxxx"')
  console.log("  node scripts/upload-myfidelity-split-templates-to-storage.js")
  process.exit(1)
}

async function uploadTemplate() {
  // Créer le bucket s'il n'existe pas
  const createBucketRes = await fetch(`${SUPABASE_URL}/storage/v1/bucket`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${SUPABASE_SERVICE_KEY}`,
      apikey: SUPABASE_SERVICE_KEY,
    },
    body: JSON.stringify({
      name: BUCKET_NAME,
      public: false,
      file_size_limit: 104857600, // 100MB
    }),
  })

  if (!createBucketRes.ok && createBucketRes.status !== 409) {
    const errorText = await createBucketRes.text()
    throw new Error(`Impossible de créer le bucket ${BUCKET_NAME}: ${createBucketRes.status} - ${errorText}`)
  }

  console.log(`📦 Upload MyFidelity split SQL vers Storage (bucket="${BUCKET_NAME}")`)

  for (const file of FILES_IN_ORDER) {
    const localPath = path.join(__dirname, "..", "templates", "myfidelity", file)
    if (!fs.existsSync(localPath)) {
      throw new Error(`Fichier introuvable localement: ${localPath}`)
    }

    const objectKey = `myfidelity/${file}`
    const content = fs.readFileSync(localPath, "utf8")
    const fileSizeMb = (content.length / 1024 / 1024).toFixed(2)

    console.log(`\n⬆️  Upload: ${objectKey} (${fileSizeMb} MB)`)

    const uploadRes = await fetch(
      `${SUPABASE_URL}/storage/v1/object/${BUCKET_NAME}/${objectKey}`,
      {
        method: "POST",
        headers: {
          "Content-Type": "text/plain",
          Authorization: `Bearer ${SUPABASE_SERVICE_KEY}`,
          apikey: SUPABASE_SERVICE_KEY,
          "x-upsert": "true",
        },
        body: content,
      }
    )

    if (!uploadRes.ok) {
      const errorText = await uploadRes.text()
      throw new Error(`Échec upload ${objectKey}: ${uploadRes.status} - ${errorText}`)
    }
  }

  console.log("\n✅ Upload terminé avec succès.")
  console.log("💡 L'Edge Function `provision-client` utilisera automatiquement ces fichiers pour MyFidelity.")
}

uploadTemplate().catch((e) => {
  console.error("❌ Erreur:", e?.message || String(e))
  process.exit(1)
})

