# Testing and linting, for beginners

This repo checks every commit with two tools:

- **PSScriptAnalyzer** — a linter. It reads your script without running it and
  flags risky or non-idiomatic patterns (plaintext passwords, unapproved verbs,
  unused variables, etc.).
- **Pester** — a test framework. It runs your code and checks the output
  matches what you expect.

You don't need to be fluent in either to get value from them — the rest of
this doc walks through both, starting from nothing.

## How they run

| When | What runs | Blocks the commit? |
|---|---|---|
| `git commit` | `.githooks/pre-commit` lints + tests **staged files only** | Yes, on analyzer errors or test failures |
| `git push` / pull request | `.github/workflows/ci.yml` lints + tests **the whole repo** | Yes, the PR/commit gets a red ✗ on GitHub |

The local hook is your fast feedback loop; CI is the backstop in case the hook
was skipped (`--no-verify`) or never installed on a given machine.

CI runs on `windows-latest`, not Linux. Most scripts here use Windows-only
cmdlets and modules (CIM/WMI, `ActiveDirectory`, etc.) that either don't
resolve or can't be installed at all on a Linux runner — `Mock` still needs
the real command to exist to build its proxy, even though it never actually
calls it. This doesn't remove the need to mock `Get-ADUser`,
`Get-MgUser`, `Get-AzVM` and friends, though — CI has no real domain
controller or tenant to talk to regardless of OS, so those calls must always
be faked out in tests (see below).

**One-time setup per clone:**

```powershell
git config core.hooksPath .githooks
```

Without this, `git commit` won't trigger the hook — nothing else changes.

## Linting with PSScriptAnalyzer

Run it yourself, any time, against one file or the whole repo:

```powershell
Invoke-ScriptAnalyzer -Path .\Modules\Windows\PSToolboxExample\Public\Get-DiskSpaceReport.ps1 -Settings .\PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

Each finding has a `RuleName`, a `Severity` (`Error` or `Warning` in this
repo's [PSScriptAnalyzerSettings.psd1](../PSScriptAnalyzerSettings.psd1)),
and a `Message` telling you what to change. Errors block your commit;
warnings are shown but don't.

If a rule fires somewhere you're confident is fine, suppress it on that one
line instead of disabling it repo-wide:

```powershell
[Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingWriteHost', '', Justification = 'Interactive script, output is meant for the console')]
```

If a rule is consistently wrong for *this whole project* (not just one
line), add it to `ExcludeRules` in `PSScriptAnalyzerSettings.psd1` — but
that's a repo-wide decision, so do it deliberately, not to silence one
inconvenient warning.

## Writing your first Pester test

Use [Tests/Modules/Windows/PSToolboxExample.Tests.ps1](../Tests/Modules/Windows/PSToolboxExample.Tests.ps1)
as your template — copy its shape rather than starting from a blank file.

The skeleton:

```powershell
BeforeAll {
    # Import the thing you're testing
    . "$PSScriptRoot\..\..\Functions\Windows\Get-Something.ps1"
}

Describe 'Get-Something' {
    It 'does the one thing it claims to do' {
        $result = Get-Something -Name 'test'
        $result | Should -Be 'expected value'
    }
}
```

- `Describe` groups tests for one function. One `Describe` block per function
  is the convention used throughout this repo.
- `It` is a single example/behaviour. Name it as a sentence describing what
  *should* happen ("returns null when the user is not found"), not what the
  test does mechanically.
- `Should -Be`, `Should -BeNullOrEmpty`, `Should -Throw`, `Should -Contain`
  are the comparisons you'll reach for most. Run `Get-Help Should -Examples`
  for the full list.

### Where do tests live?

Tests mirror the source tree, under `Tests/`:

```
Modules/Windows/PSToolboxExample/Public/Get-DiskSpaceReport.ps1
Tests/Modules/Windows/PSToolboxExample.Tests.ps1

Functions/ActiveDirectory/Get-StaleComputerAccount.ps1
Tests/Functions/ActiveDirectory/Get-StaleComputerAccount.Tests.ps1
```

### Testing things that touch Azure, M365, or Active Directory

Most scripts in this repo will call cmdlets like `Get-MgUser`,
`Get-AzVM`, or `Get-ADUser` — real network calls you don't want firing
during a test run. **Mock them**:

```powershell
BeforeAll {
    Mock Get-ADUser {
        [pscustomobject]@{ SamAccountName = 'jdoe'; Enabled = $true }
    }
}

It 'returns only enabled accounts' {
    $result = Get-EnabledUsers
    $result.SamAccountName | Should -Contain 'jdoe'
}
```

`Mock` replaces the real cmdlet for the duration of the test with a fake one
that returns whatever you tell it to. Your function still runs for real —
only the calls it makes to *other* commands get faked out. The example test
in this repo mocks `Get-CimInstance` for exactly this reason: it lets the
test pass on any machine, with any disk layout, with no real WMI call.

### Running tests locally

```powershell
# Everything
Invoke-Pester -Path .\Tests

# Just one file, with full detail on every test
Invoke-Pester -Path .\Tests\Modules\Windows\PSToolboxExample.Tests.ps1 -Output Detailed
```

## Getting set up

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser
Install-Module Pester -Scope CurrentUser -MinimumVersion 5.0.0
git config core.hooksPath .githooks
```

## When the hook gets in your way

- `git commit --no-verify` skips it for one commit (CI still catches it on push).
- If `pwsh` isn't installed, the hook tells you so and blocks rather than
  silently skipping the checks — install PowerShell 7 from
  https://aka.ms/powershell.
