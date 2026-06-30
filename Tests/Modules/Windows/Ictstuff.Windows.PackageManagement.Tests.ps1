#Requires -Modules Pester

<#
    Pester v5 tests for the Ictstuff.Windows.PackageManagement module.
    Notable patterns demonstrated here, beyond the basics in
    PSToolboxExample.Tests.ps1:
      - TestDrive: a Pester-managed temp folder, auto-cleaned after the run.
        Used here for real (unmocked) Export-Csv/Import-Csv round-tripping.
      - Mocking external cmdlets via -ModuleName, to verify Install-IctWinGetPackage
        calls Install-WinGetPackage correctly without ever touching the real
        WinGet client.
      - Should -Invoke to assert a mock was (or wasn't) called, including
        under -WhatIf.
    See docs/Testing-and-Linting.md for a beginner walkthrough.
#>

BeforeAll {
    $moduleManifest = Join-Path $PSScriptRoot '..\..\..\Modules\Windows\Ictstuff.Windows.PackageManagement\Ictstuff.Windows.PackageManagement.psd1'
    Import-Module $moduleManifest -Force
}

AfterAll {
    Remove-Module Ictstuff.Windows.PackageManagement -ErrorAction SilentlyContinue
}

Describe 'Export-IctWinGetPackage' {

    BeforeAll {
        Mock -ModuleName Ictstuff.Windows.PackageManagement Get-WinGetPackage {
            @(
                [pscustomobject]@{ Name = 'Git'; Id = 'Git.Git'; InstalledVersion = '2.45.0' },
                [pscustomobject]@{ Name = 'VS Code'; Id = 'Microsoft.VisualStudioCode'; InstalledVersion = '1.90.0' },
                [pscustomobject]@{ Name = 'System Component'; Id = 'MSIX\SomeSystemPackage'; InstalledVersion = '1.0.0' },
                [pscustomobject]@{ Name = 'Legacy Entry'; Id = 'ARP\LegacyApp'; InstalledVersion = '1.0.0' }
            )
        }
    }

    It 'exports only the non-MSIX, non-ARP packages' {
        $path = Join-Path $TestDrive 'packages.csv'

        Export-IctWinGetPackage -Path $path

        $result = Import-Csv -Path $path -Delimiter ';'
        $result.Count | Should -Be 2
        $result.Id | Should -Contain 'Git.Git'
        $result.Id | Should -Contain 'Microsoft.VisualStudioCode'
    }

    It 'uses the specified delimiter' {
        $path = Join-Path $TestDrive 'packages-comma.csv'

        Export-IctWinGetPackage -Path $path -Delimiter ','

        (Get-Content -Path $path -First 1) | Should -Match ','
    }

    It 'does not create a file when no packages are found' {
        Mock -ModuleName Ictstuff.Windows.PackageManagement Get-WinGetPackage { @() }
        $path = Join-Path $TestDrive 'empty.csv'

        Export-IctWinGetPackage -Path $path -WarningAction SilentlyContinue

        Test-Path -Path $path | Should -BeFalse
    }

    It 'does not overwrite a file that already exists' {
        $path = Join-Path $TestDrive 'existing.csv'
        'do-not-touch-me' | Set-Content -Path $path

        Export-IctWinGetPackage -Path $path -ErrorAction SilentlyContinue

        Get-Content -Path $path -Raw | Should -Match 'do-not-touch-me'
    }
}

Describe 'Import-IctWinGetPackage' {

    BeforeAll {
        Mock -ModuleName Ictstuff.Windows.PackageManagement Install-IctWinGetPackage { }
    }

    It 'calls Install-IctWinGetPackage with the package IDs from the CSV' {
        $path = Join-Path $TestDrive 'import.csv'
        @(
            [pscustomobject]@{ Name = 'Git'; Id = 'Git.Git' },
            [pscustomobject]@{ Name = 'VS Code'; Id = 'Microsoft.VisualStudioCode' }
        ) | Export-Csv -Path $path -Delimiter ';' -NoTypeInformation

        Import-IctWinGetPackage -Path $path

        Should -Invoke -ModuleName Ictstuff.Windows.PackageManagement Install-IctWinGetPackage -Times 1 -Exactly -ParameterFilter {
            $PackageId.Count -eq 2 -and $PackageId -contains 'Git.Git'
        }
    }

    It 'does not call Install-IctWinGetPackage when the file does not exist' {
        Import-IctWinGetPackage -Path (Join-Path $TestDrive 'missing.csv') -ErrorAction SilentlyContinue

        Should -Invoke -ModuleName Ictstuff.Windows.PackageManagement Install-IctWinGetPackage -Times 0
    }

    It 'does not call Install-IctWinGetPackage when the CSV has no Id column' {
        $path = Join-Path $TestDrive 'no-id-column.csv'
        @([pscustomobject]@{ Name = 'Git' }) | Export-Csv -Path $path -Delimiter ';' -NoTypeInformation

        Import-IctWinGetPackage -Path $path -ErrorAction SilentlyContinue

        Should -Invoke -ModuleName Ictstuff.Windows.PackageManagement Install-IctWinGetPackage -Times 0
    }

    It 'does not install anything when -WhatIf is specified' {
        $path = Join-Path $TestDrive 'whatif.csv'
        @([pscustomobject]@{ Name = 'Git'; Id = 'Git.Git' }) | Export-Csv -Path $path -Delimiter ';' -NoTypeInformation

        Import-IctWinGetPackage -Path $path -WhatIf

        Should -Invoke -ModuleName Ictstuff.Windows.PackageManagement Install-IctWinGetPackage -Times 0
    }
}

Describe 'Install-IctWinGetPackage' {

    BeforeAll {
        Mock -ModuleName Ictstuff.Windows.PackageManagement Install-WinGetPackage { }
    }

    It 'skips a package that is already installed' {
        Mock -ModuleName Ictstuff.Windows.PackageManagement Get-WinGetPackage {
            [pscustomobject]@{ Id = 'Git.Git'; InstalledVersion = '2.45.0' }
        }

        Install-IctWinGetPackage -PackageId 'Git.Git'

        Should -Invoke -ModuleName Ictstuff.Windows.PackageManagement Install-WinGetPackage -Times 0
    }

    It 'installs a package that is not already installed' {
        Mock -ModuleName Ictstuff.Windows.PackageManagement Get-WinGetPackage { $null }

        Install-IctWinGetPackage -PackageId 'Git.Git'

        Should -Invoke -ModuleName Ictstuff.Windows.PackageManagement Install-WinGetPackage -Times 1 -Exactly -ParameterFilter {
            $Id -eq 'Git.Git' -and $Source -eq 'winget'
        }
    }

    It 'accepts multiple package IDs from the pipeline' {
        Mock -ModuleName Ictstuff.Windows.PackageManagement Get-WinGetPackage { $null }

        'Git.Git', 'Microsoft.VisualStudioCode' | Install-IctWinGetPackage

        Should -Invoke -ModuleName Ictstuff.Windows.PackageManagement Install-WinGetPackage -Times 2 -Exactly
    }

    It 'does not install anything when -WhatIf is specified' {
        Mock -ModuleName Ictstuff.Windows.PackageManagement Get-WinGetPackage { $null }

        Install-IctWinGetPackage -PackageId 'Git.Git' -WhatIf

        Should -Invoke -ModuleName Ictstuff.Windows.PackageManagement Install-WinGetPackage -Times 0
    }
}
