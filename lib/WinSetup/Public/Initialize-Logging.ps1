function Initialize-Logging {
<#
.SYNOPSIS
    Set up a timestamped log file and reset per-run state for Invoke-Step / Show-Summary.

.PARAMETER LogDir
    Directory to write logs to. Defaults to $env:USERPROFILE\win-setup-logs.

.PARAMETER LogPrefix
    Filename prefix. Defaults to 'bootstrap'. Output is "<prefix>-<yyyyMMdd-HHmmss>.log".

.OUTPUTS
    [PSCustomObject] with LogFile, LogDir, Stamp properties.
#>
    [CmdletBinding()]
    param(
        [string]$LogDir    = (Join-Path $env:USERPROFILE 'win-setup-logs'),
        [string]$LogPrefix = 'bootstrap'
    )

    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

    $script:LogFile     = Join-Path $LogDir "$LogPrefix-$stamp.log"
    $script:LogDir      = $LogDir
    $script:LogStamp    = $stamp
    $script:Summary     = New-Object System.Collections.Generic.List[object]
    $script:ActiveSteps = $null
    $script:LogDryRun   = $false

    return [PSCustomObject]@{
        LogFile = $script:LogFile
        LogDir  = $script:LogDir
        Stamp   = $stamp
    }
}
