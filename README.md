# win-setup

Automation for clean-installing Windows 11 on the ASUS Zenbook S16 UM5606WA
(or any similar Win11 box). Designed to be **idempotent** — re-running it after
a Windows feature update reverts settings that Microsoft silently re-enabled.

## What's where

```
win-setup/
├── bootstrap.ps1                  # Orchestrator with tag-based step filtering
├── lib/
│   └── Logging.ps1                # Reusable Write-Log / Invoke-Step / Show-Summary
├── autounattend-firstlogon.ps1    # Embed in Schneegans autounattend.xml (optional)
├── apps.json                      # Winget package list
├── tweaks.reg                     # Registry tweaks
├── CustomAppsList.txt             # Win11Debloat custom Appx removals
├── ooshutup10.cfg                 # PLACEHOLDER — generate via OOSU10.exe
└── README.md                      # This file
```

Every step logs to `%USERPROFILE%\win-setup-logs\bootstrap-<timestamp>.log` plus
companion files for winget, OOSU10, Win11Debloat, and `reg import`.

## Usage

### Full first-time run (initial install)

```powershell
.\bootstrap.ps1
```

Runs every step. About 5–10 minutes plus winget download time.

### After a Windows feature update

```powershell
.\bootstrap.ps1 -PostUpdate
```

Equivalent to `-Steps debloat,privacy,features,power,defender`. Skips restore
point, apps, and one-time stuff. Re-flattens whatever Microsoft re-enabled
(Copilot, Widgets, telemetry, etc.). ~60 seconds.

### Just sync apps

```powershell
.\bootstrap.ps1 -AppsOnly
```

Runs only winget source update + import. Use after editing `apps.json` to add
or remove packages.

### Preview without changes

```powershell
.\bootstrap.ps1 -Verify
```

Dry-run: every step logs what it *would* do, nothing actually executes.

### Cherry-pick by tag

```powershell
# Just reapply tweaks.reg and OOSU10
.\bootstrap.ps1 -Steps privacy

# Just (re)set power plan and Defender exclusions
.\bootstrap.ps1 -Steps power,defender

# Just touch WSL (kernel update + .wslconfig)
.\bootstrap.ps1 -Steps wsl
```

## Step tags

Pre-flight checks (admin, network, OS build, execution policy) have **no tags
and always run** — they're gates, not user-configurable steps.

The configurable steps:

| Step | Tags |
|------|------|
| System restore point | `restore` |
| Win11Debloat | `core` `debloat` |
| O&O ShutUp10++ | `core` `debloat` `privacy` |
| `tweaks.reg` import | `core` `debloat` `privacy` `config` |
| winget source update | `apps` |
| winget import apps.json | `apps` |
| Power: High Performance plan | `core` `power` |
| Power: USB selective suspend | `core` `power` |
| Defender exclusions | `core` `defender` |
| Windows features | `features` |
| WSL update | `wsl` |
| WSL install Ubuntu | `wsl` |
| Write `.wslconfig` | `wsl` `config` |
| TODO checklist on Desktop | `checklist` |

A step runs if **any** of its tags is in your `-Steps` list.

Preset switches:

| Switch | Expands to |
|--------|------------|
| `-PostUpdate` | `-Steps debloat,privacy,features,power,defender` |
| `-AppsOnly` | `-Steps apps` |
| `-Verify` | `-DryRun` (runs everything, changes nothing) |

## Idempotency guarantees

Safe to run repeatedly. Specifically:

- **WSL data is never touched.** Ubuntu install only runs if Ubuntu isn't already registered. Existing Ubuntu home dirs, projects, packages — all left alone.
- **`.wslconfig` is conservative by default.** If you've customized it by hand, the script leaves it. To refresh from the canonical template (and back up the existing one), pass `-ForceWslConfig`.
- **All registry, services, power, Defender, and feature operations are no-ops if the desired state already holds.**
- **Win11Debloat, OOSU10, and `tweaks.reg`** are pure setters — applying them again is a no-op when current state already matches.
- **winget import** treats `apps.json` as desired state: removed-from-system apps that are still in `apps.json` WILL be reinstalled. Keep `apps.json` honest, or use `-AppsOnly` selectively.

