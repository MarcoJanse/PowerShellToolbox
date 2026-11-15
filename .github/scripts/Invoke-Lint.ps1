<#
.SYNOPSIS
    Lints PowerShell files with PSScriptAnalyzer and fails (exit 1) on blocking findings.
    Called from both .githooks/pre-commit.ps1 (local, staged files) and .github/workflows/ci.yml
    (CI, whole repo), so the rules can never drift between the two - change a rule here, and it
    applies in both places.

.DESCRIPTION
    Blocking findings:
      - ParseError : the file doesn't parse (syntax error). Also checked with the PowerShell parser
                     itself, so a settings file can never filter syntax errors out.
      - Error      : any Error-severity rule
      - Warning    : only the rules listed in -BlockingWarningRules
    Other warnings and information findings are shown but don't fail the run.

    Each file is analysed with the NEAREST PSScriptAnalyzerSettings.psd1 in the repository:
    the file's own folder first, then each parent folder up to the repo root. A folder with its
    own settings file (e.g. Scripts/Microsoft365/Intune for Windows PowerShell 5.1 scripts)
    REPLACES the root settings for everything below it - settings files don't inherit.

    In GitHub Actions findings become annotations on the file and line (::error / ::warning);
    in Azure Pipelines they become ##vso[task.logissue] entries.

.PARAMETER Files
    Repo-relative paths of the files to lint (the pre-commit hook passes the staged files).
    Omit to lint every .ps1/.psm1/.psd1 file in the repo, which is what CI does.

.PARAMETER Root
    Folder that contains -Files. Defaults to the repo root. The pre-commit hook points this at a
    snapshot of the staged files, so exactly what will be committed is linted. Settings files
    are always resolved against the repository itself.

.PARAMETER BlockingWarningRules
    Warning-severity rules that fail the run anyway.
    PSUseBOMForUnicodeEncodedFile: a non-ASCII file without BOM breaks in Windows PowerShell 5.1.

.EXAMPLE
    ./.github/scripts/Invoke-Lint.ps1
    Lints the whole repo, exactly like CI.

.EXAMPLE
    ./.github/scripts/Invoke-Lint.ps1 -Files 'Scripts/Microsoft365/Intune/Remediate-Something.ps1'
    Lints one file with the same rules (and the right settings file for its folder).
#>
[CmdletBinding()]
param(
    [string[]]$Files,
    [string]$Root,
    [string[]]$BlockingWarningRules = @('PSUseBOMForUnicodeEncodedFile')
)

$ErrorActionPreference = 'Stop'

$minimumAnalyzerVersion = [version]'1.24.0'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $Root) { $Root = $repoRoot }
$Root = (Resolve-Path -LiteralPath $Root).Path

# --- PSScriptAnalyzer (same minimum version locally and in CI) -----------------------------------
$analyzer = Get-Module -ListAvailable -Name PSScriptAnalyzer |
    Where-Object { $_.Version -ge $minimumAnalyzerVersion } |
    Sort-Object Version -Descending | Select-Object -First 1
if (-not $analyzer) {
    Write-Host "Installing PSScriptAnalyzer (>= $minimumAnalyzerVersion)..."
    Install-PSResource -Name PSScriptAnalyzer -TrustRepository -Scope CurrentUser
    $analyzer = Get-Module -ListAvailable -Name PSScriptAnalyzer | Sort-Object Version -Descending | Select-Object -First 1
}
Import-Module $analyzer.Path -Force
Write-Host "PSScriptAnalyzer $($analyzer.Version)"

# --- Output helpers: plain console locally, annotations in CI ------------------------------------
function ConvertTo-GitHubData([string]$Text) {
    $Text.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
}
function ConvertTo-GitHubProperty([string]$Text) {
    (ConvertTo-GitHubData $Text).Replace(':', '%3A').Replace(',', '%2C')
}

function Write-LintMessage {
    param(
        [string]$Message,
        [ValidateSet('error', 'warning', 'info')][string]$Type = 'info',
        [string]$File,
        $Line,
        [string]$Title
    )
    if ($env:GITHUB_ACTIONS -eq 'true' -and $Type -ne 'info') {
        $props = @()
        if ($File)  { $props += 'file=' + (ConvertTo-GitHubProperty $File) }
        if ($Line)  { $props += "line=$Line" }
        if ($Title) { $props += 'title=' + (ConvertTo-GitHubProperty $Title) }
        $propText = if ($props) { ' ' + ($props -join ',') } else { '' }
        Write-Host "::$Type$propText::$(ConvertTo-GitHubData $Message)"
    } elseif ($env:TF_BUILD -and $Type -ne 'info') {
        $where = if ($File) { "${File}:$Line " } else { '' }
        Write-Host "##vso[task.logissue type=$Type]$where$Message"
    } else {
        $colour = @{ error = 'Red'; warning = 'Yellow'; info = 'Gray' }[$Type]
        Write-Host $Message -ForegroundColor $colour
    }
}

