# Exécute templates/myfidelity/function.sql avec le VRAI psql.exe (aucun fallback).
# Usage (PowerShell):
#   .\scripts\run-function-sql-psql.ps1 -ProjectRef "xxxxx" -DbPassword "yyyyy"
#
# Optionnel:
#   -SqlFile "C:\...\function.sql"
#   -PsqlPath "C:\Program Files\PostgreSQL\18\bin\psql.exe"
#   -Port 6543
#   -Database "postgres"
#
# Notes:
# - Utilise le POOLER Supabase (aws-0-ca-central-1.pooler.supabase.com) avec IPv4
# - Utilise ON_ERROR_STOP=1 => stoppe au premier ERROR
# - N'UTILISE PAS npx (qui peut appeler un package npm "psql")

param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectRef,

  [Parameter(Mandatory = $true)]
  [string]$DbPassword,

  [string]$SqlFile = "",

  [string]$PsqlPath = "",

  [int]$Port = 6543,

  [string]$Database = "postgres"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-PsqlPath {
  param([string]$ExplicitPath)

  if ($ExplicitPath -and (Test-Path $ExplicitPath)) {
    return (Resolve-Path $ExplicitPath).Path
  }

  # 1) si psql est deja dans le PATH
  $cmd = Get-Command psql -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source) {
    return $cmd.Source
  }

  # 2) chemins communs
  $common = @(
    "C:\Program Files\PostgreSQL\18\bin\psql.exe",
    "C:\Program Files\PostgreSQL\17\bin\psql.exe",
    "C:\Program Files\PostgreSQL\16\bin\psql.exe",
    "C:\Program Files\PostgreSQL\15\bin\psql.exe",
    "C:\Program Files\PostgreSQL\14\bin\psql.exe",
    "C:\Program Files (x86)\PostgreSQL\18\bin\psql.exe",
    "C:\Program Files (x86)\PostgreSQL\17\bin\psql.exe",
    "C:\Program Files (x86)\PostgreSQL\16\bin\psql.exe"
  )

  foreach ($p in $common) {
    if (Test-Path $p) { return $p }
  }

  # 3) scan dossiers d'install PostgreSQL
  $bases = @("C:\Program Files\PostgreSQL", "C:\Program Files (x86)\PostgreSQL")
  foreach ($base in $bases) {
    if (-not (Test-Path $base)) { continue }
    Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
      Sort-Object Name -Descending |
      ForEach-Object {
        $candidate = Join-Path $_.FullName "bin\psql.exe"
        if (Test-Path $candidate) { throw [System.Exception]::new($candidate) }
      }
  }

  return $null
}

try {
  # SqlFile defaut: templates/myfidelity/function.sql depuis la racine du repo
  if (-not $SqlFile) {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $SqlFile = Join-Path $repoRoot "templates\myfidelity\function.sql"
  }

  if (-not (Test-Path $SqlFile)) {
    throw "SQL file introuvable: $SqlFile"
  }

  # Utiliser le POOLER Supabase (IPv4) au lieu du direct (IPv6 only)
  # Format: postgres.[PROJECT_REF] comme username @ aws-0-ca-central-1.pooler.supabase.com
  $PoolerHost = "aws-0-ca-central-1.pooler.supabase.com"
  $PoolerUser = "postgres.$ProjectRef"

  $resolvedPsql = $null
  try {
    $resolvedPsql = Resolve-PsqlPath -ExplicitPath $PsqlPath
  } catch {
    # Trick: on a "throw candidate" pour break le pipeline
    $resolvedPsql = $_.Exception.Message
  }

  if (-not $resolvedPsql) {
    throw "psql.exe introuvable. Donne -PsqlPath ou installe PostgreSQL."
  }

  Write-Host ""
  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host "  Execution de function.sql via psql"    -ForegroundColor Cyan
  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "psql  : $resolvedPsql" -ForegroundColor Green
  Write-Host "SQL   : $(Resolve-Path $SqlFile)" -ForegroundColor Green
  Write-Host "Host  : $PoolerHost" -ForegroundColor Gray
  Write-Host "Port  : $Port" -ForegroundColor Gray
  Write-Host "User  : $PoolerUser" -ForegroundColor Gray
  Write-Host "DB    : $Database" -ForegroundColor Gray
  Write-Host ""

  # Connection string via pooler (IPv4)
  $encodedPwd = [System.Uri]::EscapeDataString($DbPassword)
  $conn = "postgresql://${PoolerUser}:${encodedPwd}@${PoolerHost}:${Port}/${Database}"

  # PGPASSWORD (evite le mot de passe dans les logs)
  $env:PGPASSWORD = $DbPassword

  Write-Host "Connexion en cours..." -ForegroundColor Yellow
  $startTime = Get-Date

  # Stop au premier ERROR
  & $resolvedPsql -v ON_ERROR_STOP=1 -d $conn -f $SqlFile
  $exitCode = $LASTEXITCODE

  $duration = ((Get-Date) - $startTime).TotalSeconds

  if ($exitCode -ne 0) {
    Write-Host ""
    Write-Host "psql a termine avec le code $exitCode apres $([math]::Round($duration,1))s" -ForegroundColor Red
    throw "psql a termine avec un code $exitCode (echec)."
  }

  Write-Host ""
  Write-Host "========================================" -ForegroundColor Green
  Write-Host "  Termine sans erreur ($([math]::Round($duration,1))s)" -ForegroundColor Green
  Write-Host "========================================" -ForegroundColor Green
} finally {
  Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
}
