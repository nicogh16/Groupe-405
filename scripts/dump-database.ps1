# Script pour faire un dump complet de la base de données Supabase
# Usage: .\scripts\dump-database.ps1

param(
    [string]$ConnectionString = $env:SUPABASE_DB_CONNECTION_STRING,
    [string]$OutputFile = "full_dump-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').sql"
)

# Connection string par défaut si non fournie
if (-not $ConnectionString) {
    $ConnectionString = "postgresql://postgres:I954634osECksaLV@db.nbtzgyvwphbrhadlwdqf.supabase.co:5432/postgres"
}

Write-Host "[DUMP] Export complet de la base de donnees" -ForegroundColor Cyan
Write-Host ("-" * 80)
Write-Host "Source: db.nbtzgyvwphbrhadlwdqf.supabase.co" -ForegroundColor Gray
Write-Host "Fichier de sortie: $OutputFile" -ForegroundColor Gray
Write-Host ""

# Vérifier si pg_dump est installé
$pgDumpPath = Get-Command pg_dump -ErrorAction SilentlyContinue
if (-not $pgDumpPath) {
    # Chercher dans les emplacements standards PostgreSQL
    $pgPaths = @(
        "C:\Program Files\PostgreSQL\*\bin\pg_dump.exe",
        "C:\Program Files (x86)\PostgreSQL\*\bin\pg_dump.exe"
    )
    $found = $false
    foreach ($path in $pgPaths) {
        $files = Get-ChildItem -Path $path -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        if ($files) {
            $pgDumpPath = $files[0]
            $found = $true
            break
        }
    }
    if (-not $found) {
        Write-Host "[ERREUR] pg_dump n'est pas installe ou n'est pas dans le PATH" -ForegroundColor Red
        Write-Host "   Installez PostgreSQL pour obtenir pg_dump" -ForegroundColor Yellow
        Write-Host "   Telechargement: https://www.postgresql.org/download/windows/" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "[OK] pg_dump trouve: $($pgDumpPath.Source)" -ForegroundColor Green
Write-Host ""

# Construire la commande pg_dump
Write-Host "[EXECUTION] Export en cours..." -ForegroundColor Cyan
Write-Host "           Cela peut prendre plusieurs minutes selon la taille de la base..." -ForegroundColor Gray
Write-Host ""

try {
    # Utiliser pg_dump avec la connection string
    # Format: pg_dump "postgresql://user:password@host:port/database" -f output.sql
    if ($pgDumpPath -is [System.IO.FileInfo]) {
        # Utiliser le chemin complet si trouvé manuellement
        & $pgDumpPath.FullName "$ConnectionString" `
            --verbose `
            --no-owner `
            --no-acl `
            --file="$OutputFile"
    } else {
        # Utiliser la commande normale si dans le PATH
        & pg_dump "$ConnectionString" `
            --verbose `
            --no-owner `
            --no-acl `
            --file="$OutputFile"
    }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "[SUCCES] Dump cree avec succes!" -ForegroundColor Green
        Write-Host "        Fichier: $OutputFile" -ForegroundColor Cyan
        
        if (Test-Path $OutputFile) {
            $fileSize = (Get-Item $OutputFile).Length / 1MB
            Write-Host "        Taille: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Gray
        }
        
        Write-Host ""
        Write-Host "[INFO] Pour restaurer ce dump:" -ForegroundColor Yellow
        Write-Host "       psql `"$ConnectionString`" -f `"$OutputFile`"" -ForegroundColor Gray
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
