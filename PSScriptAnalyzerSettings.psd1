@{
    # Used by: VS Code PowerShell extension, the local pre-commit hook
    # (.githooks/pre-commit) and the GitHub Actions CI workflow.
    # Docs: https://github.com/PowerShell/PSScriptAnalyzer

    Severity     = @('Error', 'Warning')

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
