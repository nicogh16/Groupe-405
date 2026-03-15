# Configuration GitHub pour le projet

Ce guide explique comment pousser le projet vers votre compte GitHub.

## ⚠️ Important : GitHub n'utilise plus les mots de passe

Depuis août 2021, GitHub n'accepte plus les mots de passe pour l'authentification Git. Vous devez utiliser un **Personal Access Token (PAT)**.

## Méthode 1 : Utiliser le script PowerShell (Recommandé)

### Étape 1 : Créer un Personal Access Token

1. Allez sur https://github.com/settings/tokens
2. Cliquez sur **"Generate new token"** → **"Generate new token (classic)"**
3. Donnez-lui un nom (ex: "Groupe 405 Panel")
4. Sélectionnez les permissions :
   - ✅ **`repo`** (accès complet aux repositories)
5. Cliquez sur **"Generate token"**
6. **COPIEZ LE TOKEN IMMÉDIATEMENT** (il ne sera plus visible après)

### Étape 2 : Exécuter le script

```powershell
.\scripts\setup-github.ps1
```

Le script vous demandera :
- Votre nom d'utilisateur GitHub
- Votre email GitHub
- Votre Personal Access Token

Il créera automatiquement le repository et poussera le code.

## Méthode 2 : Configuration manuelle

### Étape 1 : Créer le repository sur GitHub

1. Allez sur https://github.com/new
2. Nom du repository : `groupe-405-panel` (ou un autre nom)
3. Description : "Dashboard de gestion clients Supabase - Groupe 405 Inc"
4. Choisissez Public ou Private
5. **Ne cochez PAS** "Initialize with README" (le projet existe déjà)
6. Cliquez sur **"Create repository"**

### Étape 2 : Configurer Git

```powershell
# Configurer votre identité Git
git config user.name "Votre Nom"
git config user.email "votre.email@example.com"

# Ou globalement pour tous vos projets
git config --global user.name "Votre Nom"
git config --global user.email "votre.email@example.com"
```

### Étape 3 : Créer un Personal Access Token

1. Allez sur https://github.com/settings/tokens
2. Cliquez sur **"Generate new token"** → **"Generate new token (classic)"**
3. Donnez-lui un nom
4. Sélectionnez la permission **`repo`**
5. Cliquez sur **"Generate token"**
6. **COPIEZ LE TOKEN**

### Étape 4 : Ajouter le remote et pousser

```powershell
# Ajouter le remote (remplacez USERNAME et TOKEN)
git remote add origin https://TOKEN@github.com/USERNAME/groupe-405-panel.git

# Ou avec votre nom d'utilisateur et token
git remote add origin https://USERNAME:TOKEN@github.com/USERNAME/groupe-405-panel.git

# Faire le commit initial
git add .
git commit -m "Initial commit: Groupe 405 Panel"

# Pousser vers GitHub
git push -u origin main
# Si main n'existe pas, essayez:
git push -u origin master
```

## Méthode 3 : Utiliser GitHub CLI (gh)

Si vous avez GitHub CLI installé :

```powershell
# Installer GitHub CLI (si pas déjà installé)
# winget install GitHub.cli

# Se connecter
gh auth login

# Créer le repository et pousser
gh repo create groupe-405-panel --public --source=. --remote=origin --push
```

## Stocker le token de manière sécurisée

Pour éviter de retaper le token à chaque fois, vous pouvez utiliser Git Credential Manager :

```powershell
# Le token sera stocké de manière sécurisée
git config --global credential.helper manager-core
```

Ou utiliser un fichier `.git-credentials` (moins sécurisé) :

```powershell
# Créer le fichier (remplacez USERNAME et TOKEN)
echo "https://USERNAME:TOKEN@github.com" | Out-File -FilePath "$env:USERPROFILE\.git-credentials" -Encoding utf8
git config --global credential.helper store
```

## Vérification

Après le push, vérifiez que tout est bien sur GitHub :

1. Allez sur https://github.com/VOTRE_USERNAME/groupe-405-panel
2. Vérifiez que tous les fichiers sont présents
3. Vérifiez que le `.env.local` n'est **PAS** présent (il ne doit jamais être commité)

## Dépannage

### Erreur : "remote origin already exists"
```powershell
# Supprimer l'ancien remote
git remote remove origin

# Ajouter le nouveau
git remote add origin https://TOKEN@github.com/USERNAME/groupe-405-panel.git
```

### Erreur : "Authentication failed"
- Vérifiez que votre token est correct
- Vérifiez que le token a la permission `repo`
- Le token peut avoir expiré, créez-en un nouveau

### Erreur : "Repository not found"
- Vérifiez que le repository existe sur GitHub
- Vérifiez que vous avez les permissions d'écriture
- Vérifiez le nom du repository dans l'URL

## Sécurité

⚠️ **IMPORTANT** :
- Ne commitez **JAMAIS** votre `.env.local` ou vos tokens
- Ne partagez **JAMAIS** votre Personal Access Token
- Si vous avez accidentellement commité des secrets, changez-les immédiatement
- Utilisez des tokens avec des permissions minimales nécessaires
