function Import-GroupSyncCsv {
    <#
    .SYNOPSIS
        Reads the group list (CSV) and returns one object per destination group.
    .DESCRIPTION
        The defaults match the output of Get-MemberOfDynamicGroups.ps1 exported with Export-Csv:
        DisplayName (destination), ObjectId (destination) and SourceGroups (source group names
        joined with '; ').

        Accepted layouts, which can be mixed:
          - one row per destination, with several sources in one cell separated by one of
            -SourceSeparator (default ';' and '|'),
          - several rows for the same destination, one source each.
        The destination is identified by the ObjectId column when it holds a GUID, otherwise by
        the display name. Source values may be object IDs or display names. Rows for the same
        destination are merged, blank cells are ignored, duplicates are removed, and a
        destination without any source throws, because syncing from nothing would empty the group.
    .PARAMETER Path
        CSV file.
    .PARAMETER DestinationColumn
        Column with the destination display name.
    .PARAMETER DestinationIdColumn
        Optional column with the destination object ID. Used in preference to the name.
    .PARAMETER SourceColumn
        Column with the source group(s).
    .PARAMETER Delimiter
        CSV delimiter. Excel with Dutch regional settings usually saves ';'.
    .PARAMETER SourceSeparator
        Separator(s) between several sources in one cell. May equal the delimiter, because the
        CSV is parsed before the cell is split.
    .EXAMPLE
        Import-GroupSyncCsv -Path ./memberOf-groups.csv -Delimiter ';'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
        [string] $Path,

        [string] $DestinationColumn = 'DisplayName',
        [string] $DestinationIdColumn = 'ObjectId',
        [string] $SourceColumn = 'SourceGroups',
        [string] $Delimiter = ',',
        [string[]] $SourceSeparator = @(';', '|')
    )

    $rows = @(Import-Csv -Path $Path -Delimiter $Delimiter)
    if ($rows.Count -eq 0) {
        throw "CSV '$Path' contains no rows."
    }

    $columns = $rows[0].PSObject.Properties.Name
    $hasName = $columns -contains $DestinationColumn
    $hasId = $columns -contains $DestinationIdColumn
    if (-not ($hasName -or $hasId)) {
        throw "Neither column '$DestinationColumn' nor '$DestinationIdColumn' found in '$Path'. Found: $($columns -join ', '). Use -DestinationColumn / -DestinationIdColumn / -Delimiter."
    }
    if ($columns -notcontains $SourceColumn) {
        throw "Column '$SourceColumn' not found in '$Path'. Found: $($columns -join ', '). Use -SourceColumn / -Delimiter."
    }

    $byDestination = [ordered]@{}
    foreach ($row in $rows) {
        $name = if ($hasName) { ([string]$row.$DestinationColumn).Trim() } else { '' }
        $id = if ($hasId) { ([string]$row.$DestinationIdColumn).Trim() } else { '' }

        $parsed = [guid]::Empty
        $identifier = if ($id -and [guid]::TryParse($id, [ref] $parsed)) { $parsed.ToString('D') } else { $name }
        if (-not $identifier) { continue }

        $key = $identifier.ToLowerInvariant()
        if (-not $byDestination.Contains($key)) {
            $byDestination[$key] = [PSCustomObject]@{
                Destination     = $identifier
                DestinationName = if ($name) { $name } else { $identifier }
                Sources         = [System.Collections.Generic.List[string]]::new()
            }
        }

        $cell = [string]$row.$SourceColumn
        foreach ($source in $cell.Split([string[]]$SourceSeparator, [System.StringSplitOptions]::RemoveEmptyEntries)) {
            $source = $source.Trim()
            $list = $byDestination[$key].Sources
            if ($source -and -not ($list | Where-Object { $_ -ieq $source })) {
                $list.Add($source)
            }
        }
    }

    foreach ($entry in $byDestination.Values) {
        if ($entry.Sources.Count -eq 0) {
            throw "Destination '$($entry.DestinationName)' has no source group in the CSV."
        }
        [PSCustomObject]@{
            Destination     = $entry.Destination
            DestinationName = $entry.DestinationName
            Sources         = [string[]]$entry.Sources
        }
    }
}
