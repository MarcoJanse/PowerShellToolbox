#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    ONE-TIME: converts the dynamic groups in a CSV (MemberOf rules) to Assigned groups.
.DESCRIPTION
    For every destination group in the CSV:
      1. Resolves the group and its source group(s) (object ID or exact display name).
         A name that is not found, or not unique, skips that group.
      2. Skips it when it is not dynamic, or when its rule does not contain "memberOf"
         (override with -IncludeNonMemberOfRules).
      3. Saves a snapshot (rule, description, member list) to a backup JSON file BEFORE
         changing anything.
      4. Removes "DynamicMembership" from groupTypes, pauses the rule processing state and
         sets the description to the "managed by automation" marker text (the sync refuses
         to write to a group without that marker). A previous description is kept at the end
         when it fits.
      5. Re-reads the member list. If members disappeared during the conversion, they are
         added back from the snapshot (skip with -NoRestore). The sync run that follows
         corrects the membership to the current state of the source groups.

    Every step is logged. Supports -WhatIf and asks for confirmation per group.
    Needs Connect-MgGraph with Group.ReadWrite.All and at least the Groups Administrator role.
.PARAMETER CsvPath
    CSV with the destination group and its source group(s). See Import-GroupSyncCsv.
.PARAMETER IncludeNonMemberOfRules
    Also convert dynamic groups whose rule does not use memberOf.
.PARAMETER NoRestore
    Do not add members back from the snapshot when the conversion removed them.
.PARAMETER LogPath
    Log file. Defaults to ./logs/convert-dynamic-<UTC timestamp>.log.
.PARAMETER BackupPath
    Snapshot file. Defaults to ./logs/convert-dynamic-backup-<UTC timestamp>.json.
.EXAMPLE
    Connect-MgGraph -Scopes 'Group.ReadWrite.All'
    .\Convert-DynamicGroupsToAssigned.ps1 -CsvPath .\memberOf-groups.csv -Delimiter ';' -WhatIf
.NOTES
Version: 1.0
Last modified on: 2026-11-18
By Claude AI (Sonnet 5.5) and Marco Janse
Tested against a mocked Microsoft Graph only; run with -WhatIf against the real tenant first.
The functions in Functions/Microsoft365/EntraID are copies of the ones in the groupsync-automation repo.
Keep Get-GroupSyncDescriptionMarker identical in both places: the sync only writes to groups whose
description contains that text.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string] $CsvPath,

    [string] $DestinationColumn = 'DisplayName',
    [string] $DestinationIdColumn = 'ObjectId',
    [string] $SourceColumn = 'SourceGroups',
    [string] $Delimiter = ',',
    [string[]] $SourceSeparator = @(';', '|'),

    [switch] $IncludeNonMemberOfRules,
    [switch] $NoRestore,

    [ValidateRange(0, 60)]
    [int] $SettleSeconds = 5,

    [string] $LogPath = (Join-Path $PWD ('logs/convert-dynamic-{0:yyyyMMdd-HHmmss}.log' -f [datetime]::UtcNow)),
    [string] $BackupPath = (Join-Path $PWD ('logs/convert-dynamic-backup-{0:yyyyMMdd-HHmmss}.json' -f [datetime]::UtcNow))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$functionsPath = Join-Path $PSScriptRoot '../../../Functions/Microsoft365/EntraID'
foreach ($name in @(
    'Add-GroupSyncMember',
    'Compare-GroupSyncMember',
    'Format-GroupSyncDescription',
    'Get-GroupSyncDescriptionMarker',
    'Get-GroupSyncDirectMember',
    'Get-GroupSyncGroup',
    'Import-GroupSyncCsv',
    'Resolve-GroupSyncGroup',
    'Test-GroupSyncDescription',
    'Write-GroupSyncLog'
)) {
    . (Join-Path $functionsPath "$name.ps1")
}

if (-not (Get-Command -Name Get-MgContext -ErrorAction SilentlyContinue) -or -not (Get-MgContext)) {
    throw 'Not connected to Microsoft Graph. Run Connect-MgGraph -Scopes Group.ReadWrite.All first.'
}

$null = New-Item -ItemType Directory -Path (Split-Path -Path $LogPath -Parent) -Force -WhatIf:$false
$entries = @(Import-GroupSyncCsv -Path $CsvPath -DestinationColumn $DestinationColumn -DestinationIdColumn $DestinationIdColumn -SourceColumn $SourceColumn -Delimiter $Delimiter -SourceSeparator $SourceSeparator)
Write-GroupSyncLog -Message "Read $($entries.Count) destination group(s) from '$CsvPath'.$(if ($WhatIfPreference) { ' WHATIF: nothing will be changed.' })" -Path $LogPath

$backup = [System.Collections.Generic.List[object]]::new()
$counts = @{ Converted = 0; WhatIf = 0; Skipped = 0; Failed = 0 }

