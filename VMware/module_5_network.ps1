# =============================================================================
# CIS VMware ESXi Benchmark - Module 5: NETWORK
# Checks: 5.6, 5.7, 5.8, 5.9, 5.10  
# =============================================================================
$RootDir   = Split-Path -Parent $ScriptDir
. (Join-Path $RootDir "module_utils.ps1")


Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  CIS VMware - Module 5: NETWORK CHECKS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# estrazione informazioni  portgroups
$portGroups = @(Get-VirtualPortGroup -Standard)

# 5.6 reject transmit on standard virtual switch
Test-vSwitchSecurity "5.6" "ForgedTransmits"
# 5.7  reject mac address changes on standard virtual switch
Test-vSwitchSecurity "5.7" "MacChanges"
# 5.8  reject promiscuous mode requests on standard virtual switch
Test-vSwitchSecurity "5.8" "PromiscuousMode"

# 5.9  restrict access to a default or native VLAN on standard virtual switch
Write-CheckHeader "5.9" 
$nc_59 = @()
foreach ($pg in $portGroups) {
    $ok     = ($pg.VlanId -ne 1)
    $color  = if ($ok) { "Green" } else { "Red" }
    $status = if ($ok) { "COMPLIANT" } else { "NON-COMPLIANT" }
    Write-Host "  [$status] Switch: $($pg.VirtualSwitch) | PortGroup: $($pg.Name) -> VLAN ID = $($pg.VlanId)" -ForegroundColor $color
    if (-not $ok) { $nc_59 += "PortGroup=$($pg.Name) Switch=$($pg.VirtualSwitch)" }
}
Set-CheckResult "5.9" $portGroups.Count $nc_59
Write-CheckFooter "5.9" "port group"

# 5.10 - VLAN 4095  Host must restrict the use of Virtual Guest Tagging  (VGT) on standard virtual switches
Write-CheckHeader "5.10" "Virtual Guest Tagging (VLAN ID 4095) su port group"
$nc_510 = @()
foreach ($pg in $portGroups) {
    $ok     = ($pg.VlanId -ne 4095)
    $color  = if ($ok) { "Green" } else { "Red" }
    $status = if ($ok) { "OK" } else { "NON-COMPLIANT" }
    Write-Host "  [$status] Switch: $($pg.VirtualSwitch) | PortGroup: $($pg.Name) -> VLAN ID = $($pg.VlanId)" -ForegroundColor $color
    if (-not $ok) { $nc_510 += "PortGroup=$($pg.Name) Switch=$($pg.VirtualSwitch)" }
}
Set-CheckResult "5.10" $portGroups.Count $nc_510
Write-CheckFooter "5.10" "port group"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Module 5 completato." -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
