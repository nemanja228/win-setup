#Requires -Version 5.1
<#
    WinSetup module loader.

    Dot-sources every .ps1 under Public/ and exports their function names.
    Private/ files are dot-sourced but NOT exported, so they're available to
    Public functions without leaking into the caller's session.

    All script-scoped state ($script:LogFile, $script:Summary, $script:ActiveSteps,
    $script:LogDryRun, $script:RepoRoot) lives in module scope and is private to
    the module instance.
#>

$ErrorActionPreference = 'Stop'

$publicDir  = Join-Path $PSScriptRoot 'Public'
$privateDir = Join-Path $PSScriptRoot 'Private'

# Private helpers first (so Public can call them at module-load time if needed)
if (Test-Path $privateDir) {
    Get-ChildItem -Path $privateDir -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
        . $_.FullName
    }
}

# Public functions
if (Test-Path $publicDir) {
    Get-ChildItem -Path $publicDir -Filter '*.ps1' | ForEach-Object {
        . $_.FullName
    }
}

# Resolve the repo root once at module load time (parent of lib/) and cache it.
# Get-ResourcePath reads $script:RepoRoot; callers can override with Set-WinSetupRepoRoot
# if the module is ever loaded from outside the repo tree.
$script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
