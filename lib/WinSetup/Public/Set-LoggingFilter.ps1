function Set-LoggingFilter {
<#
.SYNOPSIS
    Restrict which Invoke-Step calls actually execute by tag, and toggle dry-run mode.

.DESCRIPTION
    Call after Initialize-Logging. If -Steps is non-empty, only Invoke-Step calls
    whose -Tags list intersects $Steps will execute; others are recorded as
    'Filtered' in the summary.

    Steps with no -Tags ALWAYS run (use for pre-flight gates).

.PARAMETER Steps
    Tag list. Case-insensitive. Empty or $null clears the filter.

.PARAMETER DryRun
    When $true, Invoke-Step calls marked with -SkipOnDryRun are skipped.
#>
    [CmdletBinding()]
    param(
        [string[]]$Steps,
        [bool]$DryRun = $false
    )

    if ($Steps -and $Steps.Count -gt 0) {
        $script:ActiveSteps = $Steps | ForEach-Object { $_.ToLowerInvariant() }
    } else {
        $script:ActiveSteps = $null
    }
    $script:LogDryRun = $DryRun
}
