function Invoke-WinGetPackageInstall {
    <#
    .SYNOPSIS
        Installs a single WinGet package via the Microsoft.Winget.Client module.
    .DESCRIPTION
        Thin, module-qualified wrapper around Microsoft.Winget.Client's own
        Install-WinGetPackage cmdlet. This module's public Install-WinGetPackage
        function shares that exact name, and PowerShell resolves functions
        before module cmdlets, so a bare call from inside that function would
        recurse into itself instead of reaching the real cmdlet. Routing
        through this private, distinctly-named helper avoids the collision and
        gives tests a single, ordinary seam to mock.
    .PARAMETER Id
        WinGet package ID to install.
    .PARAMETER Source
        WinGet source to install from.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [string]$Source
    )

    Microsoft.Winget.Client\Install-WinGetPackage -Id $Id -Source $Source -Mode Silent
}
