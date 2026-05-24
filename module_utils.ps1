# =============================================================================
# module_utils.ps1 — modulo con funzioni condivise (VMware/Azure)
# =============================================================================
# Ognuno dei due moduli main chiama la relativa funzione init prima di lanciare i moduli di audit
#
# Funzioni di init:
#   - Initialize-VMwareCIS  : carica cis_vmware.csv + verifica sessione attiva su vCenter.
#   - Initialize-AzCIS      : carica cis_azure.csv + verifica sessiona attiva previo az login.
#
# Funzioni condivise tra i moduli Azure e VMware:
#   - Set-CheckResult             : registra il risultato del test nella variabile globale $Global:CISAuditResults.
#   - Get-CheckData               : legge metadati dal CSV in cache.
#   - Write-CheckHeader           : stampa a schermo del test da effettuare.
#   - Write-CheckFooter           : stampa a schermo del riepilogo del test effettuato in aggiunta alla remediation suggerita.
#
# =============================================================================


# ---------------------------------------------------------------------------
# Initialize-VMwareCIS
# Legge il contenuto di cis_vmware.csv e lo scrive in $Global:CISBenchmarkData inizializzando il
# registro dei risultati. Viene chiamata in main_vmware.ps1
# ---------------------------------------------------------------------------
function Initialize-VMwareCIS {
    param(
        [string]$CsvPath = "$PSScriptRoot\cis_vmware.csv"
    )
    # test esistenza dataset csv
    if (-not (Test-Path $CsvPath)) {
        Write-Warning "CSV non trovato: $CsvPath. Expected-value per i test e le remediation non sono disponibili."
        return $false
    }

    # verifica sessione attiva
    $session = $global:DefaultVIServers | Where-Object { $_.IsConnected -eq $true }
    if (-not $session) {
        Write-Warning "Nessuna sessione vCenter attiva. Esegui prima: Connect-VIServer"
        return $false
    }

    $Global:CISBenchmarkData = @{}
    Import-Csv -Path $CsvPath -Encoding UTF8 | ForEach-Object {
        $Global:CISBenchmarkData[$_.id.Trim()] = $_
    }
    Write-Host "  [ENGINE] Dataset VMware caricato: $($Global:CISBenchmarkData.Count) controlli" -ForegroundColor DarkCyan

    if (-not $Global:CISAuditResults) { $Global:CISAuditResults = @{} }
    return $true
}

# ---------------------------------------------------------------------------
# Test-HostAdvSettingCheck
# funzione data-driven per i controlli della sezione AdvancedSetting degli host ESXi.
# Operatori: eq, le, notempty
# ---------------------------------------------------------------------------
function Test-HostAdvSettingCheck {
    param([string]$CheckId, [string]$Label, [string]$ObjectType = "host")

    $data = Get-CheckData $CheckId
    if (-not $data) { Write-Warning "dati non trovati per $CheckId"; return }

    $settingName = $data.'setting-name'
    $expectedValue = $data.'expected-value'
    $operator    = $data.'operator'

    Write-CheckHeader $CheckId $Label

    $settings = @(Get-VMHost | Get-AdvancedSetting -Name $settingName -ErrorAction SilentlyContinue)
    $nc = @()

    foreach ($s in $settings) {
        $ok = switch ($operator) {
            "eq"       { "$($s.Value)".ToLower() -eq $expectedValue.ToLower() }
            "le"       { [double]$s.Value -le [double]$expectedValue }
            "notempty" { $null -ne $s.Value -and "$($s.Value)".Trim() -ne "" }
            default    { $false }
        }
        $color  = if ($ok) { "Green" } else { "Red" }
        $status = if ($ok) { "COMPLIANT" } else { "NON-COMPLIANT" }
        Write-Host "  [$status] $($s.Entity) -> $settingName = $($s.Value)" -ForegroundColor $color
        if (-not $ok) { $nc += "$($s.Entity) (valore=$($s.Value))" }
    }

    Set-CheckResult $CheckId $settings.Count $nc
    Write-CheckFooter $CheckId $ObjectType
}

