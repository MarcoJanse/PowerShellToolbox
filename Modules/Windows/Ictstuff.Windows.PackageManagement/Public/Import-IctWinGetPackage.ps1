function Import-IctWinGetPackage {
    <#
    .SYNOPSIS
        Reads a WinGet package list from a CSV file and installs missing packages.
    .DESCRIPTION
        Imports a CSV file previously created by Export-IctWinGetPackage and passes
        the package IDs to Install-IctWinGetPackage. Packages already present on
        the system are skipped automatically.
    .PARAMETER Path
        Full path to the CSV file to import. Must contain an 'Id' column.
    .PARAMETER Delimiter
        Delimiter character used in the CSV file. Defaults to ';'.
    .EXAMPLE
        Import-IctWinGetPackage -Path 'C:\Temp\winget-packages.csv'

        Reads the CSV and installs any packages not already present.
    .EXAMPLE
        Import-IctWinGetPackage -Path 'C:\Temp\winget-packages.csv' -WhatIf

        Shows which packages would be installed without making any changes.
    .NOTES
        Requires the Microsoft.Winget.Client PowerShell module.
    .LINK
        Export-IctWinGetPackage
    .LINK
        Install-IctWinGetPackage
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [char]$Delimiter = ';'
    )

    Write-Verbose "Starting Import-IctWinGetPackage"
    Write-Verbose "Input path: $Path"

    if (-not (Test-Path -Path $Path)) {
        Write-Error "File not found: '$Path'"
        return
    }

    try {
        Write-Verbose "Reading package list from '$Path'..."
        $csv = Import-Csv -Path $Path -Delimiter $Delimiter

        if (-not $csv) {
            Write-Warning "CSV file '$Path' is empty or could not be parsed."
            return
        }

        if (-not ($csv | Get-Member -Name 'Id' -ErrorAction SilentlyContinue)) {
            Write-Error "CSV file does not contain a required 'Id' column."
            return
        }

        $packageIds = $csv | Select-Object -ExpandProperty Id
        Write-Verbose "Found $($packageIds.Count) package ID(s) in CSV."

        if ($PSCmdlet.ShouldProcess($Path, 'Install packages from CSV')) {
            Install-IctWinGetPackage -PackageId $packageIds
        }
    }
    catch {
        Write-Error "Failed to import WinGet packages from '$Path'. $_"
    }
}
