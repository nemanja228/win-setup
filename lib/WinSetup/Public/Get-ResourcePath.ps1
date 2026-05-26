function Get-ResourcePath {
<#
.SYNOPSIS
    Resolve a path under the repo's resources/ tree, regardless of where the caller lives.

.DESCRIPTION
    The module caches $script:RepoRoot at load time (parent of lib/). Get-ResourcePath
    builds a path like <repo>/<area>/<name> and returns it. By default <area> is
    'resources' but it can be overridden for callers that point at other repo dirs.

.PARAMETER Name
    Path under the area folder. May be a simple filename ('tweaks.reg') or contain
    subdirs ('autounattend/render-autounattend.ps1').

.PARAMETER Area
    Top-level folder under the repo. Defaults to 'resources'. Use e.g. 'post-install',
    'profiles', 'snippets' for other areas.

.PARAMETER MustExist
    Throw if the resolved path does not exist on disk.

.EXAMPLE
    Get-ResourcePath -Name 'registry/tweaks.reg'
    # -> E:\code\win-setup\resources\registry\tweaks.reg

.EXAMPLE
    Get-ResourcePath -Area 'post-install' -Name 'Notepad++.Notepad++.ps1'
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)][string]$Name,
        [string]$Area = 'resources',
        [switch]$MustExist
    )

    if (-not $script:RepoRoot) {
        throw "WinSetup: repo root is not set. Re-import the module from its lib/WinSetup location, or set `$script:RepoRoot manually."
    }

    $resolved = Join-Path (Join-Path $script:RepoRoot $Area) $Name

    if ($MustExist -and -not (Test-Path $resolved)) {
        throw "Resource not found: $resolved"
    }
    return $resolved
}
