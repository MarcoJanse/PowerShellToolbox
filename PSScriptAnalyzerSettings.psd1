@{
    # Used by: VS Code PowerShell extension, and .github/scripts/Invoke-Lint.ps1, which both the
    # local pre-commit hook (.githooks/pre-commit) and the GitHub Actions CI workflow call.
    # Invoke-Lint.ps1 uses the NEAREST PSScriptAnalyzerSettings.psd1 per file: a folder with its own
    # settings file (e.g. Scripts/Microsoft365/Intune) replaces this one for everything below it.
    # Docs: https://github.com/PowerShell/PSScriptAnalyzer

    # 'ParseError' must be listed: without it a script with a syntax error reports NO findings at
    # all and passes the lint step. (Invoke-Lint.ps1 also checks syntax itself, as a safety net.)
    Severity     = @('Error', 'Warning', 'ParseError')

    # Only correctness / best-practice / security rules are enabled - no
    # opinionated formatting rules (brace placement, indentation, alignment).
    # Style nags on every commit are a fast way to make linting feel like a
    # punishment instead of a safety net; let VS Code's formatter
    # (.vscode/settings.json) handle layout instead. Revisit this once
    # you're comfortable and want stricter style enforcement.
    ExcludeRules = @(
        # Noisy for a personal toolbox: most scripts here are run
        # interactively (ad-hoc admin tasks), not shipped as products.
        'PSAvoidUsingWriteHost'
    )
}
