function Install-IctWinGetPackage {
    <#
    .SYNOPSIS
        Installs multiple WinGet packages by ID, skipping already-installed ones.
    .DESCRIPTION
        Takes one or more WinGet package IDs and installs each one silently.
        Packages already present on the system are detected and skipped, with
        their installed version reported. Supports pipeline input and -WhatIf.
    .PARAMETER PackageId
        One or more WinGet package IDs to install. Accepts pipeline input.
    .PARAMETER Source
        WinGet source to install from. Defaults to 'winget'.
    .EXAMPLE
        Install-IctWinGetPackage -PackageId 'Microsoft.VisualStudioCode', 'Git.Git'

        Installs VS Code and Git, skipping either if already present.
    .EXAMPLE
        'Microsoft.PowerToys', 'KeePassXCTeam.KeePassXC' | Install-IctWinGetPackage

        Installs packages piped in as strings.
    .EXAMPLE
        Install-IctWinGetPackage -PackageId 'Microsoft.VisualStudioCode' -WhatIf

        Shows what would be installed without making any changes.
    .EXAMPLE
        $packages = @('Microsoft.VisualStudioCode', 'Git.Git', 'Microsoft.PowerToys')
        $packages | Install-IctWinGetPackage

        Installs an array of packages piped in from a variable.
    .NOTES
        Requires the Microsoft.Winget.Client module.
    .LINK
        Export-IctWinGetPackage
    .LINK
        Import-IctWinGetPackage
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]$PackageId,

        [Parameter()]
        [string]$Source = 'winget'
    )

    process {
        foreach ($id in $PackageId) {
            Write-Verbose "Checking installation status for '$id'..."

            try {
                $installed = Get-WinGetPackage -Id $id -MatchOption Equals -ErrorAction SilentlyContinue

                if ($installed) {
                    Write-Host "Skipping '$id' - already installed (v$($installed.InstalledVersion))"
                }
                else {
                    if ($PSCmdlet.ShouldProcess($id, 'Install WinGet package')) {
                        Write-Host "Installing '$id'..."
                        Write-Verbose "Running: Install-WinGetPackage -Id '$id' -Source '$Source' -Mode Silent"

                        Install-WinGetPackage -Id $id -Source $Source -Mode Silent

                        Write-Verbose "Successfully installed '$id'."
                    }
                }
            }
            catch {
                Write-Error "Failed to install '$id'. $_"
            }
        }
    }
}
