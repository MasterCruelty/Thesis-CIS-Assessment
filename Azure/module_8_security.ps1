# =============================================================================
# module_8_security.ps1
# CIS Azure Benchmark  -  Sezione 8: Security Services  (13 controlli)
# =============================================================================
. (Join-Path (Split-Path $PSScriptRoot -Parent) "module_utils.ps1")

Write-Host "`n### SECURITY SERVICES (8.x) ###" -ForegroundColor Magenta


Test-DefenderPlan "8.1.1.1" "CloudPosture"                   
Test-DefenderPlan "8.1.2.1" "Api"                            
Test-DefenderPlan "8.1.3.1" "VirtualMachines"                
Test-DefenderPlan "8.1.4.1" "Containers"                     
Test-DefenderPlan "8.1.5.1" "StorageAccounts"                
Test-DefenderPlan "8.1.6.1" "AppServices"                    
Test-DefenderPlan "8.1.7.1" "CosmosDbs"                      
Test-DefenderPlan "8.1.7.2" "OpenSourceRelationalDatabases"  
Test-DefenderPlan "8.1.7.3" "SqlServerVirtualMachines"       
Test-DefenderPlan "8.1.7.4" "SqlServers"                     
Test-DefenderPlan "8.1.8.1" "KeyVaults"                      
Test-DefenderPlan "8.1.9.1" "Arm"                            

# 8.5  -  DDoS Protection su VNet  (data-driven)
Test-AzPropertyCheck "8.5" `
    -Resources (az network vnet list  | ConvertFrom-Json) `
    -ObjectType "VNet"
