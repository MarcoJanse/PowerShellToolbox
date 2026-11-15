<#
.SYNOPSIS
    Pre-commit hook implementation, invoked by the .githooks/pre-commit shell wrapper.

.DESCRIPTION
    Runs exactly the same checks as CI (.github/workflows/ci.yml), by calling the same scripts:
      1. .github/scripts/Invoke-Lint.ps1        on the STAGED PowerShell files
      2. .github/scripts/Invoke-PesterTests.ps1 (the full Pester suite)
    The only difference with CI is WHICH files are linted: the hook lints the staged files,
    CI lints the whole repo. The rules, the settings files and what blocks are identical.

    The staged versions are written byte-for-byte to a temp folder with 'git checkout-index'
    and linted there, so a fix you haven't 'git add'-ed yet can't hide a problem, and
    file-level rules such as PSUseBOMForUnicodeEncodedFile see the real bytes.

    Enabled once per clone with:  git config core.hooksPath .githooks
    Skip for one commit with:     git commit --no-verify
    See .githooks/README.md and docs/Testing-and-Linting.md.
#>
$ErrorActionPreference = 'Stop'

$repoRoot = (git rev-parse --show-toplevel).Trim()
Set-Location -LiteralPath $repoRoot
$scripts = Join-Path $repoRoot '.github/scripts'

# --- Staged PowerShell files (added, copied, modified, renamed) -----------------------------------
$staged = @(git -c core.quotepath=off diff --cached --name-only --diff-filter=ACMR |
    Where-Object { $_ -match '\.(ps1|psm1|psd1)$' })
if ($staged.Count -eq 0) { exit 0 }

# --- 1. Lint the staged snapshot ------------------------------------------------------------------
Write-Host "`n== PSScriptAnalyzer: $($staged.Count) staged file(s) ==" -ForegroundColor Cyan
$snapshot = Join-Path ([IO.Path]::GetTempPath()) ('pssa-precommit-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $snapshot | Out-Null
try {
    git checkout-index --prefix="$($snapshot.Replace('\', '/'))/" -- $staged
    if ($LASTEXITCODE -ne 0) { throw 'git checkout-index failed.' }

    & (Join-Path $scripts 'Invoke-Lint.ps1') -Files $staged -Root $snapshot
    $lintExit = $LASTEXITCODE
}
finally {
    Remove-Item -LiteralPath $snapshot -Recurse -Force -ErrorAction SilentlyContinue
}
if ($lintExit -ne 0) {
    Write-Host 'Commit blocked by PSScriptAnalyzer. Fix the findings, stage again (git add) and commit.' -ForegroundColor Red
    exit 1
}

# --- 2. Pester, in its own process (Invoke-PesterTests uses Run.Exit, which ends the process) -------
Write-Host "`n== Pester ==" -ForegroundColor Cyan
& pwsh -NoProfile -NonInteractive -File (Join-Path $scripts 'Invoke-PesterTests.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Commit blocked by failing Pester tests.' -ForegroundColor Red
    exit 1
}

exit 0
