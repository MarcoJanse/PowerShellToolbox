function Export-WinGetPackage {
    <#
    .SYNOPSIS
        Exports installed WinGet packages to a CSV file.
    .DESCRIPTION
        Retrieves all packages installed via a WinGet source and exports them to a
        semicolon-delimited CSV file, excluding system-managed MSIX and ARP entries.
        The output can later be used with Import-WinGetPackage to reproduce the
        installation on another machine.
    .PARAMETER Path
        Full path to the output CSV file. The file must not already exist.
    .PARAMETER Source
        WinGet source to filter by. Defaults to 'winget'.
    .PARAMETER Delimiter
        Delimiter character used in the CSV file. Defaults to ';'.
    .EXAMPLE
        Export-WinGetPackage -Path 'C:\Temp\winget-packages.csv'

        Exports all winget-sourced packages to the specified CSV file.
    .EXAMPLE
        Export-WinGetPackage -Path 'C:\Temp\winget-packages.csv' -Verbose

        Exports packages with verbose progress output.
    .NOTES
        Requires the Microsoft.Winget.Client module.
    .LINK
        Import-WinGetPackage
    .LINK
        Install-WinGetPackage
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$Source = 'winget',

        [Parameter()]
        [char]$Delimiter = ';'
    )

    Write-Verbose "Starting Export-WinGetPackage"
    Write-Verbose "Output path: $Path"
    Write-Verbose "Source: $Source"

    try {
        Write-Verbose "Retrieving installed WinGet packages from source '$Source'..."
        $packages = Get-WinGetPackage -Source $Source |
            Where-Object { $_.Id -notmatch 'MSIX' -and $_.Id -notmatch 'ARP' } |
            Sort-Object Name |
            Select-Object Name, Id, InstalledVersion

        if (-not $packages) {
            Write-Warning "No packages found for source '$Source'."
            return
        }

        Write-Verbose "Found $($packages.Count) package(s). Exporting to '$Path'..."

        $packages | Export-Csv -Path $Path -Delimiter $Delimiter -NoTypeInformation -NoClobber

        Write-Verbose "Export complete: $($packages.Count) packages written to '$Path'."
    }
    catch {
        Write-Error "Failed to export WinGet packages. $_"
    }
}