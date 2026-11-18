function Test-GroupSyncMapping {
    <#
    .SYNOPSIS
        Sanity-checks a group sync mapping and returns a list of problems.
    .DESCRIPTION
        Checks required properties, that 'sourceGroupIds' is a non-empty array of GUIDs
        without duplicates, the GUID format of the destination, a boolean 'enabled' flag,
        that no source equals the destination, and that no destination appears twice.
        GUIDs are compared by value, so alternate spellings of one ID are treated as equal.
        Returns an empty result when the mapping is valid.
    .PARAMETER Mapping
        The parsed content of mappings/group-sync.json.
    .EXAMPLE
        $mapping = Get-Content ./mappings/group-sync.json -Raw | ConvertFrom-Json
        Test-GroupSyncMapping -Mapping $mapping
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Mapping
    )

    $problems = [System.Collections.Generic.List[string]]::new()
    $seenDestinations = @{}
    $index = 0

    foreach ($entry in $Mapping) {
        $label = "Entry $index"
        $index++

        $missing = @('name', 'sourceGroupIds', 'destinationGroupId', 'enabled') |
            Where-Object { $null -eq $entry.PSObject.Properties[$_] }
        if ($missing) {
            foreach ($property in $missing) {
                $problems.Add("${label}: missing property '$property'")
            }
            continue
        }

        if ($entry.enabled -isnot [bool]) {
            $problems.Add("${label}: 'enabled' must be true or false")
        }

        # Guid.TryParse also accepts alternate spellings of the same ID (braces, no hyphens,
        # upper case), so compare the parsed values, not the raw strings.
        $destinationGuid = [guid]::Empty
        $destinationIsGuid = [guid]::TryParse([string] $entry.destinationGroupId, [ref] $destinationGuid)
        if (-not $destinationIsGuid) {
            $problems.Add("${label}: destinationGroupId is not a GUID")
        }

        # ConvertFrom-Json gives an array for a JSON array; a bare string means the old
        # single-source shape (or a typo), which is rejected on purpose: one shape only.
        $sources = $entry.sourceGroupIds
        if ($sources -isnot [System.Collections.IEnumerable] -or $sources -is [string]) {
            $problems.Add("${label}: 'sourceGroupIds' must be an array")
            $sources = @()
        } elseif (@($sources).Count -eq 0) {
            $problems.Add("${label}: 'sourceGroupIds' must contain at least one group ID")
        }

        $seenSources = @{}
        foreach ($source in @($sources)) {
            $sourceGuid = [guid]::Empty
            if (-not [guid]::TryParse([string] $source, [ref] $sourceGuid)) {
                $problems.Add("${label}: source '$source' is not a GUID")
                continue
            }

            $sourceKey = $sourceGuid.ToString('D')
            if ($seenSources.ContainsKey($sourceKey)) {
                $problems.Add("${label}: source '$sourceKey' is listed more than once")
            }
            $seenSources[$sourceKey] = $true

            if ($destinationIsGuid -and $sourceGuid -eq $destinationGuid) {
                $problems.Add("${label}: source and destination are the same group")
            }
        }

        if ($destinationIsGuid) {
            # Canonical lower-case, hyphenated form ("D" format) as the duplicate key.
            $key = $destinationGuid.ToString('D')
            if ($seenDestinations.ContainsKey($key)) {
                $problems.Add("${label}: destination already used by $($seenDestinations[$key])")
            } else {
                $seenDestinations[$key] = $label
            }
        }
    }

    $problems.ToArray()
}
