# snippets/

Small, self-contained PowerShell utility scripts. Each is standalone (no module dependency) so you can copy one to any machine without cloning the repo.

Every snippet:

- Has a header comment block (`.SYNOPSIS`, `.DESCRIPTION`, `.EXAMPLE`) — runs `Get-Help <script>` cleanly.
- Uses `[CmdletBinding(SupportsShouldProcess)]` where it does anything destructive, so `-WhatIf` works.
- Is idempotent — re-running with the same args is a no-op when the desired state already holds.

## Current snippets

### `Add-ToPath.ps1` — add a directory to PATH

```powershell
.\Add-ToPath.ps1 -Path 'C:\Tools\bin'                   # User scope, append
.\Add-ToPath.ps1 -Path 'C:\dev\bin' -Prepend            # User scope, prepend
.\Add-ToPath.ps1 -Path 'C:\Tools' -Scope Machine        # Requires elevation
.\Add-ToPath.ps1 -Path 'C:\foo' -WhatIf                 # Preview, no write
```

- Idempotent: no-op (no write to registry) if entry already present.
- Refreshes `$env:PATH` after the write so the change is live in the current session — no new shell needed.
- Validates `Test-Path` unless `-Force`.

### `Remove-FromPath.ps1` — remove a directory from PATH

```powershell
.\Remove-FromPath.ps1 -Path 'C:\Tools\bin'              # User scope
.\Remove-FromPath.ps1 -Path 'C:\OldTool' -Scope Machine # Requires elevation
.\Remove-FromPath.ps1 -Path 'C:\foo' -WhatIf            # Preview
```

- Idempotent: no-op if entry not present.
- Bonus: dedupes the remaining PATH while writing back — some installers leave duplicate or empty entries.

### `Get-PathEntries.ps1` — display PATH, one entry per line

```powershell
.\Get-PathEntries.ps1                                   # User + Machine + Process
.\Get-PathEntries.ps1 -Scope Process                    # Only effective PATH
.\Get-PathEntries.ps1 -Scope User -NoColor              # Plain text for piping
```

- Color-coded:
  - **green** — entry exists on disk
  - **red** — entry MISSING (typo, uninstalled program, etc.)
  - **yellow** — duplicate (appears more than once)
- `-NoColor` annotates with `[MISSING]` / `[DUP]` for grep/Select-String.

## Why these are snippets, not module functions

PATH management is the kind of thing that comes up across machines, in scripts, in one-off REPL sessions. Lifting them into the `WinSetup` module would mean any user has to clone the repo and `Import-Module` just to add a directory to PATH.

Keeping them as standalone `.ps1` files means you can:

- Copy one to a new machine via `irm <url> | Out-File`.
- Drop them into your `$PROFILE` directory and dot-source.
- Run them ad hoc in any shell without setup.

If a snippet ever needs to share substantial code with other snippets, that's the signal to lift the shared helper into the `WinSetup` module — not the other way around.

## Conventions for new snippets

- One function per file. Filename matches the function name (e.g. `Add-ToPath.ps1` exposes `Add-ToPath`-ish behaviour).
- Standalone — duplicate small helpers (like the `Get-PathArray` / `Set-PathArray` private helpers in the three PATH scripts) rather than create a snippet-only shared module.
- Idempotent. No exceptions.
- `-WhatIf` supported wherever the script writes anything.
- Self-elevation NOT done at the snippet level — if a snippet requires admin, it errors with a clear message and exits 1. Callers can handle elevation.
