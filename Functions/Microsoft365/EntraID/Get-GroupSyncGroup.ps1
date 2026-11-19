function Get-GroupSyncGroup {
    <#
    .SYNOPSIS
        Reads the properties of one group that the sync needs, by object ID.
    .DESCRIPTION
        Uses Invoke-MgGraphRequest (Microsoft.Graph.Authentication only), so no other Graph
        module has to be installed. Requires an existing Connect-MgGraph session. A failed
        request throws; callers must never treat that as an empty group.
    .PARAMETER GroupId
        Object ID of the group.
    .EXAMPLE
        Get-GroupSyncGroup -GroupId '00000000-0000-0000-0000-000000000000'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [guid] $GroupId
    )

    $select = 'id,displayName,description,groupTypes,onPremisesSyncEnabled,membershipRule,membershipRuleProcessingState'
    $uri = "https://graph.microsoft.com/v1.0/groups/$($GroupId.ToString('D'))?`$select=$select"
    $group = Invoke-MgGraphRequest -Method GET -Uri $uri

    [PSCustomObject]@{
        Id                      = ([guid]$group['id']).ToString('D')
        DisplayName             = $group['displayName']
        Description             = $group['description']
        GroupTypes              = @($group['groupTypes'])
        OnPremisesSyncEnabled   = [bool]$group['onPremisesSyncEnabled']
        MembershipRule          = $group['membershipRule']
        MembershipRuleProcessingState = $group['membershipRuleProcessingState']
    }
}
