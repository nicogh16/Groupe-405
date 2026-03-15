# 🚀 Guide Rapide : Restaurer dans un Nouveau Projet Supabase

## Étapes rapides

### 1️⃣ Préparer le dump (déjà fait ✅)
```powershell
.\scripts\prepare-dump-for-new-project.ps1
```
**Fichier créé :** `supabase_new_project.sql`

### 2️⃣ Créer un nouveau projet Supabase
- Allez sur https://supabase.com/dashboard
- Cliquez sur "New Project"
- Notez votre mot de passe et votre project reference

### 3️⃣ Restaurer le dump
```powershell
.\scripts\restore-to-new-project.ps1 -ConnectionString "postgresql://postgres:VOTRE_MOT_DE_PASSE@db.VOTRE_PROJET.supabase.co:5432/postgres"
```

### 4️⃣ Mettre à jour `.env.local`
Récupérez les nouvelles clés depuis **Settings → API** dans le dashboard Supabase.

---

**Fichiers disponibles :**
- ✅ `supabase_new_project.sql` - Dump prêt à restaurer
- 📄 `RESTORE_TO_NEW_PROJECT.md` - Guide détaillé
- 🔧 `scripts/prepare-dump-for-new-project.ps1` - Script de préparation
- 🔧 `scripts/restore-to-new-project.ps1` - Script de restauration
