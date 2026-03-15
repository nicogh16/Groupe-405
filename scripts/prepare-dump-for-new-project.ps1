# Script pour preparer un dump SQL pour un nouveau projet Supabase
# Ce script nettoie le dump en retirant les elements specifiques a Supabase
# et garde uniquement les schemas utilisateur (public, private, audit, etc.)

param(
    [Parameter(Mandatory=$true)]
    [string]$InputFile = "full_dump.sql",
    [string]$OutputFile = "supabase_new_project.sql"
)

Write-Host "[PREPARATION] Preparation du dump pour un nouveau projet Supabase" -ForegroundColor Cyan
Write-Host ("-" * 80)

# Verifier si le fichier existe
if (-not (Test-Path $InputFile)) {
    Write-Host "[ERREUR] Le fichier '$InputFile' n'existe pas" -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Fichier source: $InputFile" -ForegroundColor Gray
Write-Host "[INFO] Fichier de sortie: $OutputFile" -ForegroundColor Gray

# Lire le contenu du fichier
$content = Get-Content $InputFile -Raw -Encoding UTF8

Write-Host "[TRAITEMENT] Nettoyage en cours..." -ForegroundColor Yellow

# 1. Retirer les lignes restrict/unrestrict (specifiques a Supabase)
$content = $content -replace '\\restrict[^\n]*\n', ''
$content = $content -replace '\\unrestrict[^\n]*\n', ''

# 2. Retirer les commentaires de TOC qui ne sont pas necessaires
# (On garde les commentaires utiles)

# 3. Ajouter un en-tete avec instructions
$header = @"
-- ============================================================================
-- DUMP SQL POUR NOUVEAU PROJET SUPABASE
-- ============================================================================
-- Ce fichier contient uniquement les schemas utilisateur:
--   - public (tables publiques)
--   - private (tables privees)
--   - audit (logs d'audit)
--   - mv (materialized views)
--   - dashboard_view, view (vues)
--
-- INSTRUCTIONS D'UTILISATION:
-- 1. Creez un nouveau projet Supabase
-- 2. Obtenez votre connection string depuis le dashboard Supabase
-- 3. Executez ce script avec psql ou utilisez le script restore-to-new-project.ps1
--
-- Exemple avec psql:
--   psql "postgresql://postgres:VOTRE_MOT_DE_PASSE@db.VOTRE_PROJET.supabase.co:5432/postgres" -f supabase_new_project.sql
--
-- ============================================================================
-- IMPORTANT: Les schemas Supabase (auth, storage, realtime, etc.) sont deja
--            crees automatiquement dans un nouveau projet. Ce dump contient
--            uniquement vos schemas personnalises et vos donnees.
-- ============================================================================

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

"@

# 4. Extraire uniquement les parties interessantes
# On garde tout sauf les schemas Supabase system (auth, storage, realtime, etc.)
# Mais on garde les extensions et les schemas utilisateur

# Creer le contenu final
$finalContent = $header + $content

# 5. Retirer les CREATE SCHEMA pour les schemas Supabase system
# (Ils existent deja dans un nouveau projet)
$schemasToRemove = @(
    'CREATE SCHEMA auth',
    'CREATE SCHEMA extensions',
    'CREATE SCHEMA graphql',
    'CREATE SCHEMA graphql_public',
    'CREATE SCHEMA pgbouncer',
    'CREATE SCHEMA realtime',
    'CREATE SCHEMA storage',
    'CREATE SCHEMA vault'
)

foreach ($schema in $schemasToRemove) {
    # Retirer les lignes CREATE SCHEMA et les commentaires associes
    $finalContent = $finalContent -replace "(?m)^--.*\n.*$schema.*\n.*CREATE SCHEMA.*\n", ''
    $finalContent = $finalContent -replace "(?m)^CREATE SCHEMA $($schema.Split(' ')[-1]);\n", ''
}

# 6. Retirer les CREATE EXTENSION pour les extensions Supabase system
# (Elles sont deja installees dans un nouveau projet)
$extensionsToRemove = @(
    'CREATE EXTENSION.*pg_graphql',
    'CREATE EXTENSION.*supabase_vault'
)

foreach ($ext in $extensionsToRemove) {
    $finalContent = $finalContent -replace "(?m)^--.*\n.*$ext.*\n.*CREATE EXTENSION.*\n", ''
    $finalContent = $finalContent -replace "(?m)^CREATE EXTENSION IF NOT EXISTS.*$ext.*\n", ''
}

# 7. Retirer les event triggers specifiques a Supabase
$finalContent = $finalContent -replace "(?m)^CREATE EVENT TRIGGER.*\n.*EXECUTE FUNCTION extensions\..*\n", ''

# 8. Retirer les publications Supabase
$finalContent = $finalContent -replace "(?m)^CREATE PUBLICATION supabase_realtime.*\n", ''

# 9. Ajouter un footer
$footer = @"

-- ============================================================================
-- FIN DU DUMP
-- ============================================================================
-- Le dump est termine. Verifiez qu'il n'y a pas d'erreurs ci-dessus.
-- 
-- Prochaines etapes:
-- 1. Verifiez que toutes les tables sont creees
-- 2. Configurez les politiques RLS (Row Level Security) si necessaire
-- 3. Testez votre application avec le nouveau projet
-- ============================================================================

"@

$finalContent = $finalContent + $footer

# Sauvegarder le fichier
try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText("$PWD\$OutputFile", $finalContent, $utf8NoBom)
    
    $inputSize = (Get-Item $InputFile).Length / 1MB
    $outputSize = (Get-Item $OutputFile).Length / 1MB
    
    Write-Host ""
    Write-Host "[SUCCES] Dump prepare avec succes !" -ForegroundColor Green
    Write-Host "        Fichier source: $InputFile ($([math]::Round($inputSize, 2)) MB)" -ForegroundColor Gray
    Write-Host "        Fichier cree: $OutputFile ($([math]::Round($outputSize, 2)) MB)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "[PROCHAINES ETAPES]" -ForegroundColor Yellow
    Write-Host "1. Creez un nouveau projet Supabase" -ForegroundColor White
    Write-Host "2. Obtenez votre connection string" -ForegroundColor White
    Write-Host "3. Executez: .\scripts\restore-to-new-project.ps1 -ConnectionString `"VOTRE_CONNECTION_STRING`"" -ForegroundColor Cyan
} catch {
    Write-Host ""
    Write-Host "[ERREUR] Impossible de creer le fichier: $_" -ForegroundColor Red
    exit 1
}
