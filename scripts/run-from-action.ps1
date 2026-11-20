# Validates the action's inputs, which arrive as strings in environment variables,
# then runs ci.ps1 with them.
$ErrorActionPreference = 'Stop'

foreach ($name in 'PWSH_CI_PATH', 'PWSH_CI_SETTINGS', 'PWSH_CI_TESTS') {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
        Write-Output "pwsh-ci: inputs: FAILED - input '$($name.Substring(8).ToLowerInvariant().Replace('_', '-'))' is empty"
        exit 1
    }
}
if ($env:PWSH_CI_ALLOW_NO_TESTS -cnotin 'true', 'false') {
    Write-Output "pwsh-ci: inputs: FAILED - input 'allow-no-tests' must be true or false, got '$env:PWSH_CI_ALLOW_NO_TESTS'"
    exit 1
}

$arguments = @{
    Path           = $env:PWSH_CI_PATH
    Settings       = $env:PWSH_CI_SETTINGS
    ModuleManifest = $env:PWSH_CI_MODULE_MANIFEST
    Tests          = $env:PWSH_CI_TESTS
    AllowNoTests   = $env:PWSH_CI_ALLOW_NO_TESTS -ceq 'true'
}
& (Join-Path (Split-Path -Parent $PSScriptRoot) 'ci.ps1') @arguments
exit $LASTEXITCODE
