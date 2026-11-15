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
| `git commit` | `.githooks/pre-commit` lints the **staged files** and runs the **whole Pester suite** | Yes, on syntax errors, analyzer errors, a missing BOM, or test failures |
| `git push` / pull request | `.github/workflows/ci.yml` lints + tests **the whole repo** | Yes, the PR/commit gets a red ✗ on GitHub, with findings as annotations on the file |

Both call the same scripts in `.github/scripts/` (`Invoke-Lint.ps1` and
`Invoke-PesterTests.ps1`), so the rules and what blocks are identical; the
only difference is that the hook lints just the files you're committing.
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
How the hook works, what exactly blocks a commit and how to troubleshoot it:
[.githooks/README.md](../.githooks/README.md).

## Linting with PSScriptAnalyzer

Run it yourself, any time, with exactly the rules the hook and CI use
(including the right settings file per folder):

```powershell
# One or more files (repo-relative paths)
./.github/scripts/Invoke-Lint.ps1 -Files 'Modules/Windows/PSToolboxExample/Public/Get-DiskSpaceReport.ps1'

# The whole repo, like CI
./.github/scripts/Invoke-Lint.ps1
```

Each finding has a `RuleName`, a `Severity` and a `Message` telling you what
to change. What happens with each severity, in the hook and in CI:

| Severity | Meaning | Blocks the commit? |
|---|---|---|
| `ParseError` | The script doesn't even parse (syntax error, e.g. a missing `)`) | Yes |
| `Error` | A rule found a real problem | Yes |
| `Warning` | Probably worth fixing | No, shown only — except the rules listed in `-BlockingWarningRules` of `Invoke-Lint.ps1` (see below) |

The rules come from the repo's [PSScriptAnalyzerSettings.psd1](../PSScriptAnalyzerSettings.psd1).
A folder can have its own settings file that replaces the root one for
everything below it — `Scripts/Microsoft365/Intune/` does.

### Two rules you're likely to meet

**`PSUseBOMForUnicodeEncodedFile` (blocks the commit).** Your file contains
a character outside plain ASCII (`é`, `→`, `—`, ...) but was saved as UTF-8
*without* a byte-order mark. PowerShell 7 copes with that; Windows
PowerShell 5.1 doesn't — it reads the file as Windows-1252, some characters
turn into quote marks, and the script breaks with parse errors.
**Fix:** in VS Code, click the encoding in the status bar → **Save with
Encoding** → **UTF-8 with BOM**, then `git add` the file again — or run
`./.github/scripts/Add-MissingBom.ps1`. Or replace the special characters
with plain ASCII (`->`, `-`). Careful: the status bar shows the encoding VS
Code will *save* with, not necessarily what's on disk; `Format-Hex -Path
<file> -Count 3` shows `EF BB BF` when the BOM is really there.

**`PSUseCompatibleSyntax` (blocks the commit, Intune folder only).** Scripts
under `Scripts/Microsoft365/Intune/` run in **Windows PowerShell 5.1** —
Intune platform scripts, remediations and app requirement scripts don't use
PowerShell 7. This rule reports PowerShell 7-only syntax there, such as
`$a ?? 'default'`, `$x ? 'yes' : 'no'` or `$obj?.Property`.
**Fix:** write it the 5.1 way, e.g. `if ($null -ne $a) { $a } else { 'default' }`.

### Suppressing a rule

If a rule fires somewhere you're confident is fine, suppress it for that one
function or script instead of disabling it repo-wide. The attribute goes
directly above the `param()` block (or `[CmdletBinding()]`) of the function
or script, and applies to that whole function or script — there's no
per-line suppression:

```powershell
function Remove-OldReport {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only deletes files in a temp folder this function created itself')]
    [CmdletBinding()]
    param([string]$Path)
    ...
}
```

If a rule is consistently wrong for *this whole project* (not just one
function), add it to `ExcludeRules` in `PSScriptAnalyzerSettings.psd1` — but
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
# Everything, exactly like the hook and CI
./.github/scripts/Invoke-PesterTests.ps1

# Everything, directly with Pester
Invoke-Pester -Path .\Tests

# Just one file, with full detail on every test
Invoke-Pester -Path .\Tests\Modules\Windows\PSToolboxExample.Tests.ps1 -Output Detailed
```

## Getting set up

Run this in **PowerShell 7** — the hook runs in `pwsh`:

```powershell
git config core.hooksPath .githooks
./.github/scripts/Install-RequiredModules.ps1   # module dependencies the tests need, same versions as CI
```

PSScriptAnalyzer (1.24.0 or later) and Pester 6.x are installed automatically
by `Invoke-Lint.ps1` and `Invoke-PesterTests.ps1` when they're missing, the
same way as on the CI runner.

## When the hook gets in your way

- `git commit --no-verify` skips it for one commit (CI still catches it on push).
- If `pwsh` isn't installed, the hook tells you so and blocks rather than
  silently skipping the checks — install PowerShell 7 from
  https://aka.ms/powershell.
- The hook checks the **staged** version of your files. Fixed something but
  still blocked? `git add` the file again.
- More symptoms and fixes: [.githooks/README.md](../.githooks/README.md#troubleshooting).
