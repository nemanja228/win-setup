# OLED preservation

Generic strategy for keeping an OLED panel healthy over a multi-year ownership window. Applies to any Windows 11 box with an OLED display — laptop or external monitor. Panel-specific knobs (e.g. vendor-app Pixel Refresh) live in [`machines/`](machines/).

---

## What burns OLEDs

Persistent static content drives the affected pixels harder than their neighbours, and over months the brightness response of the worn pixels diverges from fresh ones. Most likely offenders on a dev box:

- Taskbar in the same spot for hours
- IDE chrome (menu bars, tab strips) at identical pixel coordinates for entire workdays
- Browser address bar at the top, status bar at the bottom
- Dock at the bottom of a third-party launcher
- Wallpaper showing the same image for weeks

Random content (videos, prose, code that scrolls) is not the problem. The problem is **the same pixels lit the same way for hours**.

---

## What Windows 11 24H2+ does for you

Built-in **content-aware dimming**: dims static UI elements (taskbar, system tray, persistent app chrome) gradually while keeping dynamic content at full brightness. On by default. Leave it on.

There's no setting page for this — it just works once the OS knows it's driving an OLED.

---

## What you stack on top

1. **Dark mode everywhere** — Settings → Personalization → Colors → Choose your mode → **Dark**. Fewer pixels lit per static UI element.
2. **Auto-hide the taskbar** — Settings → Personalization → Taskbar → Taskbar behaviors → Automatically hide the taskbar. `bootstrap.ps1` flips this bit automatically (step `30-region`).
3. **Brightness 50–70%** — sweet spot between visibility and panel longevity. 100% sustained for hours is the real risk; brightness changes alone are fine.
4. **Disable HDR for SDR content.** HDR-on-SDR makes static UI elements drive the panel harder than they need to.
5. **Screensaver after 5–10 min idle** — dark or moving pattern. Not the same as display-off; saver before sleep gives the panel a uniformity exercise.
6. **Wallpaper slideshow every 30 min** — desktop never has identical pixels for long. Same for lock screen. `tweaks.personal.reg` sets a 30-minute shuffle interval; you supply the wallpaper folder. (If you forked and deleted the personal file, set up the slideshow manually via Settings → Personalization → Background.)
7. **Don't pin a maximized IDE / browser at identical coordinates for 10-hour sessions.** Alt-tab away occasionally, snap to different halves, change zoom. The pixels notice.
8. **Vendor-app panel-care features** — see your machine doc. Most laptops ship a Pixel Refresh (idle-time uniformity exercise) and Pixel Shift (subtle 1-pixel UI offset) feature that supplements the OS-level dimming.

## App-specific tips

- **Obsidian**: dark theme (Things Dark, AnuPpuccin, etc.), turn off always-visible status-bar elements (line/column counter, word count).
- **VS Code**: dark theme, disable persistent status-bar items you don't need, consider Zen Mode for long writing sessions.
- **Terminal**: use a dark background (transparent or solid). Some themes (Tokyo Night, Catppuccin Mocha) are specifically tuned for OLED.
- **Browsers**: dark theme + dark new-tab page. Pin sparingly — pinned tabs sit at identical coordinates forever.
