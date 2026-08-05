# =============================================================================
# module_utils.ps1 — modulo con funzioni condivise
# =============================================================================
#
# Funzione di init:
#   - Initialize-AzCIS  : carica cis_azure.csv + verifica sessione attiva previo az login
#
# Funzioni Azure-specifiche:
#   - Test-AzPropertyCheck  : controlli data-driven basati su proprieta' di risorse Azure.
#   - Test-ActivityLogAlert : controlli 6.1.2.x (Activity Log Alert per operazione).
#   - Test-NsgInternet      : controlli 7.x su regole NSG esposte a Internet.
#   - Test-DefenderPlan     : controlli 8.x sui piani Microsoft Defender for Cloud.
#   - Get-NestedProperty    : risolve proprieta' annidate nelle risorse Azure.
#
# Funzioni condivise:
#   - Set-CheckResult    : registra il risultato del test in $Global:CISAuditResults.
#   - Get-CheckData      : legge metadati dal CSV in cache.
#   - Write-CheckHeader  : stampa a schermo del test da effettuare.
#   - Write-CheckFooter  : stampa a schermo del riepilogo e della remediation.
# =============================================================================

# ---------------------------------------------------------------------------
# Initialize-AzCIS
# Carica cis_azure.csv in $Global:CISBenchmarkData (stessa struttura hashtable
# usata dal framework VMware: module_scoring e module_report funzionano
# senza alcuna modifica) e verifica la sessione Azure CLI.
# ---------------------------------------------------------------------------
function Initialize-AzCIS {
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
    Write-Host "  [INIT] Dataset Azure caricato: $($Global:CISBenchmarkData.Count) controlli" -ForegroundColor DarkCyan

    if (-not $Global:CISAuditResults) { $Global:CISAuditResults = @{} }

    Write-Host "  [INIT] Account: $($account.user.name) | Subscription: $($account.name)" -ForegroundColor DarkCyan
    return $true
}

# ---------------------------------------------------------------------------
# Test-AzPropertyCheck
# funzione data-driven per i controlli sulle risorse via Azure CLI.
# Delega intestazione, footer e registrazione alle funzioni condivise Write-CheckHeader / Write-CheckFooter / Set-CheckResult.
# $Resources     : array di oggetti su cui effettuare il controllo
# $GetValueScript: scriptblock che riceve $_ e restituisce il valore da verificare
# $Operator      : opearatore di confronto per il controllo. eq | le | notempty  (custom = logica inline nel modulo chiamante)
# ---------------------------------------------------------------------------
function Test-AzPropertyCheck {
    param(
        [string]$CheckId,
        [array] $Resources,
        [string]$ObjectType = "risorse",
        [scriptblock]$LabelScript = { $_.name }
    )

    $data          = Get-CheckData $CheckId
    $settingName   = $data.'setting-name'
    $operator      = $data.'operator'
    $expectedValue = $data.'expected-value'

    Write-CheckHeader $CheckId
    if (-not $Resources -or $Resources.Count -eq 0) {
        Write-Host "  [N/A] Nessuna risorsa trovata per questo controllo" -ForegroundColor DarkYellow
        Set-CheckResult $CheckId 0 @() -ForceStatus "N/A"
        return
    }

    $nc = @()

    foreach ($res in $Resources) {
        #per debug
        #Write-Host "DEBUG: $($res | ConvertTo-Json -Depth 2 -Compress)" -ForegroundColor DarkGray

        $resLabel = $res | ForEach-Object $LabelScript
        try { $val = Get-NestedProperty -Object $res -Path $settingName }
        catch { $val = $null }

        $isCompliant = switch ($operator) {
            "eq"       { "$val" -eq $expectedValue }
            "le"       { [double]"$val" -le [double]$expectedValue }
            "notempty" { $null -ne $val -and "$val" -ne "" }
            default    { $false }
        }

        if ($isCompliant) {
            Write-Host "  [COMPLIANT]     $resLabel = $val" -ForegroundColor Green
        } else {                                    
            $displayVal  = if ($null -eq $val -or "$val" -eq "") { "(proprieta' assente)" } else { $val }
            $expectedStr = if ($Operator -eq "notempty") { "(valore assente o nullo)" } else { "(atteso: $ExpectedValue)" }
            Write-Host "  [NON-COMPLIANT] $resLabel = $displayVal $expectedStr" -ForegroundColor Red
            $nc += "$resLabel (valore: $displayVal)"
        }
    }

    Set-CheckResult $CheckId $Resources.Count $nc
    Write-CheckFooter $CheckId $ObjectType
}

