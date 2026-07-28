[CmdletBinding()]
param(
    [string]$Manifest = (Join-Path $PSScriptRoot 'manifests\tahoe-26.json'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'artifacts'),
    [string]$SwitchName,
    [string]$PatchedKextArchive,
    [switch]$CreateVM,
    [switch]$DownloadRecovery,
    [switch]$StartVM
)

#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$profile = Get-Content -Raw -LiteralPath $Manifest | ConvertFrom-Json
$cache = Join-Path $PSScriptRoot '.cache'
$state = Join-Path $PSScriptRoot 'state'
New-Item -ItemType Directory -Force -Path $OutputDirectory,$state | Out-Null

$guestTools = Join-Path $OutputDirectory 'guest-tools'
New-Item -ItemType Directory -Force -Path $guestTools | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot 'guest\*') `
    -Destination $guestTools -Recurse -Force
$guestPatches = Join-Path $guestTools 'patches'
New-Item -ItemType Directory -Force -Path $guestPatches | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot 'patches\*cpu-raster*.patch') `
    -Destination $guestPatches -Force

$dependencies = @(
    & (Join-Path $PSScriptRoot 'scripts\Get-Dependencies.ps1') `
        -Manifest $Manifest -Destination $cache
)
$openCore = $dependencies | Where-Object Name -eq OpenCore
$lilu = $dependencies | Where-Object Name -eq Lilu
$virtualSMC = $dependencies | Where-Object Name -eq VirtualSMC
$macHyperV = $dependencies | Where-Object Name -eq MacHyperVSupport
$patchedDependency = $dependencies | Where-Object Name -eq TahoeHyperVKexts
$macSerial = Get-ChildItem -Recurse -LiteralPath $openCore.Expanded `
    -Filter macserial.exe | Select-Object -First 1
if (-not $macSerial) { throw 'macserial.exe was not found in OpenCore.' }

$identityPath = Join-Path $state 'identity.json'
if (-not (Test-Path -LiteralPath $identityPath)) {
    & (Join-Path $PSScriptRoot 'scripts\New-MachineIdentity.ps1') `
        -MacSerial $macSerial.FullName `
        -ProductName $profile.identity.productName `
        -OutputPath $identityPath | Out-Host
}
$identity = Get-Content -Raw -LiteralPath $identityPath | ConvertFrom-Json

$config = Join-Path $OutputDirectory 'config.plist'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'config\opencore.template.plist') `
    -Destination $config -Force
& python (Join-Path $PSScriptRoot 'scripts\Set-OpenCoreIdentity.py') $config `
    --product $identity.ProductName `
    --serial $identity.SystemSerialNumber `
    --mlb $identity.MLB `
    --uuid $identity.SystemUUID `
    --rom $identity.ROM

if (-not $PatchedKextArchive -and $patchedDependency) {
    $PatchedKextArchive = $patchedDependency.Archive
}
if (-not $PatchedKextArchive) {
    throw 'A patched Tahoe kext archive is required. Use -PatchedKextArchive or a manifest containing TahoeHyperVKexts.'
}
$patchedDirectory = Join-Path $cache 'TahoeHyperVKexts'
if (-not (Test-Path -LiteralPath $patchedDirectory)) {
    Expand-Archive -LiteralPath $PatchedKextArchive -DestinationPath $patchedDirectory
}

$efiTree = Join-Path $OutputDirectory 'uefi-tree'
if (-not (Test-Path -LiteralPath $efiTree)) {
    & (Join-Path $PSScriptRoot 'scripts\New-EfiTree.ps1') `
        -OpenCoreDirectory $openCore.Expanded `
        -LiluDirectory $lilu.Expanded `
        -VirtualSMCDirectory $virtualSMC.Expanded `
        -MacHyperVDirectory $macHyperV.Expanded `
        -PatchedKextDirectory $patchedDirectory `
        -Config $config `
        -Destination $efiTree | Out-Host
}

$uefiVhdx = Join-Path $OutputDirectory 'UEFI.vhdx'
if (-not (Test-Path -LiteralPath $uefiVhdx)) {
    & (Join-Path $PSScriptRoot 'scripts\New-FatVhdx.ps1') `
        -Path $uefiVhdx `
        -SizeBytes ([UInt64]$profile.vm.uefiDiskBytes) `
        -SourceDirectory $efiTree `
        -Label OPENCORE
}

$recovery = $null
if ($DownloadRecovery) {
    $macRecovery = Get-ChildItem -Recurse -LiteralPath $openCore.Expanded `
        -Filter macrecovery.py | Select-Object -First 1
    $recovery = Join-Path $OutputDirectory 'recovery'
    & (Join-Path $PSScriptRoot 'scripts\Get-AppleRecovery.ps1') `
        -MacRecoveryPy $macRecovery.FullName -OutputDirectory $recovery
}

if ($CreateVM) {
    if (-not $SwitchName) {
        throw '-SwitchName is required with -CreateVM.'
    }
    if (-not $recovery -or -not (Test-Path -LiteralPath $recovery)) {
        throw '-CreateVM requires -DownloadRecovery.'
    }
    $recoveryVhdx = Join-Path $OutputDirectory 'Recovery.vhdx'
    if (-not (Test-Path -LiteralPath $recoveryVhdx)) {
        & (Join-Path $PSScriptRoot 'scripts\New-FatVhdx.ps1') `
            -Path $recoveryVhdx `
            -SizeBytes ([UInt64]$profile.vm.recoveryDiskBytes) `
            -SourceDirectory $recovery `
            -Label RECOVERY
    }
    $systemVhdx = Join-Path $OutputDirectory 'macOS.vhdx'
    if (-not (Test-Path -LiteralPath $systemVhdx)) {
        New-VHD -Path $systemVhdx -Dynamic `
            -SizeBytes ([UInt64]$profile.vm.systemDiskBytes) | Out-Null
    }
    $vmName = $profile.vm.name
    & (Join-Path $PSScriptRoot 'scripts\New-HyperVVM.ps1') `
        -Name $vmName `
        -SystemDisk $systemVhdx `
        -UefiDisk $uefiVhdx `
        -RecoveryDisk $recoveryVhdx `
        -SwitchName $SwitchName `
        -MemoryBytes ([UInt64]$profile.vm.memoryBytes) `
        -Processors ([int]$profile.vm.processors) `
        -MacAddress $identity.HyperVMacAddress | Out-Host
    if ($StartVM) {
        Start-VM -Name $vmName
    }
}

[pscustomobject]@{
    Profile = $profile.profile
    Identity = $identityPath
    Config = $config
    UefiTree = $efiTree
    UefiVhdx = $uefiVhdx
    Recovery = $recovery
    GuestTools = $guestTools
    Status = if ($CreateVM) { 'Hyper-V VM created.' } else { 'EFI staged and validated.' }
} | Format-List
