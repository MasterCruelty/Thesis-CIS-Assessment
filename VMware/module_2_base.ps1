# =============================================================================
# CIS VMware ESXi Benchmark  
# Module 2: BASE  (2.4, 2.6, 2.10)
# =============================================================================
$RootDir   = Split-Path -Parent $ScriptDir
. (Join-Path $RootDir "module_utils.ps1")

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  CIS VMware - Module 2: BASE CHECKS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# -----------------------------------------------------------------------------
# CHECK 2.4 - VIB(vSphere Installation Bundle) acceptance level  
# -----------------------------------------------------------------------------
Write-CheckHeader "2.4" 
$allHosts = @(Get-VMHost)
$nc_24 = @()
foreach ($esxi in $allHosts) {
    $ESXCli = Get-EsxCli -VMHost $esxi
    $level  = $ESXCli.software.acceptance.get()
    $ok     = $level -in @("VMwareCertified","VMwareAccepted","PartnerSupported")
    $color  = if ($ok) { "Green" } else { "Red" }
    $status = if ($ok) { "COMPLIANT" } else { "NON-COMPLIANT" }
    Write-Host "  [$status] $($esxi.Name) -> $level" -ForegroundColor $color
    if (-not $ok) { $nc_24 += "$($esxi.Name) (level=$level)" }
}
Set-CheckResult "2.4" $allHosts.Count $nc_24
Write-CheckFooter "2.4" "host"

# -----------------------------------------------------------------------------
# CHECK 2.6 - NTP  
# -----------------------------------------------------------------------------
Write-CheckHeader "2.6" 
$nc_26 = @()
foreach ($esxi in $allHosts) {
    $ntp = Get-VMHostNtpServer $esxi
    $svc = Get-VMHostService $esxi | Where-Object { $_.Key -eq "ntpd" }
    $ok  = ($ntp.Count -gt 0 -and $svc.Running)
    $color  = if ($ok) { "Green" } else { "Red" }
    $status = if ($ok) { "COMPLIANT" } else { "NON-COMPLIANT" }
    Write-Host "  [$status] $($esxi.Name) -> NTP: $($ntp -join ', ') | ntpd running: $($svc.Running)" -ForegroundColor $color
    if (-not $ok) { $nc_26 += "$($esxi.Name) (ntp=$($ntp.Count) servers, running=$($svc.Running))" }
}
Set-CheckResult "2.6" $allHosts.Count $nc_26
Write-CheckFooter "2.6" "host"

# -----------------------------------------------------------------------------
# CHECK 2.10 - Mem.ShareForceSalting  
# -----------------------------------------------------------------------------
Test-HostAdvSettingCheck "2.10"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Module 2 completato." -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
