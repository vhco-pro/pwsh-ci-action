# Repository instructions

Follow the relevant routes in
https://github.com/vhco-pro/docs/blob/0c108237fcd004e8636c0a2ca191436abd7bb7bd/AGENTS.md,
including the GitHub Actions convention for this repository's action and workflows.

This composite action owns the blocking PowerShell checks: settings, formatting, analysis, module
loading and Pester. It does not check out, version, tag or publish. PowerShell itself comes from
`vhco-pro/setup-pwsh-action`.

Logic lives in `ci.ps1`, which runs the same way locally and in the action. Run
`pwsh -File tests/test-fixtures.ps1` for the behaviour tests and `pwsh -File ci.ps1 -Path . -AllowNoTests`
to check this repository with itself. `test.yml` also runs the composite action and `ci.ps1` on each
fixture case and fails if their verdicts differ.

When Renovate bumps a module in `modules.pins`, refresh its `sha256` in the same change from
`https://www.powershellgallery.com/api/v2/package/<name>/<version>` before merging.
