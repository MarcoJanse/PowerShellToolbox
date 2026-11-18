function Test-GroupSyncDescription {
    <#
    .SYNOPSIS
        Returns $true when a group description carries the "managed by automation" marker.
    .DESCRIPTION
        Only the marker is checked, not the source group names in the text, because group
        names can change. The check is case-insensitive and does not require the marker at
        the start, so an admin may add text before it.

        Intended use: before syncing into a destination group, the sync reads the group's
        description and skips the mapping when this returns $false. That makes the marker
        an opt-in handshake and stops a mistyped destination ID from overwriting the
        membership of an unrelated group.
    .PARAMETER Description
        The description property of the destination group. Null or empty returns $false.
    .EXAMPLE
        Test-GroupSyncDescription -Description $group.Description
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Description
    )

    if ([string]::IsNullOrWhiteSpace($Description)) {
        return $false
    }

    $Description.IndexOf((Get-GroupSyncDescriptionMarker), [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}
