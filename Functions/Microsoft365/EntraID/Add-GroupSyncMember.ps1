function Add-GroupSyncMember {
    <#
    .SYNOPSIS
        Adds one directory object (user, device, ...) as a direct member of a group.
    .DESCRIPTION
        POST /groups/{id}/members/$ref. Honours -WhatIf and -Confirm. Returns $true when the
        change was made and $false when ShouldProcess declined it.
    .PARAMETER GroupId
        Object ID of the group.
    .PARAMETER MemberId
        Object ID of the member to add.
    .EXAMPLE
        Add-GroupSyncMember -GroupId $group -MemberId $user -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][guid] $GroupId,
        [Parameter(Mandatory)][guid] $MemberId
    )

    if (-not $PSCmdlet.ShouldProcess($GroupId.ToString('D'), "Add member $($MemberId.ToString('D'))")) {
        return $false
    }

    $uri = "https://graph.microsoft.com/v1.0/groups/$($GroupId.ToString('D'))/members/`$ref"
    $body = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($MemberId.ToString('D'))" } | ConvertTo-Json
    Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body -ContentType 'application/json' | Out-Null
    $true
}
