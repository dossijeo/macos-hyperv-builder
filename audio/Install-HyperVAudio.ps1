[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$GuestAddress,
    [Parameter(Mandatory)]
    [string]$GuestUser,
    [Parameter(Mandatory)]
    [string]$HostAddress,
    [string]$SshKey,
    [string]$FfplayPath,
    [ValidateRange(1, 65535)]
    [int]$Port = 4010
)

$ErrorActionPreference = 'Stop'

$parsedGuest = $null
$parsedHost = $null
if (-not [Net.IPAddress]::TryParse($GuestAddress, [ref]$parsedGuest) -or
    $parsedGuest.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
    throw "GuestAddress must be an IPv4 address: $GuestAddress"
}
if (-not [Net.IPAddress]::TryParse($HostAddress, [ref]$parsedHost) -or
    $parsedHost.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
    throw "HostAddress must be an IPv4 address: $HostAddress"
}
if ($GuestUser -notmatch '^[A-Za-z0-9._-]+$') {
    throw "GuestUser contains unsupported characters: $GuestUser"
}

$receiverArguments = @{
    Port = $Port
}
if ($FfplayPath) {
    $receiverArguments.FfplayPath = $FfplayPath
}
& (Join-Path $PSScriptRoot 'windows\Install-HyperVAudioReceiver.ps1') `
    @receiverArguments

$sshOptions = @()
if ($SshKey) {
    if (-not (Test-Path -LiteralPath $SshKey -PathType Leaf)) {
        throw "SSH key not found: $SshKey"
    }
    $sshOptions += @('-i', (Resolve-Path -LiteralPath $SshKey).Path)
}
$target = "${GuestUser}@${GuestAddress}"
$remoteDirectory = '~/macos-hyperv-audio-installer'

& ssh @sshOptions $target "mkdir -p ${remoteDirectory}"
if ($LASTEXITCODE -ne 0) {
    throw 'Could not prepare the macOS audio installer directory over SSH.'
}
$macFiles = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'macos') `
    -File | Select-Object -ExpandProperty FullName
& scp @sshOptions @macFiles "${target}:${remoteDirectory}/"
if ($LASTEXITCODE -ne 0) {
    throw 'Could not copy the macOS audio installer over SSH.'
}

$remoteCommand = @(
    "chmod +x ${remoteDirectory}/install.sh"
    "${remoteDirectory}/install.sh '$HostAddress' '$Port'"
) -join ' && '
& ssh @sshOptions -t $target $remoteCommand
if ($LASTEXITCODE -ne 0) {
    throw 'The macOS audio installation did not complete successfully.'
}

Write-Host 'Hyper-V audio is installed on the guest and host.'
