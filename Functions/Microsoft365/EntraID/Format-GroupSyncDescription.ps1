function Format-GroupSyncDescription {
    <#
    .SYNOPSIS
        Builds the standard description for a destination group that is managed by the sync.
    .DESCRIPTION
        The text starts with the marker that Test-GroupSyncDescription looks for, names the
        source group(s), and warns that manual membership changes are overwritten. Use it
        when converting a group from dynamic to assigned, so every managed group has the
        same wording.

        Entra group descriptions have a length limit; the default of 1024 characters is a
        conservative assumption (the Graph group reference does not state a limit, so
        verify it). When the text with all source names would be longer, the names are
        replaced by a count and a pointer to the mapping file.
    .PARAMETER SourceGroupName
        Display name(s) of the source group(s).
    .PARAMETER MaxLength
        Maximum length of the generated description.
    .EXAMPLE
        Format-GroupSyncDescription -SourceGroupName 'ADDS-Finance', 'ADDS-Accounting'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $SourceGroupName,

        [ValidateRange(100, 4096)]
        [int] $MaxLength = 1024
    )

    $marker = Get-GroupSyncDescriptionMarker
    $warning = 'Do not edit members manually: manual changes will be overwritten.'

    $text = "$marker, synced from: $($SourceGroupName -join ', '). $warning"
    if ($text.Length -gt $MaxLength) {
        $text = "$marker, synced from $($SourceGroupName.Count) source groups (see mappings/group-sync.json). $warning"
    }

    $text
}
