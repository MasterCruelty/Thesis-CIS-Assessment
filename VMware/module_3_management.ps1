# =============================================================================
# CIS VMware ESXi Benchmark - Module 3: MANAGEMENT
# Checks: 3.1, 3.2, 3.3, 3.7, 3.8, 3.9, 3.12, 3.13, 3.20, 3.21
# =============================================================================
$RootDir   = Split-Path -Parent $ScriptDir
. (Join-Path $RootDir "module_utils.ps1")

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  CIS VMware - Module 3: MANAGEMENT CHECKS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$allHosts = @(Get-VMHost)


# 3.1 - Disable SSH  
Test-HostService "3.1" "TSM-SSH" 

# 3.2 - Disable ESXi Shell  
Test-HostService "3.2" "TSM" 

# 3.3 - Disable MOB  (Manager Object Browser)
Test-HostAdvSettingCheck "3.3" 

# 3.7 - DCUI timeout  
Test-HostAdvSettingCheck "3.7" 

# 3.8 - Shell interactive timeout  
Test-HostAdvSettingCheck "3.8" 

# 3.9 - Shell service timeout  
Test-HostAdvSettingCheck "3.9" 

# 3.12 - Account lock failures  
Test-HostAdvSettingCheck "3.12" 

# 3.13 - Account unlock time  
Test-HostAdvSettingCheck "3.13" 

# 3.20 - Normal Lockdown Mode  
Write-CheckHeader "3.20" 
$nc_320 = @()
foreach ($esxi in $allHosts) {
    $ok     = $esxi.Extensiondata.Config.adminDisabled -eq $true
    $color  = if ($ok) { "Green" } else { "Red" }
    $status = if ($ok) { "COMPLIANT" } else { "NON-COMPLIANT" }
    Write-Host "  [$status] $($esxi.Name) -> adminDisabled = $($esxi.Extensiondata.Config.adminDisabled)" -ForegroundColor $color
    if (-not $ok) { $nc_320 += $esxi.Name }
}
Set-CheckResult "3.20" $allHosts.Count $nc_320
Write-CheckFooter "3.20" "host"

# 3.21 - Strict Lockdown Mode  [CUSTOM]
Write-CheckHeader "3.21" 
$nc_321 = @()
foreach ($esxi in $allHosts) {
    $mode   = $esxi.Extensiondata.Config.LockdownMode
    $ok     = ($mode -eq "lockdownStrict")
    $color  = if ($ok) { "Green" } else { "Red" }
    $status = if ($ok) { "COMPLIANT" } else { "NON-COMPLIANT" }
    Write-Host "  [$status] $($esxi.Name) -> LockdownMode = $mode" -ForegroundColor $color
    if (-not $ok) { $nc_321 += "$($esxi.Name) (mode=$mode)" }
}
Set-CheckResult "3.21" $allHosts.Count $nc_321
Write-CheckFooter "3.21" "host"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Module 3 completato." -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
