[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$SystemDisk,
    [Parameter(Mandatory)][string]$UefiDisk,
    [string]$RecoveryDisk,
    [string]$SwitchName,
    [UInt64]$MemoryBytes = 16GB,
    [int]$Processors = 4,
    [string]$MacAddress
)

#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
if (Get-VM -Name $Name -ErrorAction SilentlyContinue) {
    throw "A VM named '$Name' already exists."
}

$vm = New-VM -Name $Name -Generation 2 -MemoryStartupBytes $MemoryBytes `
    -VHDPath $SystemDisk -SwitchName $SwitchName
$vm | Set-VM -ProcessorCount $Processors -AutomaticStopAction ShutDown `
    -AutomaticCheckpointsEnabled $false
$vm | Set-VMMemory -DynamicMemoryEnabled $false
$vm | Set-VMFirmware -EnableSecureBoot Off

Add-VMHardDiskDrive -VM $vm -ControllerType SCSI -ControllerNumber 0 `
    -ControllerLocation 1 -Path $UefiDisk
if ($RecoveryDisk) {
    Add-VMHardDiskDrive -VM $vm -ControllerType SCSI -ControllerNumber 0 `
        -ControllerLocation 2 -Path $RecoveryDisk
}
if ($MacAddress) {
    $vm | Get-VMNetworkAdapter | Set-VMNetworkAdapter -StaticMacAddress $MacAddress
}

$uefi = $vm | Get-VMHardDiskDrive |
    Where-Object ControllerLocation -eq 1
$vm | Set-VMFirmware -FirstBootDevice $uefi
$vm | Select-Object Name,Id,State,ProcessorCount,MemoryStartup,
    AutomaticStopAction,AutomaticCheckpointsEnabled

