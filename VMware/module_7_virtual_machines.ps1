# =============================================================================
# CIS VMware ESXi Benchmark - Module 7: VIRTUAL MACHINES 
# (7.4, 7.5, 7.6, 7.7, 7.8, 7.9, 7.12, 7.13, 7.14, 7.15, 7.16, 7.17, 7.18, 7.19,
#  7.20, 7.21, 7.22, 7.23, 7.24, 7.25, 7.26, 7.27)
# =============================================================================
$RootDir   = Split-Path -Parent $ScriptDir
. (Join-Path $RootDir "module_utils.ps1")


Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  CIS VMware - Module 7: VIRTUAL MACHINES CHECKS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$allVMs = @(Get-VM)


# 7.4  Virtual machines should deactivate 3D graphics features when not required
Test-VMAdvSettingCheck "7.4" 

# 7.5  Virtual machines must be configured to lock when the last console connection is closed
Test-VMAdvSettingCheck "7.5" 

# 7.6  Virtual machines must limit console sharing
Test-VMAdvSettingCheck "7.6" 

# 7.7 limit PCI passthrough functionality
Write-CheckHeader "7.7" 
$pciDevices = @(Get-VM | Get-AdvancedSetting -Name "pciPassthru*.present" -ErrorAction SilentlyContinue)
$nc_77 = @()
if ($pciDevices.Count -gt 0) {
    foreach ($pci in $pciDevices) {
        Write-Host "  [NON-COMPLIANT] VM: $($pci.Entity) -> $($pci.Name) = $($pci.Value)" -ForegroundColor Red
        $nc_77 += "VM=$($pci.Entity) ($($pci.Name))"
    }
} else {
    Write-Host "  [COMPLIANT] Nessun dispositivo PCI/PCIe passthrough trovato." -ForegroundColor Green
}
Set-CheckResult "7.7" $allVMs.Count $nc_77
Write-CheckFooter "7.7" "VM"

# 7.8  Ensure unauthorized modification and disconnection of devices is disabled
Test-VMAdvSettingCheck "7.8" 

# 7.9  Virtual machines must prevent unauthorized connection of devices
Test-VMAdvSettingCheck "7.9" 

# 7.12 Virtual machines must remove unnecessary USB/XHCI devices
Test-VMDevice "7.12" { Get-VM | Get-USBDevice -ErrorAction SilentlyContinue }

# 7.13 Virtual machines must remove unnecessary serial port devices
Write-CheckHeader "7.13"
$serial = @(Get-VM | ForEach-Object {
            $vm = $_
            $vm.ExtensionData.Config.Hardware.Device |
            Where-Object { $_ -is [VMware.Vim.VirtualSerialPort] } |
            ForEach-Object { [PSCustomObject]@{ VMName = $vm.Name; DeviceLabel = $_.DeviceInfo.Label } }
            })            
$nc_713 = @()
foreach ($s in $serial) {
        Write-Host "  [NON-COMPLIANT] VM: $($s.VMName) -> $($s.DeviceLabel)" -ForegroundColor Red
        $nc_713 += "VM=$($s.VMName) Device=$($s.DeviceLabel)"
    }
if ($serial.Count -eq 0) { Write-Host "  [COMPLIANT] Nessuna porta seriale trovata." -ForegroundColor Green }
Set-CheckResult "7.13" $allVMs.Count $nc_713

Write-CheckFooter "7.13" "VM"

# 7.14 Virtual machines must remove unnecessary parallel port devices 
Write-CheckHeader "7.14" 
#$parallelCmd = Get-Command "Get-ParallelPort" -ErrorAction SilentlyContinue
#if ($parallelCmd) {
    #$parallel = @(Get-VM | Get-ParallelPort -ErrorAction SilentlyContinue)
    $parallel = @(Get-VM | ForEach-Object {
                $_.ExtensionData.Config.Hardware.Device |
                Where-Object { $_ -is [VMware.Vim.VirtualParallelPort] }
                })
    $nc_714 = @()
    foreach ($p in $parallel) {
        Write-Host "  [NON-COMPLIANT] VM: $($p.Parent.Name) -> $($p.Name)" -ForegroundColor Red
        $nc_714 += "VM=$($p.Parent.Name) Device=$($p.Name)"
    }
    if ($parallel.Count -eq 0) { Write-Host "  [COMPLIANT] Nessuna porta parallela trovata." -ForegroundColor Green }
    Set-CheckResult "7.14" $allVMs.Count $nc_714
#} else {
#    Write-Host "  [UNKNOWN] Get-ParallelPort non disponibile - verificare manualmente." -ForegroundColor DarkYellow
#    Set-CheckResult "7.14" $allVMs.Count @() "UNKNOWN"
#}
Write-CheckFooter "7.14" "VM"

# 7.15 Virtual machines must remove unnecessary CD/DVD devices 
Write-CheckHeader "7.15" 
$cdDrives = @(Get-VM | Get-CDDrive -ErrorAction SilentlyContinue |
    Where-Object { $_.ConnectionState.Connected -eq $true -or $_.IsoPath -ne $null })
$nc_715 = @()
foreach ($cd in $cdDrives) {
    Write-Host "  [NON-COMPLIANT] VM: $($cd.Parent.Name) -> $($cd.Name) ISO=$($cd.IsoPath)" -ForegroundColor Red
    $nc_715 += "VM=$($cd.Parent.Name) Device=$($cd.Name)"
}
if ($cdDrives.Count -eq 0) { Write-Host "  [COMPLIANT] Nessun CD/DVD connesso." -ForegroundColor Green }
Set-CheckResult "7.15" $allVMs.Count $nc_715
Write-CheckFooter "7.15" "VM"

# 7.16 Virtual machines must remove unnecessary floppy devices
Test-VMDevice "7.16" { Get-VM | Get-FloppyDrive -ErrorAction SilentlyContinue }

# 7.17 - 7.27  Virtual machines must deactivate:
# (console drag and drop, console copy, console paste, virtual disk shrinking operations,  virtual disk wiping)
# Virtual machines must not be able to obtain host information from the hypervisor (7.24)
# Virtual machines must limit: (the number of retained, the size of diagnostic logs)
Test-VMAdvSettingCheck "7.17" 
Test-VMAdvSettingCheck "7.18" 
Test-VMAdvSettingCheck "7.19" 
Test-VMAdvSettingCheck "7.21" 
Test-VMAdvSettingCheck "7.22" 
Test-VMAdvSettingCheck "7.24" 
Test-VMAdvSettingCheck "7.26" 
Test-VMAdvSettingCheck "7.27" 

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Module 7 completato." -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
