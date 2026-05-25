function Invoke-Step {
<#
.SYNOPSIS
    Wraps a scriptblock with logging, timing, dry-run skip, and tag-based filtering.

.DESCRIPTION
    Reads $script:ActiveSteps (filter set by Set-LoggingFilter) and $script:LogDryRun.
    Steps without -Tags always run. Steps with -Tags run only if at least one tag
    matches the active filter (or the filter is empty).

    On exception, the result is recorded as failed. Without -ContinueOnError the
    exception re-throws after summary is shown — so bootstrap fails fast.

.PARAMETER Name
    Human-readable name. Shown in the step header and the summary table.

.PARAMETER Action
    Scriptblock to execute.

.PARAMETER Tags
    Tags this step belongs to. See Set-LoggingFilter.

.PARAMETER ContinueOnError
    If set, exceptions are logged but don't abort the script.

.PARAMETER SkipOnDryRun
    If set, the action is not executed when $script:LogDryRun is true.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][scriptblock]$Action,
        [string[]]$Tags = @(),
        [switch]$ContinueOnError,
        [switch]$SkipOnDryRun
    )

    # ---- Tag-based filtering ----
    # No tags on the step => always runs (good for pre-flight gates).
    # Tags present + filter active => run only if at least one tag matches.
    if ($Tags.Count -gt 0 -and $script:ActiveSteps -and $script:ActiveSteps.Count -gt 0) {
        $lowerTags = $Tags | ForEach-Object { $_.ToLowerInvariant() }
        $match = $lowerTags | Where-Object { $script:ActiveSteps -contains $_ }
        if (-not $match) {
            $result = [PSCustomObject]@{
                Name        = $Name
                Success     = $true
                Skipped     = $true
                Filtered    = $true
                DurationSec = 0.0
                Error       = $null
                Tags        = ($Tags -join ',')
            }
            $script:Summary.Add($result)
            return
        }
    }

    Write-Log -Level STEP -Message ""
    Write-Log -Level STEP -Message "==> $Name"
    if ($Tags.Count -gt 0) {
        Write-Log -Level DEBUG -Message "    tags: $($Tags -join ',')"
    }

    $start  = Get-Date
    $result = [PSCustomObject]@{
        Name        = $Name
        Success     = $false
        Skipped     = $false
        Filtered    = $false
        DurationSec = 0.0
        Error       = $null
        Tags        = ($Tags -join ',')
    }

    try {
        if ($script:LogDryRun -and $SkipOnDryRun) {
            Write-Log -Level WARN -Message "  [DRY-RUN] skipping execution"
            $result.Skipped = $true
            $result.Success = $true
        } else {
            & $Action 2>&1 | ForEach-Object {
                if ($null -eq $_) { return }
                $text = $_.ToString().TrimEnd()
                if ([string]::IsNullOrWhiteSpace($text)) { return }
                if ($_ -is [System.Management.Automation.ErrorRecord]) {
                    Write-Log -Level WARN -Message "  ! $text"
                }
                elseif ($_ -is [System.Management.Automation.WarningRecord]) {
                    Write-Log -Level WARN -Message "  ? $text"
                }
                else {
                    Write-Log -Level TRACE -Message "    $text"
                }
            }
            $result.Success = $true
        }
    } catch {
        $result.Error = $_.Exception.Message
        Write-Log -Level ERROR -Message "  Exception: $($_.Exception.Message)"
        if ($_.ScriptStackTrace) {
            foreach ($l in ($_.ScriptStackTrace -split "`n")) {
                Write-Log -Level ERROR -Message "    $l"
            }
        }
        if (-not $ContinueOnError) {
            $result.DurationSec = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)
            $script:Summary.Add($result)
            Show-Summary
            throw
        }
    }

    $result.DurationSec = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)
    if ($result.Skipped) {
        Write-Log -Level WARN    -Message "  SKIPPED ($($result.DurationSec)s)"
    } elseif ($result.Success) {
        Write-Log -Level SUCCESS -Message "  OK ($($result.DurationSec)s)"
    } else {
        Write-Log -Level ERROR   -Message "  FAILED ($($result.DurationSec)s)"
    }
    $script:Summary.Add($result)
}