foreach ($entry in $entries) {
    Write-GroupSyncLog -Message "=== '$($entry.DestinationName)' ===" -Path $LogPath
    try {
        $group = Resolve-GroupSyncGroup -Identifier $entry.Destination
        $label = "'$($group.DisplayName)' ($($group.Id))"

        if ($group.GroupTypes -notcontains 'DynamicMembership') {
            Write-GroupSyncLog -Message "$label is not dynamic (already Assigned?). Skipped." -Level WARN -Path $LogPath
            $counts.Skipped++
            continue
        }
        if (-not $IncludeNonMemberOfRules -and $group.MembershipRule -notmatch 'memberOf') {
            Write-GroupSyncLog -Message "$label has a rule without memberOf, so it is not affected by the retirement. Skipped. Rule: $($group.MembershipRule)" -Level WARN -Path $LogPath
            $counts.Skipped++
            continue
        }

        # Sources must exist: the sync that follows needs them, and their names go in the description.
        $sourceNames = foreach ($sourceIdentifier in $entry.Sources) {
            (Resolve-GroupSyncGroup -Identifier $sourceIdentifier).DisplayName
        }

        $before = @(Get-GroupSyncDirectMember -GroupId $group.Id)
        Write-GroupSyncLog -Message "$label is dynamic. Rule: $($group.MembershipRule)" -Path $LogPath
        Write-GroupSyncLog -Message "Members before conversion: $($before.Count)" -Path $LogPath

        $description = Format-GroupSyncDescription -SourceGroupName $sourceNames
        if (Test-GroupSyncDescription -Description $group.Description) {
            $description = $group.Description
        }
        elseif ($group.Description) {
            $withPrevious = "$description Previous description: $($group.Description)"
            if ($withPrevious.Length -le 1024) { $description = $withPrevious }
        }

        $groupTypes = [string[]]@($group.GroupTypes | Where-Object { $_ -ne 'DynamicMembership' })

        if (-not $PSCmdlet.ShouldProcess($label, 'Convert from dynamic to assigned membership')) {
            Write-GroupSyncLog -Message "WhatIf: would remove DynamicMembership from groupTypes, pause the rule and set description: $description" -Path $LogPath
            $counts.WhatIf++
            continue
        }

        # Snapshot BEFORE the change.
        $backup.Add([PSCustomObject]@{
                Id                            = $group.Id
                DisplayName                   = $group.DisplayName
                GroupTypes                    = $group.GroupTypes
                MembershipRule                = $group.MembershipRule
                MembershipRuleProcessingState = $group.MembershipRuleProcessingState
                Description                   = $group.Description
                Members                       = $before
            })
        $backup | ConvertTo-Json -Depth 6 | Set-Content -Path $BackupPath -Encoding utf8

        $body = @{
            groupTypes                    = $groupTypes
            membershipRuleProcessingState = 'Paused'
            description                   = $description
        } | ConvertTo-Json
        Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/groups/$($group.Id)" -Body $body -ContentType 'application/json' | Out-Null
        Write-GroupSyncLog -Message "Converted $label to Assigned. Snapshot saved in '$BackupPath'." -Level OK -Path $LogPath

        if ($SettleSeconds -gt 0) { Start-Sleep -Seconds $SettleSeconds }
        $after = Get-GroupSyncGroup -GroupId $group.Id
        if ($after.GroupTypes -contains 'DynamicMembership') {
            throw "Group still reports DynamicMembership after the update."
        }

        $afterMembers = @(Get-GroupSyncDirectMember -GroupId $group.Id)
        Write-GroupSyncLog -Message "Members after conversion: $($afterMembers.Count) (before: $($before.Count))" -Path $LogPath

        $lost = Compare-GroupSyncMember -SourceId @($before | ForEach-Object { $_.Id }) -DestinationId @($afterMembers | ForEach-Object { $_.Id })
        if (@($lost.ToAdd).Count -gt 0) {
            if ($NoRestore) {
                Write-GroupSyncLog -Message "$(@($lost.ToAdd).Count) member(s) were removed by the conversion. -NoRestore given: the sync run must add them back." -Level WARN -Path $LogPath
            }
            else {
                Write-GroupSyncLog -Message "$(@($lost.ToAdd).Count) member(s) were removed by the conversion. Restoring them from the snapshot." -Level WARN -Path $LogPath
                foreach ($memberId in $lost.ToAdd) {
                    $member = $before | Where-Object { $_.Id -eq $memberId } | Select-Object -First 1
                    $null = Add-GroupSyncMember -GroupId $group.Id -MemberId $memberId
                    Write-GroupSyncLog -Message "Restored: $($member.DisplayName) ($($member.UserPrincipalName)) [$($member.Type)] $memberId" -Level ADD -Path $LogPath
                }
                $restored = @(Get-GroupSyncDirectMember -GroupId $group.Id)
                Write-GroupSyncLog -Message "Members after restore: $($restored.Count) (before: $($before.Count))" -Path $LogPath
            }
        }
        $counts.Converted++
    }
    catch {
        Write-GroupSyncLog -Message "Failed for '$($entry.DestinationName)': $($_.Exception.Message)" -Level ERROR -Path $LogPath
        $counts.Failed++
    }
}

Write-GroupSyncLog -Message "Finished: $($counts.Converted) converted, $($counts.WhatIf) would be converted (WhatIf), $($counts.Skipped) skipped, $($counts.Failed) failed. Log: $LogPath" -Level $(if ($counts.Failed -eq 0) { 'OK' } else { 'ERROR' }) -Path $LogPath
if ($counts.Failed -gt 0) {
    throw "$($counts.Failed) group(s) failed. See $LogPath."
}
