# Script pour restaurer une base de données depuis un fichier SQL (pg_dump)
# Usage: .\scripts\restore-database.ps1 -InputFile "database-backup.sql"

param(
    [Parameter(Mandatory=$true)]
    [string]$InputFile,
    [string]$TargetHost = $env:SUPABASE_DB_HOST,
    [string]$TargetPort = $env:SUPABASE_DB_PORT,
    [string]$TargetDatabase = $env:SUPABASE_DB_NAME,
    [string]$TargetUser = $env:SUPABASE_DB_USER,
    [string]$TargetPassword = $env:SUPABASE_DB_PASSWORD,
    [string]$ConnectionString = $env:SUPABASE_DB_CONNECTION_STRING
)

# Vérifier si le fichier existe (validation précoce)
if (-not $InputFile -or $InputFile.Length -eq 0) {
    Write-Host "[ERREUR] Le parametre InputFile est requis" -ForegroundColor Red
    Write-Host "Usage: .\scripts\restore-database.ps1 -InputFile `"chemin\vers\fichier.sql`"" -ForegroundColor Yellow
    exit 1
}

Write-Host "[RESTAURATION] Base de donnees depuis: $InputFile" -ForegroundColor Cyan
Write-Host ("-" * 80)

# Vérifier si le fichier existe
if (-not (Test-Path $InputFile)) {
    Write-Host "[ERREUR] Le fichier '$InputFile' n'existe pas" -ForegroundColor Red
    Write-Host "Verifiez le chemin du fichier et reessayez." -ForegroundColor Yellow
    exit 1
}

# Vérifier si psql est installé
$psqlPath = Get-Command psql -ErrorAction SilentlyContinue
if (-not $psqlPath) {
    Write-Host "[ERREUR] psql n'est pas installe ou n'est pas dans le PATH" -ForegroundColor Red
    Write-Host "   Installez PostgreSQL pour obtenir psql" -ForegroundColor Yellow
    exit 1
}

Write-Host "[OK] psql trouve: $($psqlPath.Source)" -ForegroundColor Green

$fileSize = (Get-Item $InputFile).Length / 1MB
Write-Host "[INFO] Fichier: $InputFile ($([math]::Round($fileSize, 2)) MB)" -ForegroundColor Gray

# Si une connection string est fournie, l'utiliser directement
if ($ConnectionString) {
    Write-Host "[INFO] Utilisation de la connection string fournie" -ForegroundColor Cyan
    
    Write-Host ""
    Write-Host "[ATTENTION] Cette operation va restaurer le fichier SQL dans la base de donnees" -ForegroundColor Yellow
    $confirm = Read-Host "   Voulez-vous continuer? (oui/non)"
    
    if ($confirm -ne "oui" -and $confirm -ne "o" -and $confirm -ne "yes" -and $confirm -ne "y") {
        Write-Host "[ANNULATION] Operation annulee" -ForegroundColor Red
        exit 0
    }
    
    Write-Host ""
    Write-Host "[RESTAURATION] Restauration en cours..." -ForegroundColor Cyan
    
    try {
        & psql "$ConnectionString" -f "$InputFile"
        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Host "[SUCCES] Base de donnees restauree avec succes !" -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host "[ERREUR] Erreur lors de la restauration (code: $LASTEXITCODE)" -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host ""
        Write-Host "[ERREUR] $_" -ForegroundColor Red
        exit 1
    }
} else {
    # Utiliser les paramètres individuels
    if (-not $TargetHost -or -not $TargetDatabase -or -not $TargetUser -or -not $TargetPassword) {
        Write-Host "[ERREUR] Parametres de connexion manquants" -ForegroundColor Red
        Write-Host "`nOptions:" -ForegroundColor Yellow
        Write-Host "1. Utiliser une connection string:" -ForegroundColor White
        Write-Host "   `$env:SUPABASE_DB_CONNECTION_STRING = 'postgresql://postgres:Maniju16052002&@db.zdicqtupwckhvxhlkiuf.supabase.co:5432/postgres'" -ForegroundColor Gray
        Write-Host "`n2. Utiliser des paramètres individuels:" -ForegroundColor White
        Write-Host "   `$env:SUPABASE_DB_HOST = 'db.zdicqtupwckhvxhlkiuf.supabase.co'" -ForegroundColor Gray
        Write-Host "   `$env:SUPABASE_DB_PORT = '5432'" -ForegroundColor Gray
        Write-Host "   `$env:SUPABASE_DB_NAME = 'postgres'" -ForegroundColor Gray
        Write-Host "   `$env:SUPABASE_DB_USER = 'postgres'" -ForegroundColor Gray
        Write-Host "   `$env:SUPABASE_DB_PASSWORD = 'Maniju16052002&'" -ForegroundColor Gray
        exit 1
    }
    
    $TargetPort = if ($TargetPort) { $TargetPort } else { "5432" }
    
    Write-Host "[INFO] Connexion a: ${TargetHost}:${TargetPort}/${TargetDatabase}" -ForegroundColor Cyan
    Write-Host "       Utilisateur: $TargetUser" -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "[ATTENTION] Cette operation va restaurer le fichier SQL dans la base de donnees" -ForegroundColor Yellow
    $confirm = Read-Host "   Voulez-vous continuer? (oui/non)"
    
    if ($confirm -ne "oui" -and $confirm -ne "o" -and $confirm -ne "yes" -and $confirm -ne "y") {
        Write-Host "[ANNULATION] Operation annulee" -ForegroundColor Red
        exit 0
    }
    
    Write-Host ""
    Write-Host "[RESTAURATION] Restauration en cours..." -ForegroundColor Cyan
    
    # Définir la variable d'environnement pour le mot de passe
    $env:PGPASSWORD = $TargetPassword
    
    try {
        & psql -h $TargetHost -p $TargetPort -U $TargetUser -d $TargetDatabase -f "$InputFile"
        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Host "[SUCCES] Base de donnees restauree avec succes !" -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host "[ERREUR] Erreur lors de la restauration (code: $LASTEXITCODE)" -ForegroundColor Red
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
}
