function Get-GroupSyncDirectMember {
    <#
    .SYNOPSIS
        Returns the direct members of a group (all pages), with a canonical ID per member.
    .DESCRIPTION
        Reads /groups/{id}/members, which returns direct members only (nested group members
        are not expanded). Follows @odata.nextLink until the last page. A failed request
        throws; callers must never treat that as an empty group.
    .PARAMETER GroupId
        Object ID of the group.
    .EXAMPLE
        @(Get-GroupSyncDirectMember -GroupId $id).Count
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [guid] $GroupId
    )

    $uri = "https://graph.microsoft.com/v1.0/groups/$($GroupId.ToString('D'))/members?`$select=id,displayName,userPrincipalName&`$top=999"

    while ($uri) {
        $page = Invoke-MgGraphRequest -Method GET -Uri $uri

        foreach ($member in @($page['value'])) {
            $type = [string]$member['@odata.type']
            [PSCustomObject]@{
                Id                = ([guid]$member['id']).ToString('D')
                DisplayName       = $member['displayName']
                UserPrincipalName = $member['userPrincipalName']
                Type              = if ($type) { $type -replace '^#microsoft\.graph\.', '' } else { 'unknown' }
            }
        }

        $uri = $page['@odata.nextLink']
    }
}
