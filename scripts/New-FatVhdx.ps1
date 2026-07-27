[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][UInt64]$SizeBytes,
    [Parameter(Mandatory)][string]$SourceDirectory,
    [string]$Label = 'OPENCORE'
)

$ErrorActionPreference = 'Stop'
$resolvedSource = (Resolve-Path -LiteralPath $SourceDirectory).Path
$resolvedTarget = [IO.Path]::GetFullPath($Path)
$parent = Split-Path -Parent $resolvedTarget
New-Item -ItemType Directory -Force -Path $parent | Out-Null
if (Test-Path -LiteralPath $resolvedTarget) {
    throw "Refusing to overwrite existing disk: $resolvedTarget"
}

$mounted = $false
try {
    $disk = New-VHD -Path $resolvedTarget -Dynamic -SizeBytes $SizeBytes |
        Mount-VHD -Passthru
    $mounted = $true
    Initialize-Disk -Number $disk.DiskNumber -PartitionStyle GPT
    $partition = New-Partition -DiskNumber $disk.DiskNumber -UseMaximumSize -AssignDriveLetter
    Format-Volume -Partition $partition -FileSystem FAT32 -NewFileSystemLabel $Label -Confirm:$false
    $root = "$($partition.DriveLetter):\"
    Copy-Item -Path (Join-Path $resolvedSource '*') -Destination $root -Recurse -Force
}
finally {
    if ($mounted) {
        Dismount-VHD -Path $resolvedTarget -ErrorAction SilentlyContinue
    }
}

