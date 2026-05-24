# =============================================================================
# module_20_virtual_machines.ps1
# CIS Azure Benchmark  -  Sezione 20: Virtual Machines  (6 controlli)
# =============================================================================
. (Join-Path (Split-Path $PSScriptRoot -Parent) "module_utils.ps1")

Write-Host "`n### VIRTUAL MACHINES (20.x) ###" -ForegroundColor Magenta

$allVMs   = az vm list   2>$null | ConvertFrom-Json


$allResourceGroups   = az group list 2>$null | ConvertFrom-Json
$allDisks = @(
    $allResourceGroups | ForEach-Object {
        az disk list --resource-group $_.name 2>$null | ConvertFrom-Json
    } | Where-Object { $_ -ne $null }
)

# 20.1  -  Managed Disks  (data-driven)
Test-AzPropertyCheck "20.1" "Virtual Machines are utilizing Managed Disks" `
    -Resources $allVMs `
    -GetValueScript { $_.storageProfile.osDisk.managedDisk.id } `
    -Operator "notempty" -ObjectType "VM"

# 20.2  -  CMK su OS + Data disk
Write-CheckHeader "20.2" "OS and Data disks encrypted with Customer Managed Key"
$nc = @()
foreach ($vm in $allVMs) {
    $osDisk = az disk show --ids $vm.storageProfile.osDisk.managedDisk.id 2>$null | ConvertFrom-Json
    $osOk   = $osDisk.encryption.type -like "*CustomerKey*"
    $dataOk = $true
    foreach ($dd in $vm.storageProfile.dataDisks) {
        $d = $allDisks | Where-Object { $_.id -eq $dd.managedDisk.id }
        if ($d.encryption.type -notlike "*CustomerKey*") { $dataOk = $false }
    }
    if (-not ($osOk -and $dataOk)) {
        Write-Host "  [NON-COMPLIANT] $($vm.name): osEnc=$($osDisk.encryption.type), dataOk=$dataOk" -ForegroundColor Red
        $nc += "$($vm.name) (osEnc=$($osDisk.encryption.type), dataDisks=$dataOk)"
    } else {
        Write-Host "  [COMPLIANT]     $($vm.name): CMK su OS e data disk" -ForegroundColor Green
    }
}
Set-CheckResult "20.2" $allVMs.Count $nc
Write-CheckFooter "20.2" "VM"

# 20.3  -  CMK su dischi scollegati  (data-driven)
Test-AzPropertyCheck "20.3" "Unattached disks encrypted with Customer Managed Key" `
    -Resources ($allDisks | Where-Object { $_.diskState -eq "Unattached" }) `
    -GetValueScript { $_.encryption.type } `
    -Operator "eq" -ExpectedValue "EncryptionAtRestWithCustomerKey" -ObjectType "disco"

# 20.4  -  Disk network access  (data-driven)
Write-CheckHeader "20.4" "Disk Network Access is NOT set to 'Enable public access from all networks'"
$nc = @()
foreach ($disk in $allDisks) {
    if ($disk.networkAccessPolicy -eq "AllowAll") {
        Write-Host "  [NON-COMPLIANT] '$($disk.name)': networkAccessPolicy=AllowAll" -ForegroundColor Red
        $nc += "$($disk.name) in $($disk.resourceGroup)"
    } else {
        Write-Host "  [COMPLIANT]     '$($disk.name)': networkAccessPolicy=$($disk.networkAccessPolicy)" -ForegroundColor Green
    }
}
Set-CheckResult "20.4" $allDisks.Count $nc
Write-CheckFooter "20.4" "disco"

# 20.10  -  Trusted Launch  (data-driven)
Test-AzPropertyCheck "20.10" "Trusted Launch is enabled on Virtual Machines" `
    -Resources $allVMs `
    -GetValueScript { $_.securityProfile.securityType } `
    -Operator "eq" -ExpectedValue "TrustedLaunch" -ObjectType "VM"

# 20.11  -  Encryption at host  (data-driven)
Test-AzPropertyCheck "20.11" "Encryption at host is enabled" `
    -Resources $allVMs `
    -GetValueScript { $_.securityProfile.encryptionAtHost } `
    -Operator "eq" -ExpectedValue "True" -ObjectType "VM"
