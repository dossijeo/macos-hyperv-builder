[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$MacSerial,
    [string]$ProductName = 'MacBookAir8,1',
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\state\identity.json')
)

$ErrorActionPreference = 'Stop'
$line = & $MacSerial -m $ProductName -n 1 | Select-Object -First 1
$parts = @($line -split '\s*\|\s*')
if ($parts.Count -lt 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or
    [string]::IsNullOrWhiteSpace($parts[1])) {
    throw "Unable to parse macserial output: $line"
}

$rom = New-Object byte[] 6
[Security.Cryptography.RandomNumberGenerator]::Fill($rom)
$rom[0] = ($rom[0] -band 0xFC) -bor 0x02
$romHex = ($rom | ForEach-Object { $_.ToString('X2') }) -join ''

$identity = [ordered]@{
    ProductName = $ProductName
    SystemSerialNumber = $parts[0]
    MLB = $parts[1]
    SystemUUID = [Guid]::NewGuid().ToString().ToUpperInvariant()
    ROM = $romHex
    HyperVMacAddress = $romHex
}

$parent = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$identity | ConvertTo-Json | Set-Content -LiteralPath $OutputPath -Encoding utf8
$identity

