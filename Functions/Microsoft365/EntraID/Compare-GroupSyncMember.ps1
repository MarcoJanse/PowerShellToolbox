function Compare-GroupSyncMember {
    <#
    .SYNOPSIS
        Works out which member IDs to add to and remove from a destination group.
    .DESCRIPTION
        Pure set comparison, no Graph calls. IDs are compared case-insensitively.
        ToAdd = in the sources but not in the destination.
        ToRemove = in the destination but not in the sources.
    .PARAMETER SourceId
        Member IDs that the destination should contain (the union of all source groups).
    .PARAMETER DestinationId
        Member IDs that the destination contains now.
    .EXAMPLE
        Compare-GroupSyncMember -SourceId $wanted -DestinationId $current
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [AllowNull()][AllowEmptyCollection()]
        [string[]] $SourceId,

        [AllowNull()][AllowEmptyCollection()]
        [string[]] $DestinationId
    )

    $wanted = [string[]]@($SourceId | Where-Object { $_ })
    $current = [string[]]@($DestinationId | Where-Object { $_ })
    $comparer = [System.StringComparer]::OrdinalIgnoreCase

    $wantedSet = [System.Collections.Generic.HashSet[string]]::new($wanted, $comparer)
    $currentSet = [System.Collections.Generic.HashSet[string]]::new($current, $comparer)

    [PSCustomObject]@{
        ToAdd    = [string[]]@($wantedSet | Where-Object { -not $currentSet.Contains($_) } | Sort-Object)
        ToRemove = [string[]]@($currentSet | Where-Object { -not $wantedSet.Contains($_) } | Sort-Object)
    }
}
