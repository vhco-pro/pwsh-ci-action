<#
.SYNOPSIS
    Runs the blocking PowerShell checks: settings, formatting, analysis, module loading and Pester.

.DESCRIPTION
    Installs the PSScriptAnalyzer and Pester versions pinned in modules.pins, refusing any
    package whose SHA-256 differs, then runs every check on -Path and changes no file.
    Prints one result line per check and exits 1 when any check fails.
#>
[CmdletBinding()]
param(
    [string]$Path = '.',
    [string]$Settings = 'PSScriptAnalyzerSettings.psd1',
    [string]$ModuleManifest = '',
    [string]$Tests = 'tests',
    [switch]$AllowNoTests,
    [string]$PinsFile = (Join-Path $PSScriptRoot 'modules.pins'),
    [string]$ModuleCache = (Join-Path ([IO.Path]::GetTempPath()) 'pwsh-ci-action-modules')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Formatting rules Invoke-Formatter applies when a settings file configures them.
$formattingRules = @(
    'PSPlaceOpenBrace', 'PSPlaceCloseBrace', 'PSUseConsistentWhitespace', 'PSUseConsistentIndentation',
    'PSAlignAssignmentStatement', 'PSUseCorrectCasing', 'PSAvoidTrailingWhitespace',
    'PSAvoidUsingCmdletAliases', 'PSAvoidUsingDoubleQuotesForConstantString',
    'PSAvoidSemicolonsAsLineTerminators', 'PSAvoidExclaimOperator'
)

$script:failed = [System.Collections.Generic.List[string]]::new()

function Write-CheckResult {
    param([string]$Check, [bool]$Passed, [string]$Detail = '')

    if ($Passed) {
        Write-Output "pwsh-ci: ${Check}: passed$(if ($Detail) { " ($Detail)" })"
    }
    else {
        $script:failed.Add($Check)
        Write-Output "pwsh-ci: ${Check}: FAILED - $Detail"
    }
}

function Exit-WithFailure {
    param([string]$Check, [string]$Detail)

    Write-CheckResult -Check $Check -Passed $false -Detail $Detail
    Write-Output "pwsh-ci: failed checks: $($script:failed -join ', ')"
    exit 1
}

function Import-PinnedModule {
    param([string]$Name, [string]$Version, [string]$Sha256, [string]$Cache)

    $destination = Join-Path $Cache $Name $Version
    $marker = Join-Path $destination '.pwsh-ci-sha256'
    if (-not ((Test-Path -LiteralPath $marker) -and ((Get-Content -LiteralPath $marker -Raw).Trim() -eq $Sha256))) {
        $download = Join-Path ([IO.Path]::GetTempPath()) "pwsh-ci-$Name.$Version.$PID.nupkg"
        Invoke-WebRequest -Uri "https://www.powershellgallery.com/api/v2/package/$Name/$Version" -OutFile $download -TimeoutSec 120 -MaximumRetryCount 3 -RetryIntervalSec 5
        $actual = (Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $Sha256) {
            Remove-Item -LiteralPath $download -Force
            Exit-WithFailure -Check 'modules' -Detail "checksum mismatch for $Name ${Version}: expected $Sha256, got $actual"
        }
        if (Test-Path -LiteralPath $destination) {
            Remove-Item -LiteralPath $destination -Recurse -Force
        }
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Expand-Archive -LiteralPath $download -DestinationPath $destination -Force
        Remove-Item -LiteralPath $download -Force
        Set-Content -LiteralPath $marker -Value $Sha256
    }
    Import-Module -Name (Join-Path $destination "$Name.psd1") -Force -Global
}

# Inputs and pinned modules.
$root = (Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue).Path
if (-not $root) {
    Exit-WithFailure -Check 'inputs' -Detail "path not found: $Path"
}
if (-not (Test-Path -LiteralPath $PinsFile)) {
    Exit-WithFailure -Check 'modules' -Detail "pins file not found: $PinsFile"
}
foreach ($line in Get-Content -LiteralPath $PinsFile) {
    if ($line -match '^\s*(#|$)') { continue }
    if ($line -notmatch '^(?<name>\S+) (?<version>\d+\.\d+\.\d+) sha256=(?<sha>[0-9a-f]{64})$') {
        Exit-WithFailure -Check 'modules' -Detail "unreadable pin: $line"
    }
    Import-PinnedModule -Name $Matches.name -Version $Matches.version -Sha256 $Matches.sha -Cache $ModuleCache
}

# Settings: required, so the rule set is always explicit.
$settingsPath = Join-Path $root $Settings
if (-not (Test-Path -LiteralPath $settingsPath)) {
    Exit-WithFailure -Check 'settings' -Detail "settings file not found: $Settings"
}
$settingsData = Import-PowerShellDataFile -LiteralPath $settingsPath
Write-CheckResult -Check 'settings' -Passed $true -Detail $Settings

# Format: report every file whose formatted text differs; change nothing.
$configured = @()
if ($settingsData.ContainsKey('Rules')) {
    $configured = @($settingsData.Rules.Keys | Where-Object { $_ -in $formattingRules -and $settingsData.Rules[$_].Enable })
}
if ($configured.Count -eq 0) {
    Write-CheckResult -Check 'format' -Passed $false -Detail "$Settings configures no formatting rule under Rules, so formatting would never be checked"
}
else {
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1')
    $different = foreach ($file in $files) {
        $text = [IO.File]::ReadAllText($file.FullName)
        if ($text.Length -eq 0) { continue }
        $relative = [IO.Path]::GetRelativePath($root, $file.FullName)
        try {
            $formatted = Invoke-Formatter -ScriptDefinition $text -Settings $settingsPath
        }
        catch {
            # Invoke-Formatter refuses some files, such as ones with mixed line endings.
            "$relative (Invoke-Formatter: $($_.Exception.Message))"
            continue
        }
        if ($formatted -cne $text) { $relative }
    }
    $different = @($different)
    if ($different.Count -gt 0) {
        Write-CheckResult -Check 'format' -Passed $false -Detail "$($different.Count) file(s) differ from Invoke-Formatter: $($different -join ', ')"
    }
    else {
        Write-CheckResult -Check 'format' -Passed $true -Detail "$($files.Count) file(s)"
    }
}

# Analyze: Error and Warning fail; Information is reported only. PSUseCorrectCasing is
# left to the format check, which applies it sequentially: under Invoke-ScriptAnalyzer it
# reads command metadata off the pipeline thread and intermittently throws a
# NullReferenceException (https://github.com/PowerShell/PSScriptAnalyzer/issues/1708).
$analyzerSettings = $settingsData.Clone()
$analyzerSettings.ExcludeRules = [string[]]@(@($settingsData.ExcludeRules) + 'PSUseCorrectCasing' | Where-Object { $_ })
$records = @(Invoke-ScriptAnalyzer -Path $root -Recurse -Settings $analyzerSettings)
$blocking = @($records | Where-Object { $_.Severity -in 'Error', 'Warning', 'ParseError' })
$information = $records.Count - $blocking.Count
foreach ($record in $blocking) {
    Write-Output "  $([IO.Path]::GetRelativePath($root, $record.ScriptPath)):$($record.Line) $($record.Severity) $($record.RuleName): $($record.Message)"
}
if ($blocking.Count -gt 0) {
    Write-CheckResult -Check 'analyze' -Passed $false -Detail "$($blocking.Count) error or warning finding(s), $information information"
}
else {
    Write-CheckResult -Check 'analyze' -Passed $true -Detail "$information information finding(s)"
}

# Load: import in a fresh process that stops on the first error, so a loader that
# reports a broken file with a non-terminating Write-Error still fails.
if ($ModuleManifest) {
    $manifestPath = Join-Path $root $ModuleManifest
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Write-CheckResult -Check 'load' -Passed $false -Detail "module manifest not found: $ModuleManifest"
    }
    else {
        $pwsh = (Get-Process -Id $PID).Path
        $env:PWSH_CI_MANIFEST = $manifestPath
        $loadCommand = '$ErrorActionPreference = ''Stop''; if ($env:PWSH_CI_MANIFEST -like ''*.psd1'') { Test-ModuleManifest -Path $env:PWSH_CI_MANIFEST | Out-Null }; Import-Module -Name $env:PWSH_CI_MANIFEST -Force'
        $loadOutput = & $pwsh -NoProfile -NonInteractive -Command $loadCommand 2>&1 | Out-String
        $loadExit = $LASTEXITCODE
        Remove-Item Env:PWSH_CI_MANIFEST
        if ($loadExit -ne 0) {
            Write-CheckResult -Check 'load' -Passed $false -Detail "importing $ModuleManifest failed: $($loadOutput.Trim())"
        }
        else {
            Write-CheckResult -Check 'load' -Passed $true -Detail $ModuleManifest
        }
    }
}

