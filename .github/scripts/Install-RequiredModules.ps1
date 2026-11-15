<#
.SYNOPSIS
    Installs the module dependencies declared in the module manifests (RequiredModules).

.DESCRIPTION
    Reads RequiredModules out of every module manifest under Modules/, so new modules don't need
    a matching ci.yml edit - just declare the dependency in the .psd1 like
    Ictstuff.Windows.PackageManagement already does.

    The declared ModuleVersion is installed as an EXACT pin, not a floor: PSResourceGet's
    open-ended range resolution (e.g. "[1.0.0,]") was verified to pick an arbitrary version rather
    than the true latest for at least one real package on PSGallery, likely because that package
    mixes 3- and 4-part version numbers across its release history, which breaks NuGet's version
    comparison. An exact pin sidesteps that and is reproducible besides - bumping to a newer
    release is then a deliberate manifest edit, not something CI does silently on your behalf.

    Called by .github/workflows/ci.yml before the tests. Run it once locally as well, so the
    tests the pre-commit hook runs find the same module versions as CI.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

$requiredModules = Get-ChildItem -Path (Join-Path $repoRoot 'Modules') -Recurse -Filter *.psd1 |
    ForEach-Object { (Import-PowerShellDataFile -Path $_.FullName).RequiredModules } |
    ForEach-Object { if ($_ -is [string]) { @{ ModuleName = $_ } } else { $_ } } |
    Group-Object { $_.ModuleName } | ForEach-Object { $_.Group[0] }

foreach ($module in $requiredModules) {
    $installArgs = @{
        Name            = $module.ModuleName
        TrustRepository = $true
        Scope           = 'CurrentUser'
    }
    if ($module.ModuleVersion) {
        $installArgs.Version = "[$($module.ModuleVersion)]"
    }

    Write-Host "Installing required module: $($module.ModuleName) $($installArgs.Version)"
    Install-PSResource @installArgs
}
