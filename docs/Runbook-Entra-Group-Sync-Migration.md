# Runbook: replace memberOf dynamic groups with an automated sync (one-time migration)

Microsoft stopped processing the `memberOf` operator in dynamic membership rules on 3 November 2026. The
groups keep their last calculated members but no longer follow their source groups. This runbook converts
those groups to Assigned and fills them from the source groups, until the GitHub Actions workflow in the
`groupsync-automation` repo takes over.

## Where things live

| What | Where |
|---|---|
| Inventory of memberOf groups | `Scripts/Microsoft365/EntraID/Get-MemberOfDynamicGroups.ps1` (this repo) |
| Conversion and mapping scripts | `Scripts/Microsoft365/EntraID/` (this repo) |
| Sync script and `mappings/group-sync.json` | `groupsync-automation` repo on GHE |

## Prerequisites

- PowerShell 7 and the `Microsoft.Graph.Authentication` module.
- At least the **Groups Administrator** role for the conversion.
- A local clone of `groupsync-automation` with the sync script merged.
- `Connect-MgGraph -Scopes 'Group.ReadWrite.All'` (`Group.Read.All` is enough for the mapping script).

## Input

The CSV from the inventory script works as is:

```powershell
.\Get-MemberOfDynamicGroups.ps1 | Export-Csv .\memberOf-groups.csv -Encoding UTF8
```

Used columns: `DisplayName`, `ObjectId` (the destination group) and `SourceGroups` (source group names joined
with `; `). Remove the rows for groups you do not want to convert. If you saved the file from Excel with
semicolons, add `-Delimiter ';'`. Other column names: `-DestinationColumn`, `-DestinationIdColumn`,
`-SourceColumn`. A source name that is not found or not unique stops that group; put its object ID in the
cell instead of the name.

## Steps (run every script with `-WhatIf` first and read the log)

1. **Convert to Assigned**

   ```powershell
   .\Convert-DynamicGroupsToAssigned.ps1 -CsvPath .\memberOf-groups.csv -WhatIf
   .\Convert-DynamicGroupsToAssigned.ps1 -CsvPath .\memberOf-groups.csv
   ```

   - Only groups that are dynamic and have `memberOf` in the rule are converted.
   - A snapshot (rule, description, members) goes to `logs\convert-dynamic-backup-<timestamp>.json` before
     each change.
   - The description is set to the "Membership managed by automation" text. The sync refuses to write to a
     group without it.
   - Members that disappear during the conversion are put back from the snapshot (`-NoRestore` to skip).

2. **Build the mapping file** (writes into the groupsync clone)

   ```powershell
   .\ConvertTo-GroupSyncMapping.ps1 -CsvPath .\memberOf-groups.csv `
       -OutputPath C:\Git\groupsync-automation\mappings\group-sync.json `
       -SchemaPath C:\Git\groupsync-automation\mappings\group-sync.schema.json
   ```

   Unresolved groups are listed together and nothing is written (`-SkipUnresolved` writes the rest).

3. **Sync, from the groupsync clone**

   ```powershell
   cd C:\Git\groupsync-automation
   .\scripts\entra\Sync-GroupMembers.ps1 -MappingFile .\mappings\group-sync.json -WhatIf
   .\scripts\entra\Sync-GroupMembers.ps1 -MappingFile .\mappings\group-sync.json -MaxChangesPerRun 500
   ```

   A mapping whose changes exceed the limit is skipped as a whole and its planned changes are logged, so
   raise the limit after reading that list.

4. **Commit the mapping** in `groupsync-automation` on a new branch (`feature/initial-mapping`) and open a
   pull request.

## Reading the sync log

Per mapping: the member count of every source and of the destination before any change (plus the union when
there are several sources); `IN SYNC` or one `[ADD]` / `[REMOVE]` line per identity; the counts after the run
and `VERIFIED` or `MISMATCH`. Logs go to `logs\` and contain UPNs, so treat them as personal data.

## References

- [Change static groups to dynamic membership groups in Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/identity/users/groups-change-type)
- [Update group (Microsoft Graph)](https://learn.microsoft.com/en-us/graph/api/group-update)
- [Add a member to a group (Microsoft Graph)](https://learn.microsoft.com/en-us/graph/api/group-post-members)
- [MC1488834: final reminder to replace MemberOf rule operator configurations](https://mc.merill.net/message/MC1488834)
