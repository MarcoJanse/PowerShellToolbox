function Write-GroupSyncLog {
    <#
    .SYNOPSIS
        Writes one timestamped log line to the information stream and, optionally, to a file.
    .DESCRIPTION
        Single place for all sync output, so the console and the log file always show the
        same lines. Format: "<UTC timestamp> [LEVEL ] message".
    .PARAMETER Message
        The text to log.
    .PARAMETER Level
        INFO, ADD, REMOVE, WARN, ERROR or OK.
    .PARAMETER Path
        Log file to append to. When omitted, only the console is written.
    .EXAMPLE
        Write-GroupSyncLog -Message 'IN SYNC' -Level OK -Path ./logs/run.log
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string] $Message,

        [ValidateSet('INFO', 'ADD', 'REMOVE', 'WARN', 'ERROR', 'OK')]
        [string] $Level = 'INFO',

        [string] $Path
    )

    $line = '{0} [{1,-6}] {2}' -f [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'), $Level, $Message
    Write-Information -MessageData $line -InformationAction Continue

    if ($Path) {
        # -WhatIf:$false: a dry run of the sync must still write its log.
        Add-Content -Path $Path -Value $line -Encoding utf8 -WhatIf:$false
    }
}