# ---------------------------------------------------------------------------
# Test-VMAdvSettingCheck
# funzione data-driven per i controlli della sezione AdvancedSetting delle Virtual Machines.
# Operatori: eq, le, notempty
# ---------------------------------------------------------------------------
function Test-VMAdvSettingCheck {
    param([string]$CheckId, [string]$Label, [string]$ObjectType = "VM")

    $data = Get-CheckData $CheckId
    if (-not $data) { Write-Warning "dati non trovati per $CheckId"; return }

    $settingName = $data.'setting-name'
    $expectedValue = $data.'expected-value'
    $operator    = $data.'operator'

    Write-CheckHeader $CheckId $Label

    $allVMs   = @(Get-VM)
    $settings = @(Get-VM | Get-AdvancedSetting -Name $settingName -ErrorAction SilentlyContinue)
    $nc = @()

    if ($settings.Count -gt 0) {
        foreach ($s in $settings) {
            $ok = switch ($operator) {
                "eq"       { "$($s.Value)".ToLower() -eq $expectedValue.ToLower() }
                "le"       { [double]$s.Value -le [double]$expectedValue }
                "notempty" { $null -ne $s.Value -and "$($s.Value)".Trim() -ne "" }
                default    { $false }
            }
            $color  = if ($ok) { "Green" } else { "Red" }
            $status = if ($ok) { "COMPLIANT" } else { "NON-COMPLIANT" }
            Write-Host "  [$status] VM: $($s.Entity) -> $settingName = $($s.Value)" -ForegroundColor $color
            if (-not $ok) { $nc += "VM=$($s.Entity) (valore=$($s.Value))" }
        }
        
        # estrazione dei nomi come stringhe per confronto con -notin
        $vmsWithSetting = @($settings | ForEach-Object { $_.Entity.Name })
        # VM su cui il setting e' assente = non conforme
        foreach ($vm in $allVMs) {
            if ($vm.Name -notin $vmsWithSetting) {
                Write-Host "  [NON-COMPLIANT] VM: $($vm.Name) -> $settingName non presente" -ForegroundColor Red
                $nc += "VM=$($vm.Name) (impostazione assente)"
            }
        }
    } else {
        Write-Host "  [WARN] Impostazione non trovata su nessuna VM - da creare su tutte." -ForegroundColor DarkYellow
        foreach ($vm in $allVMs) { $nc += "VM=$($vm.Name) (impostazione assente)" }
    }

    Set-CheckResult $CheckId $allVMs.Count $nc
    Write-CheckFooter $CheckId $ObjectType
}

# ---------------------------------------------------------------------------
# Test-HostService
# Funzione di appoggio per i test sui servizi attivi sugli host ESXi (modulo 3.x)
# ---------------------------------------------------------------------------
function Test-HostService {
    param([string]$CheckId, [string]$ServiceKey, [string]$Label)
    Write-CheckHeader $CheckId $Label
    $services = @(Get-VMHost | Get-VMHostService | Where-Object { $_.Key -eq $ServiceKey })
    $nc = @()
    foreach ($item in $services) {
        $ok     = (-not $item.Running -and $item.Policy -eq "off")
        $color  = if ($ok) { "Green" } else { "Red" }
        $status = if ($ok) { "COMPLIANT" } else { "NON-COMPLIANT" }
        Write-Host "  [$status] $($item.VMHost) -> Running: $($item.Running) | Policy: $($item.Policy)" -ForegroundColor $color
        if (-not $ok) { $nc += "$($item.VMHost) (running=$($item.Running), policy=$($item.Policy))" }
    }
    Set-CheckResult $CheckId $services.Count $nc
    Write-CheckFooter $CheckId "host"
}

# ---------------------------------------------------------------------------
# Initialize-AzCISEngine
# Carica cis_azure.csv in $Global:CISBenchmarkData (stessa struttura hashtable
# usata dal framework VMware: module_scoring e module_report funzionano
# senza alcuna modifica) e verifica la sessione Azure CLI.
# ---------------------------------------------------------------------------
function Initialize-AzCISEngine {
    param(
        [string]$CsvPath = "$PSScriptRoot\cis_azure.csv"
    )

    # test esistenza dataset csv
    if (-not (Test-Path $CsvPath)) {
        Write-Warning "CSV non trovato: $CsvPath. Expected-value per i test e le remediation non sono disponibili."
        return $false
    }

    # verifica login con sottoscrizione Azure attiva
    $account = az account show 2>$null | ConvertFrom-Json
    if (-not $account) {
        Write-Warning "Nessuna sessione Azure CLI attiva. Esegui prima: az login"
        return $false
    }
    
    $Global:CISBenchmarkData = @{}
    Import-Csv -Path $CsvPath -Encoding UTF8 | ForEach-Object {
        $Global:CISBenchmarkData[$_.id.Trim()] = $_
    }
    Write-Host "  [ENGINE] Dataset Azure caricato: $($Global:CISBenchmarkData.Count) controlli" -ForegroundColor DarkCyan

    if (-not $Global:CISAuditResults) { $Global:CISAuditResults = @{} }

    Write-Host "  [ENGINE] Account: $($account.user.name) | Subscription: $($account.name)" -ForegroundColor DarkCyan
    return $true
}

