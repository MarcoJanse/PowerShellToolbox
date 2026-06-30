#Requires -Modules Pester

<#
    Pester v5 test for the PSToolboxExample module.
    Use this file as the template when you write tests for your own modules:
      1. BeforeAll imports the module fresh so tests don't depend on what's
         already loaded in your session.
      2. Mock external/system calls (here: Get-CimInstance) so tests run
         anywhere, fast, with no dependency on the machine's real disks.
      3. One Describe per function, one It per behaviour you're checking.
    See docs/Testing-and-Linting.md for a beginner walkthrough.
#>

BeforeAll {
    $moduleManifest = Join-Path $PSScriptRoot '..\..\..\Modules\Windows\PSToolboxExample\PSToolboxExample.psd1'
    Import-Module $moduleManifest -Force
}

AfterAll {
    Remove-Module PSToolboxExample -ErrorAction SilentlyContinue
}

Describe 'Get-DiskSpaceReport' {

    BeforeAll {
        Mock -ModuleName PSToolboxExample Get-CimInstance {
            @(
                [pscustomobject]@{ DeviceID = 'C:'; Size = 100GB; FreeSpace = 25GB },
                [pscustomobject]@{ DeviceID = 'D:'; Size = 200GB; FreeSpace = 150GB }
            )
        }
    }

    It 'returns one object per local fixed drive when no DriveLetter is given' {
        $result = Get-DiskSpaceReport
        $result.Count | Should -Be 2
    }

    It 'calculates SizeGB and FreeGB correctly' {
        $result = Get-DiskSpaceReport | Where-Object DriveLetter -EQ 'C:'
        $result.SizeGB | Should -Be 100
        $result.FreeGB | Should -Be 25
    }

    It 'calculates PercentFree correctly' {
        $result = Get-DiskSpaceReport | Where-Object DriveLetter -EQ 'C:'
        $result.PercentFree | Should -Be 25
    }

    It 'filters to the requested DriveLetter only' {
        $result = Get-DiskSpaceReport -DriveLetter C
        $result.Count | Should -Be 1
        $result[0].DriveLetter | Should -Be 'C:'
    }

    It 'returns an empty result for a drive letter that does not exist' {
        $result = Get-DiskSpaceReport -DriveLetter Z
        $result | Should -BeNullOrEmpty
    }
}
