[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$MacRecoveryPy,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$BoardId = 'Mac-827FAC58A8FDFA22',
    [string]$MLB = '00000000000000000'
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
Push-Location $OutputDirectory
try {
    # Apple recovery content is fetched from Apple by OpenCore's macrecovery.
    & python $MacRecoveryPy -b $BoardId -m $MLB -os latest download
    if ($LASTEXITCODE -ne 0) {
        throw "macrecovery failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
