# Script PowerShell pour tester l'exécution de function.sql
# Usage: .\scripts\test-function-sql.ps1

# Configuration - MODIFIEZ CES VALEURS
$PROJECT_REF = "medpkzuculodumzlmbrk"
$DB_PASSWORD = "6lOMIvti9cXPHbs0"

# Connection string avec pooler (port 6543)
$connectionString = "postgresql://postgres:$([System.Web.HttpUtility]::UrlEncode($DB_PASSWORD))@db.$PROJECT_REF.supabase.co:6543/postgres"

# Chemin du fichier SQL
$sqlFile = Join-Path $PSScriptRoot "..\templates\myfidelity\function.sql"

Write-Host "🔌 Test d'exécution de function.sql" -ForegroundColor Cyan
Write-Host ""

# Vérifier que le fichier existe
if (-not (Test-Path $sqlFile)) {
    Write-Host "❌ Erreur: Le fichier $sqlFile n'existe pas" -ForegroundColor Red
    exit 1
}

Write-Host "📖 Fichier trouvé: $sqlFile" -ForegroundColor Green
$fileSize = (Get-Item $sqlFile).Length / 1MB
Write-Host "📄 Taille: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Gray
Write-Host ""

# Vérifier que psql est disponible
$psqlPath = $null
$commonPaths = @(
    "C:\Program Files\PostgreSQL\18\bin\psql.exe",
    "C:\Program Files\PostgreSQL\17\bin\psql.exe",
    "C:\Program Files\PostgreSQL\16\bin\psql.exe"
)

foreach ($path in $commonPaths) {
    if (Test-Path $path) {
        $psqlPath = $path
        break
    }
}

if (-not $psqlPath) {
    # Chercher dans les dossiers PostgreSQL
    $pgDirs = @("C:\Program Files\PostgreSQL", "C:\Program Files (x86)\PostgreSQL")
    foreach ($pgDir in $pgDirs) {
        if (Test-Path $pgDir) {
            $versions = Get-ChildItem $pgDir -Directory | Sort-Object Name -Descending
            foreach ($version in $versions) {
                $testPath = Join-Path $version.FullName "bin\psql.exe"
                if (Test-Path $testPath) {
                    $psqlPath = $testPath
                    break
                }
            }
            if ($psqlPath) { break }
        }
    }
}

if (-not $psqlPath) {
    Write-Host "❌ Erreur: psql.exe n'a pas été trouvé" -ForegroundColor Red
    Write-Host "   Installez PostgreSQL ou ajoutez psql au PATH" -ForegroundColor Yellow
    exit 1
}

Write-Host "✅ psql trouvé: $psqlPath" -ForegroundColor Green
Write-Host ""

# Exécuter le SQL
Write-Host "⚙️  Exécution du SQL (cela peut prendre plusieurs minutes)..." -ForegroundColor Yellow
Write-Host ""

$env:PGPASSWORD = $DB_PASSWORD
$startTime = Get-Date

try {
    $output = & $psqlPath -d $connectionString -f $sqlFile 2>&1
    
    $duration = ((Get-Date) - $startTime).TotalSeconds
    
    # Séparer stdout et stderr
    $stdout = $output | Where-Object { $_ -is [string] -and $_ -notmatch "ERROR|FATAL" }
    $stderr = $output | Where-Object { $_ -is [string] -and ($_ -match "ERROR|FATAL") }
    
    if ($LASTEXITCODE -eq 0 -or -not $stderr) {
        Write-Host "✅ Exécution terminée en $([math]::Round($duration, 2)) secondes" -ForegroundColor Green
        Write-Host ""
        
        # Afficher les warnings (normaux)
        $warnings = $output | Where-Object { $_ -match "WARNING|NOTICE" }
        if ($warnings) {
            Write-Host "⚠️  Avertissements (normaux):" -ForegroundColor Yellow
            $warnings | Select-Object -First 5 | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
            if ($warnings.Count -gt 5) {
                Write-Host "   ... et $($warnings.Count - 5) autre(s)" -ForegroundColor Gray
            }
            Write-Host ""
        }
        
        Write-Host "✅ Le fichier function.sql a été exécuté avec succès!" -ForegroundColor Green
        Write-Host ""
        Write-Host "💡 Vérifiez maintenant les fonctions dans Supabase:" -ForegroundColor Cyan
        Write-Host "   - Allez dans SQL Editor" -ForegroundColor Gray
        Write-Host "   - Exécutez: SELECT schemaname, COUNT(*) FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE n.nspname IN ('audit', 'mv', 'postgre_rpc', 'private', 'public') GROUP BY schemaname;" -ForegroundColor Gray
    } else {
        Write-Host "❌ Erreurs détectées:" -ForegroundColor Red
        $stderr | ForEach-Object { Write-Host "   $_" -ForegroundColor Red }
        Write-Host ""
        Write-Host "💡 Conseil: Utilisez le script Node.js (test-function-sql.js) qui gère mieux les fonctions complexes" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Host "❌ Erreur lors de l'exécution: $_" -ForegroundColor Red
    exit 1
} finally {
    Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
}
