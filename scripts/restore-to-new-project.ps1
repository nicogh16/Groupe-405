# Script pour restaurer un dump prepare dans un nouveau projet Supabase
# Usage: .\scripts\restore-to-new-project.ps1 -ConnectionString "postgresql://postgres:PASSWORD@db.PROJECT.supabase.co:5432/postgres"

param(
    [Parameter(Mandatory=$true)]
    [string]$ConnectionString,
    [string]$DumpFile = "supabase_new_project.sql"
)

Write-Host "[RESTAURATION] Restauration dans un nouveau projet Supabase" -ForegroundColor Cyan
Write-Host ("-" * 80)

# Verifier si le fichier existe
if (-not (Test-Path $DumpFile)) {
    Write-Host "[ERREUR] Le fichier '$DumpFile' n'existe pas" -ForegroundColor Red
    Write-Host "        Executez d'abord: .\scripts\prepare-dump-for-new-project.ps1" -ForegroundColor Yellow
    exit 1
}

# Verifier si psql est installe
$psqlPath = Get-Command psql -ErrorAction SilentlyContinue
if (-not $psqlPath) {
    # Chercher dans les emplacements standards PostgreSQL
    $pgPaths = @(
        "C:\Program Files\PostgreSQL\*\bin\psql.exe",
        "C:\Program Files (x86)\PostgreSQL\*\bin\psql.exe"
    )
    $found = $false
    foreach ($path in $pgPaths) {
        $files = Get-ChildItem -Path $path -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        if ($files) {
            $psqlPath = $files[0]
            $found = $true
            break
        }
    }
    if (-not $found) {
        Write-Host "[ERREUR] psql n'est pas installe ou n'est pas dans le PATH" -ForegroundColor Red
        Write-Host "   Installez PostgreSQL pour obtenir psql" -ForegroundColor Yellow
        Write-Host "   Telechargement: https://www.postgresql.org/download/windows/" -ForegroundColor Yellow
        exit 1
    }
}

if ($psqlPath -is [System.IO.FileInfo]) {
    $psqlExe = $psqlPath.FullName
} else {
    $psqlExe = "psql"
}

Write-Host "[OK] psql trouve: $psqlExe" -ForegroundColor Green

$fileSize = (Get-Item $DumpFile).Length / 1MB
Write-Host "[INFO] Fichier: $DumpFile ($([math]::Round($fileSize, 2)) MB)" -ForegroundColor Gray

# Extraire les infos de la connection string pour affichage
if ($ConnectionString -match 'postgresql://([^:]+):([^@]+)@([^:]+):(\d+)/(.+)') {
    $user = $matches[1]
    $host = $matches[3]
    $port = $matches[4]
    $database = $matches[5]
    Write-Host "[INFO] Connexion a: ${host}:${port}/${database}" -ForegroundColor Cyan
    Write-Host "       Utilisateur: $user" -ForegroundColor Gray
} else {
    Write-Host "[INFO] Connection string fournie" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "[ATTENTION] Cette operation va restaurer le dump dans votre nouveau projet Supabase" -ForegroundColor Yellow
Write-Host "           Assurez-vous que:" -ForegroundColor Yellow
Write-Host "           1. Vous avez cree un nouveau projet Supabase" -ForegroundColor White
Write-Host "           2. Le projet est vide ou vous acceptez d'ecraser les donnees existantes" -ForegroundColor White
Write-Host ""
$confirm = Read-Host "   Voulez-vous continuer? (oui/non)"

if ($confirm -ne "oui" -and $confirm -ne "o" -and $confirm -ne "yes" -and $confirm -ne "y") {
    Write-Host "[ANNULATION] Operation annulee" -ForegroundColor Red
    exit 0
}

Write-Host ""
Write-Host "[RESTAURATION] Restauration en cours..." -ForegroundColor Cyan
Write-Host "              Cela peut prendre plusieurs minutes selon la taille du dump..." -ForegroundColor Gray

try {
    # Extraire le mot de passe de la connection string pour PGPASSWORD
    if ($ConnectionString -match 'postgresql://([^:]+):([^@]+)@') {
        $env:PGPASSWORD = $matches[2]
    }
    
    # Executer psql
    & $psqlExe "$ConnectionString" -f "$DumpFile" 2>&1 | Tee-Object -Variable output
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "[SUCCES] Base de donnees restauree avec succes !" -ForegroundColor Green
        Write-Host ""
        Write-Host "[PROCHAINES ETAPES]" -ForegroundColor Yellow
        Write-Host "1. Verifiez les tables dans le dashboard Supabase" -ForegroundColor White
        Write-Host "2. Configurez les politiques RLS si necessaire" -ForegroundColor White
        Write-Host "3. Mettez a jour votre fichier .env.local avec les nouvelles cles API" -ForegroundColor White
        Write-Host "4. Testez votre application" -ForegroundColor White
    } else {
        Write-Host ""
        Write-Host "[ERREUR] Erreur lors de la restauration (code: $LASTEXITCODE)" -ForegroundColor Red
        Write-Host ""
        Write-Host "Verifiez les erreurs ci-dessus et:" -ForegroundColor Yellow
        Write-Host "1. Assurez-vous que la connection string est correcte" -ForegroundColor White
        Write-Host "2. Verifiez que le projet Supabase est accessible" -ForegroundColor White
        Write-Host "3. Certaines erreurs peuvent etre normales (tables deja existantes, etc.)" -ForegroundColor White
        exit 1
    }
} catch {
    Write-Host ""
    Write-Host "[ERREUR] $_" -ForegroundColor Red
    exit 1
} finally {
    # Nettoyer le mot de passe de l'environnement
    Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
}
