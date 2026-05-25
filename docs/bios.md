# BIOS / UEFI

Settings that need to be right for Windows 11, virtualization, and modern dev work. Generic baseline below; vendor-specific support pages and quirks live in [`machines/`](machines/).

---

## Baseline

| Setting | Value | Why |
|---|---|---|
| Secure Boot | Enabled | Windows 11 requirement, modern security baseline |
| TPM / fTPM | Enabled | Windows 11 requirement |
| SVM (AMD) / VT-x (Intel) | **Enabled** | Required for Hyper-V, WSL2, Docker, Android emulator |
| Fast Boot | Enabled | Cosmetic; you can still hold the interrupt key from power-off |
| Boot order | Windows Boot Manager first | Default; verify after install if you've ever booted from a USB |

Without SVM/VT-x enabled, `bootstrap.ps1`'s `features` step will succeed at enabling Hyper-V and WSL but the VM platform itself won't start — symptom is `wsl --install` reporting "WSL 2 requires an update to its kernel component" repeatedly even after running `wsl --update`. Toggle it in BIOS, reboot, and the next `wsl --update` works.

## When to update BIOS

- **Before installing Windows**, if a newer version is available. Firmware-validated drivers depend on a specific BIOS range, and Live Update tools assume you're on a recent version.
- **After a Windows feature update** if the vendor app flags a new release. Don't update BIOS over a draining battery.

## What the consumer BIOS usually does NOT expose

Most laptops let the firmware decide:

- C-states (always managed)
- PBO / per-core voltage offsets (AMD)
- Memory training overrides
- TDP slider beyond the vendor app's preset modes

If you need those, you need a desktop or a workstation-class laptop with a proper BIOS. Most consumer laptops route these knobs through the vendor app instead — see your `machines/<this-machine>.md`.

## Generating `autounattend.xml` requires a recent ISO

`autounattend.xml` (rendered from [`../resources/autounattend/`](../resources/autounattend/)) targets the **Win11 24H2/25H2 setup runtime**. Older ISOs ignore some of the unattend keys, in particular the OOBE skips and language pack settings.

Use a current Microsoft ISO. Don't use Rufus's "tweaked install" mode — it injects its own autounattend.xml on the USB that takes precedence.
