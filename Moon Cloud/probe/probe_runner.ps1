# =============================================================================
# probe_runner.ps1 - collettore tra il framework CIS Azure e la sonda Moon Cloud
# =============================================================================
#
# Questo script si limita a orchestrare l'esecuzione del framework CIS Powershell
# già esistente in modo tale che la sonda Python richiami solamente questo sorgente
# durante la sua esecuzione.
# 
#
# La sessione Azure CLI si assume già attiva poiché è la sonda python Moon Cloud
# a eseguire il comando di login su Microsoft Azure prima di invocare questo script.
#
# Exit code previsti:
#   0  esecuzione completata (l'esito di compliance è all'interno del JSON)
#   2  inizializzazione fallita (dataset mancante o sessione Azure non attiva)
#   3  sezione documento CIS richiesta non valida
#   4  errore imprevisto durante l'esecuzione dei moduli
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FrameworkRoot,

    [Parameter(Mandatory = $true)]
    [ValidateSet('app_service', 'management', 'networking', 'security', 'virtual_machines', 'all')]
    [string]$Section,

    [Parameter(Mandatory = $true)]
    [string]$JsonPath,

    [double]$Wc   = 0.40,
    [double]$Wd   = 0.30,
    [double]$Wr   = 0.30,
    [double]$Alfa = 0.35,
    [double]$Beta = 0.70
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# evita formattazioni di numeri con la virgola come separatore decimale 
# ---------------------------------------------------------------------------
[System.Threading.Thread]::CurrentThread.CurrentCulture   = [System.Globalization.CultureInfo]::InvariantCulture
[System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::InvariantCulture

# ---------------------------------------------------------------------------
# Risoluzione dei path del framework
# ---------------------------------------------------------------------------
$RootDir    = (Resolve-Path $FrameworkRoot).Path
$AzureDir   = Join-Path $RootDir 'Azure'
$ReportDir  = Join-Path $RootDir 'Analisi_Report'
$CsvPath    = Join-Path $RootDir 'cis_azure.csv'
$UtilsPath  = Join-Path $RootDir 'module_utils.ps1'
$ScoringPs1 = Join-Path $ReportDir 'module_scoring.ps1'

foreach ($p in @($UtilsPath, $CsvPath, $ScoringPs1)) {
    if (-not (Test-Path $p)) {
        Write-Error "File del framework non trovato: $p"
        exit 2
    }
}

# ---------------------------------------------------------------------------
# Mappa sezione CIS -> modulo PowerShell da eseguire
# ---------------------------------------------------------------------------
$sectionMap = [ordered]@{
    'app_service'      = 'module_2_app_service.ps1'
    'management'       = 'module_6_management.ps1'
    'networking'       = 'module_7_networking.ps1'
    'security'         = 'module_8_security.ps1'
    'virtual_machines' = 'module_20_virtual_machines.ps1'
}

# potenzialmente estendibile all'esecuzione di tutte le sezioni disponibili una dopo l'altra
$modulesToRun = if ($Section -eq 'all') {
    @($sectionMap.Values)
} else {
    @($sectionMap[$Section])
}

if (-not $modulesToRun -or $modulesToRun.Count -eq 0) {
    Write-Error "Sezione non valida: $Section"
    exit 3
}

# ---------------------------------------------------------------------------
# Inizializzazione del framework (carica il dataset e verifica la sessione az)
# ---------------------------------------------------------------------------
. $UtilsPath

$initOk = Initialize-AzCIS -CsvPath $CsvPath
if (-not $initOk) {
    Write-Error 'Initialize-AzCIS fallita: dataset mancante o sessione Azure CLI non attiva.'
    exit 2
}

# ---------------------------------------------------------------------------
# Esecuzione dei controlli di conformità
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '================================================================'
Write-Host "  CIS Azure - sezione: $Section"
Write-Host '================================================================'

try {
    foreach ($modFile in $modulesToRun) {
        $modPath = Join-Path $AzureDir $modFile
        if (-not (Test-Path $modPath)) {
            Write-Warning "Modulo non trovato, saltato: $modPath"
            continue
        }
        Write-Host ''
        Write-Host ">>> $modFile"
        & $modPath
    }
}
catch {
    Write-Error "Errore durante l'esecuzione : $($_.Exception.Message)"
    exit 4
}

# ---------------------------------------------------------------------------
# Scoring + export JSON
# ---------------------------------------------------------------------------
try {
    & $ScoringPs1 -CsvPath $CsvPath `
                  -Wc $Wc -Wd $Wd -Wr $Wr `
                  -Alpha $Alfa -Beta $Beta `
                  -ExportJson -JsonPath $JsonPath
}
catch {
    Write-Error "Errore durante lo scoring: $($_.Exception.Message)"
    exit 4
}

if (-not (Test-Path $JsonPath)) {
    Write-Error "Il file JSON di output non è stato prodotto: $JsonPath"
    exit 4
}

Write-Host ''
Write-Host "Esecuzione completata. Risultati in: $JsonPath"
exit 0