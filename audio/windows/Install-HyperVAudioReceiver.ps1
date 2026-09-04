[CmdletBinding()]
param(
    [string]$FfplayPath,
    [ValidateRange(1, 65535)]
    [int]$Port = 4010
)

$ErrorActionPreference = 'Stop'

if (-not $FfplayPath) {
    $command = Get-Command ffplay.exe -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) {
        $FfplayPath = $command.Source
    }
    elseif (Test-Path -LiteralPath 'C:\ffmpeg\bin\ffplay.exe') {
        $FfplayPath = 'C:\ffmpeg\bin\ffplay.exe'
    }
}
if (-not $FfplayPath -or
    -not (Test-Path -LiteralPath $FfplayPath -PathType Leaf)) {
    throw 'ffplay.exe was not found. Install FFmpeg or pass -FfplayPath.'
}
$FfplayPath = (Resolve-Path -LiteralPath $FfplayPath).Path

$installDirectory = Join-Path $env:LOCALAPPDATA 'MacHyperVAudio'
$installedReceiver = Join-Path $installDirectory 'receiver.ps1'
$sourceReceiver = Join-Path $PSScriptRoot 'receiver.ps1'
New-Item -ItemType Directory -Force -Path $installDirectory | Out-Null
Copy-Item -LiteralPath $sourceReceiver -Destination $installedReceiver -Force

$receiverPattern = [regex]::Escape($installedReceiver)
Get-CimInstance Win32_Process |
    Where-Object {
        ($_.Name -ieq 'powershell.exe' -and
            $_.CommandLine -match $receiverPattern) -or
        ($_.Name -ieq 'ffplay.exe' -and
            $_.CommandLine -match "0\.0\.0\.0:$Port")
    } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

$ruleName = "macOS Hyper-V Audio UDP $Port"
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdministrator = $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if ($isAdministrator) {
    Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule
    New-NetFirewallRule `
        -DisplayName $ruleName `
        -Direction Inbound `
        -Action Allow `
        -Protocol UDP `
        -LocalPort $Port `
        -Program $FfplayPath `
        -Profile Private | Out-Null
}
else {
    Write-Warning (
        'The receiver was installed without a firewall rule. If Windows ' +
        'blocks it, rerun this installer from an elevated PowerShell.'
    )
}

$startupDirectory = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startupDirectory 'Mac Hyper-V Audio Receiver.lnk'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$shortcut.Arguments = @(
    '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass'
    "-File `"$installedReceiver`""
    "-FfplayPath `"$FfplayPath`""
    "-Port $Port"
) -join ' '
$shortcut.WorkingDirectory = $installDirectory
$shortcut.Save()

Start-Process `
    -FilePath $shortcut.TargetPath `
    -ArgumentList $shortcut.Arguments `
    -WorkingDirectory $installDirectory `
    -WindowStyle Hidden

for ($attempt = 0; $attempt -lt 20; $attempt++) {
    Start-Sleep -Milliseconds 500
    $processes = Get-CimInstance Win32_Process
    $receiver = $processes |
        Where-Object {
            $_.Name -ieq 'powershell.exe' -and
            $_.CommandLine -match $receiverPattern
        } |
        Select-Object -First 1
    $player = $processes |
        Where-Object {
            $_.Name -ieq 'ffplay.exe' -and
            $_.CommandLine -match "0\.0\.0\.0:$Port"
        } |
        Select-Object -First 1
    if ($receiver -and $player) {
        break
    }
}
if (-not $receiver) {
    throw "The receiver did not start. Check $installDirectory\receiver.log."
}
if (-not $player) {
    throw "ffplay did not start. Check $installDirectory\receiver.log."
}

Write-Host "Windows audio receiver is listening on UDP port $Port."
