#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }
<#
.SYNOPSIS
Pester 6 tests for Import-GroupSyncCsv (reads the memberOf inventory CSV).

.DESCRIPTION
Runs the function against small CSV files in $TestDrive. No Microsoft Graph connection needed.

Run:
    Invoke-Pester -Path .\Tests\Functions\Import-GroupSyncCsv.Tests.ps1 -Output Detailed

Version: 1.0
Last modified on: 2026-11-18
By Claude AI (Sonnet 5.5) and Marco Janse
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Functions/Microsoft365/EntraID/Import-GroupSyncCsv.ps1')

    function Write-TestCsv {
        param([string[]] $Line)
        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString() + '.csv')
        Set-Content -Path $path -Value $Line
        $path
    }
}

Describe 'Import-GroupSyncCsv' {
    It 'reads the columns that Get-MemberOfDynamicGroups.ps1 exports' {
        $path = Write-TestCsv 'DisplayName,ObjectId,SourceGroups,MemberCount', 'Dest1,11111111-1111-1111-1111-111111111111,Src1; Src2,5'
        $result = @(Import-GroupSyncCsv -Path $path)
        $result.Count | Should -Be 1
        $result[0].Destination | Should -Be '11111111-1111-1111-1111-111111111111'
        $result[0].DestinationName | Should -Be 'Dest1'
        $result[0].Sources | Should -Be @('Src1', 'Src2')
    }

    It 'falls back to the display name when there is no ObjectId column' {
        $path = Write-TestCsv 'DisplayName,SourceGroups', 'Dest1,Src1'
        $result = @(Import-GroupSyncCsv -Path $path)
        $result[0].Destination | Should -Be 'Dest1'
    }

    It 'reads one source per row and merges rows for the same destination' {
        $path = Write-TestCsv 'DisplayName,SourceGroups', 'Dest1,Src1', 'dest1,Src2', 'Dest1,src1'
        $result = @(Import-GroupSyncCsv -Path $path)
        $result.Count | Should -Be 1
        $result[0].Sources | Should -Be @('Src1', 'Src2')
    }

    It 'splits sources on a pipe as well' {
        $path = Write-TestCsv 'DisplayName,SourceGroups', 'Dest1,Src1|Src2'
        (Import-GroupSyncCsv -Path $path).Sources | Should -Be @('Src1', 'Src2')
    }

    It 'supports a semicolon delimiter with semicolons inside quoted cells' {
        $path = Write-TestCsv 'DisplayName;ObjectId;SourceGroups', 'Dest1;;"Src1; Src2"'
        $result = @(Import-GroupSyncCsv -Path $path -Delimiter ';')
        $result[0].Destination | Should -Be 'Dest1'
        $result[0].Sources | Should -Be @('Src1', 'Src2')
    }

    It 'supports custom column names' {
        $path = Write-TestCsv 'Target;From', 'Dest1;Src1|Src2'
        $result = @(Import-GroupSyncCsv -Path $path -Delimiter ';' -DestinationColumn 'Target' -SourceColumn 'From')
        $result[0].Sources.Count | Should -Be 2
    }

    It 'throws when the source column is missing' {
        $path = Write-TestCsv 'DisplayName,Foo', 'a,b'
        { Import-GroupSyncCsv -Path $path } | Should -Throw '*not found*'
    }

    It 'throws when no destination column is found' {
        $path = Write-TestCsv 'Foo,SourceGroups', 'a,b'
        { Import-GroupSyncCsv -Path $path } | Should -Throw '*Neither column*'
    }

    It 'throws when a destination has no source' {
        $path = Write-TestCsv 'DisplayName,SourceGroups', 'Dest1,'
        { Import-GroupSyncCsv -Path $path } | Should -Throw '*no source*'
    }
}
