# Git hooks

This folder contains the repository's **pre-commit hook**. It runs **the same checks as GitHub Actions**, by calling the same scripts in `.github/scripts/`:

- [PSScriptAnalyzer](https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/overview) via `Invoke-Lint.ps1`, on the files you're committing;
- [Pester](https://pester.dev/) via `Invoke-PesterTests.ps1`, the full test suite.

If a check fails, the commit is refused, so you find out on your own machine instead of in CI.

| File | Purpose |
|---|---|
| `pre-commit` | Shell wrapper. Git only runs a hook file named exactly `pre-commit` (no extension) and always starts it with `sh` (Git Bash's `sh.exe` on Windows). The wrapper hands off to `pwsh`. |
| `pre-commit.ps1` | Collects the staged PowerShell files, makes a snapshot of them, and calls `.github/scripts/Invoke-Lint.ps1` and `Invoke-PesterTests.ps1`. It contains no rules of its own. |
| `README.md` | This file. |

New to PSScriptAnalyzer or Pester? Read [docs/Testing-and-Linting.md](../docs/Testing-and-Linting.md) first.

## One-time setup (per clone)

Run this in the root of your clone, in PowerShell 7:

```powershell
git config core.hooksPath .githooks
./.github/scripts/Install-RequiredModules.ps1    # module dependencies the tests need, same versions as CI
```

- **PowerShell 7 (`pwsh`) must be on your `PATH`.** The wrapper refuses to run without it.
- **PSScriptAnalyzer and Pester:** `Invoke-Lint.ps1` and `Invoke-PesterTests.ps1` install them with PSResourceGet when they're missing (PSScriptAnalyzer 1.24.0 or later, Pester 6.x), exactly as on the CI runner. To install them up front: `Install-PSResource PSScriptAnalyzer, Pester -TrustRepository`.
- **`core.hooksPath` replaces `.git/hooks`.** Hooks you had in `.git/hooks` stop running; move them here if you still need them.
- **On Linux/macOS** the wrapper must be executable. It's committed with the executable bit, so clones get it automatically.

## What happens when you commit

Nothing runs if the commit contains no `.ps1`, `.psm1` or `.psd1` files. Otherwise:

1. **Snapshot of the staged files.** `git checkout-index` writes the *staged* version of each changed PowerShell file (what will actually be committed, not what's on disk) to a temp folder.
2. **Lint.** `Invoke-Lint.ps1 -Files <staged files> -Root <snapshot>` analyses that snapshot. A fix you haven't `git add`-ed yet can't hide a problem, and file-level checks such as the BOM rule see the real bytes.
3. **Test.** `Invoke-PesterTests.ps1` runs the full suite in `Tests/`, in a separate `pwsh` process. Pester can't run against the snapshot, so tests use the files on disk; unstaged changes can influence the result.

### Hook vs. CI

| | Pre-commit hook | GitHub Actions (`.github/workflows/ci.yml`) |
|---|---|---|
| Lint script | `Invoke-Lint.ps1` | `Invoke-Lint.ps1` |
| Files linted | Staged files only | Every `.ps1`/`.psm1`/`.psd1` in the repo |
| Rules, settings files, what blocks | Same | Same, plus findings as annotations on the file and line |
| Test script | `Invoke-PesterTests.ps1` | `Invoke-PesterTests.ps1 -ResultsPath ./TestResults` (results uploaded as an artifact) |
| Module dependencies | `Install-RequiredModules.ps1`, run once by you | `Install-RequiredModules.ps1`, every run |

So the hook can pass while CI fails only because of files you didn't change, for example after a commit with `--no-verify`.

### What blocks a commit (and a CI run)

| Finding | Blocks? |
|---|---|
| `ParseError`: the script doesn't parse (syntax error) | Yes |
| `Error` severity, including `PSUseCompatibleSyntax` in Windows PowerShell 5.1 folders | Yes |
| `Warning` rules listed in `-BlockingWarningRules` of `Invoke-Lint.ps1` (currently `PSUseBOMForUnicodeEncodedFile`) | Yes |
| Any other `Warning` | No, shown only |
| A failing Pester test | Yes |

`PSUseBOMForUnicodeEncodedFile` blocks because a script with non-ASCII characters (`é`, `→`, `—`) saved as UTF-8 *without* BOM is read as Windows-1252 by Windows PowerShell 5.1. Some of those characters then turn into quote characters, and the script no longer parses. Save PowerShell files as **UTF-8 with BOM**: `.editorconfig` and `.vscode/settings.json` do that for you, and `./.github/scripts/Add-MissingBom.ps1` repairs existing files.

To make another warning rule blocking, add it to the default value of `-BlockingWarningRules` in `Invoke-Lint.ps1`. It then applies to the hook and CI at once.

## Per-folder rule sets

Most scripts here run in PowerShell 7. Scripts that run in **Windows PowerShell 5.1**, such as Intune platform scripts, remediations and app requirement scripts, need an extra check: `PSUseCompatibleSyntax` reports PowerShell 7-only syntax (`??`, `? :`, `?.`) as an error.

`Invoke-Lint.ps1` analyses each file with the **nearest** `PSScriptAnalyzerSettings.psd1`: first the file's own folder, then each parent folder, up to the repository root. The Windows PowerShell 5.1 scripts live in their own folder with their own settings file:

```text
PSScriptAnalyzerSettings.psd1                               # default rules for the whole repo
Scripts/Microsoft365/Intune/PSScriptAnalyzerSettings.psd1   # Windows PowerShell 5.1 rules
```

> **Settings files don't inherit.** A folder's `PSScriptAnalyzerSettings.psd1` **replaces** the root file for everything below it; it doesn't add to it. Copy the settings you want to keep (`Severity`, `ExcludeRules`) and update both files when the shared settings change. If a settings file uses `IncludeRules`, a rule must also be listed there.

Need Windows PowerShell 5.1 rules somewhere else, e.g. `Functions/Microsoft365/Intune`? Put a copy of the settings file in that folder.

Both the hook and CI log which settings file was used for how many files:

```text
Settings: PSScriptAnalyzerSettings.psd1  ->  3 file(s)
Settings: Scripts/Microsoft365/Intune/PSScriptAnalyzerSettings.psd1  ->  1 file(s)
```

## Running the checks yourself

```powershell
# Exactly what CI runs
./.github/scripts/Invoke-Lint.ps1
./.github/scripts/Invoke-PesterTests.ps1

# Lint specific files (repo-relative paths), with the same rules
./.github/scripts/Invoke-Lint.ps1 -Files 'Scripts/Microsoft365/Intune/Remediate-Something.ps1'
```

## Skipping the hook

For a single commit, in an emergency:

```powershell
git commit --no-verify
```

CI still checks the whole repo on push and in the pull request, so use this sparingly.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `pwsh (PowerShell 7+) was not found on PATH` | Install PowerShell 7 (<https://aka.ms/powershell>) and restart your terminal or VS Code. |
| First commit is slow, or fails on `Install-PSResource` | The scripts install PSScriptAnalyzer/Pester when they're missing. Without access to the PowerShell Gallery, install them manually (see setup). |
| Tests fail locally with a missing module, but pass in CI | Run `./.github/scripts/Install-RequiredModules.ps1` once: it installs the module versions the manifests declare, like CI does. |
| Hook fails with `bad interpreter` or `$'\r': command not found` | The wrapper was checked out with CRLF line endings. `.gitattributes` enforces LF; delete the file and check it out again: `Remove-Item .githooks/pre-commit; git checkout -- .githooks/pre-commit`. |
| Commit from VS Code fails without details | Click **Show Command Output** in the error dialog, or run `git commit` in a terminal to see the findings. |
| VS Code doesn't underline PowerShell 7 syntax in an Intune script, but the hook blocks it | Expected. `powershell.scriptAnalysis.settingsPath` in `.vscode/settings.json` points to the root settings file only; per-folder rules are applied by `Invoke-Lint.ps1`. Check a file with `./.github/scripts/Invoke-Lint.ps1 -Files <path>`. |
| VS Code shows **UTF-8 with BOM**, but the lint step says the BOM is missing | The status bar shows the encoding VS Code *will save* with (from `files.encoding`), not what's on disk. Check the bytes with `Format-Hex -Path <file> -Count 3` (`EF BB BF` = BOM), then use **Save with Encoding → UTF-8 with BOM** or `./.github/scripts/Add-MissingBom.ps1`. |
| Commit blocked although you fixed the problem | The hook checks the *staged* version. `git add` the fixed file and commit again. |
| Hook passes, CI fails | CI lints the whole repo. Run `./.github/scripts/Invoke-Lint.ps1` locally to see findings in files you didn't change. |
