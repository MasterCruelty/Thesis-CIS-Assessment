# =============================================================================
# CIS VMware ESXi Benchmark - Module 6: FEATURES  (6.3.1) 
# =============================================================================
$RootDir   = Split-Path -Parent $ScriptDir
. (Join-Path $RootDir "module_utils.ps1")


Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  CIS VMware - Module 6: FEATURES CHECKS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""


# 6.3.1 Host iSCSI client must employ bidirectional/mutual CHAP authentication
Write-CheckHeader "6.3.1" 
Write-Host "        NOTE: Applicabile solo se iSCSI e' in uso." -ForegroundColor DarkGray
Write-Host ""

$iscsiAdapters = @(Get-VMHost | Get-VMHostHba | Where-Object { $_.Type -eq "Iscsi" })

if ($iscsiAdapters.Count -gt 0) {
    $nc = @()
    foreach ($adpt in $iscsiAdapters) {
        $ok     = ($adpt.ChapType -in @("Mutual","Required"))
        $color  = if ($ok) { "Green" } else { "Red" }
        $status = if ($ok) { "COMPLIANT" } else { "NON-COMPLIANT" }
        Write-Host "  [$status] Host: $($adpt.VMHost) | Adapter: $($adpt.Device) | ChapType: $($adpt.ChapType)" -ForegroundColor $color
        if (-not $ok) { $nc += "Host=$($adpt.VMHost) Adapter=$($adpt.Device) (ChapType=$($adpt.ChapType))" }
    }
    Set-CheckResult "6.3.1" $iscsiAdapters.Count $nc
} else {
    Write-Host "  [N/A] Nessun adapter iSCSI trovato." -ForegroundColor Gray
    Set-CheckResult "6.3.1" 0 @() "N/A"
}
Write-CheckFooter "6.3.1" "adapter"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Module 6 completato." -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
