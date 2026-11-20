# Runs ci.ps1 directly on a built fixture and records its exit code as a step output,
# so test.yml can compare it with the composite action's verdict.
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [ValidateSet('true', 'false')]
    [string]$AllowNoTests
)

$arguments = @{ Path = $Path; ModuleManifest = 'Clean.psm1' }
if ($AllowNoTests -eq 'true') { $arguments.AllowNoTests = $true }
& (Join-Path (Split-Path -Parent $PSScriptRoot) 'ci.ps1') @arguments
$exitCode = $LASTEXITCODE
Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "exit-code=$exitCode"
Write-Output "ci.ps1 exited $exitCode"