# Test: Pester; no tests fails unless -AllowNoTests.
$testsPath = Join-Path $root $Tests
$testFiles = @(if (Test-Path -LiteralPath $testsPath) { Get-ChildItem -LiteralPath $testsPath -Recurse -File -Filter '*.Tests.ps1' })
if ($testFiles.Count -eq 0) {
    if ($AllowNoTests) {
        Write-CheckResult -Check 'test' -Passed $true -Detail "no tests in $Tests, allowed"
    }
    else {
        Write-CheckResult -Check 'test' -Passed $false -Detail "no tests found in $Tests"
    }
}
else {
    $configuration = New-PesterConfiguration
    $configuration.Run.Path = $testsPath
    $configuration.Run.PassThru = $true
    $configuration.Output.Verbosity = 'Normal'
    $result = Invoke-Pester -Configuration $configuration
    if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') {
        Write-CheckResult -Check 'test' -Passed $false -Detail "$($result.FailedCount) failed, $($result.PassedCount) passed"
    }
    elseif ($result.PassedCount -eq 0) {
        Write-CheckResult -Check 'test' -Passed $false -Detail "no tests found in $Tests"
    }
    else {
        Write-CheckResult -Check 'test' -Passed $true -Detail "$($result.PassedCount) passed"
    }
}

if ($script:failed.Count -gt 0) {
    Write-Output "pwsh-ci: failed checks: $($script:failed -join ', ')"
    exit 1
}
Write-Output 'pwsh-ci: all checks passed'