## First-time setup (clean install)

1. **(Optional) Generate `autounattend.xml`** via <https://schneegans.de/windows/unattend-generator/>. Embed `autounattend-firstlogon.ps1` as a "runs on first logon" custom script and edit `$RepoRawBase` in it. Skip this step if you want manual OOBE.
2. **(Optional) Copy autounattend.xml** to the root of your install USB.
3. **Install Windows.** With autounattend, OOBE is skipped and your bootstrap runs automatically. Without it, do manual OOBE then run `bootstrap.ps1` yourself.
4. Walk through the TODO checklist that lands on your Desktop.

## Subsequent runs

After every major Windows feature update:

```powershell
cd $env:USERPROFILE\win-setup
.\bootstrap.ps1 -PostUpdate
```

After editing `apps.json`:

```powershell
.\bootstrap.ps1 -AppsOnly
```

After editing `tweaks.reg` or your `ooshutup10.cfg`:

```powershell
.\bootstrap.ps1 -Steps privacy
```

## Customising

| What you want to change | Where |
|-------------------------|-------|
| Add/remove apps installed at first run | `apps.json` |
| Add/remove Appx removals | `CustomAppsList.txt` |
| Add registry settings | `tweaks.reg` |
| Adjust WSL memory/cpu | inside `bootstrap.ps1` — search for `[wsl2]` |
| Defender exclusion paths | inside `bootstrap.ps1` — search for `Defender:` |
| Privacy toggles | regenerate `ooshutup10.cfg` via O&O ShutUp10++ |
| Logging behaviour | `lib/Logging.ps1` |

## Logs

All under `%USERPROFILE%\win-setup-logs\`:

| File | What |
|------|------|
| `bootstrap-<stamp>.log` | Master log of every step |
| `winget-<stamp>.log` | Raw winget output (package-by-package) |
| `oosu-<stamp>.log` | O&O ShutUp10++ stdout |
| `win11debloat-<stamp>.log` | Win11Debloat transcript |
| `reg-import-<stamp>.log` | `reg.exe import` output |

The summary table at the end of the master log gives a one-screen verdict:

```
=================== SUMMARY ===================
Succeeded:    11
Skipped (dry): 0
Filtered out:  3
Failed:        0

  [OK] Pre-flight: admin check  (0.0s)
  [OK] Win11Debloat (apps + telemetry + UI tweaks)  (48.2s)
  [OK] O&O ShutUp10++ (apply saved privacy config)  (3.4s)
  [--] winget: update sources  (0.0s)
  [--] winget: import apps.json  (0.0s)
  [OK] Power: restore High Performance plan  (0.1s)
  ...
```

Markers: `[OK]` ran successfully · `[~ ]` skipped (dry-run) · `[--]` filtered out · `[X ]` failed (with inline exception)

## Reusable logging library

`lib/Logging.ps1` is dot-sourceable from any other PowerShell script you write.
Same colour-coded console + file logging, same step wrapping with timing and
exception capture, same summary table — for free in any utility script.

```powershell
. "$PSScriptRoot\lib\Logging.ps1"
$init = Initialize-Logging -LogPrefix 'my-utility'

Invoke-Step -Name "Do a thing" -Action {
    # ...
}

Show-Summary
```

## What it doesn't do

- **BitLocker** — intentionally skipped for personal use.
- **MyASUS settings** (Battery Care, fan mode, etc.) — app-only, no API.
- **BIOS update** — via MyASUS or the support site.
- **Audient EVO driver** — manual install from audient.com.
- **Office activation** — log in via Word > Account.

These live in the generated `TODO-post-install.txt` on the Desktop.
