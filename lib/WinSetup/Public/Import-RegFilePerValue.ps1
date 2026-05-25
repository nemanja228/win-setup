function Import-RegFilePerValue {
<#
.SYNOPSIS
    Import a .reg file value-by-value, recording per-value OK/FAIL with reg.exe output.

.DESCRIPTION
    `reg import` on a file with multiple values keeps going past errors and only
    emits a generic "Not all data was successfully written" summary, which is
    useless for triage. This function splits the file into one-value temp .reg
    files, imports each, and returns a structured result.

    Used by step 20 (initial tweaks.reg) and step 60 (post-apps re-apply to clean
    up installer-created context-menu junk).

.PARAMETER Path
    Path to the .reg file.

.PARAMETER DetailLog
    Optional path to a detailed log file. Each value imported gets one line with
    [OK]/[FAIL] + key\value + (on failure) the exact reg.exe output.

.OUTPUTS
    [PSCustomObject] with OkCount, FailCount, Failed (list of {Key, Value, Line, ExitCode, Output}).

.EXAMPLE
    $result = Import-RegFilePerValue -Path (Get-ResourcePath 'registry/tweaks.reg')
    if ($result.FailCount -gt 0) { Write-Log -Level WARN "$($result.FailCount) values failed" }
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [string]$DetailLog
    )

    if (-not (Test-Path $Path)) {
        throw "Reg file not found: $Path"
    }

    if ($DetailLog) {
        Set-Content -Path $DetailLog -Encoding UTF8 -Value @"
Per-value reg import for $Path
Start: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

"@
    }

    $content  = Get-Content -Path $Path -Raw
    $splitIdx = $content.IndexOf("`n[")
    if ($splitIdx -lt 0) {
        throw "No [HKEY_*] sections found in $Path"
    }
    $header = $content.Substring(0, $splitIdx + 1).TrimEnd()
    $rest   = $content.Substring($splitIdx + 1)
    $blocks = $rest -split '(?m)(?=^\[)'

    $okCount = 0
    $failed  = New-Object System.Collections.Generic.List[pscustomobject]

    foreach ($block in $blocks) {
        if ([string]::IsNullOrWhiteSpace($block)) { continue }
        # Join backslash-continuation lines so multi-line binary values stay intact
        $joined = $block -replace '\\\s*\r?\n\s*', ''
        $lines  = $joined -split "`r?`n"
        $keyHeader = $lines[0].Trim()
        if (-not $keyHeader.StartsWith('[')) { continue }

        # Key-delete form: [-HKEY_...]  — emit the line on its own (no value lines below it).
        if ($keyHeader.StartsWith('[-')) {
            $regBody = "$header`r`n`r`n$keyHeader`r`n"
            $tmp     = Join-Path $env:TEMP ("regprobe-{0}.reg" -f [guid]::NewGuid())
            Set-Content -LiteralPath $tmp -Value $regBody -Encoding ASCII
            $out  = & reg.exe import $tmp 2>&1
            $code = $LASTEXITCODE
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue

            $keyPath = $keyHeader.Trim('[', ']').TrimStart('-')

            if ($code -eq 0) {
                $okCount++
                if ($DetailLog) { Add-Content -Path $DetailLog -Encoding UTF8 -Value ("[OK  ] DELETE  {0}" -f $keyPath) }
            } else {
                $failed.Add([pscustomobject]@{
                    Key      = $keyPath
                    Value    = '(delete)'
                    Line     = $keyHeader
                    ExitCode = $code
                    Output   = ($out -join ' | ')
                })
                if ($DetailLog) {
                    Add-Content -Path $DetailLog -Encoding UTF8 -Value ("[FAIL] DELETE  {0}" -f $keyPath)
                    Add-Content -Path $DetailLog -Encoding UTF8 -Value ("       line: $keyHeader")
                    Add-Content -Path $DetailLog -Encoding UTF8 -Value ("       exit: $code")
                    Add-Content -Path $DetailLog -Encoding UTF8 -Value ("       out : $($out -join ' | ')")
                }
            }
            continue
        }

        foreach ($line in $lines[1..($lines.Length - 1)]) {
            $t = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($t)) { continue }
            if ($t.StartsWith(';'))                 { continue }
            if ($t -notmatch '^("[^"]*"|@)\s*=')    { continue }

            $regBody = "$header`r`n`r`n$keyHeader`r`n$t`r`n"
            $tmp     = Join-Path $env:TEMP ("regprobe-{0}.reg" -f [guid]::NewGuid())
            Set-Content -LiteralPath $tmp -Value $regBody -Encoding ASCII
            $out  = & reg.exe import $tmp 2>&1
            $code = $LASTEXITCODE
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue

            $valueName = if ($t.StartsWith('@')) { '(Default)' } else { ($t -split '=', 2)[0].Trim('"') }
            $keyPath   = $keyHeader.Trim('[', ']')

            if ($code -eq 0) {
                $okCount++
                if ($DetailLog) { Add-Content -Path $DetailLog -Encoding UTF8 -Value ("[OK  ] {0}\{1}" -f $keyPath, $valueName) }
            } else {
                $failed.Add([pscustomobject]@{
                    Key      = $keyPath
                    Value    = $valueName
                    Line     = $t
                    ExitCode = $code
                    Output   = ($out -join ' | ')
                })
                if ($DetailLog) {
                    Add-Content -Path $DetailLog -Encoding UTF8 -Value ("[FAIL] {0}\{1}" -f $keyPath, $valueName)
                    Add-Content -Path $DetailLog -Encoding UTF8 -Value ("       line: $t")
                    Add-Content -Path $DetailLog -Encoding UTF8 -Value ("       exit: $code")
                    Add-Content -Path $DetailLog -Encoding UTF8 -Value ("       out : $($out -join ' | ')")
                }
            }
        }
    }

    if ($DetailLog) {
        Add-Content -Path $DetailLog -Encoding UTF8 -Value ("`r`nSummary: {0} OK, {1} FAILED" -f $okCount, $failed.Count)
    }

    return [PSCustomObject]@{
        OkCount   = $okCount
        FailCount = $failed.Count
        Failed    = $failed
    }
}
