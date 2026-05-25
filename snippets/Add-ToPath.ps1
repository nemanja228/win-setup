<#
.SYNOPSIS
    Append (or prepend) a directory to PATH, idempotently. User scope by default.

.DESCRIPTION
    Hides the ugly [Environment]::GetEnvironmentVariable / SetEnvironmentVariable
    machinery behind a clean wrapper. No-op if the path is already present
    (case-insensitive). Refreshes $env:PATH so the change is live in the
    current session.

    Machine scope writes to HKLM and requires elevation.

.PARAMETER Path
    Directory to add. Must exist unless -Force.

.PARAMETER Scope
    'User' (default) or 'Machine'.

.PARAMETER Prepend
    Add to the front of PATH instead of the end. Useful when you want the new
    entry to win over conflicting binaries elsewhere on PATH.

.PARAMETER Force
    Add even if the directory doesn't exist on disk yet.

.EXAMPLE
    .\Add-ToPath.ps1 -Path 'C:\Tools\bin'
    # Adds to user PATH (no-op if already present)

.EXAMPLE
    .\Add-ToPath.ps1 -Path 'C:\dev\node\bin' -Prepend
    # Prepends to user PATH so this takes precedence

.EXAMPLE
    .\Add-ToPath.ps1 -Path 'C:\Program Files\MyTool' -Scope Machine
    # Machine-wide (requires elevation)
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Path,

    [ValidateSet('User','Machine')]
    [string]$Scope = 'User',

    [switch]$Prepend,
    [switch]$Force
)

# --- Private helpers (duplicated across snippets so each remains standalone) ---

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
    # Refresh the current session so the change is live without a new shell.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:PATH = "$machine;$user"
}

# --- Main ---

$Path = $Path.TrimEnd('\')

if (-not $Force -and -not (Test-Path -LiteralPath $Path)) {
    Write-Error "Path '$Path' does not exist. Use -Force to add anyway."
    exit 1
}

if ($Scope -eq 'Machine') {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Error "Machine scope requires elevation. Re-run from an elevated PowerShell."
        exit 1
    }
}

$entries = Get-PathArray -Scope $Scope
$alreadyThere = $entries | Where-Object { $_.TrimEnd('\').Equals($Path, [StringComparison]::OrdinalIgnoreCase) }

if ($alreadyThere) {
    Write-Host "Already in $Scope PATH — no-op: $Path" -ForegroundColor DarkGray
    return
}

if ($Prepend) {
    $new = @($Path) + $entries
} else {
    $new = $entries + @($Path)
}

if ($PSCmdlet.ShouldProcess("$Scope PATH", "Add '$Path' ($(if($Prepend){'prepend'}else{'append'}))")) {
    Set-PathArray -Scope $Scope -Entries $new
    Write-Host "Added to $Scope PATH: $Path" -ForegroundColor Green
}
