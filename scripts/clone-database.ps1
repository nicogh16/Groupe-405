# Script pour cloner une base de données Supabase avec pg_dump
# Usage: .\scripts\clone-database.ps1

param(
    [string]$SourceHost = $env:SUPABASE_DB_HOST,
    [string]$SourcePort = $env:SUPABASE_DB_PORT,
    [string]$SourceDatabase = $env:SUPABASE_DB_NAME,
    [string]$SourceUser = $env:SUPABASE_DB_USER,
    [string]$SourcePassword = $env:SUPABASE_DB_PASSWORD,
    [string]$OutputFile = "database-backup-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').sql",
    [switch]$DataOnly = $false,
    [switch]$SchemaOnly = $false,
    [string]$ConnectionString = $env:SUPABASE_DB_CONNECTION_STRING
)

Write-Host "[CLONAGE] Base de donnees Supabase avec pg_dump" -ForegroundColor Cyan
Write-Host ("-" * 80)

# Vérifier si pg_dump est installé
$pgDumpPath = Get-Command pg_dump -ErrorAction SilentlyContinue
if (-not $pgDumpPath) {
    Write-Host "[ERREUR] pg_dump n'est pas installe ou n'est pas dans le PATH" -ForegroundColor Red
    Write-Host "   Installez PostgreSQL pour obtenir pg_dump" -ForegroundColor Yellow
    Write-Host "   Telechargement: https://www.postgresql.org/download/windows/" -ForegroundColor Yellow
    exit 1
}

Write-Host "[OK] pg_dump trouve: $($pgDumpPath.Source)" -ForegroundColor Green

# Si une connection string est fournie, l'utiliser directement
if ($ConnectionString) {
    Write-Host "[INFO] Utilisation de la connection string fournie" -ForegroundColor Cyan
    
    # Construire la commande pg_dump
    $pgDumpArgs = @()
    
    if ($SchemaOnly) {
        $pgDumpArgs += "--schema-only"
        Write-Host "[MODE] Schema uniquement (pas de donnees)" -ForegroundColor Yellow
    } elseif ($DataOnly) {
        $pgDumpArgs += "--data-only"
        Write-Host "[MODE] Donnees uniquement (pas de schema)" -ForegroundColor Yellow
    } else {
        Write-Host "[MODE] Schema + Donnees (complet)" -ForegroundColor Green
    }
    
    $pgDumpArgs += "--verbose"
    $pgDumpArgs += "--no-owner"
    $pgDumpArgs += "--no-acl"
    $pgDumpArgs += "--file=`"$OutputFile`""
    $pgDumpArgs += "`"$ConnectionString`""
    
    Write-Host ""
    Write-Host "[EXECUTION] Execution de pg_dump..." -ForegroundColor Cyan
    Write-Host "           Fichier de sortie: $OutputFile" -ForegroundColor Gray
    
    try {
        & pg_dump $pgDumpArgs
        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Host "[SUCCES] Base de donnees clonee avec succes !" -ForegroundColor Green
            Write-Host "        Fichier: $OutputFile" -ForegroundColor Cyan
            $fileSize = (Get-Item $OutputFile).Length / 1MB
            Write-Host "        Taille: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Gray
        } else {
            Write-Host ""
            Write-Host "[ERREUR] Erreur lors de l'export (code: $LASTEXITCODE)" -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host ""
        Write-Host "[ERREUR] $_" -ForegroundColor Red
        exit 1
    }
} else {
    # Utiliser les paramètres individuels
    if (-not $SourceHost -or -not $SourceDatabase -or -not $SourceUser -or -not $SourcePassword) {
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
        Write-Host "`n3. Ou passer les paramètres directement:" -ForegroundColor White
        Write-Host "   .\scripts\clone-database.ps1 -ConnectionString 'postgresql://postgres:Maniju16052002&@db.zdicqtupwckhvxhlkiuf.supabase.co:5432/postgres'" -ForegroundColor Gray
        Write-Host "   .\scripts\clone-database.ps1 -SourceHost 'db.zdicqtupwckhvxhlkiuf.supabase.co' -SourceUser 'postgres' ..." -ForegroundColor Gray
        exit 1
    }
    
    $SourcePort = if ($SourcePort) { $SourcePort } else { "5432" }
    
    Write-Host "[INFO] Connexion a: ${SourceHost}:${SourcePort}/${SourceDatabase}" -ForegroundColor Cyan
    Write-Host "       Utilisateur: $SourceUser" -ForegroundColor Gray
    
    # Construire la commande pg_dump
    $pgDumpArgs = @()
    
    if ($SchemaOnly) {
        $pgDumpArgs += "--schema-only"
        Write-Host "[MODE] Schema uniquement (pas de donnees)" -ForegroundColor Yellow
    } elseif ($DataOnly) {
        $pgDumpArgs += "--data-only"
        Write-Host "[MODE] Donnees uniquement (pas de schema)" -ForegroundColor Yellow
    } else {
        Write-Host "[MODE] Schema + Donnees (complet)" -ForegroundColor Green
    }
    
    $pgDumpArgs += "--verbose"
    $pgDumpArgs += "--no-owner"
    $pgDumpArgs += "--no-acl"
    $pgDumpArgs += "--host=$SourceHost"
    $pgDumpArgs += "--port=$SourcePort"
    $pgDumpArgs += "--username=$SourceUser"
    $pgDumpArgs += "--dbname=$SourceDatabase"
    $pgDumpArgs += "--file=`"$OutputFile`""
    
    Write-Host ""
    Write-Host "[EXECUTION] Execution de pg_dump..." -ForegroundColor Cyan
    Write-Host "           Fichier de sortie: $OutputFile" -ForegroundColor Gray
    
    # Définir la variable d'environnement pour le mot de passe
    $env:PGPASSWORD = $SourcePassword
    
    try {
        & pg_dump $pgDumpArgs
        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Host "[SUCCES] Base de donnees clonee avec succes !" -ForegroundColor Green
            Write-Host "        Fichier: $OutputFile" -ForegroundColor Cyan
            $fileSize = (Get-Item $OutputFile).Length / 1MB
            Write-Host "        Taille: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Gray
        } else {
            Write-Host ""
            Write-Host "[ERREUR] Erreur lors de l'export (code: $LASTEXITCODE)" -ForegroundColor Red
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

Write-Host ""
Write-Host "[INFO] Pour restaurer cette sauvegarde:" -ForegroundColor Yellow
Write-Host "      .\scripts\restore-database.ps1 -InputFile `"$OutputFile`"" -ForegroundColor Gray
