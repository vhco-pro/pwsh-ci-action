# Prints the fixture case names as a JSON array, for test.yml's matrix.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'cases.ps1')

$names = ConvertTo-Json -Compress -InputObject @($FixtureCases.Name)
if ($env:GITHUB_OUTPUT) {
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "names=$names"
}
Write-Output $names
