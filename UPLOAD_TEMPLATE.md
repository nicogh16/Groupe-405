# Upload du template SQL vers Storage

Le fichier template SQL doit être stocké dans un bucket Storage Supabase pour être accessible depuis l'Edge Function `provision-client`.

## Étapes

### 1. Exporter le template (si pas déjà fait)

```bash
node scripts/export-supabase-template.js
```

Cela génère le fichier `templates/supabase-template-zdicqtupwckhvxhlkiuf.sql`

### 2. Uploader vers Storage

```bash
# Définir les variables d'environnement
$env:SUPABASE_URL="https://votre-projet.supabase.co"
$env:SUPABASE_SERVICE_KEY="sbp_votre_service_key"

# Uploader le fichier
node scripts/upload-template-to-storage.js
```

## Configuration requise

- **SUPABASE_URL** : URL de votre projet Supabase (ex: `https://xxxxx.supabase.co`)
- **SUPABASE_SERVICE_KEY** : Service role key (⚠️ pas l'anon key, mais la service_role key)

## Ce que fait le script

1. ✅ Vérifie que le fichier template existe
2. ✅ Crée le bucket `templates` s'il n'existe pas (bucket privé)
3. ✅ Upload le fichier `supabase-template-zdicqtupwckhvxhlkiuf.sql` dans le bucket
4. ✅ Le fichier est maintenant accessible depuis l'Edge Function

## Vérification

Vous pouvez vérifier que le fichier est bien uploadé dans le Dashboard Supabase :
- **Storage** → **Buckets** → **templates** → Vérifier que le fichier est présent

## Note importante

⚠️ Le bucket `templates` doit être accessible avec la **service_role key** (pas l'anon key). Le script utilise la service_role key pour créer le bucket et uploader le fichier.
