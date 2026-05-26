# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Post-install automation for Windows 11 on an ASUS Zenbook S16 UM5606WA (Ryzen AI 9 HX 370, Radeon 890M, OLED). The whole thing is designed to be **idempotent**: re-running after a Windows feature update reverts settings Microsoft silently re-enabled (Copilot, telemetry, Widgets, web search, etc.). A full run is ~60s.

Use cases the design is tuned for: .NET / WSL dev work, music production with an Audient EVO 4, OLED preservation, minimum Microsoft noise. `additions/setup-guide.md` explains the *why* behind every choice.

## Commands

All PowerShell commands run from the repo root. `bootstrap.ps1` requires an **elevated** PowerShell (it self-checks and throws otherwise).

```powershell
# Full run
.\bootstrap.ps1

# Preview without making changes (skips destructive steps)
.\bootstrap.ps1 -DryRun

# Fast re-run for just the tweaks layer (skips winget import + WSL)
.\bootstrap.ps1 -SkipApps -SkipWSL

# Apply individual layers manually
reg import tweaks.reg
winget import --import-file apps.json --accept-package-agreements --accept-source-agreements --ignore-unavailable
.\OOSU10.exe ooshutup10.cfg /quiet
```

Standalone helpers in `additions/` (interactive, not invoked by `bootstrap.ps1`):

```powershell
.\additions\Setup-Git-GitHub.ps1 -SshEmail ... -KeyAlias ... -HostAlias ... -GistUrl ... -GitUserName ... -GitUserEmail ...
.\additions\Install-Npp-Plugins.ps1
```

There are no tests, no build, no linter. This repo is pure config + automation scripts.

## Architecture

### Three-layer install pipeline

