# Behaviour tests for ci.ps1. Each case copies tests/fixtures/clean, applies one change,
# runs ci.ps1 in a fresh pwsh and checks the exit code, the check it names, and that no
# file in the copy changed. Needs network access for the pinned module downloads.
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$ci = Join-Path $root 'ci.ps1'
$pins = Join-Path $root 'modules.pins'
$clean = Join-Path $PSScriptRoot 'fixtures' 'clean'
$pwsh = (Get-Process -Id $PID).Path
$work = Join-Path ([IO.Path]::GetTempPath()) "pwsh-ci-tests-$PID"
$cache = Join-Path $work 'module-cache'
New-Item -ItemType Directory -Path $cache -Force | Out-Null
$script:failures = 0

function Get-TreeHash([string]$Path) {
    Get-ChildItem -Path $Path -Recurse -File |
        Sort-Object FullName |
        ForEach-Object { "$($_.FullName.Substring($Path.Length))=$((Get-FileHash $_.FullName).Hash)" }
}

function Invoke-Case {
    param(
        [string]$Name,
        [scriptblock]$Change = {},
        [string[]]$Arguments = @('-ModuleManifest', 'Clean.psm1'),
        [int]$ExpectExit,
        [string]$ExpectText,
        [string]$PinsFile = $pins,
        [string]$ModuleCache = $cache
    )

    $copy = Join-Path $work $Name
    Copy-Item -Path $clean -Destination $copy -Recurse
    & $Change $copy
    $before = Get-TreeHash $copy
    $output = & $pwsh -NoProfile -File $ci -Path $copy -PinsFile $PinsFile -ModuleCache $ModuleCache @Arguments 2>&1 | Out-String
    $exit = $LASTEXITCODE
    $after = Get-TreeHash $copy

    $problems = @()
    if ($exit -ne $ExpectExit) { $problems += "exit $exit, expected $ExpectExit" }
    if ($output -notmatch [regex]::Escape($ExpectText)) { $problems += "output lacks '$ExpectText'" }
    if (Compare-Object $before $after) { $problems += 'files changed' }

    if ($problems) {
        $script:failures++
        Write-Output "FAIL: $Name ($($problems -join '; '))"
        Write-Output $output
    }
    else {
        Write-Output "ok: $Name"
    }
}

function Add-File([string]$Path, [string]$Content) {
    Set-Content -LiteralPath $Path -Value $Content -Encoding utf8NoBOM
}

Invoke-Case -Name 'clean' -ExpectExit 0 -ExpectText 'pwsh-ci: all checks passed'

Invoke-Case -Name 'information-only' -ExpectExit 0 -ExpectText 'pwsh-ci: all checks passed' -Change {
    param($dir)
    Add-File (Join-Path $dir 'Public' 'Get-Count.ps1') @'
function Get-Count {
    [CmdletBinding()]
    [OutputType([int])]
    param()

    'three'
}
'@
}

Invoke-Case -Name 'formatting-diff' -ExpectExit 1 -ExpectText 'pwsh-ci: format: FAILED' -Change {
    param($dir)
    Add-File (Join-Path $dir 'Public' 'Get-Spaced.ps1') @'
function Get-Spaced {
  [CmdletBinding()]
  param()

  'two spaces'
}
'@
}

Invoke-Case -Name 'no-formatting-rule' -ExpectExit 1 -ExpectText 'configures no formatting rule' -Change {
    param($dir)
    Add-File (Join-Path $dir 'PSScriptAnalyzerSettings.psd1') '@{ ExcludeRules = @() }'
}

Invoke-Case -Name 'missing-settings' -ExpectExit 1 -ExpectText 'pwsh-ci: settings: FAILED' -Change {
    param($dir)
    Remove-Item (Join-Path $dir 'PSScriptAnalyzerSettings.psd1')
}

Invoke-Case -Name 'analyzer-warning' -ExpectExit 1 -ExpectText 'pwsh-ci: analyze: FAILED' -Change {
    param($dir)
    Add-File (Join-Path $dir 'Public' 'Get-Note.ps1') @'
function Get-Note {
    [CmdletBinding()]
    param()

    Write-Host 'a note'
}
'@
}

Invoke-Case -Name 'write-error-loader' -ExpectExit 1 -ExpectText 'pwsh-ci: load: FAILED' -Change {
    param($dir)
    Add-File (Join-Path $dir 'Public' 'Get-Broken.ps1') "throw 'broken at import'"
}

Invoke-Case -Name 'failing-test' -ExpectExit 1 -ExpectText 'pwsh-ci: test: FAILED' -Change {
    param($dir)
    Add-File (Join-Path $dir 'tests' 'Failing.Tests.ps1') @'
Describe 'a failing test' {
    It 'fails' {
        1 | Should -Be 2
    }
}
'@
}

Invoke-Case -Name 'no-tests' -ExpectExit 1 -ExpectText 'no tests' -Change {
    param($dir)
    Remove-Item (Join-Path $dir 'tests') -Recurse
}

Invoke-Case -Name 'no-tests-allowed' -ExpectExit 0 -ExpectText 'pwsh-ci: all checks passed' -Arguments @('-ModuleManifest', 'Clean.psm1', '-AllowNoTests') -Change {
    param($dir)
    Remove-Item (Join-Path $dir 'tests') -Recurse
}

# A module package whose SHA-256 differs from its pin is refused before it is imported.
$badPins = Join-Path $work 'bad.pins'
(Get-Content -LiteralPath $pins) -replace 'sha256=[0-9a-f]{64}', ('sha256=' + ('0' * 64)) | Set-Content -LiteralPath $badPins
$freshCache = Join-Path $work 'fresh-cache'
Invoke-Case -Name 'wrong-checksum' -ExpectExit 1 -ExpectText 'checksum mismatch' -PinsFile $badPins -ModuleCache $freshCache
if (Get-ChildItem -Path $freshCache -Recurse -Filter '*.psd1' -ErrorAction SilentlyContinue) {
    $script:failures++
    Write-Output 'FAIL: wrong-checksum (a module was extracted)'
}

Remove-Item -Path $work -Recurse -Force
if ($script:failures -gt 0) {
    Write-Output "$script:failures case(s) failed"
    exit 1
}
Write-Output 'all cases passed'
