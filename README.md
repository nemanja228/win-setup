# win-setup

Automation for clean-installing Windows 11 on the ASUS Zenbook S16 UM5606WA
(or any similar Win11 box). Designed to be **idempotent** — re-running it after
a Windows feature update reverts settings that Microsoft silently re-enabled.

## What it does

A single elevated PowerShell run will:

1. Create a system restore point.
2. Run **Win11Debloat** (apps, telemetry, UI tweaks) silently with defaults +
   your custom apps list.
3. Apply your saved **O&O ShutUp10++** privacy config.
4. Apply additional **registry tweaks** (`tweaks.reg`).
5. Bulk-install your dev/audio/general apps via **winget import**.
6. Restore the **High Performance** power plan and disable USB selective
   suspend (matters for audio interfaces).
7. Add Windows Defender **exclusions** for dev/audio paths.
8. Enable **Hyper-V, WSL, VirtualMachinePlatform, Windows Sandbox** features.
9. Update WSL kernel, install Ubuntu, write `.wslconfig`.
10. Drop a manual TODO checklist on the Desktop.

Every step is logged to console (colour-coded) **and** to a timestamped file:
`%USERPROFILE%\win-setup-logs\bootstrap-YYYYMMDD-HHMMSS.log`.

A summary table prints at the end:

```
=================== SUMMARY ===================
Succeeded: 14
Skipped:   1
Failed:    0

  [OK] Pre-flight: admin check  (0.0s)
  [OK] Pre-flight: network connectivity  (0.4s)
  [OK] Create system restore point  (4.1s)
  [OK] Win11Debloat (apps + telemetry + UI tweaks)  (48.2s)
  [~ ] O&O ShutUp10++ (apply saved privacy config)  (0.1s)  -- skipped (no cfg)
  [OK] Apply registry tweaks (tweaks.reg)  (0.2s)
  ...
```

## Files

| File | Purpose |
|------|---------|
| `bootstrap.ps1` | The main script. Idempotent. Run with `-DryRun` first to preview. |
| `autounattend-firstlogon.ps1` | Embed into Schneegans' autounattend.xml so the first logon auto-fetches and runs `bootstrap.ps1`. |
| `apps.json` | Winget package list — edit to match your stack. |
| `tweaks.reg` | UI / privacy / Copilot / Storage Sense / etc. tweaks not handled by the tools. |
| `CustomAppsList.txt` | Custom Appx removals consumed by Win11Debloat. |
| `ooshutup10.cfg` | **PLACEHOLDER** — replace with your real exported O&O config. |

## First-time setup (clean install)

1. **Generate autounattend.xml** via <https://schneegans.de/windows/unattend-generator/>.
   In the "Custom scripts" section, paste the contents of
   `autounattend-firstlogon.ps1` as a "runs on first logon" script.
   Edit `$RepoRawBase` inside it to point at your repo / share.
2. **Copy autounattend.xml** to the root of your Windows 11 installation USB
   (next to `setup.exe`).
3. **Install Windows.** It will:
   - Skip OOBE.
   - Create the local account.
   - Remove apps you marked for removal.
   - On first logon, fetch this folder, then launch `bootstrap.ps1` elevated.
4. Watch `bootstrap.ps1` run, or check
   `%USERPROFILE%\win-setup-logs\bootstrap-*.log` afterwards.
5. Walk through the TODO checklist on your Desktop.

## Subsequent runs (after Windows feature updates)

```powershell
cd $env:USERPROFILE\win-setup
.\bootstrap.ps1
```

About 60 seconds. Telemetry, Copilot, web search, and other Microsoft Goodies
that snuck back in will be turned off again.

## Useful flags

```powershell
# Preview without making changes
.\bootstrap.ps1 -DryRun

# Skip the app install step (if you only want to re-apply tweaks)
.\bootstrap.ps1 -SkipApps

# Skip WSL setup
.\bootstrap.ps1 -SkipWSL
```

## Customising

| What you want to change | Where |
|--|--|
| Add/remove apps installed at first run | `apps.json` |
| Add/remove Appx removals | `CustomAppsList.txt` |
| Add registry settings | `tweaks.reg` |
| Adjust WSL memory/cpu | inside `bootstrap.ps1` — search for `[wsl2]` |
| Defender exclusion paths | inside `bootstrap.ps1` — search for `Defender:` |
| Privacy toggles | regenerate `ooshutup10.cfg` via O&O ShutUp10++ |

## Logs

Everything is under `%USERPROFILE%\win-setup-logs\`:

| File | What |
|--|--|
| `bootstrap-<stamp>.log`     | The master log of every step. |
| `winget-<stamp>.log`        | Raw winget output (package-by-package). |
| `oosu-<stamp>.log`          | O&O ShutUp10++ stdout. |
| `win11debloat-<stamp>.log`  | Win11Debloat transcript. |
| `reg-import-<stamp>.log`    | `reg.exe import` output. |

If something failed, those are where to look. Each step in the summary that
shows `[X ]` will have the exception message inline.

## What it doesn't do

- **BitLocker** — intentionally skipped for personal use.
- **MyASUS settings** (Battery Care 80%, fan mode) — must be done in the app
  manually; not exposed via PowerShell.
- **BIOS update** — must be done from MyASUS or the support site.
- **Audient EVO driver** — manual install from audient.com.
- **Office activation** — log in via Word > Account.

These are listed in the generated `TODO-post-install.txt` on the Desktop.
