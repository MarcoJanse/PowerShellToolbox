#
# Pre-commit hook implementation, invoked by the .githooks/pre-commit shell
# wrapper (PowerShell itself only runs *.ps1 files, so the file git actually
# looks for - named "pre-commit", no extension - can't contain this logic
# directly).
#
# Lints staged PowerShell files with PSScriptAnalyzer and
# runs the Pester test suite. Blocks the commit on analyzer errors or test
# failures. Analyzer warnings are shown but do not block.
#
# Enabled once per clone via:
#   git config core.hooksPath .githooks
#
# Skip for one commit with: git commit --no-verify
# See docs/Testing-and-Linting.md for what each check means and how to fix findings.

$ErrorActionPreference = 'Stop'
$repoRoot = git rev-parse --show-toplevel
Set-Location $repoRoot

function Write-HookHeader {
    param([string]$Text)
    Write-Host "`n== $Text ==" -ForegroundColor Cyan
}

# --- Gather staged PowerShell files -----------------------------------
$stagedFiles = git diff --cached --name-only --diff-filter=ACM |
    Where-Object { $_ -match '\.(ps1|psm1|psd1)$' }

if (-not $stagedFiles) {
    exit 0
}

$stagedFiles = $stagedFiles | ForEach-Object { Join-Path $repoRoot $_ } | Where-Object { Test-Path $_ }

# --- PSScriptAnalyzer ---------------------------------------------------
Write-HookHeader 'Linting staged files with PSScriptAnalyzer'

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Host 'PSScriptAnalyzer is not installed.' -ForegroundColor Red
    Write-Host 'Install it with: Install-Module PSScriptAnalyzer -Scope CurrentUser' -ForegroundColor Yellow
    exit 1
}

Import-Module PSScriptAnalyzer

$settingsPath = Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
$analyzerResults = $stagedFiles | ForEach-Object { Invoke-ScriptAnalyzer -Path $_ -Settings $settingsPath }

$analyzerErrors = $analyzerResults | Where-Object Severity -EQ 'Error'
$analyzerWarnings = $analyzerResults | Where-Object Severity -EQ 'Warning'

if ($analyzerWarnings) {
    Write-Host "`nWarnings (not blocking the commit):" -ForegroundColor Yellow
    $analyzerWarnings | Format-Table RuleName, ScriptName, Line, Message -AutoSize | Out-Host
}

if ($analyzerErrors) {
    Write-Host "`nErrors (blocking the commit):" -ForegroundColor Red
    $analyzerErrors | Format-Table RuleName, ScriptName, Line, Message -AutoSize | Out-Host
    Write-Host 'Fix the errors above, or see docs/Testing-and-Linting.md.' -ForegroundColor Red
    exit 1
}

Write-Host 'No analyzer errors found.' -ForegroundColor Green

# --- Pester ---------------------------------------------------------------
Write-HookHeader 'Running Pester tests'

if (-not (Get-Module -ListAvailable -Name Pester | Where-Object Version -GE '5.0.0')) {
    Write-Host 'Pester 5+ is not installed.' -ForegroundColor Red
    Write-Host 'Install it with: Install-Module Pester -Scope CurrentUser -MinimumVersion 5.0.0' -ForegroundColor Yellow
    exit 1
}

Import-Module Pester -MinimumVersion 5.0.0

$pesterConfig = New-PesterConfiguration
$pesterConfig.Run.Path = Join-Path $repoRoot 'Tests'
$pesterConfig.Run.PassThru = $true
$pesterConfig.Output.Verbosity = 'Normal'

$testResult = Invoke-Pester -Configuration $pesterConfig

if ($testResult.FailedCount -gt 0) {
    Write-Host "`n$($testResult.FailedCount) Pester test(s) failed. Commit blocked." -ForegroundColor Red
    exit 1
}

Write-Host 'All Pester tests passed.' -ForegroundColor Green
exit 0
