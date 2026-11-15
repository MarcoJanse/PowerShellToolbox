<#
.SYNOPSIS
    Runs the Pester suite under /Tests. Called from both .githooks/pre-commit.ps1 (local) and
    .github/workflows/ci.yml (CI) so a local pass and a CI pass mean the same thing.

.DESCRIPTION
    Uses Pester 6.x (installed with PSResourceGet when missing), the same major version locally
    and in CI. Exits with a non-zero code when tests fail (Pester's Run.Exit), so run it as its
    own process when you need to continue afterwards.

    Module dependencies declared in the manifests (RequiredModules) are installed by
    Install-RequiredModules.ps1, not here: CI calls that first; locally, run it once.

.PARAMETER ResultsPath
    When set, also writes NUnitXml test results (and, with -WithCoverage, JaCoCo coverage)
    to this folder, for CI to upload. Omit for a plain local run.

.PARAMETER WithCoverage
    Also collect code coverage over Modules/ and Functions/. Requires -ResultsPath.

.PARAMETER Verbosity
    Pester output verbosity. CI uses Detailed; the pre-commit hook uses the default.
#>
[CmdletBinding()]
param(
    [string]$ResultsPath,
    [switch]$WithCoverage,
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Verbosity = 'Normal'
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# --- Pester 6.x (same major version locally and in CI) ---------------------------------------------
function Get-Pester6 {
    Get-Module -ListAvailable -Name Pester |
        Where-Object { $_.Version.Major -eq 6 } |
        Sort-Object Version -Descending | Select-Object -First 1
}
$pester = Get-Pester6
if (-not $pester) {
    Write-Host 'Installing Pester 6.x...'
    Install-PSResource -Name Pester -Version '[6.0.0, 7.0.0)' -TrustRepository -Scope CurrentUser
    $pester = Get-Pester6
}
Import-Module $pester.Path -Force
Write-Host "Pester $($pester.Version)"

$config = New-PesterConfiguration
$config.Run.Path = Join-Path $repoRoot 'Tests'
$config.Run.Exit = $true
$config.Output.Verbosity = $Verbosity

if ($ResultsPath) {
    New-Item -ItemType Directory -Path $ResultsPath -Force | Out-Null
    $config.TestResult.Enabled      = $true
    $config.TestResult.OutputFormat = 'NUnitXml'
    $config.TestResult.OutputPath   = Join-Path $ResultsPath 'Pester.xml'

    if ($WithCoverage) {
        $config.CodeCoverage.Enabled      = $true
        $config.CodeCoverage.Path         = @(
            Join-Path $repoRoot 'Modules'
            Join-Path $repoRoot 'Functions'
        )
        $config.CodeCoverage.OutputFormat = 'JaCoCo'
        $config.CodeCoverage.OutputPath   = Join-Path $ResultsPath 'Coverage.xml'
    }
}

Invoke-Pester -Configuration $config
