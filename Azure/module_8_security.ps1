# =============================================================================
# module_8_security.ps1
# CIS Azure Benchmark  -  Sezione 8: Security Services  (13 controlli)
# =============================================================================
. (Join-Path (Split-Path $PSScriptRoot -Parent) "module_utils.ps1")

Write-Host "`n### SECURITY SERVICES (8.x) ###" -ForegroundColor Magenta


Test-DefenderPlan "8.1.1.1" "CloudPosture"                   "CSPM"
Test-DefenderPlan "8.1.2.1" "Api"                            "APIs"
Test-DefenderPlan "8.1.3.1" "VirtualMachines"                "Servers"
Test-DefenderPlan "8.1.4.1" "Containers"                     "Containers"
Test-DefenderPlan "8.1.5.1" "StorageAccounts"                "Storage"
Test-DefenderPlan "8.1.6.1" "AppServices"                    "App Services"
Test-DefenderPlan "8.1.7.1" "CosmosDbs"                      "Azure Cosmos DB"
Test-DefenderPlan "8.1.7.2" "OpenSourceRelationalDatabases"  "Open-Source Relational Databases"
Test-DefenderPlan "8.1.7.3" "SqlServerVirtualMachines"       "SQL Managed Instance"
Test-DefenderPlan "8.1.7.4" "SqlServers"                     "SQL Servers on Machines"
Test-DefenderPlan "8.1.8.1" "KeyVaults"                      "Key Vault"
Test-DefenderPlan "8.1.9.1" "Arm"                            "Resource Manager"

# 8.5  -  DDoS Protection su VNet  (data-driven)
Test-AzPropertyCheck "8.5" "Azure DDoS Network Protection enabled on virtual networks" `
    -Resources (az network vnet list 2>$null | ConvertFrom-Json) `
    -GetValueScript { $_.ddosProtectionPlan.id } `
    -Operator "notempty" -ObjectType "VNet"
