[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$FfplayPath,
    [ValidateRange(1, 65535)]
    [int]$Port = 4010,
    [string]$BindAddress = '0.0.0.0'
)

$ErrorActionPreference = 'SilentlyContinue'
$logDirectory = Join-Path $env:LOCALAPPDATA 'MacHyperVAudio'
$logFile = Join-Path $logDirectory 'receiver.log'
$udpInput = "udp://${BindAddress}:${Port}?fifo_size=1000000&overrun_nonfatal=1"
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null

$createdNew = $false
$mutexName = "Local\MacHyperVAudioReceiver-$Port"
$mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
if (-not $createdNew) {
    exit 0
}

try {
    while ($true) {
        if (-not (Test-Path -LiteralPath $FfplayPath -PathType Leaf)) {
            "$(Get-Date -Format o) ffplay not found at $FfplayPath" |
                Add-Content -LiteralPath $logFile
            Start-Sleep -Seconds 30
            continue
        }

        & $FfplayPath `
            -nodisp `
            -loglevel warning `
            -fflags nobuffer `
            -flags low_delay `
            -probesize 32 `
            -analyzeduration 0 `
            -f s16le `
            -ar 48000 `
            -ch_layout stereo `
            -i $udpInput 2>> $logFile

        "$(Get-Date -Format o) ffplay exited; restarting in 2 seconds" |
            Add-Content -LiteralPath $logFile
        Start-Sleep -Seconds 2
    }
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
