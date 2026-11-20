# Behaviour tests for ci.ps1. Each case in cases.ps1 copies tests/fixtures/clean, applies
# one change, runs ci.ps1 in a fresh pwsh and checks the exit code, the check it names, and
# that no file in the copy changed. Needs network access for the pinned module downloads.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'cases.ps1')

$root = Split-Path -Parent $PSScriptRoot
$ci = Join-Path $root 'ci.ps1'
$pins = Join-Path $root 'modules.pins'
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

function Test-Run {
    param([string]$Name, [string]$Copy, [object]$Case, [string]$PinsFile, [string]$ModuleCache)

    $arguments = @('-Path', $Copy, '-ModuleManifest', 'Clean.psm1', '-PinsFile', $PinsFile, '-ModuleCache', $ModuleCache)
    if ($Case.AllowNoTests) { $arguments += '-AllowNoTests' }
    $before = Get-TreeHash $Copy
    $output = & $pwsh -NoProfile -File $ci @arguments 2>&1 | Out-String
    $exit = $LASTEXITCODE
    $after = Get-TreeHash $Copy

    $problems = @()
    if ($exit -ne $Case.ExpectExit) { $problems += "exit $exit, expected $($Case.ExpectExit)" }
    if ($output -notmatch [regex]::Escape($Case.ExpectText)) { $problems += "output lacks '$($Case.ExpectText)'" }
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

foreach ($case in $FixtureCases) {
    $copy = Join-Path $work $case.Name
    $null = Build-Fixture -Name $case.Name -Destination $copy
    Test-Run -Name $case.Name -Copy $copy -Case $case -PinsFile $pins -ModuleCache $cache
}

# A module package whose SHA-256 differs from its pin is refused before it is imported.
$badPins = Join-Path $work 'bad.pins'
(Get-Content -LiteralPath $pins) -replace 'sha256=[0-9a-f]{64}', ('sha256=' + ('0' * 64)) | Set-Content -LiteralPath $badPins
$freshCache = Join-Path $work 'fresh-cache'
$copy = Join-Path $work 'wrong-checksum'
$null = Build-Fixture -Name 'clean' -Destination $copy
$wrongChecksum = [pscustomobject]@{ ExpectExit = 1; ExpectText = 'checksum mismatch'; AllowNoTests = $false }
Test-Run -Name 'wrong-checksum' -Copy $copy -Case $wrongChecksum -PinsFile $badPins -ModuleCache $freshCache
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
# The last child run may have left a non-zero $LASTEXITCODE, which a GitHub pwsh step
# would report as a failure.
exit 0
