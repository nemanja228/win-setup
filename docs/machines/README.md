# docs/machines/

Machine-specific supplements to the generic docs in `../`. The generic docs (BIOS, drivers, OLED, audio, WSL, etc.) assume **any Windows 11 dev box**; anything that depends on a particular laptop, motherboard, vendor app, or hardware quirk lands here instead.

## Convention

One file per machine, named after the model (kebab-case, vendor-prefixed):

```
docs/machines/<vendor>-<model>-<sku>.md
```

Examples that already exist:

- `asus-zenbook-s16-um5606wa.md`

Examples that might exist later:

- `dell-xps-13-9340.md`
- `framework-13-amd-ai-300.md`
- `desktop-am5-x670e.md`

## What goes in a machine doc

- **Vendor app settings** that have no PowerShell API (e.g. MyASUS, Lenovo Vantage, Razer Synapse). Battery care, fan curves, function-key behaviour, noise-cancellation toggles.
- **Hardware quirks** that affect the install order or settings choices: hybrid CPU topology, single-sided M.2 constraint, panel-specific OLED behaviours, dock latency issues.
- **BIOS** support URL + any non-default settings specific to this firmware that aren't in the generic baseline.
- **Driver source** specifics (vendor's Live Update pulls a curated driver pack; AMD/Intel/Nvidia direct usually supersedes pieces of it).
- **Per-machine app preferences** if they differ wildly from defaults — but most users keep this in their global `apps.<tier>.json` files instead.

## What does NOT go in a machine doc

- Generic Windows 11 settings — those go in `../`.
- Personal taste (colour schemes, terminal themes) — those go in `profiles/` and `docs/terminal-profile.md`.
- The reasoning behind the layered debloat strategy — that's in `../debloat.md`.

## Adding a new machine

1. Copy an existing machine file as a template.
2. Update the title, model, and the BIOS / vendor-app sections.
3. Strip notes that don't apply.
4. Link to it from `../bios.md`, `../drivers.md`, `../oled.md`, `../audio.md` wherever a generic statement has a machine-specific follow-up.
5. Reference it from the root `README.md` if multiple machines coexist long-term.