# Per-finding annotations only in CI; locally the table is enough
$inCi = ($env:GITHUB_ACTIONS -eq 'true') -or [bool]$env:TF_BUILD

# --- Which files ---------------------------------------------------------------------------------
if (-not $Files) {
    # Whole repo. -Force so dot-folders (.githooks, .github) are included on every OS; skip .git.
    $Files = @(Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Force -Include '*.ps1', '*.psm1', '*.psd1' |
        Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
        ForEach-Object { $_.FullName.Substring($repoRoot.Length).TrimStart('\', '/') })
}
$Files = @($Files | ForEach-Object { $_.Replace('\', '/') })
if ($Files.Count -eq 0) {
    Write-LintMessage 'No PowerShell files to lint.'
    exit 0
}

# --- Nearest settings file per file ----------------------------------------------------------------
function Get-AnalyzerSettingsPath {
    param([string]$RelativePath)
    $dir = Split-Path -Path $RelativePath -Parent
    while ($true) {
        $folder = if ($dir) { Join-Path $repoRoot $dir } else { $repoRoot }
        $candidate = Join-Path $folder 'PSScriptAnalyzerSettings.psd1'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
        if (-not $dir) { return $null }
        $dir = Split-Path -Path $dir -Parent
    }
}

$settingsByFile = @{}
foreach ($file in $Files) { $settingsByFile[$file] = Get-AnalyzerSettingsPath -RelativePath $file }
$settingsByFile.GetEnumerator() | Group-Object { $_.Value } | ForEach-Object {
    $label = if ($_.Name) { $_.Name.Substring($repoRoot.Length).TrimStart('\', '/') } else { '(none - default rule set)' }
    Write-LintMessage "Settings: $label  ->  $($_.Count) file(s)"
}

# --- Analyse ---------------------------------------------------------------------------------------
$findings = @(foreach ($file in $Files) {
    $fullPath = Join-Path $Root $file
    $analyzerParams = @{ Path = $fullPath }
    if ($settingsByFile[$file]) { $analyzerParams.Settings = $settingsByFile[$file] }

    $fileFindings = @(foreach ($r in @(Invoke-ScriptAnalyzer @analyzerParams)) {
        [pscustomobject]@{
            Severity = [string]$r.Severity
            RuleName = $r.RuleName
            File     = $file
            Line     = $r.Line
            Message  = $r.Message
        }
    })

    # Safety net: a settings file with a Severity filter (e.g. only 'Error','Warning') silently drops
    # ParseError findings. Parse the file ourselves so a syntax error always blocks.
    if (-not @($fileFindings | Where-Object Severity -eq 'ParseError').Count) {
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($fullPath, [ref]$null, [ref]$parseErrors)
        foreach ($e in @($parseErrors)) {
            $fileFindings += [pscustomobject]@{
                Severity = 'ParseError'
                RuleName = $e.ErrorId
                File     = $file
                Line     = $e.Extent.StartLineNumber
                Message  = $e.Message
            }
        }
    }
    $fileFindings
})

$blocking = @($findings | Where-Object {
    $_.Severity -in 'ParseError', 'Error' -or
    ($_.Severity -eq 'Warning' -and $BlockingWarningRules -contains $_.RuleName)
})
$nonBlocking = @($findings | Where-Object { $blocking -notcontains $_ })

# Out-String -Width: Out-Host/Format-Table print an empty table when there's no console (git hook, CI)
if ($nonBlocking.Count) {
    Write-Host "`nNon-blocking findings:" -ForegroundColor Yellow
    $nonBlocking | Sort-Object File, Line | Format-Table Severity, RuleName, File, Line, Message -AutoSize -Wrap |
        Out-String -Width 220 | Write-Host
    foreach ($n in @($nonBlocking | Where-Object { $inCi -and $_.Severity -eq 'Warning' })) {
        Write-LintMessage -Type warning -File $n.File -Line $n.Line -Title $n.RuleName -Message $n.Message
    }
}

if ($blocking.Count) {
    Write-Host "`nBlocking findings:" -ForegroundColor Red
    $blocking | Sort-Object File, Line | Format-Table Severity, RuleName, File, Line, Message -AutoSize -Wrap |
        Out-String -Width 220 | Write-Host
    foreach ($b in @($blocking | Where-Object { $inCi })) {
        Write-LintMessage -Type error -File $b.File -Line $b.Line -Title $b.RuleName -Message $b.Message
    }
    Write-LintMessage -Type error -Message "$($blocking.Count) blocking PSScriptAnalyzer finding(s) in $($Files.Count) file(s)."
    exit 1
}

Write-LintMessage "PSScriptAnalyzer: $($Files.Count) file(s), no blocking findings ($($nonBlocking.Count) non-blocking)."
exit 0
