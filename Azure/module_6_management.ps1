# =============================================================================
# module_6_management.ps1
# CIS Azure Benchmark -- Sezione 6.1: Management and Governance (15 controlli)
# =============================================================================
. (Join-Path (Split-Path $PSScriptRoot -Parent) "module_utils.ps1")

Write-Host "`n### MANAGEMENT & GOVERNANCE (6.1.x) ###" -ForegroundColor Magenta

$subId = (az account show 2>$null | ConvertFrom-Json).id

# ---------------------------------------------------------------------------
# 6.1.1.1 -- Diagnostic Setting esiste per Subscription Activity Log
# ---------------------------------------------------------------------------
Write-CheckHeader "6.1.1.1" "Diagnostic Setting exists for Subscription Activity Log"
$diagSettings = az monitor diagnostic-settings list --resource "/subscriptions/$subId" 2>$null | ConvertFrom-Json
if (-not $diagSettings -or $diagSettings.Count -eq 0) {
    Write-Host "  [NON-COMPLIANT] Nessun Diagnostic Setting configurato" -ForegroundColor Red
    Set-CheckResult "6.1.1.1" 1 @("Subscription $subId - nessun Diagnostic Setting")
} else {
    Write-Host "  [COMPLIANT]     $($diagSettings.Count) Diagnostic Setting(s) trovati" -ForegroundColor Green
    Set-CheckResult "6.1.1.1" 1 @()
}
Write-CheckFooter "6.1.1.1" "Diagnostic Setting"

# ---------------------------------------------------------------------------
# 6.1.1.2 -- Categorie appropriate abilitate
# ---------------------------------------------------------------------------
$requiredCats = @("Administrative","Security","Alert","Policy")
Write-CheckHeader "6.1.1.2" "Diagnostic Setting captures appropriate categories"
$nc = @()
foreach ($ds in $diagSettings) {
    $enabled = ($ds.logs | Where-Object { $_.enabled -eq $true }).category
    $missing = $requiredCats | Where-Object { $_ -notin $enabled }
    if ($missing) {
        Write-Host "  [NON-COMPLIANT] '$($ds.name)': mancanti = $($missing -join ', ')" -ForegroundColor Red
        $nc += "$($ds.name) - mancanti: $($missing -join ', ')"
    } else {
        Write-Host "  [COMPLIANT]     '$($ds.name)': tutte le categorie abilitate" -ForegroundColor Green
    }
}
$tot = if ($diagSettings) { $diagSettings.Count } else { 1 }
Set-CheckResult "6.1.1.2" $tot $nc
Write-CheckFooter "6.1.1.2" "Diagnostic Setting"

# ---------------------------------------------------------------------------
# 6.1.1.4 -- Key Vault logging abilitato
# ---------------------------------------------------------------------------
Write-CheckHeader "6.1.1.4" "Logging for Azure Key Vault is 'Enabled'"
$keyVaults = az keyvault list 2>$null | ConvertFrom-Json
$nc = @()
foreach ($key in $keyVaults) {
    $keyDiag = az monitor diagnostic-settings list --resource $key.id 2>$null | ConvertFrom-Json
    $hasLog  = $keyDiag | Where-Object { ($_.logs | Where-Object { $_.enabled -eq $true }).Count -gt 0 }
    if (-not $hasLog) {
        Write-Host "  [NON-COMPLIANT] KeyVault '$($key.name)': nessun log abilitato" -ForegroundColor Red
        $nc += "$($key.name) - nessun diagnostic log"
    } else {
        Write-Host "  [COMPLIANT]     KeyVault '$($key.name)': log attivo" -ForegroundColor Green
    }
}
if ($keyVaults.Count -eq 0) { Write-Host "  [N/A] Nessun Key Vault trovato" -ForegroundColor DarkYellow }
Set-CheckResult "6.1.1.4" $keyVaults.Count $nc
Write-CheckFooter "6.1.1.4" "Key Vault"


# ---------------------------------------------------------------------------
# 6.1.2.1 -- 6.1.2.10 Activity Log Alert per operazioni critiche
# ---------------------------------------------------------------------------
Test-ActivityLogAlert "6.1.2.1"  "Create Policy Assignment"           "Microsoft.Authorization/policyAssignments/write"
Test-ActivityLogAlert "6.1.2.2"  "Delete Policy Assignment"           "Microsoft.Authorization/policyAssignments/delete"
Test-ActivityLogAlert "6.1.2.3"  "Create or Update NSG"               "Microsoft.Network/networkSecurityGroups/write"
Test-ActivityLogAlert "6.1.2.4"  "Delete NSG"                         "Microsoft.Network/networkSecurityGroups/delete"
Test-ActivityLogAlert "6.1.2.5"  "Create or Update Security Solution" "Microsoft.Security/securitySolutions/write"
Test-ActivityLogAlert "6.1.2.6"  "Delete Security Solution"           "Microsoft.Security/securitySolutions/delete"
Test-ActivityLogAlert "6.1.2.7"  "Create or Update SQL Server"        "Microsoft.Sql/servers/write"
Test-ActivityLogAlert "6.1.2.8"  "Delete SQL Server"                  "Microsoft.Sql/servers/delete"
Test-ActivityLogAlert "6.1.2.9"  "Create or Update Public IP"         "Microsoft.Network/publicIPAddresses/write"
Test-ActivityLogAlert "6.1.2.10" "Delete Public IP"                   "Microsoft.Network/publicIPAddresses/delete"

# ---------------------------------------------------------------------------
# 6.1.2.11 -- Service Health alert
# ---------------------------------------------------------------------------
Write-CheckHeader "6.1.2.11" "Activity Log Alert exists for Service Health"
$sh = $activityAlerts | Where-Object {
    $_.condition.allOf | Where-Object { $_.field -eq "category" -and $_.equals -eq "ServiceHealth" }
}
if ($sh) {
    Write-Host "  [COMPLIANT]     Service Health alert trovato: '$($sh[0].name)'" -ForegroundColor Green
    Set-CheckResult "6.1.2.11" 1 @()
} else {
    Write-Host "  [NON-COMPLIANT] Nessun Service Health alert configurato" -ForegroundColor Red
    Set-CheckResult "6.1.2.11" 1 @("Subscription $subId - Service Health alert mancante")
}
Write-CheckFooter "6.1.2.11" "alert"

# ---------------------------------------------------------------------------
# 6.1.3.1 -- Application Insights configurato
# ---------------------------------------------------------------------------
Write-CheckHeader "6.1.3.1" "Application Insights are Configured"
$ai = az resource list --resource-type "microsoft.insights/components" 2>$null | ConvertFrom-Json
if ($ai -and $ai.Count -gt 0) {
    $ai | ForEach-Object { Write-Host "  [COMPLIANT]     '$($_.name)' in '$($_.resourceGroup)'" -ForegroundColor Green }
    Set-CheckResult "6.1.3.1" 1 @()
} else {
    Write-Host "  [NON-COMPLIANT] Nessuna risorsa Application Insights trovata" -ForegroundColor Red
    Set-CheckResult "6.1.3.1" 1 @("Subscription $subId - Application Insights non configurato")
}
Write-CheckFooter "6.1.3.1" "Application Insights"
