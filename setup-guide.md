# ASUS Zenbook S16 UM5606WA — Windows 11 Setup Guide

A complete personal reference for clean-installing and tuning the Zenbook S16
(Ryzen AI 9 HX 370, Radeon 890M, OLED) for:

- Daily dev work (.NET, WSL)
- Music production with an Audient EVO 4 interface
- OLED preservation
- Long battery life when mobile
- Minimum Microsoft noise

Companion automation lives in `/win-setup/` — this guide explains *why* every
step exists.

---

## Table of contents

1. [Strategy overview](#1-strategy-overview)
2. [Pre-install](#2-pre-install)
3. [BIOS / UEFI](#3-bios--uefi)
4. [Driver installation order](#4-driver-installation-order)
5. [MyASUS configuration](#5-myasus-configuration)
6. [Windows 11 power & performance](#6-windows-11-power--performance)
7. [OLED preservation](#7-oled-preservation)
8. [Audio routing & latency (Audient EVO 4)](#8-audio-routing--latency-audient-evo-4)
9. [Automation pipeline](#9-automation-pipeline)
10. [Debloating philosophy](#10-debloating-philosophy)
11. [WSL2 setup](#11-wsl2-setup)
12. [Re-running after Windows feature updates](#12-re-running-after-windows-feature-updates)
13. [Logs & troubleshooting](#13-logs--troubleshooting)

---

## 1. Strategy overview

Three layers, each automating more than the previous:

| Layer | When it runs | What it does |
|-------|-------------|--------------|
| `autounattend.xml` | During Windows Setup, before first boot | Skips OOBE, creates local account, removes Appx packages, applies basic registry tweaks. |
| `autounattend-firstlogon.ps1` | First user logon | Pulls down the win-setup repo, launches `bootstrap.ps1` elevated. |
| `bootstrap.ps1` | First logon and on demand | Debloat, app install, power/Defender/WSL config. Idempotent. |

Once set up, a clean install is **plug in USB → wait → log in → done**.

After a Windows feature update months later, re-running `bootstrap.ps1` re-applies everything in ~60s.

---

## 2. Pre-install

- Use a current Windows 11 **24H2 or 25H2** ISO from Microsoft. ASUS only supports 24H2+ on this machine and drivers won't work properly on older builds.
- **Don't** use Rufus's "tweaked Windows install" mode — it injects its own `autounattend.xml` that takes precedence over yours. Use plain Microsoft ISO + your own `autounattend.xml` on the USB root.
- Only single-sided M.2 SSDs fit the slot — there are surface-mounted components nearby.
- Update BIOS to current version (currently 319, Oct 2025) before installing. Easiest via the support site, more reliable via EZ Flash from a FAT32 USB.

---

## 3. BIOS / UEFI

| Setting | Value | Reason |
|--|--|--|
| Secure Boot | Enabled | Win11 requirement, security baseline |
| TPM / fTPM | Enabled | Win11 requirement |
| SVM Mode (virtualisation) | **Enabled** | Required for Hyper-V, WSL2, Docker, Android emulator. You're a .NET dev — you need this. |
| Fast Boot | Enabled | Cosmetic; hold F2 from power-off if you need to interrupt boot |
| USB Power Delivery in S5 | Off | Negligible battery save unless you USB-charge peripherals from the laptop |
| Boot order | Windows Boot Manager first | Default; verify after install |
| Wake on LID open | Personal preference | Disable if it wakes in your bag |

ASUS consumer BIOS doesn't expose C-states, PBO, or fine-grained power
knobs — those are firmware-driven via ASUS Intelligent Performance Technology.

---

## 4. Driver installation order

1. **Pause Windows Update for a week** before doing anything, so Windows doesn't fight you.
2. Install **MyASUS** from the Microsoft Store. Run **Live Update** — this pulls the ASUS-curated driver pack (chipset, audio, fingerprint, keyboard FN keys, ASUS System Control Interface). Most important step; these are validated against the firmware.
3. **AMD chipset driver** from amd.com directly (newer than what ASUS ships, includes scheduler updates for the Zen 5 + Zen 5c hybrid layout).
4. **AMD Adrenalin (Radeon 890M)** from AMD. Factory Reset install option the first time.
5. Re-enable Windows Update and let it patch everything else.

> Don't install standalone Realtek HD Audio from random sites. Use whatever
> MyASUS provides — the audio stack here includes ASUS/Dolby tuning that
> breaks if you swap the underlying driver.

---

## 5. MyASUS configuration

In Device Settings:

| Setting | Value | Reason |
|--|--|--|
| **Battery Health Charging** | Balanced (80%) | Roughly doubles battery lifespan over years. Bump to 100% on travel days. |
| **Fan Mode** | Standard | Switch to Whisper for quiet/listening, Performance only when compiling/encoding |
| **AI Noise Cancellation (mic)** | On for calls, **OFF for recording** | Adds latency/colouration in DAW |
| **Function Key Lock** | F1–F12 default | You're a dev. Toggle with Fn+Esc. |
| **Splendid / Display color** | Native or sRGB | "Vivid" oversaturates the already-wide-gamut OLED |
| **USB-C charging** | Enabled | Up to 100W via compatible chargers |

---

## 6. Windows 11 power & performance

Modern Win11 mostly uses the three-mode slider (Settings → System → Power & Battery → Power Mode):

| State | Mode |
|--|--|
| On battery | Best Power Efficiency |
| Plugged in, general use | Balanced |
| Plugged in, heavy work / music sessions | Best Performance |

`bootstrap.ps1` restores the classic **High Performance** plan via
`powercfg /duplicatescheme` — useful when you want `Minimum processor state =
100%` so the CPU doesn't downclock mid-buffer during DAW work.

Other toggles:

- Sleep / hibernate timeouts: generous on AC, aggressive on DC
- Battery Saver at 20% — default, fine
- Storage Sense: **off** if you keep large temp files you care about
- Developer Mode: on (Settings → System → For developers)

---

## 7. OLED preservation

Windows 11 24H2+ has built-in OLED protection — content-aware dimming that
gradually reduces brightness for static UI elements while keeping dynamic
content normal. Layer these on top:

- **Dark mode everywhere** — Settings → Personalization → Colors → Choose your mode → Dark.
- **Auto-hide taskbar** — taskbar settings → Taskbar behaviors. The taskbar in the same spot for hours is the #1 burn-in risk on Windows OLED.
- **Brightness 50–70%** — best balance between visibility and panel longevity. Avoid 100% for hours. Disable HDR for SDR content.
- **Screensaver after 5–10 min idle** — dark or moving pattern.
- **Wallpaper slideshow every 30 min** — desktop never has identical pixels for long. Same for lock screen.
- **MyASUS OLED Care** — enable Pixel Refresh / Pixel Shift. Run Pixel Refresh manually every couple of months.
- **Don't pin your IDE / browser maximised at identical coordinates for 10-hour sessions.** Alt-tab away occasionally.
- **Obsidian**: use a dark theme (Things Dark, AnuPpuccin), turn off always-visible status-bar elements.

---

## 8. Audio routing & latency (Audient EVO 4)

**Always route everything through the EVO 4 when it's connected.** Reasons:

- The EVO's converters and amp are dramatically better than internal Realtek.
- Single audio path = predictable behaviour. Buffer / sample rate / ASIO routing stay the same whether producing or listening.
- Lower DPC latency overall — class-compliant USB audio bypasses much of the Realtek/Dolby/MyASUS post-processing stack.
- EVO 4 has loopback for streaming/recording system audio.

### Connection

**Plug the EVO 4 directly into the laptop USB-A or USB-C — never through the HP G4 dock.** Docks add a USB hub that introduces jitter and DPC spikes. Audio interfaces always prefer direct connection.

### Setup

1. Install latest **Audient EVO driver** from audient.com (includes ASIO + standalone mixer).
2. Sound Settings → System → Sound → Output: pick EVO 4 as default for Playback and Recording.
3. Sound Settings → More sound settings → Communications: **Do nothing** (stops Windows ducking your music when an app thinks a call is happening).
4. mmsys.cpl → EVO 4 → Properties → Advanced: **24-bit, 48000 Hz** for general use. Match DAW project rate when working. Disable both "exclusive control" checkboxes.
5. **Disable** internal Realtek speaker output in Device Manager when you're permanently at the desk (right-click → Disable device). Re-enable when traveling. Same for HDMI audio outs.
6. In DAW: pick **Audient EVO ASIO**, not ASIO4ALL, not WASAPI. 256-sample buffer to start; drop to 128 once LatencyMon confirms headroom.
7. **Disable** MyASUS AI Noise Cancellation when recording.

### Verifying low latency

Install **LatencyMon** (it's in `apps.json`). Run for 15–20 min idle with your DAW open. Watch for high ISR / DPC times — common culprits are WiFi drivers, Bluetooth, ACPI, GPU. Disable WiFi power saving on the adapter (Device Manager → properties → Power Management) during recording sessions, and disable Bluetooth if you don't need it.

---

## 9. Automation pipeline

The full unattended flow:

```
┌──────────────────────────────────────────────────────────────────┐
│  1. Generate autounattend.xml at schneegans.de/windows/...       │
│     - Embed autounattend-firstlogon.ps1 as a "first logon" script│
│  2. Copy autounattend.xml to root of Windows 11 install USB      │
└─────────────────────────┬────────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────────┐
│  Windows Setup runs unattended:                                  │
│    - Skips OOBE / MS account                                     │
│    - Creates local account                                       │
│    - Removes selected Appx packages                              │
│    - Disables telemetry baseline                                 │
└─────────────────────────┬────────────────────────────────────────┘
                          │ (first boot, first logon)
                          ▼
┌──────────────────────────────────────────────────────────────────┐
│  autounattend-firstlogon.ps1 runs:                               │
│    - Waits for network                                           │
│    - Downloads bootstrap.ps1, apps.json, tweaks.reg, etc.        │
│    - Launches bootstrap.ps1 elevated                             │
└─────────────────────────┬────────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────────┐
│  bootstrap.ps1 runs all configured steps with logging:           │
│    - Restore point                                               │
│    - Win11Debloat (apps + telemetry + UI)                        │
│    - O&O ShutUp10++ with your saved config                       │
│    - tweaks.reg                                                  │
│    - winget import apps.json                                     │
│    - Power plan, Defender, Windows features, WSL, .wslconfig     │
│    - TODO-post-install.txt on Desktop                            │
└──────────────────────────────────────────────────────────────────┘
```

### Generating autounattend.xml

Use Christoph Schneegans' generator: <https://schneegans.de/windows/unattend-generator/>.
It works with Windows 11 24H2 and 25H2 in both ConX and legacy setup modes.
There's also a .NET Core library (`cschneegans/unattend-generator` on GitHub)
if you ever want to generate variations programmatically.

Recommended choices:

| Section | Value |
|--|--|
| Edition | Windows 11 Pro |
| Region / language | your locale + en-US secondary keyboard |
| User accounts | one local admin, **placeholder password** (change after first boot) |
| Bypass MS account | Yes |
| Disable telemetry | Yes (all of it) |
| Wi-Fi | pre-configure SSID + password for zero-touch |
| Remove apps | aggressive list (all OEM, Bing, Cortana, Family, Movies/TV, News, new Outlook, People, Phone Link, Power Automate, Quick Assist, Solitaire, Sticky Notes, Tips, Weather, Whiteboard, Xbox, Your Phone, Clipchamp, Copilot, AI Hub, Dev Home, Feedback Hub, Get Help, Get Started, Maps, Mixed Reality, OneNote, Office Hub, Skype, Sound Recorder) |
| Keep | Calculator, Camera, Notepad, Paint, Photos, Snipping Tool, Store, Terminal |
| System tweaks | show file extensions / hidden files, disable Bing, disable Widgets, disable Recall, classic context menu (optional) |
| Custom scripts → "runs on first logon, user context" | Paste `autounattend-firstlogon.ps1` contents (edit `$RepoRawBase`) |

Download generated XML → put on USB root → install.

---

## 10. Debloating philosophy

Rules I won't break:

- **Do it on a fresh install.** Not on a daily-driver months in.
- **Don't use Tiny11 / NTLite for a personal machine you depend on.** They strip too aggressively, break .NET/WSL stuff, can't be cleanly updated.
- **Don't fully disable Defender** unless replacing it. It's genuinely good on Win11. Disable telemetry separately.
- **Group Policy / registry to disable telemetry**, not killing the underlying service. Some apps poke its API.
- **Save your debloat preset.** Major feature updates revert tweaks.
- **System Restore point before each major step.** Cheap safety net.

### Tools (in order)

1. **Schneegans autounattend.xml** — image-level removal, before first boot. Cleanest possible result.
2. **Win11Debloat** (Raphire) — runs from `bootstrap.ps1` with `-RunDefaults -Silent`. Conservative, app + UI focused. Has CLI mode that doesn't need user input.
3. **O&O ShutUp10++** — `OOSU10.exe ooshutup10.cfg /quiet`. Granular privacy toggles. Generate the config interactively once, then apply silently forever.
4. **Manual `tweaks.reg`** — fills gaps the above tools miss (Copilot policy, advertising ID, lock-screen suggestions, Storage Sense, Edge preload, etc.).
5. **Group Policy (gpedit.msc)** — for Pro edition extras (Cloud Content, Search, AI, Widgets policies).

### What NOT to remove

| Don't remove | Why |
|--|--|
| `Microsoft.NET.*`, `.NETFramework` | You're a .NET dev. |
| `Microsoft.VCLibs.*` | Runtime for many store apps. |
| `Microsoft.UI.Xaml.*` | Same. |
| `Microsoft.Services.Store.Engagement` | Needed for store updates. |
| `Microsoft.WindowsAppRuntime.*` | Needed for modern Win apps. |
| Microsoft Store | Unless you're certain you'll never want a Store app. |
| Microsoft Edge | Can't fully remove anyway; just disable. Half the OS embeds WebView2. |
| Windows Search service | Set to Manual or limit indexed paths instead. |
| `Connected User Experiences and Telemetry` service | Use GPO/registry to disable telemetry. Don't kill the service. |
| WebView2 Runtime | Half the modern Windows apps embed it. |

### Office-specific

- Install via **Office Deployment Tool** (microsoft.com/.../id=49117) with custom XML. Word/Excel/PowerPoint/Outlook only — skip OneNote/Teams/Publisher/Skype. Generate XML at config.office.com.
- Each app: File → Options → Trust Center → Privacy Options → disable optional connected experiences and "Send data about how you use Office."
- **Semi-Annual Channel** if you want fewer surprise feature changes.

---

## 11. WSL2 setup

The autounattend / bootstrap pipeline already enables features and installs Ubuntu. After that:

1. Reboot.
2. Launch Ubuntu once: `wsl -d Ubuntu` — set username/password.
3. `.wslconfig` (already written by bootstrap) caps memory and enables sparse VHDs:

```ini
[wsl2]
memory=16GB
processors=8
swap=4GB
localhostForwarding=true
nestedVirtualization=true

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
```

4. Inside Ubuntu: install your dev stack (apt). Run `zsh` or `fish` with `starship` / `oh-my-posh`. Mount Windows from `/mnt/c`. VS Code Remote-WSL extension edits both sides transparently.
5. WSLg works out of the box — Linux GUI apps run windowed.

WSLg won't help with VSTs / guitar — those need a Windows-native or full Linux audio stack with PipeWire/Pulse. That's the reason for staying on Windows for this machine.

---

## 12. Re-running after Windows feature updates

Major Windows updates (24H2 → 25H2, etc.) re-enable telemetry, consumer features, Widgets, Copilot, and similar. After every feature update:

```powershell
cd $env:USERPROFILE\win-setup
.\bootstrap.ps1
```

Idempotent — re-applies everything without touching what's already correct. About 60 seconds.

**Optional**: schedule a weekly task that runs just the `tweaks.reg` portion if you're paranoid about silent re-enablement between feature updates.

---

## 13. Logs & troubleshooting

Everything `bootstrap.ps1` does goes to `%USERPROFILE%\win-setup-logs\`:

| File | What |
|--|--|
| `bootstrap-<stamp>.log`     | Master log, every step. |
| `winget-<stamp>.log`        | Raw winget output per package. |
| `oosu-<stamp>.log`          | O&O ShutUp10++ stdout. |
| `win11debloat-<stamp>.log`  | Win11Debloat transcript. |
| `reg-import-<stamp>.log`    | `reg.exe import` output. |

Each line is timestamped with severity:

```
[2026-05-25 14:23:01] [STEP   ] ==> Win11Debloat (apps + telemetry + UI tweaks)
[2026-05-25 14:23:01] [INFO   ]   Found custom apps list: C:\Users\X\win-setup\CustomAppsList.txt
[2026-05-25 14:23:01] [DEBUG  ]   Copied to C:\Users\X\AppData\Local\Temp\Win11Debloat\Config\CustomAppsList.txt
[2026-05-25 14:23:49] [SUCCESS]   OK (48.2s)
```

The summary at the end lists every step with status, duration, and any error:

```
=================== SUMMARY ===================
Succeeded: 14
Skipped:   1
Failed:    0

  [OK] Pre-flight: admin check  (0.0s)
  [OK] Win11Debloat (apps + telemetry + UI tweaks)  (48.2s)
  [~ ] O&O ShutUp10++ (apply saved privacy config)  (0.1s)  -- skipped (no cfg)
  ...
```

`[X ]` markers indicate failures with the inline exception message.

### Common issues

| Symptom | Fix |
|--|--|
| `Not running as Administrator` | Right-click PowerShell → Run as administrator |
| `No network connectivity` | Connect WiFi first, re-run |
| `OOSU10 exited with code N` | Open `oosu-*.log` for details; usually a malformed cfg |
| `winget import` partial failure | Check `winget-*.log`; failing packages don't stop others |
| Feature update re-enabled Copilot etc. | Just re-run `bootstrap.ps1` |

---

## Quick reference: commands

```powershell
# Initial run
.\bootstrap.ps1

# Preview without changes
.\bootstrap.ps1 -DryRun

# Re-apply only tweaks (skip slow steps)
.\bootstrap.ps1 -SkipApps -SkipWSL

# Manually re-import app list later
winget import --import-file apps.json --accept-package-agreements --accept-source-agreements --ignore-unavailable

# Re-apply registry tweaks only
reg import tweaks.reg

# Re-apply OOSU config only
.\OOSU10.exe ooshutup10.cfg /quiet
```

```bash
# Inside WSL Ubuntu
sudo apt update && sudo apt upgrade
# Recommended initial packages
sudo apt install -y zsh git build-essential curl unzip jq
```

---

## File map

```
win-setup/
├── autounattend-firstlogon.ps1   # Embed in Schneegans autounattend.xml
├── bootstrap.ps1                  # Main automation, idempotent
├── apps.json                      # Winget package list
├── tweaks.reg                     # Registry tweaks
├── CustomAppsList.txt             # Win11Debloat custom Appx removals
├── ooshutup10.cfg                 # PLACEHOLDER — generate via OOSU10.exe
└── README.md                      # Operational notes
```
