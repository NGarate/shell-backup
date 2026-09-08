# shell-backup

Self-contained development environment installer for Apple Silicon macOS and
apt-based Linux (amd64/arm64). All desktop configuration is embedded in [setup.sh](./setup.sh).

## Install

Requires curl, Git, internet access and permission to install system packages.
macOS requires version 14+ for cmux.

```bash
curl -fsSL https://raw.githubusercontent.com/ngarate/shell-backup/main/setup.sh | bash

# Or from a local clone:
bash setup.sh
bash setup.sh --ci             # No optional prompts; also --non-interactive
bash setup.sh --with-herdr     # Opt into Herdr on macOS
```

| Platform | Terminal | Persistent sessions |
|---|---|---|
| Linux | Ghostty | Herdr |
| macOS arm64 | cmux | Herdr when selected; never started automatically in cmux |

Both profiles install zsh with Zinit, Starship, Yazi with Git/Starship plugins,
fzf, zoxide, ripgrep, fd, NVM/Node, pnpm and JetBrains Mono.

Reruns update managed tools below target and preserve compatible newer versions.
Existing configuration is backed up in `~/.backup`; results and versions are
logged in `~/.setup.log`. A failed required stage produces a nonzero exit status.
See [DEPENDENCIES.md](./DEPENDENCIES.md) for versions, checksums and platform limits.

## Herdr

```bash
herdr session attach personal  # Create or resume this computer's named session
herdr session list
herdr integration status
```

Setup configures the prefix as **Ctrl+Space**. Press it, then `q`, to detach and
leave pane processes running; `?` shows bindings. Reload Herdr's configuration or
reattach after changing the prefix. `exit` closes the pane's shell.

After verifying Herdr, interactive setup offers missing OpenCode, Hermes, Codex
and Claude Code integrations. Select numbers, `all`, or Enter/`q` to skip.
Harnesses and their initialized configurations must already exist. Existing
integrations are preserved; unknown or outdated states are reported for review.
CI and runs without a controlling terminal skip this selector.

For mobile access, prepare SSH separately and reconnect to the same host/session.
[TERMUX.md](./TERMUX.md) covers the Android widget and touch buttons.
TermRover is the Android/iPad client described by its [guide](https://termrover.sh/guide).
Each computer keeps its own sessions; cmux workspaces remain local to the Mac.

## Customize

| File | Purpose |
|---|---|
| `~/.zshrc.local` | Local aliases and shell preferences; preserved on reruns |
| `~/.env` | Local environment variables, loaded by generated `~/.zshenv` |
| `~/.config/ghostty/config.local` | Local rendering overrides for Ghostty/cmux |
| `~/.config/starship.toml` | Prompt theme |
| `~/.config/yazi/{init.lua,yazi.toml}` | File manager configuration |
| `~/.config/herdr/config.toml` | Herdr configuration; setup only changes the prefix |

Edit the heredocs in `setup.sh` for shared defaults. Generated files can be
replaced by the next setup run, so keep machine-specific shell/terminal changes
in the `.local` files. Run `exec zsh` to reload the shell.

## Everyday commands

| Command / key | Action |
|---|---|
| `gswf [filter]` | Switch to a matching Git branch; use fzf if several match |
| `gst`, `gco`, `gcb` | Git status, checkout, create branch (OMZ aliases) |
| `z <directory>` | Jump to a frequently used directory |
| `y` | Open Yazi and keep its exit directory in the shell |
| `Ctrl+R` / `Ctrl+T` | Search history / files with fzf |
| Up / Down after typing | Search history containing that text |
| `Cmd+Shift+F` (macOS), `Alt+Shift+F` (Linux) | Toggle fullscreen |
| `Shift+Enter` | Send escaped newline |

Zinit plugins update in the background once per day. To update manually, run
`zinit self-update` and `zinit update --all`; use `ya pkg upgrade` for Yazi plugins.

## Check or troubleshoot

Start with `~/.setup.log`, fix the reported failure and rerun setup. For shell
plugins, run `exec zsh`, then `zinit list` interactively. Check Yazi with
`yazi --version` and `ya pkg list`; check the terminal's font setting if glyphs
look wrong. For widget connection failures, first run `ssh laptop` in Termux.

Repository checks use temporary homes and mock commands; they do not install software:

```bash
bash -n setup.sh
bash -n termux-shortcuts/Herdr
python3 -m unittest discover -s tests -v
```

Full installation, upgrades and visual checks on target machines remain manual;
see the [validation limits](./DEPENDENCIES.md#validation-performed-and-pending).