# ---------------------------------------------------------------------------
# Funzione di appoggio per risolvere path specifici nelle proprietà delle risorse Azure
# Utilizzata all'interno di Test-AzPropertyCheck.
# Le proprietà Azure sono spesso annidate in oggetti JSON profondi.
# ---------------------------------------------------------------------------
function Get-NestedProperty {
    param($Object, [string]$Path)
    $value = $Object
    foreach ($part in $Path -split '\.') {
        if ($null -eq $value) { return $null }
        $value = $value.$part
    }
    return $value
}


# ---------------------------------------------------------------------------
# popolata al primo utilizzo, riusata dalle chiamate successive per i test 6.1.2.x
# ---------------------------------------------------------------------------
$Script:ActivityAlertsCache = $null
# ---------------------------------------------------------------------------
# Funzione di appoggio per i controlli 6.1.2.x (Activity Log Alert per operazione specifica)
# ---------------------------------------------------------------------------
function Test-ActivityLogAlert {
    param([string]$CheckId, [string]$OperationName)
    Write-CheckHeader $CheckId 

    if ($null -eq $Script:ActivityAlertsCache) {
        $Script:ActivityAlertsCache = @(az monitor activity-log alert list 2>$null | ConvertFrom-Json)
    }

    $match = $Script:ActivityAlertsCache | Where-Object {
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
# Funzione di appoggio per i controlli della sezione networking 7.x
# ---------------------------------------------------------------------------
function Test-NsgInternet {
    param([string]$CheckId, [string[]]$Ports, [string]$Proto = "Tcp")
    Write-CheckHeader $CheckId 
    $nc = @()
    foreach ($nsg in $allNSGs) {
        $bad = $nsg.securityRules | Where-Object { Test-NsgAllowsInternet $_ $Ports $Proto }
        if ($bad) {
            $bad | ForEach-Object {
                Write-Host "  [NON-COMPLIANT] NSG '$($nsg.name)' regola '$($_.name)'" -ForegroundColor Red
                $nc += "$($nsg.name)/$($_.name) (porta $($_.destinationPortRange) da Internet)"
            }
        } else {
            Write-Host "  [COMPLIANT]     NSG '$($nsg.name)': nessuna regola aperta" -ForegroundColor Green
        }
    }
    Set-CheckResult $CheckId $allNSGs.Count $nc
    Write-CheckFooter $CheckId "NSG"
}

# ---------------------------------------------------------------------------
# Funzione di appoggio per i controlli della sezione security 8.x
# ---------------------------------------------------------------------------
function Test-DefenderPlan {
    param([string]$CheckId, [string]$PlanName)
    Write-CheckHeader $CheckId
    $pricing = @(az security pricing show --name $PlanName 2>$null | ConvertFrom-Json)
    $tier    = if ($pricing -and $pricing.Count -gt 0) { $pricing[0].pricingTier } else { "N/A" }
    if ($tier -eq "Standard") {
        Write-Host "  [COMPLIANT]     Defender for $PlanName : pricingTier=$tier" -ForegroundColor Green
        Set-CheckResult $CheckId 1 @()
    } else {
        Write-Host "  [NON-COMPLIANT] Defender for $PlanName : pricingTier=$tier" -ForegroundColor Red
        Set-CheckResult $CheckId 1 @("$PlanName  -  pricingTier=$tier")
    }
    Write-CheckFooter $CheckId "servizi"
}



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
    param([string]$CheckId)
    $data = Get-CheckData $CheckId
    $name = if ($data -and $data.'name') { $data.'name' } else { "" }
    $expected = if ($data -and $data.'expected-value') { $data.'expected-value' } else { "" }
    $setting  = if ($data -and $data.'setting-name')   { $data.'setting-name' }   else { "" }

    Write-Host "[$CheckId] $name" -ForegroundColor Yellow
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