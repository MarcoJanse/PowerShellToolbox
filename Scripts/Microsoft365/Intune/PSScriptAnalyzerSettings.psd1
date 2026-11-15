@{
    # Scripts in this folder run in Windows PowerShell 5.1 (Intune platform scripts, remediations,
    # app requirement scripts). This file REPLACES the root PSScriptAnalyzerSettings.psd1 for this
    # folder and everything below it - settings files don't inherit, so keep the shared settings
    # (Severity, ExcludeRules) in sync with the root file.

    Severity     = @('Error', 'Warning', 'ParseError')

    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
    )

    Rules        = @{
        # Reports PowerShell 7-only syntax ('??', '? :', '?.', ...) as an Error.
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.4')
        }
    }
}