# ---------------------------------------------------------------------------
# Test-AzPropertyCheck
# funzione data-driven per i controlli sulle risorse via Azure CLI.
# Delega intestazione, footer e registrazione alle funzioni condivise Write-CheckHeader / Write-CheckFooter / Set-CheckResult.
# $Resources     : array di oggetti su cui effettuare il controllo
# $GetValueScript: scriptblock che riceve $_ e restituisce il valore da verificare
# $Operator      : opearatore di confronto per il controllo. eq | le | notempty  (custom = logica inline nel modulo chiamante)
# $LabelScript   : scriptblock che restituisce la label della risorsa per i log
# ---------------------------------------------------------------------------
function Test-AzPropertyCheck {
    param(
        [string]      $CheckId,
        [string]      $Label,
        [array]       $Resources,
        [scriptblock] $GetValueScript,
        [string]      $Operator,
        [string]      $ExpectedValue = "",
        [scriptblock] $LabelScript   = { $_.name },
        [string]      $ObjectType    = "risorse"
    )

    Write-CheckHeader $CheckId $Label

    if (-not $Resources -or $Resources.Count -eq 0) {
        Write-Host "  [N/A] Nessuna risorsa trovata per questo controllo" -ForegroundColor DarkYellow
        Set-CheckResult $CheckId 0 @()
        return
    }

    $nc = @()

    foreach ($res in $Resources) {
        $resLabel = & $LabelScript
        try   { $val = & $GetValueScript }
        catch { $val = $null }

        $isCompliant = switch ($Operator) {
            "eq"       { "$val" -eq $ExpectedValue }
            "le"       { [double]"$val" -le [double]$ExpectedValue }
            "notempty" { $null -ne $val -and "$val" -ne "" }
            default    { $false }
        }

        if ($isCompliant) {
            Write-Host "  [COMPLIANT]     $resLabel = $val" -ForegroundColor Green
        } else {
            Write-Host "  [NON-COMPLIANT] $resLabel = $val (atteso: $ExpectedValue)" -ForegroundColor Red
            $nc += "$resLabel (valore: $val)"
        }
    }

    Set-CheckResult $CheckId $Resources.Count $nc
    Write-CheckFooter $CheckId $ObjectType
}


# ---------------------------------------------------------------------------
# Funzione di appoggio per i controlli 6.1.2.x (Activity Log Alert per operazione specifica)
# ---------------------------------------------------------------------------
$activityAlerts = az monitor activity-log alert list 2>$null | ConvertFrom-Json

function Test-ActivityLogAlert {
    param([string]$CheckId, [string]$Description, [string]$OperationName)
    Write-CheckHeader $CheckId "Activity Log Alert: $Description"
    $match = $activityAlerts | Where-Object {
        $_.condition.allOf | Where-Object { $_.field -eq "operationName" -and $_.equals -eq $OperationName }
    }
    if ($match) {
        Write-Host "  [COMPLIANT]     Alert trovato: '$($match[0].name)'" -ForegroundColor Green
        Set-CheckResult $CheckId 1 @()
    } else {
        Write-Host "  [NON-COMPLIANT] Nessun alert per: $OperationName" -ForegroundColor Red
        Set-CheckResult $CheckId 1 @("Operazione '$OperationName' - alert mancante")
    }
    Write-CheckFooter $CheckId "alert"
}

# ---------------------------------------------------------------------------
# di seguito le funzioni condivise tra i moduli Azure e VMware
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Set-CheckResult
# ---------------------------------------------------------------------------
function Set-CheckResult {
    param(
        [string]$CheckId,
        [int]$Total,
        [array]$NonCompliantObjects,   # usato per il conteggio
        [string]$ForceStatus  = "",    # usato per N/A, UNKNOWN
        [array]$ReportObjects = @()    # se valorizzato, usato nel report al posto di NonCompliantObjects
    )
    $nc = if ($NonCompliantObjects) { @($NonCompliantObjects) } else { @() }
    $status = if ($ForceStatus) { $ForceStatus }
              elseif ($nc.Count -eq 0) { "COMPLIANT" }
              else { "NON-COMPLIANT" }

    $objForReport = if ($ReportObjects.Count -gt 0) { $ReportObjects } else { $nc }

    $Global:CISAuditResults[$CheckId] = @{
        Status       = $status
        Total        = $Total
        NonCompliant = $nc.Count
        Objects      = $objForReport
    }
}

# ---------------------------------------------------------------------------
# Get-CheckData 
# ---------------------------------------------------------------------------
function Get-CheckData {
    param([string]$CheckId)
    if ($Global:CISBenchmarkData.ContainsKey($CheckId)) {
        return $Global:CISBenchmarkData[$CheckId]
    }
    return $null
}

# ---------------------------------------------------------------------------
# Write-CheckHeader 
# ---------------------------------------------------------------------------
function Write-CheckHeader {
    param([string]$CheckId, [string]$Label)
    $data = Get-CheckData $CheckId
    $expected = if ($data -and $data.'expected-value') { $data.'expected-value' } else { "" }
    $setting  = if ($data -and $data.'setting-name')   { $data.'setting-name' }   else { "" }

    Write-Host "[$CheckId] $Label" -ForegroundColor Yellow
    if ($setting)  { Write-Host "       Setting : $setting" }
    if ($expected) { Write-Host "       Expected: $expected" }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Write-CheckFooter 
# ---------------------------------------------------------------------------
function Write-CheckFooter {
    param([string]$CheckId, [string]$ObjectType = "oggetti")
    $rem    = $Global:CISAuditResults[$CheckId]
    $data = Get-CheckData $CheckId

    $compliant = $rem.Total - $rem.NonCompliant
    Write-Host ""
    Write-Host "  Riepilogo: $compliant/$($rem.Total) $ObjectType conformi" -ForegroundColor DarkCyan

    if ($data -and $data.remediation) {
        $rem = ($data.remediation -replace "`r","").Trim()
        Write-Host ""
        Write-Host "  REMEDIATION:" -ForegroundColor DarkGray
        $rem -split "`n" | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    }
    Write-Host ""
}