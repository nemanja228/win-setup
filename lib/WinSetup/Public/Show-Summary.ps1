function Show-Summary {
<#
.SYNOPSIS
    Print a final per-step pass/fail/skipped/filtered table to console + log file.

.NOTES
    Reads $script:Summary populated by Invoke-Step. Call once at the end of a run
    (Invoke-Step also calls it implicitly if a non-ContinueOnError step throws).
#>
    [CmdletBinding()]
    param()

    Write-Log -Level STEP -Message ""
    Write-Log -Level STEP -Message "=================== SUMMARY ==================="

    $ok       = ($script:Summary | Where-Object { $_.Success -and -not $_.Skipped }).Count
    $skipped  = ($script:Summary | Where-Object { $_.Skipped -and -not $_.Filtered }).Count
    $filtered = ($script:Summary | Where-Object { $_.Filtered }).Count
    $fail     = ($script:Summary | Where-Object { -not $_.Success }).Count

    Write-Log -Level SUCCESS -Message "Succeeded:    $ok"
    Write-Log -Level WARN    -Message "Skipped (dry):$skipped"
    Write-Log -Level INFO    -Message "Filtered out: $filtered"
    Write-Log -Level $(if ($fail) { 'ERROR' } else { 'INFO' }) -Message "Failed:       $fail"
    Write-Log -Level INFO    -Message ""

    foreach ($s in $script:Summary) {
        $marker =
            if ($s.Filtered)       { '--' }
            elseif ($s.Skipped)    { '~ ' }
            elseif ($s.Success)    { 'OK' }
            else                   { 'X ' }

        $lvl =
            if ($s.Filtered)       { 'DEBUG' }
            elseif ($s.Skipped)    { 'WARN' }
            elseif ($s.Success)    { 'INFO' }
            else                   { 'ERROR' }

        $extra = if ($s.Error) { "  -- $($s.Error)" } else { '' }
        $line  = ("  [{0}] {1}  ({2}s){3}" -f $marker, $s.Name, $s.DurationSec, $extra)
        Write-Log -Level $lvl -Message $line
    }

    Write-Log -Level STEP -Message "==============================================="
    Write-Log -Level INFO -Message ""
    if ($script:LogFile) {
        Write-Log -Level INFO -Message "Full log: $script:LogFile"
    }
}
