function Write-Log {
<#
.SYNOPSIS
    Colour-coded console + file logger. Adds timestamp and level prefix to every line.

.PARAMETER Message
    Text to log. May be empty.

.PARAMETER Level
    One of INFO, WARN, ERROR, SUCCESS, STEP, DEBUG, TRACE. Determines colour.

.NOTES
    Reads $script:LogFile (set by Initialize-Logging). If the log file isn't set,
    output goes to console only.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('INFO','WARN','ERROR','SUCCESS','STEP','DEBUG','TRACE')]
        [string]$Level = 'INFO'
    )
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$($Level.PadRight(7))] $Message"
    $color = switch ($Level) {
        'INFO'    { 'Gray' }
        'WARN'    { 'Yellow' }
        'ERROR'   { 'Red' }
        'SUCCESS' { 'Green' }
        'STEP'    { 'Cyan' }
        'DEBUG'   { 'DarkGray' }
        'TRACE'   { 'DarkGray' }
        default   { 'White' }
    }
    Write-Host $line -ForegroundColor $color
    if ($script:LogFile) {
        try {
            Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
        } catch {
            Write-Host "  [log write failed: $($_.Exception.Message)]" -ForegroundColor Red
        }
    }
}
