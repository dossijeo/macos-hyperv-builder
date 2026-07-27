[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OpenCoreDirectory,
    [Parameter(Mandatory)][string]$LiluDirectory,
    [Parameter(Mandatory)][string]$VirtualSMCDirectory,
    [Parameter(Mandatory)][string]$MacHyperVDirectory,
    [Parameter(Mandatory)][string]$PatchedKextDirectory,
    [Parameter(Mandatory)][string]$Config,
    [string]$AcpiDirectory = (Join-Path $PSScriptRoot '..\config\acpi'),
    [Parameter(Mandatory)][string]$Destination
)

$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $Destination) {
    throw "Refusing to replace existing EFI staging directory: $Destination"
}

$ocEfi = Get-ChildItem -Recurse -Directory -LiteralPath $OpenCoreDirectory |
    Where-Object { $_.FullName -match '[\\/]X64[\\/]EFI$' } |
    Select-Object -First 1
if (-not $ocEfi) { throw 'OpenCore X64/EFI directory was not found.' }

New-Item -ItemType Directory -Force -Path $Destination | Out-Null
Copy-Item -LiteralPath $ocEfi.FullName -Destination $Destination -Recurse
$efi = Join-Path $Destination 'EFI'
$oc = Join-Path $efi 'OC'
Copy-Item -LiteralPath $Config -Destination (Join-Path $oc 'config.plist') -Force

$kextDestination = Join-Path $oc 'Kexts'
New-Item -ItemType Directory -Force -Path $kextDestination | Out-Null
$wantedKexts = @(
    @{ Root = $LiluDirectory; Name = 'Lilu.kext' },
    @{ Root = $VirtualSMCDirectory; Name = 'VirtualSMC.kext' },
    @{ Root = $VirtualSMCDirectory; Name = 'SMCBatteryManager.kext' },
    @{ Root = $VirtualSMCDirectory; Name = 'SMCSuperIO.kext' },
    @{ Root = $MacHyperVDirectory; Name = 'MacHyperVSupport.kext' },
    @{ Root = $PatchedKextDirectory; Name = 'MacHyperVSupportMonterey.kext' },
    @{ Root = $PatchedKextDirectory; Name = 'MacHyperVFramebuffer.kext' }
)
foreach ($wanted in $wantedKexts) {
    $source = Get-ChildItem -Recurse -Directory -LiteralPath $wanted.Root |
        Where-Object Name -eq $wanted.Name | Select-Object -First 1
    if (-not $source) { throw "Required kext not found: $($wanted.Name)" }
    Copy-Item -LiteralPath $source.FullName -Destination $kextDestination -Recurse
}

$acpiDestination = Join-Path $oc 'ACPI'
New-Item -ItemType Directory -Force -Path $acpiDestination | Out-Null
foreach ($name in 'SSDT-HV-DEV.aml','SSDT-HV-DEV-WS2022.aml',
    'SSDT-HV-PLUG.aml','SSDT-HV-VMBUS.aml') {
    $source = Get-ChildItem -Recurse -File -LiteralPath $AcpiDirectory `
        -Filter $name | Select-Object -First 1
    if (-not $source) { throw "Required ACPI table not found: $name" }
    Copy-Item -LiteralPath $source.FullName -Destination $acpiDestination
}

$validator = Get-ChildItem -Recurse -File -LiteralPath $OpenCoreDirectory `
    -Filter ocvalidate.exe | Select-Object -First 1
if (-not $validator) { throw 'ocvalidate.exe was not found.' }
& $validator.FullName (Join-Path $oc 'config.plist')
if ($LASTEXITCODE -ne 0) { throw "ocvalidate failed with exit code $LASTEXITCODE" }

Get-Item -LiteralPath $efi
