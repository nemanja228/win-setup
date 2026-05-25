<#
.SYNOPSIS
    Enable git's built-in scheduled maintenance for one or more repos.

.DESCRIPTION
    Wraps `git maintenance start` so you can enroll many repos in one shot.
    Each enrolled repo gets a `maintenance.repo = <path>` line added to
    ~/.gitconfig; git runs background prefetch / gc / commit-graph updates
    against that repo on a schedule (via Windows Task Scheduler).

    Three ways to call:

      .\Enable-GitMaintenance.ps1                        # current directory
      .\Enable-GitMaintenance.ps1 -Path 'C:\code\foo'    # single repo
      .\Enable-GitMaintenance.ps1 -Tree 'C:\code'        # every .git under that tree

    Tree mode is for "set and forget" — enroll every repo under your code
    root in one go. Subsequent clones still need a manual enrollment (or
    re-run this with -Tree).

    Idempotent: `git maintenance start` checks before re-adding, so running
    over an already-enrolled repo is a cheap no-op.

    To disable for one repo:   git -C <path> maintenance unregister
    To disable for all repos:  git maintenance unregister  (in each one)

.PARAMETER Path
    Path to a single repo to enroll. Defaults to the current directory.

.PARAMETER Tree
    Path to a directory tree. Every git work-tree under it (anything with
    a .git/) gets enrolled. Recurses; skips bare repos, submodules nested
    inside .git/.

.EXAMPLE
    cd C:\code\my-repo
    .\snippets\Enable-GitMaintenance.ps1

.EXAMPLE
    .\snippets\Enable-GitMaintenance.ps1 -Tree "$env:USERPROFILE\code"
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName='Path')]
param(
    [Parameter(ParameterSetName='Path')]
    [string]$Path = (Get-Location).Path,

    [Parameter(ParameterSetName='Tree', Mandatory=$true)]
    [string]$Tree
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "git is not on PATH. Install git first."
    exit 1
}

function Enable-OneRepo {
    param([string]$RepoPath)
    if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) {
        Write-Host "  skip (not a git repo): $RepoPath" -ForegroundColor DarkGray
        return
    }
    if ($PSCmdlet.ShouldProcess($RepoPath, "git maintenance start")) {
        $out = & git -C $RepoPath maintenance start 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  enrolled: $RepoPath" -ForegroundColor Green
        } else {
            Write-Host "  failed:   $RepoPath  ($out)" -ForegroundColor Yellow
        }
    }
}

if ($PSCmdlet.ParameterSetName -eq 'Tree') {
    if (-not (Test-Path -LiteralPath $Tree)) {
        Write-Error "Tree path does not exist: $Tree"
        exit 1
    }
    Write-Host "Scanning $Tree for git repos..." -ForegroundColor Cyan
    # Find .git dirs but exclude nested ones (e.g. submodules under another .git/).
    # A repo's worktree is the parent of its .git directory.
    $gitDirs = Get-ChildItem -Path $Tree -Filter '.git' -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\\.git\\' }
    Write-Host "Found $($gitDirs.Count) repo(s)" -ForegroundColor Cyan
    Write-Host ""
    foreach ($gd in $gitDirs) {
        Enable-OneRepo -RepoPath $gd.Parent.FullName
    }
} else {
    Enable-OneRepo -RepoPath (Resolve-Path -LiteralPath $Path).Path
}

Write-Host ""
Write-Host "Enrolled repos are listed in ~/.gitconfig under [maintenance]." -ForegroundColor DarkGray
Write-Host "Verify with:  git config --global --get-all maintenance.repo" -ForegroundColor DarkGray
