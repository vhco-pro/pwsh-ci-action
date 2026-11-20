# Builds one fixture case for test.yml and writes its settings as step outputs.
param(
    [Parameter(Mandatory = $true)]
    [string]$Name,

    [Parameter(Mandatory = $true)]
    [string]$Destination
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'cases.ps1')

$case = Build-Fixture -Name $Name -Destination $Destination
if ($env:GITHUB_OUTPUT) {
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "expect-exit=$($case.ExpectExit)"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "allow-no-tests=$($case.AllowNoTests.ToString().ToLowerInvariant())"
}