1. **`autounattend.xml`** (generated externally at <https://schneegans.de/windows/unattend-generator/>) — runs during Windows Setup. Skips OOBE, creates the local account, removes Appx packages, applies baseline telemetry settings. Lives on the install USB; **not in this repo** (`.gitignore` excludes it).
2. **First-logon script** — embedded into `autounattend.xml` as a "runs on first logon" custom script. Downloads this repo and launches `bootstrap.ps1` elevated. The previous version `autounattend-firstlogon.ps1` was deleted from the working tree; a new templating approach is being built under `autounattend/` (currently empty placeholders: `autounattend.template.xml`, `render-autounattend.ps1`, `autounattend.md`).
3. **`bootstrap.ps1`** — the workhorse. Runs idempotently any number of times.

### `bootstrap.ps1` internals

Every action goes through `Invoke-Step -Name <label> -Action { ... }`. This wrapper:

- Times each step, captures all output streams (stdout/stderr/warning/error), forwards them to console with severity-colored logging AND to `%USERPROFILE%\win-setup-logs\bootstrap-<stamp>.log`.
- Appends a record to `$Script:Summary` so the final summary table can show `[OK]` / `[~ ]` (skipped) / `[X ]` (failed) per step with duration and error message.
- Honors `-DryRun` via the `-SkipOnDryRun` switch (destructive steps no-op but still appear in summary).
- Honors `-ContinueOnError` — without it, a step's exception aborts the whole script after printing the summary.

The pipeline (in execution order, all wrapped in `Invoke-Step`):

1. Pre-flight: admin check, OS build (warns if <24H2 / build 26100), network, set process-scope execution policy
2. System restore point (overrides the 1440-min throttle via `SystemRestorePointCreationFrequency=0`)
3. **Win11Debloat** — downloaded fresh each run from `https://debloat.raphi.re/` and invoked with `-RunDefaults -Silent`. `CustomAppsList.txt` is copied to `%TEMP%\Win11Debloat\Config\` first so Win11Debloat picks up custom Appx removals.
4. **O&O ShutUp10++** — `OOSU10.exe` downloaded fresh to `%TEMP%`, then invoked with the local `ooshutup10.cfg` and `/quiet`. Skips with a warning if `ooshutup10.cfg` is missing.
5. **`tweaks.reg`** — applied via `reg.exe import`. Settings that Win11Debloat and OOSU10 don't cover (Copilot policy, advertising ID, Storage Sense, classic context menu, etc.).
6. **winget import** of `apps.json` (skipped under `-SkipApps`).
7. Power plan: duplicate the **High Performance** GUID `8c5e7fda-...` if not already present, disable USB selective suspend on AC + DC (matters for the EVO 4 / DPC latency).
8. **Defender exclusions** for `~/source`, `~/projects`, `~/.vscode`, `~/.nuget`, REAPER Media dirs, `C:\ProgramData\Audient`.
9. **Windows optional features**: `Microsoft-Hyper-V-All`, `VirtualMachinePlatform`, `Microsoft-Windows-Subsystem-Linux`, `Containers-DisposableClientVM` (Sandbox). `-NoRestart`; reboot is in the TODO checklist.
10. **WSL2** (skipped under `-SkipWSL`): `wsl --update`, install Ubuntu if not already registered, write `~/.wslconfig` (16GB memory, 8 processors, sparseVhd, autoMemoryReclaim=gradual). Backs up an existing `.wslconfig` to `.bak-<stamp>` only if its contents differ.
11. Generates `TODO-post-install.txt` on the Desktop with manual steps (reboot, BIOS confirmations, MyASUS settings, Audient EVO driver, OLED preservation, etc.).

### Layered debloat philosophy

The order is deliberate — see `additions/setup-guide.md` §10. Each layer fills gaps the previous one leaves:

1. **autounattend** (cleanest — strips Appx at image time, before first boot)
2. **Win11Debloat** (apps + UI tweaks, opinionated defaults)
3. **O&O ShutUp10++** (granular privacy toggles)
4. **`tweaks.reg`** (whatever's still left — registry-only settings)

There's an explicit "do not remove" list in `setup-guide.md` (e.g. `Microsoft.NET.*`, `VCLibs`, `WindowsAppRuntime`, WebView2, Microsoft Store) — these are dependencies for dev work or modern Windows apps and stripping them silently breaks things later.

### Logs

Everything lands in `%USERPROFILE%\win-setup-logs\` with a shared `<stamp>` suffix per run: `bootstrap-`, `winget-`, `oosu-`, `win11debloat-`, `reg-import-`. The summary table at the end of `bootstrap.ps1` is the entry point for triage — failed steps embed the exception message inline.

## Editing conventions

- Adding a new pipeline step: wrap it in `Invoke-Step`. Use `-SkipOnDryRun` for anything destructive and `-ContinueOnError` for non-critical steps so one failure doesn't abort the run. Log details with `Write-Log -Level DEBUG`.
- Adding apps: append to `apps.json` (winget schema 2.0). Use `--ignore-unavailable` semantics — packages that disappear from winget shouldn't break the whole import.
- Adding Appx removals: one PackageFamilyName per line in `CustomAppsList.txt`. Verify exact names with `Get-AppxPackage -AllUsers | Out-GridView` before committing — OEM names drift.
- Registry tweaks: prefer `tweaks.reg` over inline PowerShell so changes survive without re-running `bootstrap.ps1`. Group by section with `;`-prefixed comment headers.
- Privacy toggles: regenerate `ooshutup10.cfg` interactively via `OOSU10.exe`, **File → Export**. Don't hand-edit it. The file in this repo may be a real config or a placeholder — check before relying on it.

## Things this repo intentionally doesn't do

- BitLocker setup
- BIOS update (manual via MyASUS or ASUS support site)
- MyASUS configuration (Battery Care, Fan Mode — not exposed to PowerShell)
- Audient EVO driver install (download manually from audient.com)
- Office activation (sign in via Word > Account)

All of these are listed in the auto-generated `TODO-post-install.txt` on the Desktop.
