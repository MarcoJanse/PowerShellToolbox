#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Builds mappings/group-sync.json from the group CSV by looking up the object IDs in Entra.
.DESCRIPTION
    The CSV may contain display names or object IDs. Names are resolved through Microsoft
    Graph (exact match, must be unique). Rows for the same destination are merged, so a
    destination with two source groups becomes one entry with two sourceGroupIds.

    Unresolved groups are all reported together (a to-do list for the CSV). Nothing is written
    when any group is unresolved, unless -SkipUnresolved is given. The result is checked with
    Test-GroupSyncMapping and against mappings/group-sync.schema.json before it is saved.

    Needs Connect-MgGraph with Group.Read.All (read only).
.PARAMETER CsvPath
    CSV with the destination group and its source group(s). See Import-GroupSyncCsv.
.PARAMETER OutputPath
    Where to write the JSON. Defaults to group-sync.json in the current folder. To prepare a
    pull request, point it at mappings/group-sync.json in your groupsync-automation clone.
.PARAMETER SchemaPath
    Optional. mappings/group-sync.schema.json from the groupsync-automation clone; when given, the
    result is also validated against it.
.PARAMETER SkipUnresolved
    Write the entries that resolved and report the others.
.EXAMPLE
    Connect-MgGraph -Scopes 'Group.Read.All'
    .\ConvertTo-GroupSyncMapping.ps1 -CsvPath .\memberOf-groups.csv -Delimiter ';' `
        -OutputPath C:\Git\groupsync-automation\mappings\group-sync.json `
        -SchemaPath C:\Git\groupsync-automation\mappings\group-sync.schema.json
.NOTES
Version: 1.0
Last modified on: 2026-11-18
By Claude AI (Sonnet 5.5) and Marco Janse
Tested against a mocked Microsoft Graph only; run with -WhatIf against the real tenant first.
The functions in Functions/Microsoft365/EntraID are copies of the ones in the groupsync-automation repo.
Keep Get-GroupSyncDescriptionMarker identical in both places: the sync only writes to groups whose
description contains that text.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string] $CsvPath,

    [string] $DestinationColumn = 'DisplayName',
    [string] $DestinationIdColumn = 'ObjectId',
    [string] $SourceColumn = 'SourceGroups',
    [string] $Delimiter = ',',
    [string[]] $SourceSeparator = @(';', '|'),

    [string] $OutputPath = (Join-Path $PWD 'group-sync.json'),

    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string] $SchemaPath,

    [switch] $SkipUnresolved
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$functionsPath = Join-Path $PSScriptRoot '../../../Functions/Microsoft365/EntraID'
foreach ($name in @(
    'Get-GroupSyncDescriptionMarker',
    'Get-GroupSyncGroup',
    'Import-GroupSyncCsv',
    'Resolve-GroupSyncGroup',
    'Test-GroupSyncDescription',
    'Test-GroupSyncMapping'
)) {
    . (Join-Path $functionsPath "$name.ps1")
}

if (-not (Get-Command -Name Get-MgContext -ErrorAction SilentlyContinue) -or -not (Get-MgContext)) {
    throw 'Not connected to Microsoft Graph. Run Connect-MgGraph -Scopes Group.Read.All first.'
}

$entries = @(Import-GroupSyncCsv -Path $CsvPath -DestinationColumn $DestinationColumn -DestinationIdColumn $DestinationIdColumn -SourceColumn $SourceColumn -Delimiter $Delimiter -SourceSeparator $SourceSeparator)

$cache = @{}
$resolve = {
    param([string] $identifier)
    $key = $identifier.ToLowerInvariant()
    if (-not $cache.ContainsKey($key)) { $cache[$key] = Resolve-GroupSyncGroup -Identifier $identifier }
    $cache[$key]
}

$mapping = [System.Collections.Generic.List[object]]::new()
$unresolved = [System.Collections.Generic.List[string]]::new()

foreach ($entry in $entries) {
    try {
        $destination = & $resolve $entry.Destination
        $sourceIds = foreach ($sourceIdentifier in $entry.Sources) { (& $resolve $sourceIdentifier).Id }

        if (-not (Test-GroupSyncDescription -Description $destination.Description)) {
            Write-Warning "'$($destination.DisplayName)' does not have the managed-by-automation marker in its description yet; the sync will skip it until Convert-DynamicGroupsToAssigned.ps1 (or you) has added it."
        }
        if ($destination.GroupTypes -contains 'DynamicMembership') {
            Write-Warning "'$($destination.DisplayName)' is still dynamic; the sync will skip it until it is converted."
        }

        $mapping.Add([ordered]@{
                name               = $destination.DisplayName
                sourceGroupIds     = [string[]]@($sourceIds)
                destinationGroupId = $destination.Id
                enabled            = $true
            })
    }
    catch {
        $unresolved.Add("'$($entry.DestinationName)': $($_.Exception.Message)")
    }
}

if ($unresolved.Count -gt 0) {
    Write-Warning "$($unresolved.Count) destination(s) could not be resolved:"
    $unresolved | ForEach-Object { Write-Warning "  $_" }
    if (-not $SkipUnresolved) {
        throw "Nothing written. Fix the CSV (use object IDs for ambiguous names) or run with -SkipUnresolved."
    }
}

$sorted = @($mapping | Sort-Object -Property { $_.name })
$problems = @(Test-GroupSyncMapping -Mapping ($sorted | ForEach-Object { [PSCustomObject]$_ }))
if ($problems.Count -gt 0) {
    $problems | ForEach-Object { Write-Error -Message $_ -ErrorAction Continue }
    throw "The generated mapping failed the sanity checks ($($problems.Count) problem(s)). Nothing written."
}

$json = ConvertTo-Json -InputObject $sorted -Depth 5
if ($SchemaPath -and -not (Test-Json -Json $json -SchemaFile $SchemaPath)) {
    throw "The generated JSON does not match '$SchemaPath'. Nothing written."
}

Set-Content -Path $OutputPath -Value $json -Encoding utf8
Write-Information -MessageData "Wrote $($sorted.Count) mapping(s) to '$OutputPath'. Unresolved: $($unresolved.Count)." -InformationAction Continue
