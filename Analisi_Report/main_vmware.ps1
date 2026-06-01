# =============================================================================
# CIS VMware ESXi Benchmark 
# main_vmware.ps1
# modulo main per i controlli CIS VMware ESXi.
# =============================================================================
# Prerequisito: essere gia' connessi al vCenter con Connect-VIServer
#
# Usage:
#   .\main_vmware.ps1
#   .\main_vmware.ps1 -AuditOnly
#   .\main_vmware.ps1 -Wc 0.5 -Wd 0.3 -Wr 0.2 -Alfa 0.3 -Beta 0.65
#   .\main_vmware.ps1 -OutputDir "C:\reports"
# =============================================================================

param(
    [double]$Wc        = 0.40,
    [double]$Wd        = 0.35,
    [double]$Wr        = 0.25,
    [double]$Alfa      = 0.35,
    [double]$Beta      = 0.70,
    [string]$CsvPath   = "",
    [string]$OutputDir = "",
    [switch]$AuditOnly,
    [switch]$ExportLog
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir   = Split-Path -Parent $ScriptDir                          # Framework CIS\
$VMwareDir  = Join-Path $RootDir "VMware"                             # Framework CIS\VMware\

if (-not $CsvPath)   { $CsvPath   = Join-Path $RootDir "cis_vmware.csv" }
if (-not $OutputDir) { $OutputDir = $ScriptDir }

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogFile   = Join-Path $OutputDir "cis_vmware_log_$Timestamp.txt"

# Verifica sessione attiva
if (-not $global:DefaultVIServers -or $global:DefaultVIServers.Count -eq 0) {
    Write-Error "Nessuna sessione vCenter attiva. Esegui prima: Connect-VIServer -Server <vcenter>"
    exit 1
}
Write-Host ""
Write-Host "Sessione attiva su: $($global:DefaultVIServers.Name -join ', ')" -ForegroundColor Green

if ($ExportLog) {
    Start-Transcript -Path $LogFile -Append | Out-Null
    Write-Host "Log: $LogFile" -ForegroundColor DarkYellow
}

# Carica il dataset VMware e inizializza i globali
. (Join-Path $RootDir "module_engine.ps1")
$ok = Initialize-VMwareCIS -CsvPath $CsvPath
if (-not $ok) { exit 1 }

$modules = @(
    @{ File = "module_2_base.ps1";            Label = "Modulo 2 - BASE" },
    @{ File = "module_3_management.ps1";       Label = "Modulo 3 - MANAGEMENT" },
    @{ File = "module_4_logging.ps1";          Label = "Modulo 4 - LOGGING" },
    @{ File = "module_5_network.ps1";          Label = "Modulo 5 - NETWORK" },
    @{ File = "module_6_features.ps1";         Label = "Modulo 6 - FEATURES" },
    @{ File = "module_7_virtual_machines.ps1"; Label = "Modulo 7 - VIRTUAL MACHINES" }
)

Write-Host ""
Write-Host "################################################################" -ForegroundColor Magenta
Write-Host "  CIS VMware ESXi Benchmark - Full Compliance Run" -ForegroundColor Magenta
Write-Host "  Data: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Magenta
Write-Host "################################################################" -ForegroundColor Magenta

foreach ($module in $modules) {
    $modulePath = Join-Path $VMwareDir $module.File
    if (Test-Path $modulePath) {
        Write-Host ""
        Write-Host ">>> $($module.Label)" -ForegroundColor Magenta
        & $modulePath
    } else {
        Write-Host "[ERRORE] File non trovato: $modulePath" -ForegroundColor Red
    }
}

if (-not $AuditOnly) {
    # Scoring
    $scoringPath = Join-Path $ScriptDir "module_scoring.ps1"
    if (Test-Path $scoringPath) {
        & $scoringPath -CsvPath $CsvPath -ExportCsv -Wc $Wc -Wd $Wd -Wr $Wr -Alfa $Alfa -Beta $Beta 
    } else {
        Write-Host "[WARN] module_scoring.ps1 non trovato." -ForegroundColor DarkYellow
    }
}

if ($ExportLog) { Stop-Transcript | Out-Null }

Write-Host ""
Write-Host "################################################################" -ForegroundColor Magenta
Write-Host "  Esecuzione completata." -ForegroundColor Magenta
Write-Host "################################################################" -ForegroundColor Magenta
