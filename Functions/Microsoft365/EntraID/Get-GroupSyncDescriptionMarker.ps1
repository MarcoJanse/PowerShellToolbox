function Get-GroupSyncDescriptionMarker {
    <#
    .SYNOPSIS
        Returns the marker text that identifies a group as managed by the group sync.
    .DESCRIPTION
        Single source of truth for the marker, used by Format-GroupSyncDescription (writes it)
        and Test-GroupSyncDescription (checks for it). Changing the text means every managed
        group's description has to be updated, so treat it as a stable identifier.
    .EXAMPLE
        Get-GroupSyncDescriptionMarker
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    'Membership managed by automation'
}
