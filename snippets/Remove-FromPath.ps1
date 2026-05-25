<#
.SYNOPSIS
    Remove a directory from PATH, idempotently. User scope by default.

.DESCRIPTION
    Hides the [Environment] machinery. No-op if the path isn't there. Trims
    empty and duplicate entries while writing back (some installers leave
    broken PATH state). Refreshes $env:PATH for the current session.

    Machine scope writes to HKLM and requires elevation.

.PARAMETER Path
    Directory to remove. Case-insensitive comparison; trailing backslash ignored.

.PARAMETER Scope
    'User' (default) or 'Machine'.

.EXAMPLE
    .\Remove-FromPath.ps1 -Path 'C:\Tools\bin'

.EXAMPLE
    .\Remove-FromPath.ps1 -Path 'C:\OldThing' -Scope Machine
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Path,

    [ValidateSet('User','Machine')]
    [string]$Scope = 'User'
)

function Get-PathArray {
    param([ValidateSet('User','Machine','Process')][string]$Scope)
    if ($Scope -eq 'Process') {
        return @($env:PATH -split ';' | Where-Object { $_ })
    }
    @([Environment]::GetEnvironmentVariable('Path', $Scope) -split ';' | Where-Object { $_ })
}

function Set-PathArray {
    param([ValidateSet('User','Machine')][string]$Scope, [string[]]$Entries)
    [Environment]::SetEnvironmentVariable('Path', ($Entries -join ';'), $Scope)
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:PATH = "$machine;$user"
}

$Path = $Path.TrimEnd('\')

if ($Scope -eq 'Machine') {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Error "Machine scope requires elevation. Re-run from an elevated PowerShell."
        exit 1
    }
}

$entries = Get-PathArray -Scope $Scope
$matched = $entries | Where-Object { $_.TrimEnd('\').Equals($Path, [StringComparison]::OrdinalIgnoreCase) }

if (-not $matched) {
    Write-Host "Not in $Scope PATH — no-op: $Path" -ForegroundColor DarkGray
    return
}

# Filter out the match AND dedupe + drop empties for a tidier PATH while we're here.
$cleaned = $entries |
    Where-Object { -not $_.TrimEnd('\').Equals($Path, [StringComparison]::OrdinalIgnoreCase) } |
    Select-Object -Unique

if ($PSCmdlet.ShouldProcess("$Scope PATH", "Remove '$Path' (matched $(@($matched).Count) entries)")) {
    Set-PathArray -Scope $Scope -Entries $cleaned
    Write-Host "Removed from $Scope PATH: $Path" -ForegroundColor Green
}
