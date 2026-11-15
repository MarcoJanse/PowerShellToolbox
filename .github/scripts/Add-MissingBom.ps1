<#
.SYNOPSIS
    Adds a UTF-8 BOM to PowerShell files that contain non-ASCII characters but have no BOM.

.DESCRIPTION
    One-time / occasional repair for what Invoke-Lint.ps1 blocks with PSUseBOMForUnicodeEncodedFile.
    Files that aren't valid UTF-8 (e.g. saved as Windows-1252/ANSI) are reported, not changed:
    converting them automatically would garble their special characters.
    Line endings are kept as they are.

.PARAMETER Path
    Repository root. Defaults to the current folder.

.EXAMPLE
    ./.github/scripts/Add-MissingBom.ps1 -WhatIf
    ./.github/scripts/Add-MissingBom.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$Path = '.')

$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)   # throws on invalid UTF-8
$utf8Bom    = New-Object System.Text.UTF8Encoding($true)
$rootPath   = (Resolve-Path -LiteralPath $Path).Path

Get-ChildItem -LiteralPath $rootPath -Recurse -File -Force -Include '*.ps1', '*.psm1', '*.psd1' |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
    ForEach-Object {
        $file   = $_
        $rel    = $file.FullName.Substring($rootPath.Length).TrimStart('\', '/')
        $bytes  = [IO.File]::ReadAllBytes($file.FullName)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        if ($hasBom -or -not ($bytes -gt 0x7F)) { return }        # already OK, or pure ASCII

        try { $text = $strictUtf8.GetString($bytes) }
        catch [System.Text.DecoderFallbackException] {
            Write-Warning "Not valid UTF-8 (probably Windows-1252/ANSI), not changed - convert by hand: $rel"
            return
        }
        if ($PSCmdlet.ShouldProcess($rel, 'Add UTF-8 BOM')) {
            [IO.File]::WriteAllText($file.FullName, $text, $utf8Bom)
            "BOM added: $rel"
        }
    }
