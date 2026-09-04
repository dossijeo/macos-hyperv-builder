[CmdletBinding()]
param(
    [ValidateRange(1, 65535)]
    [int]$Port = 4010,
    [switch]$RemoveLogs
)

$ErrorActionPreference = 'Stop'
$installDirectory = Join-Path $env:LOCALAPPDATA 'MacHyperVAudio'
$installedReceiver = Join-Path $installDirectory 'receiver.ps1'
$receiverPattern = [regex]::Escape($installedReceiver)

Get-CimInstance Win32_Process |
    Where-Object {
        ($_.Name -ieq 'powershell.exe' -and
            $_.CommandLine -match $receiverPattern) -or
        ($_.Name -ieq 'ffplay.exe' -and
            $_.CommandLine -match "0\.0\.0\.0:$Port")
    } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

$shortcutPath = Join-Path `
    ([Environment]::GetFolderPath('Startup')) `
    'Mac Hyper-V Audio Receiver.lnk'
Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $installedReceiver -Force -ErrorAction SilentlyContinue
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if ($principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )) {
    Get-NetFirewallRule -DisplayName "macOS Hyper-V Audio UDP $Port" `
        -ErrorAction SilentlyContinue | Remove-NetFirewallRule
}

if ($RemoveLogs -and (Test-Path -LiteralPath $installDirectory)) {
    Remove-Item -LiteralPath $installDirectory -Recurse -Force
}

Write-Host 'Windows audio receiver removed.'
