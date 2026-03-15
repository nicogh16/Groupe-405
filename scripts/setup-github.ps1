# Script pour configurer Git avec GitHub
# Usage: .\scripts\setup-github.ps1

param(
    [string]$GitHubUsername = $env:GITHUB_USERNAME,
    [string]$GitHubEmail = $env:GITHUB_EMAIL,
    [string]$GitHubToken = $env:GITHUB_TOKEN,
    [string]$RepoName = "groupe-405-panel"
)

Write-Host "[CONFIGURATION] Configuration Git pour GitHub" -ForegroundColor Cyan
Write-Host ("-" * 80)

# Demander les informations si non fournies
if (-not $GitHubUsername) {
    $GitHubUsername = Read-Host "Entrez votre nom d'utilisateur GitHub"
}

if (-not $GitHubEmail) {
    $GitHubEmail = Read-Host "Entrez votre email GitHub"
}

if (-not $GitHubToken) {
    Write-Host ""
    Write-Host "[INFO] GitHub n'utilise plus les mots de passe pour Git" -ForegroundColor Yellow
    Write-Host "       Vous devez creer un Personal Access Token (PAT)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Pour creer un token:" -ForegroundColor Cyan
    Write-Host "1. Allez sur https://github.com/settings/tokens" -ForegroundColor White
    Write-Host "2. Cliquez sur 'Generate new token' -> 'Generate new token (classic)'" -ForegroundColor White
    Write-Host "3. Donnez-lui un nom (ex: 'Groupe 405 Panel')" -ForegroundColor White
    Write-Host "4. Selectionnez les permissions: repo (acces complet aux repositories)" -ForegroundColor White
    Write-Host "5. Cliquez sur 'Generate token'" -ForegroundColor White
    Write-Host "6. COPIEZ LE TOKEN IMMEDIATEMENT (il ne sera plus visible)" -ForegroundColor Yellow
    Write-Host ""
    $GitHubToken = Read-Host "Collez votre Personal Access Token ici" -AsSecureString
    $GitHubToken = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($GitHubToken)
    )
}

# Configurer Git
Write-Host ""
Write-Host "[CONFIGURATION] Configuration de Git..." -ForegroundColor Cyan
git config user.name "$GitHubUsername"
git config user.email "$GitHubEmail"

Write-Host "[OK] Git configure avec:" -ForegroundColor Green
Write-Host "     Nom: $GitHubUsername" -ForegroundColor Gray
Write-Host "     Email: $GitHubEmail" -ForegroundColor Gray

# Vérifier si le repo existe déjà
Write-Host ""
Write-Host "[VERIFICATION] Verification du repository GitHub..." -ForegroundColor Cyan

$repoExists = $false
try {
    $response = Invoke-RestMethod -Uri "https://api.github.com/repos/$GitHubUsername/$RepoName" `
        -Headers @{Authorization = "token $GitHubToken"} `
        -ErrorAction SilentlyContinue
    $repoExists = $true
    Write-Host "[INFO] Le repository existe deja sur GitHub" -ForegroundColor Yellow
} catch {
    Write-Host "[INFO] Le repository n'existe pas encore, creation en cours..." -ForegroundColor Cyan
    
    # Créer le repository
    $body = @{
        name = $RepoName
        description = "Dashboard de gestion clients Supabase - Groupe 405 Inc"
        private = $false
    } | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethod -Uri "https://api.github.com/user/repos" `
            -Method Post `
            -Headers @{
                Authorization = "token $GitHubToken"
                "Content-Type" = "application/json"
            } `
            -Body $body
        
        Write-Host "[SUCCES] Repository cree avec succes!" -ForegroundColor Green
        Write-Host "        URL: $($response.html_url)" -ForegroundColor Cyan
        $repoExists = $true
    } catch {
        Write-Host "[ERREUR] Impossible de creer le repository: $_" -ForegroundColor Red
        Write-Host "         Vous pouvez le creer manuellement sur https://github.com/new" -ForegroundColor Yellow
        exit 1
    }
}

# Ajouter le remote
Write-Host ""
Write-Host "[CONFIGURATION] Configuration du remote GitHub..." -ForegroundColor Cyan

$remoteUrl = "https://${GitHubToken}@github.com/${GitHubUsername}/${RepoName}.git"

# Vérifier si le remote existe déjà
$existingRemote = git remote get-url origin -ErrorAction SilentlyContinue
if ($existingRemote) {
    Write-Host "[INFO] Remote 'origin' existe deja: $existingRemote" -ForegroundColor Yellow
    $update = Read-Host "Voulez-vous le mettre a jour? (oui/non)"
    if ($update -eq "oui" -or $update -eq "o") {
        git remote set-url origin $remoteUrl
        Write-Host "[OK] Remote mis a jour" -ForegroundColor Green
    }
} else {
    git remote add origin $remoteUrl
    Write-Host "[OK] Remote 'origin' ajoute" -ForegroundColor Green
}

# Faire le commit initial si nécessaire
Write-Host ""
Write-Host "[VERIFICATION] Verification des commits..." -ForegroundColor Cyan
$commitCount = (git rev-list --count HEAD 2>$null)
if ($commitCount -eq 0) {
    Write-Host "[INFO] Aucun commit trouve, creation du commit initial..." -ForegroundColor Yellow
    git add .
    git commit -m "Initial commit: Groupe 405 Panel - Dashboard de gestion clients Supabase"
    Write-Host "[OK] Commit initial cree" -ForegroundColor Green
}

# Pousser vers GitHub
Write-Host ""
Write-Host "[PUSH] Envoi vers GitHub..." -ForegroundColor Cyan
Write-Host "       Cela peut prendre quelques instants..." -ForegroundColor Gray

try {
    git push -u origin main 2>&1 | ForEach-Object {
        if ($_ -match "error|fatal") {
            Write-Host $_ -ForegroundColor Red
        } else {
            Write-Host $_
        }
    }
    
    # Si main n'existe pas, essayer master
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[INFO] Tentative avec la branche 'master'..." -ForegroundColor Yellow
        git push -u origin master 2>&1 | ForEach-Object {
            if ($_ -match "error|fatal") {
                Write-Host $_ -ForegroundColor Red
            } else {
                Write-Host $_
            }
        }
    }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "[SUCCES] Projet pousse vers GitHub avec succes!" -ForegroundColor Green
        Write-Host "        Repository: https://github.com/$GitHubUsername/$RepoName" -ForegroundColor Cyan
    } else {
        Write-Host ""
        Write-Host "[ERREUR] Erreur lors du push" -ForegroundColor Red
        Write-Host "         Verifiez vos permissions et votre token" -ForegroundColor Yellow
    }
} catch {
    Write-Host "[ERREUR] $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "[INFO] Pour les prochains pushes, utilisez simplement:" -ForegroundColor Yellow
Write-Host "       git push" -ForegroundColor Gray
