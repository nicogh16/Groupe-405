# Script pour créer le repository GitHub et pousser le code
# Usage: .\scripts\create-and-push-repo.ps1

param(
    [Parameter(Mandatory=$true)]
    [string]$GitHubToken,
    [string]$RepoName = "groupe-405-panel",
    [string]$GitHubUsername = "nicogh16"
)

Write-Host "[CREATION] Creation du repository GitHub..." -ForegroundColor Cyan
Write-Host ("-" * 80)

# Créer le repository via l'API GitHub
$body = @{
    name = $RepoName
    description = "Dashboard de gestion clients Supabase - Groupe 405 Inc"
    private = $false
} | ConvertTo-Json

try {
    Write-Host "[API] Appel de l'API GitHub pour creer le repository..." -ForegroundColor Cyan
    $response = Invoke-RestMethod -Uri "https://api.github.com/user/repos" `
        -Method Post `
        -Headers @{
            Authorization = "token $GitHubToken"
            "Content-Type" = "application/json"
            "User-Agent" = "GitHub-Repo-Creator"
        } `
        -Body $body
    
    Write-Host "[SUCCES] Repository cree avec succes!" -ForegroundColor Green
    Write-Host "        Nom: $($response.name)" -ForegroundColor Gray
    Write-Host "        URL: $($response.html_url)" -ForegroundColor Cyan
    Write-Host ""
    
    # Ajouter le remote
    Write-Host "[CONFIGURATION] Configuration du remote..." -ForegroundColor Cyan
    $remoteUrl = "https://${GitHubToken}@github.com/${GitHubUsername}/${RepoName}.git"
    
    # Vérifier si le remote existe déjà
    $existingRemote = git remote get-url origin -ErrorAction SilentlyContinue
    if ($existingRemote) {
        Write-Host "[INFO] Remote 'origin' existe deja, mise a jour..." -ForegroundColor Yellow
        git remote set-url origin $remoteUrl
    } else {
        git remote add origin $remoteUrl
    }
    
    Write-Host "[OK] Remote configure" -ForegroundColor Green
    Write-Host ""
    
    # Pousser vers GitHub
    Write-Host "[PUSH] Envoi du code vers GitHub..." -ForegroundColor Cyan
    Write-Host "       Cela peut prendre quelques instants..." -ForegroundColor Gray
    Write-Host ""
    
    git push -u origin main 2>&1 | ForEach-Object {
        Write-Host $_
    }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "[SUCCES] Code pousse vers GitHub avec succes!" -ForegroundColor Green
        Write-Host "        Repository: $($response.html_url)" -ForegroundColor Cyan
    } else {
        Write-Host ""
        Write-Host "[ERREUR] Erreur lors du push (code: $LASTEXITCODE)" -ForegroundColor Red
        Write-Host "         Verifiez votre token et vos permissions" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host ""
    Write-Host "[ERREUR] Impossible de creer le repository: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Vous pouvez creer le repository manuellement:" -ForegroundColor Yellow
    Write-Host "1. Allez sur https://github.com/new" -ForegroundColor White
    Write-Host "2. Nom: $RepoName" -ForegroundColor White
    Write-Host "3. Cliquez sur 'Create repository'" -ForegroundColor White
    Write-Host ""
    Write-Host "Ensuite executez:" -ForegroundColor Yellow
    Write-Host "  git remote add origin https://${GitHubToken}@github.com/${GitHubUsername}/${RepoName}.git" -ForegroundColor Gray
    Write-Host "  git push -u origin main" -ForegroundColor Gray
    exit 1
}
