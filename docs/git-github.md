# Git and GitHub

How `scripts/Setup-Git-GitHub.ps1` works, the in-repo `.gitconfig` setup, and the multi-account SSH pattern.

---

## What the script does

`scripts/Setup-Git-GitHub.ps1` is an interactive, one-shot setup. Required parameters:

- `-SshEmail` — email address embedded in the SSH key comment
- `-KeyAlias` — filename for the SSH key (e.g. `id_ed25519_personal`)
- `-HostAlias` — SSH config alias (`github.com`, or `github.com-work` for multi-account)
- `-GitUserName` — full name for git commits
- `-GitUserEmail` — primary email for git commits

Optional:

- `-GistUrl` — fetch global `.gitconfig` from a remote Gist instead of the in-repo file. Most users don't need this.

Example:

```powershell
.\scripts\Setup-Git-GitHub.ps1 `
    -SshEmail 'you@example.com' `
    -KeyAlias 'id_ed25519_github' `
    -HostAlias 'github.com' `
    -GitUserName 'Your Name' `
    -GitUserEmail 'you@example.com'
```

What runs:

1. **Self-elevation** if not already admin.
2. **Install / upgrade Git** via winget.
3. **Apply global `.gitconfig`** — copies `profiles/git/.gitconfig` from the repo to `$HOME/.gitconfig`, backing up any existing one with `.gitconfig.bak_<stamp>`. (Or downloads from `-GistUrl` if you passed one.)
4. **Set global identity** — runs `git config --global user.name "$GitUserName"` and `user.email "$GitUserEmail"`. These don't go in the in-repo `.gitconfig` so it stays shareable.
5. **Generate ed25519 SSH key** at `~/.ssh/<KeyAlias>` (with empty passphrase — see below).
6. **Append SSH config entry** under the given host alias.
7. **Copy public key to clipboard** and open `https://github.com/settings/ssh/new` in your default browser. Paste the key and save.

---

## Why an in-repo `.gitconfig`?

The repo holds `profiles/git/.gitconfig` — the actual global config. Originally this was a public Gist, which meant maintaining two sources of truth (Gist + script's `-GistUrl` default). Bringing it in-repo:

- Single source of truth, versioned with everything else.
- No network dependency for setup once you've cloned.
- The file IS identity-free — no `[user] name=…` block. The script writes `user.name` / `user.email` via `git config --global` after the file lands, so the in-repo copy stays shareable / forkable.

If you want to override the in-repo config on a specific machine (custom work setup, different defaults), pass `-GistUrl <raw-url>` to fetch from anywhere. Same machinery, different source.

Future Linux split (if you ever go full Linux): add `profiles/git/.gitconfig.windows` + `profiles/git/.gitconfig.linux` and have `Install-Profiles.ps1` (or its Linux equivalent) pick by `$IsWindows`/`$IsLinux`. Not designed for now.

---

## Multi-account SSH

For multiple GitHub accounts (personal + work, etc.), generate a separate key per account and give each a distinct SSH host alias.

```powershell
# Personal — primary account
.\scripts\Setup-Git-GitHub.ps1 `
    -SshEmail 'me@personal.com' `
    -KeyAlias 'id_ed25519_personal' `
    -HostAlias 'github.com' `
    -GitUserName 'Your Name' `
    -GitUserEmail 'me@personal.com'

# Work — secondary alias
.\scripts\Setup-Git-GitHub.ps1 `
    -SshEmail 'you@work.com' `
    -KeyAlias 'id_ed25519_work' `
    -HostAlias 'github.com-work' `
    -GitUserName 'Your Name' `
    -GitUserEmail 'you@work.com'
```

After both run, `~/.ssh/config` looks like:

```
Host github.com
    HostName github.com
    User git
    IdentityFile C:\Users\you\.ssh\id_ed25519_personal
    IdentitiesOnly yes

Host github.com-work
    HostName github.com
    User git
    IdentityFile C:\Users\you\.ssh\id_ed25519_work
    IdentitiesOnly yes
```

To clone a work repo, replace the host in the URL:

```bash
# Original (uses personal):
git clone git@github.com:work-org/repo.git

# Work alias:
git clone git@github.com-work:work-org/repo.git
```

Personal projects keep working with the default `github.com` host. The script runs `git config --global user.email` for whichever invocation ran last — for per-repo identity overrides, use the per-repo `git config user.email "…"` inside each clone.

For finer-grained identity rules (e.g. all repos under `~/work/` use work identity automatically), use `includeIf` in `.gitconfig`:

```
[includeIf "gitdir:~/work/"]
    path = ~/.gitconfig-work
```

with `~/.gitconfig-work` containing the work `[user]` block. This isn't in the in-repo `.gitconfig` because the path varies per machine.

---

## SSH key passphrase

The script generates ed25519 keys with **empty passphrase** (`ssh-keygen -N '""'`). Tradeoff:

- **Pro**: No prompts during `git push` / `git fetch`. Smooth CLI experience.
- **Con**: If your `~/.ssh/` is exfiltrated, the keys are useable directly.

If you want passphrases, edit the script to remove `-N '""'` and let ssh-keygen prompt interactively. The OpenSSH agent (`ssh-agent` service on Windows) will cache the unlocked key for the session.

---

## Verifying

After setup:

```powershell
git config --global --list      # should show user.name, user.email, plus everything from profiles/git/.gitconfig
ssh -T git@github.com           # should respond: "Hi <username>! You've successfully authenticated..."
ssh -T git@github.com-work      # only if you set up a -work host alias
```

If `ssh -T` fails:

- **Permission denied (publickey)**: GitHub doesn't have the public key yet. Re-open `https://github.com/settings/ssh` and paste from `~/.ssh/<KeyAlias>.pub` (`Get-Content ~/.ssh/id_ed25519_personal.pub | Set-Clipboard`).
- **Could not resolve hostname**: typo in the host alias, or the SSH config has a syntax error. `ssh -G github.com` shows what config the client is reading.
