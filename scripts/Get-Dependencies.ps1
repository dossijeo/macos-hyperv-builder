[CmdletBinding()]
param(
    [string]$Manifest = (Join-Path $PSScriptRoot '..\manifests\tahoe-26.json'),
    [string]$Destination = (Join-Path $PSScriptRoot '..\.cache')
)

$ErrorActionPreference = 'Stop'
$profile = Get-Content -Raw -LiteralPath $Manifest | ConvertFrom-Json
New-Item -ItemType Directory -Force -Path $Destination | Out-Null

foreach ($dependency in $profile.dependencies) {
    $archive = Join-Path $Destination "$($dependency.name)-$($dependency.version).zip"
    if (-not (Test-Path -LiteralPath $archive)) {
        Invoke-WebRequest -Uri $dependency.url -OutFile $archive
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
    if ($actual -ne $dependency.sha256) {
        throw "Checksum mismatch for $($dependency.name): $actual"
    }
    $expanded = Join-Path $Destination "$($dependency.name)-$($dependency.version)"
    if (-not (Test-Path -LiteralPath $expanded)) {
        Expand-Archive -LiteralPath $archive -DestinationPath $expanded
    }
    [pscustomobject]@{
        Name = $dependency.name
        Version = $dependency.version
        Archive = $archive
        Expanded = $expanded
        SHA256 = $actual
    }
}

