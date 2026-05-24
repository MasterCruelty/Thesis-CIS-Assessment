# =============================================================================
# main_azure.ps1
# modulo main per i controlli CIS Azure.
#
# PREREQUISITI
#   1. Azure CLI installato: https://learn.microsoft.com/cli/azure/install-azure-cli
#   2. Sessione attiva:  az login
#      Subscription esistente e attiva:     az account set --subscription "<nome o id>"
#
# USO
#   .\main_azure.ps1
#   .\main_azure.ps1 -AuditOnly
#   .\main_azure.ps1 -Wc 0.5 -Wd 0.3 -Wr 0.2
# =============================================================================
[CmdletBinding(PositionalBinding=$false)]
param(
    [switch]$AuditOnly,
    [double]$Wc      = 0.4,
    [double]$Wd      = 0.3,
    [double]$Wr      = 0.3,
    [double]$Alpha   = 0.35,
    [double]$Beta    = 0.65,
    [string]$CsvPath = ""
)

$ErrorActionPreference = "Stop"

# Cartelle chiave
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition  # Analisi_Report\
$RootDir   = Split-Path -Parent $ScriptDir                          # Framework CIS\
$AzureDir  = Join-Path $RootDir "Azure"                             # Framework CIS\Vmware\

if (-not $CsvPath) { $CsvPath = Join-Path $RootDir "cis_azure.csv" }

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  CIS Azure Benchmark -- Audit Framework" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Carica il modulo utils condiviso (Framework CIS\module_utils.ps1)
# ---------------------------------------------------------------------------
$utilsPath = Join-Path $RootDir "module_utils.ps1"
if (-not (Test-Path $utilsPath)) {
    Write-Error "module_utils.ps1 non trovato in: $RootDir"
    exit 1
}
. $utilsPath

# ---------------------------------------------------------------------------
# Inizializza modulo Azure (carica CSV + verifica az login)
# ---------------------------------------------------------------------------
$initOk = Initialize-AzCIS -CsvPath $CsvPath
if (-not $initOk) { exit 1 }

# ---------------------------------------------------------------------------
# Moduli di audit (Framework CIS\Azure\)
# ---------------------------------------------------------------------------
$modules = @(
    "module_2_app_service.ps1",
    "module_6_management.ps1",
    "module_7_networking.ps1",
    "module_8_security.ps1",
    "module_20_virtual_machines.ps1"
)

foreach ($modFile in $modules) {
    $modPath = Join-Path $AzureDir $modFile
    if (Test-Path $modPath) {
        Write-Host ""
        Write-Host ">>> $modFile" -ForegroundColor Magenta
        & $modPath
    } else {
        Write-Warning "Modulo non trovato: $modPath"
    }
}

# ---------------------------------------------------------------------------
# Riepilogo
# ---------------------------------------------------------------------------
$tot = $Global:CISAuditResults.Count
$complianceCount = ($Global:CISAuditResults.Values | Where-Object { $_.Status -eq "COMPLIANT" }).Count
$complianceRate = if ($tot -gt 0) { [math]::Round($complianceCount / $tot * 100, 1) } else { 0 }

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  RIEPILOGO: $complianceCount/$tot COMPLIANT ($complianceRate`%)" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

if ($AuditOnly) {
    Write-Host "  [AuditOnly] Scoring e report saltati." -ForegroundColor DarkYellow
    exit 0
}

# ---------------------------------------------------------------------------
# Scoring e report (Framework CIS\Analisi_Report\)
# ---------------------------------------------------------------------------
$Global:Wc    = $Wc
$Global:Wd    = $Wd
$Global:Wr    = $Wr
$Global:Alpha = $Alpha
$Global:Beta  = $Beta

$scoringPath = Join-Path $ScriptDir "module_scoring.ps1"
if (Test-Path $scoringPath) {
    Write-Host ""
    Write-Host ">>> Calcolo scoring effort..." -ForegroundColor Magenta
    . $scoringPath -CsvPath $CsvPath -ExportCsv
} else {
    Write-Warning "module_scoring.ps1 non trovato in: $ScriptDir"
}

$reportPath = Join-Path $ScriptDir "module_report.ps1"
if (Test-Path $reportPath) {
    Write-Host ""
    Write-Host ">>> Generazione report HTML e CSV..." -ForegroundColor Magenta
    . $reportPath -CsvPath $CsvPath
} else {
    Write-Warning "module_report.ps1 non trovato in: $ScriptDir"
}

Write-Host ""
Write-Host "  Completato." -ForegroundColor Cyan
