# The fixture cases, shared by test-fixtures.ps1 (local and CI runs of ci.ps1) and by
# build-fixture.ps1 (test.yml's comparison of the composite action with ci.ps1).
# Each case copies tests/fixtures/clean and applies its change.

function Add-FixtureFile([string]$Path, [string]$Content) {
    # LF throughout, so the file's line endings are consistent on every platform.
    [IO.File]::WriteAllText($Path, ($Content -replace "`r`n", "`n") + "`n")
}

$FixtureCases = @(
    [pscustomobject]@{ Name = 'clean'; ExpectExit = 0; ExpectText = 'pwsh-ci: all checks passed'; AllowNoTests = $false; Change = {} }
    [pscustomobject]@{ Name = 'information-only'; ExpectExit = 0; ExpectText = 'pwsh-ci: all checks passed'; AllowNoTests = $false; Change = {
            param($dir)
            Add-FixtureFile (Join-Path $dir 'Public' 'Get-Count.ps1') "function Get-Count {`n    [CmdletBinding()]`n    [OutputType([int])]`n    param()`n`n    'three'`n}"
        }
    }
    [pscustomobject]@{ Name = 'formatting-diff'; ExpectExit = 1; ExpectText = 'pwsh-ci: format: FAILED'; AllowNoTests = $false; Change = {
            param($dir)
            Add-FixtureFile (Join-Path $dir 'Public' 'Get-Spaced.ps1') "function Get-Spaced {`n  [CmdletBinding()]`n  param()`n`n  'two spaces'`n}"
        }
    }
    [pscustomobject]@{ Name = 'wrong-casing'; ExpectExit = 1; ExpectText = 'pwsh-ci: format: FAILED'; AllowNoTests = $false; Change = {
            param($dir)
            Add-FixtureFile (Join-Path $dir 'Public' 'Get-Lower.ps1') "function Get-Lower {`n    [CmdletBinding()]`n    [OutputType([string])]`n    param()`n`n    write-output 'lower'`n}"
        }
    }
    [pscustomobject]@{ Name = 'mixed-line-endings'; ExpectExit = 1; ExpectText = 'pwsh-ci: format: FAILED'; AllowNoTests = $false; Change = {
            param($dir)
            [IO.File]::WriteAllText((Join-Path $dir 'Public' 'Get-Mixed.ps1'), "function Get-Mixed {`r`n    [CmdletBinding()]`n    param()`r`n`n    'mixed'`n}`n")
        }
    }
    [pscustomobject]@{ Name = 'no-formatting-rule'; ExpectExit = 1; ExpectText = 'configures no formatting rule'; AllowNoTests = $false; Change = {
            param($dir)
            Add-FixtureFile (Join-Path $dir 'PSScriptAnalyzerSettings.psd1') '@{ ExcludeRules = @() }'
        }
    }
    [pscustomobject]@{ Name = 'missing-settings'; ExpectExit = 1; ExpectText = 'pwsh-ci: settings: FAILED'; AllowNoTests = $false; Change = {
            param($dir)
            Remove-Item (Join-Path $dir 'PSScriptAnalyzerSettings.psd1')
        }
    }
    [pscustomobject]@{ Name = 'analyzer-warning'; ExpectExit = 1; ExpectText = 'pwsh-ci: analyze: FAILED'; AllowNoTests = $false; Change = {
            param($dir)
            Add-FixtureFile (Join-Path $dir 'Public' 'Get-Note.ps1') "function Get-Note {`n    [CmdletBinding()]`n    param()`n`n    Write-Host 'a note'`n}"
        }
    }
    [pscustomobject]@{ Name = 'write-error-loader'; ExpectExit = 1; ExpectText = 'pwsh-ci: load: FAILED'; AllowNoTests = $false; Change = {
            param($dir)
            Add-FixtureFile (Join-Path $dir 'Public' 'Get-Broken.ps1') "throw 'broken at import'"
        }
    }
    [pscustomobject]@{ Name = 'failing-test'; ExpectExit = 1; ExpectText = 'pwsh-ci: test: FAILED'; AllowNoTests = $false; Change = {
            param($dir)
            Add-FixtureFile (Join-Path $dir 'tests' 'Failing.Tests.ps1') "Describe 'a failing test' {`n    It 'fails' {`n        1 | Should -Be 2`n    }`n}"
        }
    }
    # A test that checks a written error passes as it does under Invoke-Pester's defaults: the
    # checks' own stop-on-error preference must not turn the function's Write-Error into a throw.
    [pscustomobject]@{ Name = 'test-checks-written-error'; ExpectExit = 0; ExpectText = 'pwsh-ci: all checks passed'; AllowNoTests = $false; Change = {
            param($dir)
            Add-FixtureFile (Join-Path $dir 'Public' 'Get-Missing.ps1') "function Get-Missing {`n    [CmdletBinding()]`n    param()`n`n    Write-Error 'not found'`n    'carried on'`n}"
            Add-FixtureFile (Join-Path $dir 'tests' 'Get-Missing.Tests.ps1') "BeforeAll {`n    Import-Module (Join-Path `$PSScriptRoot '..' 'Clean.psm1') -Force`n}`n`nDescribe 'Get-Missing' {`n    It 'writes an error and carries on' {`n        `$output = Get-Missing 2>&1`n        `$output[0] | Should -BeOfType ([System.Management.Automation.ErrorRecord])`n        `$output[1] | Should -Be 'carried on'`n    }`n}"
        }
    }
    [pscustomobject]@{ Name = 'no-tests'; ExpectExit = 1; ExpectText = 'no tests'; AllowNoTests = $false; Change = {
            param($dir)
            Remove-Item (Join-Path $dir 'tests') -Recurse
        }
    }
    [pscustomobject]@{ Name = 'no-tests-allowed'; ExpectExit = 0; ExpectText = 'pwsh-ci: all checks passed'; AllowNoTests = $true; Change = {
            param($dir)
            Remove-Item (Join-Path $dir 'tests') -Recurse
        }
    }
)

function Build-Fixture {
    param([string]$Name, [string]$Destination)

    $case = $FixtureCases | Where-Object Name -EQ $Name
    if (-not $case) {
        throw "unknown fixture case: $Name"
    }
    Copy-Item -Path (Join-Path $PSScriptRoot 'fixtures' 'clean') -Destination $Destination -Recurse
    & $case.Change $Destination
    $case
}
