function Get-DiskSpaceReport {
    <#
    .SYNOPSIS
        Reports free and used disk space for local fixed drives.

    .DESCRIPTION
        Returns a PSCustomObject per local fixed drive with size, free space
        and percentage free, rounded to 2 decimals. Acts as a template for
        new functions in this toolbox: comment-based help, parameter
        validation, pipeline support and a single responsibility.

    .PARAMETER DriveLetter
        One or more drive letters to report on, e.g. 'C'. Defaults to all
        local fixed drives when omitted.

    .EXAMPLE
        Get-DiskSpaceReport

        Reports on every local fixed drive.

    .EXAMPLE
        Get-DiskSpaceReport -DriveLetter C, D

        Reports only on the C: and D: drives.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^[A-Za-z]$')]
        [string[]]
        $DriveLetter
    )

    begin {
        $drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3'
    }

    process {
        $selected = if ($DriveLetter) {
            $drives | Where-Object { $DriveLetter -contains $_.DeviceID.TrimEnd(':') }
        }
        else {
            $drives
        }

        foreach ($drive in $selected) {
            $freeGb = [math]::Round($drive.FreeSpace / 1GB, 2)
            $sizeGb = [math]::Round($drive.Size / 1GB, 2)
            $percentFree = if ($drive.Size) { [math]::Round(($drive.FreeSpace / $drive.Size) * 100, 2) } else { 0 }

            [pscustomobject]@{
                DriveLetter = $drive.DeviceID
                SizeGB      = $sizeGb
                FreeGB      = $freeGb
                PercentFree = $percentFree
            }
        }
    }
}
