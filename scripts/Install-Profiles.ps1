<#
.SYNOPSIS
    Deploy profile files from the repo into their real OS locations.

.DESCRIPTION
    Six categories handled, each as one Invoke-Step so the run shows a summary:

      git         profiles/git/.gitconfig
                    -> $HOME\.gitconfig

      pwsh        profiles/powershell/Microsoft.PowerShell_profile.ps1
                    -> $PROFILE.CurrentUserAllHosts

      omp         profiles/oh-my-posh/*.omp.json
                    -> $env:LocalAppData\oh-my-posh\themes\

      wt          profiles/windows-terminal/settings.json
                    -> $env:LocalAppData\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json

      fonts       profiles/fonts/*.ttf, *.otf
                    -> %WINDIR%\Fonts\ + HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts
                    (install-only, never symlinked; requires elevation)

      ahk         profiles/autohotkey/WtTransparent.ahk
                    -> shortcut in %APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\
                    (.ahk stays in the repo; shortcut points at it)

    All targets are backed up to .bak-<stamp> before being overwritten, unless -Force.
    -WhatIf shows planned operations without writing anything.
    -Symlink creates symbolic links instead of copies — requires elevation OR
    Developer Mode. Falls back to copy with a WARN if neither.

    Fonts are always installed via Copy (not symlinked) because the Fonts
    namespace COM API needs a real file.

.PARAMETER Symlink
    Use symbolic links instead of copies for the file-based targets. Requires
    elevation OR Developer Mode on Windows.

.PARAMETER WhatIf
    Show what would happen without changing anything.

.PARAMETER Force
    Skip the backup of existing target files (overwrites directly).

.PARAMETER Only
    Install just specified categories. Default: all six.
    Choices: git, pwsh, omp, wt, fonts, ahk

.EXAMPLE
    .\Install-Profiles.ps1
    # Deploy everything, copies, backup existing

.EXAMPLE
    .\Install-Profiles.ps1 -Symlink
    # Symlinks where possible (needs elevation or Dev Mode)

.EXAMPLE
    .\Install-Profiles.ps1 -Only git,pwsh
    # Just git config + PowerShell profile

.EXAMPLE
    .\Install-Profiles.ps1 -WhatIf
    # Preview only
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Symlink,
    [switch]$Force,

    [ValidateSet('git','pwsh','omp','wt','fonts','ahk')]
    [string[]]$Only,

    # When set, skip own Initialize-Logging + Show-Summary so this script can
    # share the calling session's logger (e.g. when invoked from bootstrap's
    # steps/80-profiles.ps1). Inner Invoke-Step calls still write to the
    # module's shared $script:Summary, so categories show up in the caller's
    # summary table.
    [switch]$NoInit
)

# =============================================================================
# Module
# =============================================================================

$scriptDir = $PSScriptRoot
$repoRoot  = Split-Path -Parent $scriptDir
$modulePath = Join-Path $repoRoot 'lib\WinSetup'

# When -NoInit is set, a parent session (e.g. bootstrap.ps1) has already loaded
# the module and populated its $script:Summary / $script:LogDryRun. Re-importing
# with -Force would reset those and break the integration. So: import without
# -Force when the module is already loaded.
if (Get-Module -Name WinSetup) {
    Import-Module $modulePath -ErrorAction SilentlyContinue
} else {
    Import-Module $modulePath -Force
}

if (-not $NoInit) {
    $init = Initialize-Logging -LogPrefix 'install-profiles'
    $script:LogDir   = $init.LogDir
    $script:LogStamp = $init.Stamp

    Write-Log -Level STEP -Message "==============================================="
    Write-Log -Level STEP -Message " win-setup Install-Profiles"
    Write-Log -Level STEP -Message "==============================================="
    Write-Log -Level INFO -Message "Repo:   $repoRoot"
    Write-Log -Level INFO -Message "Mode:   $(if ($Symlink) { 'Symlink' } else { 'Copy' })"
    Write-Log -Level INFO -Message "Force:  $($Force.IsPresent)"
    Write-Log -Level INFO -Message "WhatIf: $($WhatIfPreference)"
    if ($Only) { Write-Log -Level INFO -Message "Only:   $($Only -join ',')" }
}

# =============================================================================
# Helpers
# =============================================================================

function Test-DevMode {
    try {
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
        if (-not (Test-Path $key)) { return $false }
        (Get-ItemProperty -Path $key -Name 'AllowDevelopmentWithoutDevLicense' -ErrorAction Stop).AllowDevelopmentWithoutDevLicense -eq 1
    } catch { $false }
}

function Test-IsAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Copy-OrLink {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Target,
        [switch]$Symlink,
        [switch]$Force
    )
    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Source does not exist: $Source"
    }

    # Ensure parent dir
    $parent = Split-Path -Parent $Target
    if (-not (Test-Path -LiteralPath $parent)) {
        if ($PSCmdlet.ShouldProcess($parent, "Create directory")) {
            New-Item -Path $parent -ItemType Directory -Force | Out-Null
        }
    }

    # Backup if target exists
    if ((Test-Path -LiteralPath $Target) -and -not $Force) {
        $backup = "$Target.bak-$script:LogStamp"
        if ($PSCmdlet.ShouldProcess($Target, "Backup to $backup")) {
            Copy-Item -LiteralPath $Target -Destination $backup -Force
            Write-Log -Level DEBUG -Message "    backup: $backup"
        }
    }

    # Existing item must be removed before mklink or before clean copy
    if (Test-Path -LiteralPath $Target) {
        if ($PSCmdlet.ShouldProcess($Target, "Remove existing")) {
            Remove-Item -LiteralPath $Target -Force
        }
    }

    if ($Symlink) {
        $canSymlink = (Test-IsAdmin) -or (Test-DevMode)
        if (-not $canSymlink) {
            Write-Log -Level WARN -Message "    -Symlink requested but neither elevated nor Dev Mode; falling back to copy"
            if ($PSCmdlet.ShouldProcess($Target, "Copy from $Source")) {
                Copy-Item -LiteralPath $Source -Destination $Target -Force
            }
            return
        }
        if ($PSCmdlet.ShouldProcess($Target, "Symlink to $Source")) {
            New-Item -ItemType SymbolicLink -Path $Target -Target $Source -Force | Out-Null
            Write-Log -Level DEBUG -Message "    symlink: $Target -> $Source"
        }
    } else {
        if ($PSCmdlet.ShouldProcess($Target, "Copy from $Source")) {
            Copy-Item -LiteralPath $Source -Destination $Target -Force
            Write-Log -Level DEBUG -Message "    copy: $Source -> $Target"
        }
    }
}

function Install-Font {
    param([Parameter(Mandatory=$true)][string]$FontFile)
    $fontsDir = Join-Path $env:WinDir 'Fonts'
    $name = Split-Path -Leaf $FontFile
    $target = Join-Path $fontsDir $name

    if (Test-Path -LiteralPath $target) {
        Write-Log -Level DEBUG -Message "    font already present: $name (skip)"
        return
    }

    if (-not (Test-IsAdmin)) {
        throw "Installing fonts requires elevation. Re-run from elevated PowerShell."
    }

    if ($PSCmdlet.ShouldProcess($name, "Install to $fontsDir")) {
        # Shell.Application COM with namespace(0x14) (FONTS) + CopyHere flag 0x10 (no UI)
        # is the documented way to install a font without restart — it copies the file
        # AND registers it in HKLM\...\Fonts in one operation.
        $shell = New-Object -ComObject Shell.Application
        $fonts = $shell.NameSpace(0x14)
        $fonts.CopyHere($FontFile, 0x10)
        Write-Log -Level DEBUG -Message "    installed font: $name"
    }
}

function New-StartupShortcut {
    param(
        [Parameter(Mandatory=$true)][string]$Target,
        [Parameter(Mandatory=$true)][string]$ShortcutName
    )
    $startup = [Environment]::GetFolderPath('Startup')
    $linkPath = Join-Path $startup "$ShortcutName.lnk"

    if (Test-Path -LiteralPath $linkPath) {
        # Check if it already points at the right target
        $wsh = New-Object -ComObject WScript.Shell
        $existing = $wsh.CreateShortcut($linkPath)
        if ($existing.TargetPath -eq $Target) {
            Write-Log -Level DEBUG -Message "    startup shortcut already points at $Target — skip"
            return
        }
        Write-Log -Level INFO -Message "    existing shortcut at $linkPath points elsewhere; overwriting"
    }

    if ($PSCmdlet.ShouldProcess($linkPath, "Create startup shortcut to $Target")) {
        $wsh = New-Object -ComObject WScript.Shell
        $shortcut = $wsh.CreateShortcut($linkPath)
        $shortcut.TargetPath = $Target
        $shortcut.WorkingDirectory = Split-Path -Parent $Target
        $shortcut.Save()
        Write-Log -Level DEBUG -Message "    shortcut: $linkPath -> $Target"
    }
}

function Stop-AhkScriptProcess {
    param([Parameter(Mandatory=$true)][string[]]$ScriptPaths)
    # Find AutoHotkey processes whose CommandLine references any of $ScriptPaths,
    # stop only those. Safe when no match (no-op). Other AHK scripts untouched.
    # Waits for each killed process to actually exit so the file handle releases
    # before we try to overwrite.
    $procs = Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'" -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        foreach ($path in $ScriptPaths) {
            if ($p.CommandLine -and $p.CommandLine -like "*$path*") {
                Write-Log -Level DEBUG -Message "    stopping AHK pid=$($p.ProcessId): $($p.CommandLine)"
                Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
                Wait-Process -Id $p.ProcessId -Timeout 5 -ErrorAction SilentlyContinue
                break
            }
        }
    }
}

# =============================================================================
# Categories
# =============================================================================

function Should-Install { param([string]$Cat) -not $Only -or ($Only -contains $Cat) }

# --- git ---

if (Should-Install 'git') {
    Invoke-Step -Name "git: deploy .gitconfig (preserve local additions)" -Tags @('profiles','git') -ContinueOnError -SkipOnDryRun -Action {
        $src = Join-Path $repoRoot 'profiles\git\.gitconfig'
        $dst = Join-Path $HOME '.gitconfig'

        # Snapshot the FULL current global config before overwrite. Anything
        # the user added locally that isn't in the new template (identity,
        # maintenance.repo entries, credential blocks, includeIf paths,
        # custom aliases, …) gets restored afterward. Template wins for
        # keys present in BOTH — that's the point of redeploying.
        $beforeEntries = @()
        $hasGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
        if ($hasGit) {
            $beforeEntries = @(& git config --global --list 2>$null) | Where-Object { $_ }
        } else {
            Write-Log -Level DEBUG -Message "    git not on PATH yet — nothing to preserve"
        }

        # Force copy (never symlink) for .gitconfig. The repo file is identity-
        # free by design; a symlink would route `git config --global` writes
        # INTO the repo file, leaking personal config into a shared file.
        Copy-OrLink -Source $src -Target $dst -Force:$Force

        if ($hasGit -and $beforeEntries.Count -gt 0) {
            $afterEntries = @(& git config --global --list 2>$null) | Where-Object { $_ }
            $afterKeys = @($afterEntries | ForEach-Object { ($_ -split '=', 2)[0] }) | Sort-Object -Unique

            # Group "lost" entries by key. A key with zero entries in the new
            # template (i.e. purely a user addition) gets all its values re-
            # added. A key with entries in the new template (template wins)
            # is skipped.
            $lostByKey = @{}
            foreach ($entry in $beforeEntries) {
                $parts = $entry -split '=', 2
                $key   = $parts[0]
                $value = if ($parts.Count -gt 1) { $parts[1] } else { '' }
                if ($key -notin $afterKeys) {
                    if (-not $lostByKey.ContainsKey($key)) { $lostByKey[$key] = @() }
                    $lostByKey[$key] += $value
                }
            }

            foreach ($key in $lostByKey.Keys | Sort-Object) {
                foreach ($value in $lostByKey[$key]) {
                    if ($PSCmdlet.ShouldProcess($key, "git config --global --add (= $value)")) {
                        & git config --global --add $key $value | Out-Null
                        Write-Log -Level DEBUG -Message "    restored $key = $value"
                    }
                }
            }

            $restoredCount = ($lostByKey.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
            $totalCount    = $beforeEntries.Count
            Write-Log -Level INFO -Message "  Preserved $restoredCount local entr$(if ($restoredCount -eq 1) { 'y' } else { 'ies' }) (of $totalCount in old config); $($afterEntries.Count) entries from the new template"
        }
    }
}

# --- pwsh ---

if (Should-Install 'pwsh') {
    Invoke-Step -Name "pwsh: deploy profile to pwsh 7 + Windows PowerShell 5.1" -Tags @('profiles','pwsh') -ContinueOnError -SkipOnDryRun -Action {
        $src = Join-Path $repoRoot 'profiles\powershell\Microsoft.PowerShell_profile.ps1'
        # Hard-target both PS host directories. Do NOT use $PROFILE.CurrentUserAllHosts —
        # it resolves to whichever host launched the script, leaving the other host
        # unconfigured. Profile internally gates PS 5.1-incompatible features (PSReadLine
        # 2.2+, etc.) via $PSVersionTable checks, so it's safe in both.
        $documents = [Environment]::GetFolderPath('MyDocuments')
        $targets = @(
            (Join-Path $documents 'PowerShell\Microsoft.PowerShell_profile.ps1')         # pwsh 7
            (Join-Path $documents 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1')  # PS 5.1
        )
        foreach ($dst in $targets) {
            Copy-OrLink -Source $src -Target $dst -Symlink:$Symlink -Force:$Force
        }
    }
}

# --- omp ---

if (Should-Install 'omp') {
    Invoke-Step -Name "omp: deploy themes" -Tags @('profiles','omp') -ContinueOnError -SkipOnDryRun -Action {
        $srcDir = Join-Path $repoRoot 'profiles\oh-my-posh'
        $dstDir = Join-Path $env:LocalAppData 'oh-my-posh\themes'
        $themes = Get-ChildItem -Path $srcDir -Filter '*.omp.json' -File
        if (-not $themes -or $themes.Count -eq 0) {
            Write-Log -Level WARN -Message "  no themes in $srcDir"
            return
        }
        foreach ($theme in $themes) {
            $dst = Join-Path $dstDir $theme.Name
            Copy-OrLink -Source $theme.FullName -Target $dst -Symlink:$Symlink -Force:$Force
        }
    }
}

# --- wt ---

if (Should-Install 'wt') {
    Invoke-Step -Name "wt: deploy settings.json" -Tags @('profiles','wt') -ContinueOnError -SkipOnDryRun -Action {
        $src = Join-Path $repoRoot 'profiles\windows-terminal\settings.json'
        $dst = Join-Path $env:LocalAppData 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
        if (-not (Test-Path (Split-Path -Parent $dst))) {
            Write-Log -Level WARN -Message "  Windows Terminal LocalState dir not found — is WT installed? Skipping."
            return
        }
        Copy-OrLink -Source $src -Target $dst -Symlink:$Symlink -Force:$Force
    }
}

# --- fonts ---

if (Should-Install 'fonts') {
    Invoke-Step -Name "fonts: install Nerd Fonts" -Tags @('profiles','fonts') -ContinueOnError -SkipOnDryRun -Action {
        $srcDir = Join-Path $repoRoot 'profiles\fonts'
        if (-not (Test-Path $srcDir)) {
            Write-Log -Level WARN -Message "  profiles\fonts\ does not exist — skipping"
            return
        }
        $fonts = Get-ChildItem -Path $srcDir -Include '*.ttf','*.otf' -File -Recurse
        if (-not $fonts -or $fonts.Count -eq 0) {
            Write-Log -Level WARN -Message "  no .ttf/.otf in $srcDir — skipping"
            return
        }
        foreach ($font in $fonts) {
            Install-Font -FontFile $font.FullName
        }
    }
}

# --- ahk ---

if (Should-Install 'ahk') {
    Invoke-Step -Name "ahk: stage WtTransparent.ahk + startup shortcut" -Tags @('profiles','ahk') -ContinueOnError -SkipOnDryRun -Action {
        $src      = Join-Path $repoRoot 'profiles\autohotkey\WtTransparent.ahk'
        $stageDir = Join-Path $env:LocalAppData 'win-setup\autohotkey'
        $staged   = Join-Path $stageDir 'WtTransparent.ahk'

        if (-not (Test-Path -LiteralPath $src)) {
            Write-Log -Level WARN -Message "  $src not found - skipping"
            return
        }

        if (-not (Test-Path -LiteralPath $stageDir)) {
            New-Item -Path $stageDir -ItemType Directory -Force | Out-Null
        }

        $srcHash    = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
        $stagedHash = if (Test-Path -LiteralPath $staged) {
            (Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash
        } else { '' }

        if ($srcHash -ne $stagedHash) {
            # Kill any AHK process holding the staged file OR the old repo path,
            # so first migration after upgrade also unlocks the destination.
            Stop-AhkScriptProcess -ScriptPaths @($staged, $src)
            Copy-Item -LiteralPath $src -Destination $staged -Force
            Write-Log -Level INFO -Message "  staged: $staged"
        } else {
            Write-Log -Level DEBUG -Message "  staged file up to date - skip copy"
        }

        # Shortcut points at the staged copy. New-StartupShortcut already
        # overwrites a shortcut whose target differs, so migration from the
        # old (repo-pointing) shortcut is automatic.
        New-StartupShortcut -Target $staged -ShortcutName 'WtTransparent'
    }
}

# =============================================================================
# Wrap up — only when standalone (bootstrap's dispatcher handles its own).
# =============================================================================

if (-not $NoInit) {
    Show-Summary

    $failed = (Get-StepSummary | Where-Object { -not $_.Success }).Count
    if ($failed -eq 0) {
        Write-Log -Level SUCCESS -Message "Install-Profiles complete."
        exit 0
    } else {
        Write-Log -Level WARN -Message "$failed step(s) failed."
        exit 1
    }
}
