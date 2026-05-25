# WSL2 setup

WSL2 (Windows Subsystem for Linux v2) gives a real Linux kernel running in a lightweight VM, with deep Windows integration (filesystem mounting, network passthrough, GUI app support via WSLg). This repo enables the features, installs Ubuntu, writes a sane `.wslconfig`, and otherwise stays out of WSL itself.

---

## What bootstrap does

Step `70-features-wsl` covers:

1. Enables Windows optional features: **Hyper-V**, **Virtual Machine Platform**, **Windows Subsystem for Linux**, **Windows Sandbox**. These all need a reboot to take effect.
2. Runs `wsl --update` to pull the latest in-WSL kernel.
3. `wsl --install -d Ubuntu --no-launch` if Ubuntu isn't already registered. Doesn't touch existing Ubuntu installs.
4. Writes `~/.wslconfig` with the canonical config (16 GB / 8 procs / sparseVhd / autoMemoryReclaim=gradual) if no `.wslconfig` exists. **Existing files are preserved** — pass `-ForceWslConfig` to override (with backup).

After a reboot:

```powershell
wsl -d Ubuntu     # first launch: prompts for username + password
```

Then inside Ubuntu, set up your dev stack:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y zsh git build-essential curl unzip jq
```

---

## .wslconfig

```ini
# Managed by win-setup bootstrap.ps1
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

Tuning notes:

- **memory=16GB** — leaves the rest for Windows (assumes 32 GB total). Bump if you have more RAM.
- **processors=8** — half of a typical modern dev laptop. WSL2 will time-share these with Windows.
- **swap=4GB** — small. WSL pages are cheap and Linux likes a little swap. Don't go to 0.
- **localhostForwarding=true** — required so `localhost:N` in Windows reaches `N` in WSL. Default true on recent WSL releases anyway.
- **nestedVirtualization=true** — lets you run Docker / KVM inside WSL2. Required for Docker Desktop's WSL backend.
- **autoMemoryReclaim=gradual** — releases WSL2 RAM back to Windows when idle, gradually. Without this, WSL holds onto its peak allocation forever.
- **sparseVhd=true** — shrinks the WSL VHD when files are deleted. Without this, the VHD only grows.

If you've edited `.wslconfig` and want bootstrap to leave it alone: just have a file at `$env:USERPROFILE\.wslconfig` that differs from the canonical config. Bootstrap detects the difference and warns instead of overwriting.

---

## Living inside WSL

- **Edit Windows files from Linux**: paths under `/mnt/c/...`. Slow for IO-heavy workloads (npm install, git checkout) — keep your project tree inside the Linux filesystem instead (e.g. `~/code/...`).
- **Edit Linux files from Windows**: the WSL distro exposes a network share at `\\wsl.localhost\Ubuntu\home\<user>\...`. VS Code's Remote-WSL extension handles this transparently.
- **GUI Linux apps work via WSLg** — install a Linux app (e.g. `sudo apt install gimp`), launch from the terminal, it pops up windowed alongside Windows apps. No X server setup needed.
- **Native Docker** in WSL is much faster than Docker Desktop's bind mounts. If you don't need the cross-WSL feature, `apt install docker.io` inside the distro works fine.
- **Audio works** — Linux apps that use PulseAudio/PipeWire route through Windows via WSLg's audio bridge. But for music production / DAW work, **stay on Windows**: WSL audio latency is high, and VST plugins / Audient drivers don't exist on Linux.

## Shell + prompt

Inside Ubuntu:

```bash
# zsh + Oh My Zsh
sudo apt install -y zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
chsh -s $(which zsh)

# Starship prompt (cross-shell)
curl -sS https://starship.rs/install.sh | sh
echo 'eval "$(starship init zsh)"' >> ~/.zshrc
```

For Oh-My-Posh inside WSL (same `.omp.json` theme as the Windows side):
```bash
curl -s https://ohmyposh.dev/install.sh | bash -s
echo 'eval "$(oh-my-posh init zsh --config /mnt/c/Users/<you>/AppData/Local/oh-my-posh/theme.omp.json)"' >> ~/.zshrc
```
