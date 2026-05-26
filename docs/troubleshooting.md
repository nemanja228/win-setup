# Troubleshooting

Where to look when something goes wrong during a bootstrap run.

---

## Logs

Everything bootstrap does is logged. Default location:

```
%USERPROFILE%\win-setup-logs\
```

Per-run files share a `<yyyyMMdd-HHmmss>` stamp:

| File | What |
|---|---|
| `bootstrap-<stamp>.log` | Master log of every step. Read this first. |
| `winget-<stamp>.log` | Raw winget output per package. |
| `oosu-<stamp>.log` | O&O ShutUp10++ stdout. |
| `oosu-<stamp>.log.err` | OOSU10 stderr. |
| `win11debloat-<stamp>.log` | Win11Debloat transcript. |
| `reg-import-<stamp>.log` | Per-value tweaks.reg + tweaks.personal.reg import results from step 20 (both files append to the same log). |
| `reg-import-post-apps-<stamp>.log` | Per-value re-import of tweaks.reg only from step 60 (post-winget). |

Each line in the master log is timestamped:

```
[2026-05-25 14:23:01] [STEP   ] ==> Win11Debloat (apps + telemetry + UI tweaks)
[2026-05-25 14:23:01] [INFO   ]   Found custom apps list: ...\resources\debloat\CustomAppsList.txt
[2026-05-25 14:23:01] [DEBUG  ]   Copied to %TEMP%\Win11Debloat\Config\CustomAppsList.txt
[2026-05-25 14:23:49] [SUCCESS]   OK (48.2s)
```

The summary at the end of the master log gives a one-screen verdict:

```
=================== SUMMARY ===================
Succeeded:    14
Skipped (dry): 0
Filtered out:  0
Failed:        1

  [OK] Pre-flight: admin check  (0.0s)
  [OK] Win11Debloat (apps + telemetry + UI tweaks)  (48.2s)
  [OK] O&O ShutUp10++ (apply saved privacy config)  (3.4s)
  [X ] Apply registry tweaks (tweaks.reg)  (1.2s)  -- All 87 registry values failed to import. See ...
  ...
```

Markers: `[OK]` ran successfully · `[~ ]` skipped (dry-run) · `[--]` filtered out · `[X ]` failed (with inline exception)

---

## Common failures

### "Not running as Administrator"

`bootstrap.ps1` has `#Requires -RunAsAdministrator`. Right-click PowerShell → **Run as administrator**. Then `cd` into the repo and re-run.

### "Cannot find WinSetup module at ..."

The `lib/WinSetup/` folder isn't where bootstrap expects it. Verify:

```powershell
Test-Path .\lib\WinSetup\WinSetup.psd1
```

If you've reorganized the repo or are running from outside it, `cd` into the repo root before running bootstrap.

### "No network connectivity to github.com or 1.1.1.1"

Connect to WiFi first, then re-run. The pre-flight gates GitHub specifically because some steps fetch scripts from it (Win11Debloat is fetched live via `iex (irm https://debloat.raphi.re/)`).

### `OOSU10 exited with code N`

Open `oosu-<stamp>.log` for the specific failing setting. Usually a malformed cfg — regenerate via `OOSU10.exe` interactively (UI → File → Export) and replace `resources/shutup/ooshutup10.cfg`.

### `winget import` partial failure

Open `winget-<stamp>.log`. Failing packages don't stop others; the import keeps going. Common causes:

- Package id changed in the winget repo (rare but does happen for OEM bundles).
- Package was renamed across a major version bump.
- Package is now in a different source than `Microsoft.Winget.Source`.

Fix the `apps.<tier>.json` entry and re-run with `.\bootstrap.ps1 -AppsOnly`.

### `tweaks.reg` partial import: "N of M registry values failed"

The bootstrap log shows `[WARN]` lines per failure with the exact key + value + reg.exe output. For deeper analysis:

```powershell
.\scripts\Test-RegImport.ps1
```

This runs the same per-value import on `resources/registry/tweaks.reg` and emits a structured report. Each failure has the offending line + reg.exe's exact output, so you can see whether it's a parse error (your tweaks.reg has a syntax issue) or a runtime refusal (the OS won't let that key be written from .reg, often because a service has an exclusive lock or the key has a SID-restricted owner).

Common causes:

- **Value name typo** in the .reg file — fix the file.
- **Key parent doesn't exist** — Windows .reg can create whole key trees, but some HKLM paths require ownership transfer first. Either skip that value or do it via PowerShell with `takeown` + ACL fixup first.
- **Win11Debloat already set the same value with a different type** — happens with `TaskbarDa` (Widgets button). Remove from `tweaks.reg` if Win11Debloat handles it, or vice versa.
- **Per-machine restriction** — some keys behave differently across hardware. See the relevant `machines/<this-machine>.md` for known cases (e.g. `TaskbarDa` failing consistently on certain laptops; that one is removed from `tweaks.reg` and handled via Win11Debloat + Appx removal instead).

### Step shows `[X]` but the action seems to have worked

`Invoke-Step` treats a `throw` from the action as failure, but native commands that exit non-zero don't throw unless explicitly checked. Some steps (notably `winget`, `wsl`) print errors on a single failing package while the rest succeed — bootstrap treats the whole step as OK because nothing threw. Check the per-tool log (winget-, wsl-) for per-item status.

### Step looks like it hung

Some steps are slow but not stuck:

- Win11Debloat: 30–60 seconds (Appx provisioning + scheduled task removal).
- OOSU10: 5–10 seconds (writing dozens of registry values).
- `winget import` of a fresh `apps.common.json`: 5–15 minutes (depends on what's already installed).
- WSL kernel update: 30–60 seconds.
- Defender exclusions: instant, but `Add-MpPreference` sometimes pauses on first call as the Defender service registers the action.

Watch the bootstrap log file in another window (`Get-Content -Wait`) if you want a live view of what step is currently running.

### Bootstrap aborts at the first failed step

By default, only steps explicitly marked `-ContinueOnError` survive a thrown exception. The pre-flight gates (admin, network) do throw and abort — these are gates, not optional. Most other steps have `-ContinueOnError` so one failure doesn't take down the whole run.

If a "should be continue-on-error" step keeps aborting, check the step file in `steps/` — the `-ContinueOnError` switch may have been dropped accidentally.

---

## Resetting state

### "I want to redo everything from scratch"

```powershell
# Roll back to the most recent System Restore point
rstrui.exe

# Or, more surgically: clear post-install sentinels so 61-app-extras re-runs every hook
Remove-Item "$env:LocalAppData\win-setup\post-install\*.hash"

# Then re-run bootstrap normally
.\bootstrap.ps1
```

### "I changed `apps.<tier>.json` and want bootstrap to pick it up"

```powershell
.\bootstrap.ps1 -AppsOnly
```

This expands to `-Steps apps,extras`. Runs the winget import + the app-extras scanner; skips everything else.

### "I edited a post-install/ hook and want it to re-run"

The hash sentinel detects content changes automatically. Just re-run:

```powershell
.\bootstrap.ps1 -Steps extras
```

Or force every hook regardless of sentinel:

```powershell
.\bootstrap.ps1 -ForceAppExtras
```
