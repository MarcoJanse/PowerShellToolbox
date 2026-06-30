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
├── .githooks/                # Local pre-commit hook (lint + test staged files)
├── .github/workflows/        # CI: lint + test on every push and PR
├── PSScriptAnalyzerSettings.psd1
├── .gitattributes             # Enforces LF line endings repo-wide
└── .gitignore
```

**Rule of thumb for what goes where:**

- A script you run once or on a schedule, with no expectation of reuse → `Scripts/`
- One function you'll `. source` or copy into other scripts → `Functions/`
- A handful of related functions you'll `Import-Module` → `Modules/`
- A fragment too small to run on its own (a one-liner, a config block) → `Snippets/`

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
local git hook, and re-checked by GitHub Actions on every push/PR. **New to
Pester or PSScriptAnalyzer?** Start with
[docs/Testing-and-Linting.md](docs/Testing-and-Linting.md) — it explains both
tools from scratch and walks through writing your first test.

Quick setup:

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser
Install-Module Pester -Scope CurrentUser -MinimumVersion 5.0.0
git config core.hooksPath .githooks
```

## Line endings

This repo commits with LF line endings (`.gitattributes`) so it works cleanly
across Windows, Linux and macOS. Git converts line endings for you on
checkout/commit — you don't need to do anything, just don't fight it with
`core.autocrlf=true` settings that override repo-level config.
