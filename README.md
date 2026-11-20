# pwsh-ci-action

Run blocking PowerShell checks: settings, formatting, PSScriptAnalyzer, module loading and Pester.
The action changes no file. It runs on the pinned PowerShell from
[setup-pwsh-action](https://github.com/vhco-pro/setup-pwsh-action) and installs pinned,
checksum-verified versions of PSScriptAnalyzer and Pester, so a run gives the same verdict wherever
it runs.

```yaml
steps:
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
    with:
      persist-credentials: false
  - uses: vhco-pro/pwsh-ci-action@FULL_COMMIT_SHA # vX.Y.Z
    with:
      module-manifest: MyModule.psm1
```

Replace the placeholder with a released commit and its tag.

## Inputs

| Input | Default | Purpose |
| --- | --- | --- |
| `path` | `.` | Directory to check |
| `settings` | `PSScriptAnalyzerSettings.psd1` | PSScriptAnalyzer settings relative to `path` |
| `module-manifest` | empty | `.psd1` or `.psm1` to import, relative to `path` |
| `tests` | `tests` | Pester tests directory relative to `path` |
| `allow-no-tests` | `false` | `true` lets a run with no Pester tests pass |

The `pwsh-version` output holds the PowerShell version the checks ran on.

## Checks

Each check prints one `pwsh-ci: <check>: passed` or `FAILED` line, and the run fails if any check
fails.

1. **Settings.** The settings file must exist, so the rule set is always explicit.
2. **Format.** `Invoke-Formatter` with the settings must leave every `.ps1`, `.psm1` and `.psd1`
   unchanged. Settings that configure no formatting rule under `Rules` fail, because nothing would
   be checked.
3. **Analyze.** `Invoke-ScriptAnalyzer` fails on any `Error` or `Warning`; `Information` is reported
   only. Casing is checked by the format step instead, because PSScriptAnalyzer's `UseCorrectCasing`
   rule intermittently throws under `Invoke-ScriptAnalyzer`
   ([PSScriptAnalyzer#1708](https://github.com/PowerShell/PSScriptAnalyzer/issues/1708)).
4. **Load.** With `module-manifest` set, the module is imported in a fresh `pwsh` that stops on the
   first error, so a loader that reports a broken file with `Write-Error` fails. A `.psd1` also goes
   through `Test-ModuleManifest`.
5. **Test.** Pester 6 must pass, and must find tests unless `allow-no-tests` is `true`.

Keep the settings file free of `IncludeRules`, so the default analyzer rules run alongside the
formatting rules.

## Run it locally

`ci.ps1` takes the same settings as the action: `pwsh -File ci.ps1 -Path . -ModuleManifest MyModule.psm1`.
It downloads the pinned modules into a cache under the temporary directory. Locally it runs on whatever
PowerShell is installed; the action's verdict on the pinned PowerShell is the one that counts.

## Pinned modules

[`modules.pins`](modules.pins) holds each module's version and the SHA-256 of its Gallery package.
Renovate proposes new versions through a custom manager; refresh the checksum in the same PR.

## Tests

`pwsh -File tests/test-fixtures.ps1` copies the clean fixture module, applies one change per case and
checks each verdict, the check it names and that no file changed, plus a wrong-checksum case.
[`test.yml`](.github/workflows/test.yml) runs those cases on Linux and Windows, checks this repository
with the action, and runs the composite action and `ci.ps1` on every case to prove they agree.
