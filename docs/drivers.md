# Driver install order

There's a right and a wrong order for installing drivers on a fresh Windows. Doing it wrong leaves you with a half-fighting mix of vendor-curated drivers and Windows Update's generic ones — usually fine until you hit a weird sleep/wake bug six months later.

Generic pattern below; per-machine specifics (vendor app, source URLs) live in [`machines/`](machines/).

---

## The order

1. **Pause Windows Update for a week.** Settings → Windows Update → Pause. Stops Windows from racing you to install generic drivers while you're trying to install vendor-curated ones.
2. **Update the Microsoft Store**, then install your **vendor app** (MyASUS, Lenovo Vantage, Dell SupportAssist, HP Support Assistant, ASUS Armoury Crate, etc. — whichever ships with your machine).
3. **Run the vendor app's Live Update.** This pulls a curated driver pack validated against the firmware: chipset, fingerprint, function keys, vendor-specific control interfaces. Don't skip it — these are the most important drivers on the machine.
4. **Update BIOS** if you haven't already (see [`bios.md`](bios.md)).
5. **CPU / chipset / GPU driver** direct from the silicon vendor (amd.com, intel.com, nvidia.com). Usually newer than what the vendor app shipped and includes important fixes — scheduler updates for hybrid CPUs, security patches, power management tweaks. The direct version supersedes the vendor app's copy of these specific drivers.
6. **Resume Windows Update.** Let it patch the OS and pick up everything else (printers, Bluetooth peripheral drivers, etc.). Re-run until "no updates available."

## Why vendor app first?

The vendor app driver pack is the only source that knows about machine-specific bits:

- ASUS / HP / Dell *system control interface* — controls hardware buttons, status LEDs, lid-close behaviour.
- Vendor audio tuning (Dolby Atmos profiles, equalizer presets baked into the audio driver).
- Fingerprint reader, IR camera, NFC — vendor-bundled drivers, not on Windows Update.
- Function-key behaviour (FN+F1..F12 brightness/volume/etc.).

Skipping the vendor app and just running Windows Update will give you generic drivers that *work* but lose features. The fix is more painful than just doing it in order.

## Why CPU/GPU/chipset direct after?

AMD and Intel ship updates faster than vendor apps push them through. Specifically:

- **AMD chipset** — Zen 5 / Zen 5c hybrid layouts had scheduler thrash that AMD fixed in chipset updates 3-6 months before laptop vendors picked them up.
- **AMD Adrenalin / Intel Graphics** — driver-side optimizations for games and creator apps, plus Vulkan/DirectX 12 fixes. Vendor app versions lag by quarters.
- **Intel ME / AMD PSP** — security patches occasionally land via vendor direct first.

Choose **Factory Reset Install** on AMD Adrenalin the first time so it doesn't fight whatever leftover bits the vendor app dropped.

## Realtek / Conexant audio

**Don't install standalone audio drivers from random Realtek download sites.** Most modern laptops ship audio with vendor-applied tuning baked into the driver — swapping for the generic Realtek build *can* improve raw output but breaks features (mic noise cancellation, Atmos, vendor-specific EQ).

Use whatever your vendor app provides. If you don't like the result, use an external interface instead — see [`audio.md`](audio.md).

## Verifying

After all updates, in Device Manager:

- **No yellow exclamation marks** anywhere. Anything unrecognized — search the hardware ID against vendor support pages.
- **Display adapters** lists your dGPU/iGPU with the right driver version (check via right-click → Properties → Driver tab).
- **System devices** has entries from your vendor (`ASUS System Control Interface`, `Dell System Manager`, etc.).
- **Sound, video and game controllers** lists your audio interface(s), including vendor-tuned ones if applicable.

LatencyMon (in `apps.personal.json`) is the gold-standard tool for catching driver-induced DPC latency spikes. Run for 15-20 minutes idle after the install settles.
