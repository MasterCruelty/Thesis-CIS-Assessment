# =============================================================================
# CIS VMware ESXi Benchmark - Module 4: LOGGING  (4.2)
# =============================================================================
$RootDir   = Split-Path -Parent $ScriptDir
. (Join-Path $RootDir "module_utils.ps1")


Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  CIS VMware - Module 4: LOGGING CHECKS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# 4.2 - Remote syslog  
Test-HostAdvSettingCheck "4.2"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Module 4 completato." -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
