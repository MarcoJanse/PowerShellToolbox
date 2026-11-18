function Resolve-GroupSyncGroup {
    <#
    .SYNOPSIS
        Finds one group by object ID or by exact display name.
    .DESCRIPTION
        A GUID is read directly. Any other text is treated as a display name and must match
        exactly one group; zero or several matches throw, so a name can never silently pick
        the wrong group. Use the object ID in the CSV for names that are not unique.
    .PARAMETER Identifier
        Object ID or display name.
    .EXAMPLE
        Resolve-GroupSyncGroup -Identifier 'ADDS-Finance'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Identifier
    )

    $parsed = [guid]::Empty
    if ([guid]::TryParse($Identifier, [ref] $parsed)) {
        return Get-GroupSyncGroup -GroupId $parsed
    }

    $escaped = $Identifier.Replace("'", "''")
    $filter = [uri]::EscapeDataString("displayName eq '$escaped'")
    $uri = "https://graph.microsoft.com/v1.0/groups?`$filter=$filter&`$select=id"
    $response = Invoke-MgGraphRequest -Method GET -Uri $uri
    $found = @($response['value'])

    if ($found.Count -eq 0) {
        throw "No group found with display name '$Identifier'."
    }
    if ($found.Count -gt 1) {
        throw "$($found.Count) groups have the display name '$Identifier'. Use the object ID in the CSV instead."
    }

    Get-GroupSyncGroup -GroupId ([guid]$found[0]['id'])
}
