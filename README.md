# PowerShell Toolbox

A personal collection of PowerShell scripts, functions, modules and snippets
for managing Microsoft 365, Azure, Active Directory and Windows — linted with
[PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) and tested
with [Pester](https://pester.dev/) on every commit.

## Folder structure

Top-level folders are organized **by type**; each one has a subfolder **per
technology**. Pick whichever technology folders you actually need — add more
as you go (e.g. `Exchange`, `Intune`, `SharePoint`, `Teams` under
`Microsoft365`, or `Linux`, `macOS` alongside `Windows`).

```text
PowerShellToolbox/
├── Modules/                 # Reusable modules: multiple functions, a manifest, versioned
│   ├── Azure/
│   ├── Microsoft365/
│   ├── ActiveDirectory/
│   └── Windows/
│       └── PSToolboxExample/    # Template module - copy this structure for new modules
│           ├── PSToolboxExample.psd1
│           ├── PSToolboxExample.psm1
│           ├── Public/          # Exported functions, one file per function
│           └── Private/         # Internal helper functions, not exported
├── Scripts/                 # Standalone, run-it-and-done scripts (not meant to be imported)
│   ├── Azure/
│   ├── Microsoft365/
│   │   └── Intune/              # Windows PowerShell 5.1 scripts (platform scripts, remediations)
│   │       └── PSScriptAnalyzerSettings.psd1   # adds the 5.1 compatibility check for this folder
│   ├── ActiveDirectory/
│   └── Windows/
├── Functions/                # Single reusable functions not (yet) part of a module
│   ├── Azure/
│   ├── Microsoft365/
│   ├── ActiveDirectory/
│   └── Windows/
├── Snippets/                 # Small code fragments / examples, not meant to run standalone
├── Tests/                    # Pester tests, mirroring the folders above
│   ├── Modules/
│   ├── Scripts/
│   └── Functions/
├── docs/
│   └── Testing-and-Linting.md   # Beginner-friendly guide to Pester + PSScriptAnalyzer
├── .githooks/                # Local pre-commit hook: lints the staged files + runs Pester - see .githooks/README.md
│   ├── pre-commit              # sh wrapper that git calls; hands off to pwsh
│   ├── pre-commit.ps1          # snapshots the staged files and calls the .github/scripts below
│   └── README.md               # setup, what blocks a commit, per-folder rule sets, troubleshooting
├── .github/
│   ├── scripts/                # Shared by ci.yml AND .githooks/pre-commit - one source of truth
│   │   ├── Invoke-Lint.ps1
│   │   ├── Invoke-PesterTests.ps1
│   │   ├── Install-RequiredModules.ps1   # module dependencies from the manifests (CI + once locally)
│   │   └── Add-MissingBom.ps1            # repairs PowerShell files with special characters but no BOM
│   └── workflows/ci.yml        # CI: lint + test on every push and PR
├── .vscode/
│   ├── extensions.json         # Recommends the PowerShell and EditorConfig extensions
│   └── settings.json           # LF line endings, UTF-8 with BOM for PowerShell, analyzer wired to the settings file
├── PSScriptAnalyzerSettings.psd1   # Default analyzer rules for the whole repo
├── .editorconfig              # UTF-8 with BOM for PowerShell files, LF line endings
├── .gitattributes             # Enforces LF line endings repo-wide
└── .gitignore
```

**Rule of thumb for what goes where:**

- A script you run once or on a schedule, with no expectation of reuse → `Scripts/`
- One function you'll `. source` or copy into other scripts → `Functions/`
- A handful of related functions you'll `Import-Module` → `Modules/`
- A fragment too small to run on its own (a one-liner, a config block) → `Snippets/`
- A script that must run in **Windows PowerShell 5.1** (Intune platform scripts, remediations, app requirement scripts) → `Scripts/Microsoft365/Intune/`, where the linter also checks for PowerShell 7-only syntax

### Example: a real Microsoft 365 / Azure / AD setup

```text
Modules/
├── Microsoft365/
│   └── M365.UserOffboarding/      # Disable account, revoke sessions, convert mailbox, etc.
├── Azure/
│   └── Az.CostReporting/          # Pull cost data, build a report, email it
└── ActiveDirectory/
    └── AD.HygieneChecks/          # Stale accounts, password-never-expires audit, etc.

Scripts/
├── Microsoft365/
│   └── Invoke-WeeklyLicenseAudit.ps1
├── Azure/
│   └── Stop-IdleVMsOutsideBusinessHours.ps1
└── ActiveDirectory/
    └── Export-InactiveComputerAccounts.ps1

Functions/
├── Microsoft365/
│   └── Get-MailboxSizeReport.ps1
└── ActiveDirectory/
    └── Test-IsAccountLockedOut.ps1

Tests/
├── Modules/Microsoft365/M365.UserOffboarding.Tests.ps1
├── Scripts/Azure/Stop-IdleVMsOutsideBusinessHours.Tests.ps1
└── Functions/ActiveDirectory/Test-IsAccountLockedOut.Tests.ps1
```

## Linting and testing

Every commit is linted with PSScriptAnalyzer and tested with Pester via a
local git hook, and re-checked by GitHub Actions on every push/PR. Both call
the same scripts in `.github/scripts/`, so a local pass and a CI pass mean the
same thing. **New to Pester or PSScriptAnalyzer?** Start with
[docs/Testing-and-Linting.md](docs/Testing-and-Linting.md) — it explains both
tools from scratch and walks through writing your first test.

Quick setup (in PowerShell 7):

```powershell
git config core.hooksPath .githooks
./.github/scripts/Install-RequiredModules.ps1   # module dependencies the tests need, same versions as CI
```

PSScriptAnalyzer and Pester 6 are installed automatically by the lint and test
scripts when they're missing.

In short:

- **Same rules everywhere.** The hook lints the **staged** version of the files you commit; CI lints the **whole repo**. Both use `Invoke-Lint.ps1`, so the rules and what blocks are identical.
- **Nearest settings file.** Each file is checked with the nearest `PSScriptAnalyzerSettings.psd1`. `Scripts/Microsoft365/Intune/` has its own, which adds the Windows PowerShell 5.1 compatibility check.
- **What blocks.** Syntax errors, `Error` findings, a missing BOM in files with special characters, and failing Pester tests block both the commit and CI. Other warnings are only shown.

Details, the per-folder rule sets and troubleshooting: [.githooks/README.md](.githooks/README.md).

## Line endings

This repo commits with LF line endings (`.gitattributes`) so it works cleanly
across Windows, Linux and macOS. Git converts line endings for you on
checkout/commit — you don't need to do anything, just don't fight it with
`core.autocrlf=true` settings that override repo-level config.

## Encoding

Save PowerShell files (`.ps1`, `.psm1`, `.psd1`) as **UTF-8 with BOM**.
PowerShell 7 reads UTF-8 with or without BOM, but Windows PowerShell 5.1
reads a file *without* BOM as Windows-1252. Special characters such as `é`,
`→` or `—` then turn into other characters, some of which PowerShell treats
as quotes, and the script fails with parse errors.

Three things take care of this:

- **`.editorconfig`** sets `charset = utf-8-bom` for PowerShell files, in editors that support EditorConfig (VS Code with the recommended extension, Visual Studio, JetBrains).
- **`.vscode/settings.json`** sets `"files.encoding": "utf8bom"` for PowerShell, so VS Code does the same even without the extension.
- **`Invoke-Lint.ps1`** (hook and CI) blocks files that contain special characters but no BOM (`PSUseBOMForUnicodeEncodedFile`). `./.github/scripts/Add-MissingBom.ps1` repairs them.

Plain ASCII is always safe: when in doubt, use `->` and `-` instead of `→` and `—`.
