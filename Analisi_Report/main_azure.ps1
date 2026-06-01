# =============================================================================
# CIS Microsoft Azure Benchmark
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
#   .\main_azure.ps1 -ExportLog 
#   .\main_azure.ps1 -Wc 0.5 -Wd 0.3 -Wr 0.2
# =============================================================================
[CmdletBinding(PositionalBinding=$false)]
param(
    [switch]$AuditOnly,
    [double]$Wc      = 0.4,
    [double]$Wd      = 0.3,
    [double]$Wr      = 0.3,
    [double]$Alpha   = 0.35,
    [double]$Beta    = 0.70,
    [string]$CsvPath = "",
    [string]$OutputDir = "", 
    [switch]$ExportLog
)

# Cartelle chiave
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition  # Analisi_Report\
$RootDir   = Split-Path -Parent $ScriptDir                          # Framework CIS\
$AzureDir  = Join-Path $RootDir "Azure"                             # Framework CIS\Vmware\

if (-not $CsvPath) { $CsvPath = Join-Path $RootDir "cis_azure.csv" }
if (-not $OutputDir) { $OutputDir = $ScriptDir }

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogFile   = Join-Path $OutputDir "cis_vmware_log_$Timestamp.txt"

Write-Host ""
Write-Host "################################################################" -ForegroundColor Magenta
Write-Host "  CIS Microsoft Azure Benchmark - Audit Framework" -ForegroundColor Magenta
Write-Host "  Data: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Magenta
Write-Host "################################################################" -ForegroundColor Magenta


# ---------------------------------------------------------------------------
# Inizia trascrizione file di log
# ---------------------------------------------------------------------------
if ($ExportLog) {
    Start-Transcript -Path $LogFile -Append | Out-Null
    Write-Host "Log: $LogFile" -ForegroundColor DarkYellow
}


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
# Moduli CIS Benchmark selezionati (Framework CIS\Azure\)
# ---------------------------------------------------------------------------
$modules = @(
    "module_2_app_service.ps1",
    "module_6_management.ps1",
    "module_7_networking.ps1",
    "module_8_security.ps1",
    "module_20_virtual_machines.ps1"
)

foreach ($modules in $modules) {
    $modPath = Join-Path $AzureDir $modules
    if (Test-Path $modPath) {
        Write-Host ""
        Write-Host ">>> $modules" -ForegroundColor Magenta
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

if (-not $AuditOnly) {
    # Scoring
    $scoringPath = Join-Path $ScriptDir "module_scoring.ps1"
    if (Test-Path $scoringPath) {
        & $scoringPath -CsvPath $CsvPath -ExportCsv -Wc $Wc -Wd $Wd -Wr $Wr -Alpha $Alpha -Beta $Beta 
    } else {
        Write-Host "[WARN] module_scoring.ps1 non trovato." -ForegroundColor DarkYellow
    }
}

if ($ExportLog) { Stop-Transcript | Out-Null }

Write-Host ""
Write-Host "################################################################" -ForegroundColor Magenta
Write-Host "  Esecuzione completata." -ForegroundColor Magenta
Write-Host "################################################################" -ForegroundColor Magenta
