# CLAUDE.md

Personal PowerShell toolbox (Microsoft 365 / Entra ID, Azure, Active Directory, Windows). Scripts, functions, modules and snippets, linted with PSScriptAnalyzer and tested with Pester 6 on every commit and in CI. See [README.md](README.md) for the full folder tree and [docs/Testing-and-Linting.md](docs/Testing-and-Linting.md) for the tooling guide.

## Layout: top level by type, subfolder per technology

| Folder | Holds |
|---|---|
| `Scripts/<Tech>/` | Standalone run-it-and-done scripts (param block, comment-based help, `#Requires`). Entra ID tooling lives in `Scripts/Microsoft365/EntraID/`. |
| `Functions/<Tech>/` | One function per file, dot-sourced by scripts or copied elsewhere (file name = function name). |
| `Modules/<Tech>/<Name>/` | Real modules: `.psd1` manifest, `.psm1` that dot-sources `Public/*.ps1` and `Private/*.ps1` and exports only the public ones. `PSToolboxExample` is the template; `Ictstuff.Windows.PackageManagement` is a real one. |
| `Snippets/` | Fragments that don't run standalone. |
| `Tests/` | Pester tests mirroring the above: `Tests/Scripts/X.Tests.ps1`, `Tests/Functions/X.Tests.ps1`, `Tests/Modules/<Tech>/X.Tests.ps1`. |
| `.github/scripts/` | Lint/test/setup scripts shared by CI and the pre-commit hook (single source of truth). |

Where something goes: run once/scheduled -> Scripts; one reusable function -> Functions; related functions you `Import-Module` -> Modules; PowerShell 5.1-only scripts (Intune platform scripts, remediations) -> `Scripts/Microsoft365/Intune/`.

## Commands (PowerShell 7)

```powershell
git config core.hooksPath .githooks                 # one-time: enable the pre-commit hook
./.github/scripts/Install-RequiredModules.ps1       # one-time: install manifest RequiredModules (exact-pinned versions)
./.github/scripts/Invoke-Lint.ps1                   # lint whole repo (like CI)
./.github/scripts/Invoke-Lint.ps1 -Files 'Scripts/Microsoft365/EntraID/Get-EntraGroupUsage.ps1'   # lint specific repo-relative files
./.github/scripts/Invoke-PesterTests.ps1            # full Pester suite
Invoke-Pester -Path ./Tests/Functions/Import-GroupSyncCsv.Tests.ps1 -Output Detailed   # one test file
./.github/scripts/Add-MissingBom.ps1                # add the BOM to files that need it
```

Pester must be 6.x and PSScriptAnalyzer >= 1.24.0; the scripts install them when missing.

## Lint rules and what blocks

- Root `PSScriptAnalyzerSettings.psd1` (Error/Warning/ParseError; formatting rules not enabled; `PSAvoidUsingWriteHost` excluded). The **nearest** settings file per file wins and does not inherit; `Scripts/Microsoft365/Intune/` has its own that adds `PSUseCompatibleSyntax` for Windows PowerShell 5.1.
- Blocking: parse errors, any Error, the `PSUseBOMForUnicodeEncodedFile` warning, failing Pester tests. Other warnings are shown only.
- The hook lints the **staged** snapshot of changed files, then runs the full Pester suite against files on disk. Never bypass with `--no-verify`.

## Conventions

- **Encoding:** `.ps1/.psm1/.psd1` are UTF-8 **with BOM** (5.1 reads BOM-less files as Windows-1252). Prefer plain ASCII (`->`, `-`) in code and help. Line endings are LF (`.gitattributes`); `.bat/.cmd` are CRLF.
- Scripts and tests carry a header: `.SYNOPSIS`/`.DESCRIPTION`, version, last-modified date, author line, and (for tests) `#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }`.
- Scripts declare Graph dependencies with `#Requires -Modules Microsoft.Graph.*`, support `-WhatIf`/`ShouldProcess` when they change things, and emit objects to the pipeline (no export logic in the script itself).
- Tests are mostly static (parse/inspect the script, never connect to Graph) or run functions against `$TestDrive` with mocks. Tests must never need a live tenant.
- Module dependencies go in the manifest `RequiredModules`; CI installs them from there, so no `ci.yml` edit is needed.
- CI (`.github/workflows/ci.yml`, windows-latest) runs install -> lint -> Pester on every push and on PRs from forks only (same-repo PRs are covered by the push run).

## Current work: Entra memberOf migration (branch `feature/entra-memberof-migration`)

Microsoft stopped processing the `memberOf` dynamic-rule operator (3 Nov 2026). Tooling to convert those groups to Assigned and sync members from source groups:

- `Scripts/Microsoft365/EntraID/Get-MemberOfDynamicGroups.ps1` - inventory (CSV input for the rest); `Get-EntraGroupUsage.ps1` - where a group is used (CA, apps, Intune, nesting).
- `Convert-DynamicGroupsToAssigned.ps1`, `ConvertTo-GroupSyncMapping.ps1` - conversion (snapshot/backup, supports `-WhatIf`) and mapping generation.
- `Functions/Microsoft365/EntraID/*GroupSync*.ps1` - helper functions, dot-sourced by the scripts. They are **copies** of those in the separate `groupsync-automation` repo (GHE); keep them in sync.
- Procedure: [docs/Runbook-Entra-Group-Sync-Migration.md](docs/Runbook-Entra-Group-Sync-Migration.md).

## Housekeeping

- `.gitkeep` files hold empty folders; delete one when the folder gets real content (the `Functions/Microsoft365` and `Tests/Functions` ones are already being removed).
- Add new tests alongside new scripts/functions in the mirrored `Tests/` path.
