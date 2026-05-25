<#
.SYNOPSIS
    Print PATH entries one per line, color-coded for existence and duplicates.

.DESCRIPTION
    Default shows all three views (User, Machine, Process) side by side as
    grouped sections. Per-entry coloring:
      green   — exists on disk
      red     — doesn't exist on disk
      yellow  — duplicate (appears more than once across the chosen scope)

    Use -NoColor for plain output suitable for piping.

.PARAMETER Scope
    'All' (default), 'User', 'Machine', or 'Process'.

.PARAMETER NoColor
    Plain text output, no ANSI sequences. Suitable for piping to grep / select-string.

.EXAMPLE
    .\Get-PathEntries.ps1
    # Shows User, Machine, and Process PATH grouped

.EXAMPLE
    .\Get-PathEntries.ps1 -Scope Process | Select-String 'node'
    # Find node-related PATH entries currently active
#>
[CmdletBinding()]
param(
    [ValidateSet('All','User','Machine','Process')]
    [string]$Scope = 'All',

    [switch]$NoColor
)

function Get-PathArray {
    param([ValidateSet('User','Machine','Process')][string]$Scope)
    if ($Scope -eq 'Process') {
        return @($env:PATH -split ';' | Where-Object { $_ })
    }
    @([Environment]::GetEnvironmentVariable('Path', $Scope) -split ';' | Where-Object { $_ })
}

function Show-Scope {
    param([string]$Scope, [bool]$NoColor)
    $entries = Get-PathArray -Scope $Scope
    $counts  = @{}
    foreach ($e in $entries) {
        $key = $e.TrimEnd('\').ToLowerInvariant()
        if ($counts.ContainsKey($key)) { $counts[$key]++ } else { $counts[$key] = 1 }
    }

    if ($NoColor) {
        Write-Output ""
        Write-Output "=== $Scope PATH ($($entries.Count) entries) ==="
    } else {
        Write-Host ""
        Write-Host "=== $Scope PATH ($($entries.Count) entries) ===" -ForegroundColor Cyan
    }

    foreach ($e in $entries) {
        $key = $e.TrimEnd('\').ToLowerInvariant()
        $exists = Test-Path -LiteralPath $e
        $duplicate = $counts[$key] -gt 1

        if ($NoColor) {
            $tag = if (-not $exists) { '[MISSING] ' } elseif ($duplicate) { '[DUP]     ' } else { '          ' }
            Write-Output "$tag$e"
        } else {
            $color = if (-not $exists) { 'Red' } elseif ($duplicate) { 'Yellow' } else { 'Green' }
            Write-Host "  $e" -ForegroundColor $color
        }
    }
}

$scopes = if ($Scope -eq 'All') { @('User','Machine','Process') } else { @($Scope) }
foreach ($s in $scopes) { Show-Scope -Scope $s -NoColor:$NoColor }
