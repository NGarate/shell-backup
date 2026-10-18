# shell-backup

Self-contained development environment installer for Apple Silicon macOS and
apt-based Linux (amd64/arm64). All desktop configuration is embedded in [setup.sh](./setup.sh).

## Install

Requires curl, Git, internet access and permission to install system packages.
The optional cmux extra requires macOS 14+.

```bash
curl -fsSL https://raw.githubusercontent.com/ngarate/shell-backup/main/setup.sh | bash

# Or from a local clone:
bash setup.sh
bash setup.sh --ci             # No optional prompts; also --non-interactive
bash setup.sh --with-cmux      # Also install cmux on macOS (kept updated once installed)
bash setup.sh --font=jetbrains # Terminal font: iosevka (default) or jetbrains
```

| Platform | Terminal | Persistent sessions | Extra |
|---|---|---|---|
| Linux | Ghostty (Snap) | Herdr | — |
| macOS arm64 | Ghostty (Homebrew cask) | Herdr | cmux with `--with-cmux` |

Both profiles install zsh with Zinit, Starship, Yazi with Git/Starship plugins,
fzf, zoxide, ripgrep, fd, NVM/Node, pnpm, mosh-server, [Neovim](#neovim) with
lazygit and the tree-sitter CLI, and the fonts below.

## Fonts and icons

Setup installs both terminal fonts so you can switch without downloading again:

| `--font=` | Family | Notes |
|---|---|---|
| `iosevka` (default) | Iosevka Term SS05 | Ligatures on; narrow, so more agent panes fit side by side. Covers Claude Code's ⏺ ⎿ ⏵ ✻ glyphs natively. |
| `jetbrains` | JetBrainsMono Nerd Font | The previous look with Nerd Font icons included. |

Symbols Nerd Font Mono is installed too and configured as the icon fallback
for Ghostty/cmux. On Linux, `~/.config/fontconfig/conf.d/60-shell-backup.conf`
makes other applications fall back the same way: the chosen font, then Nerd
icons, then Noto Sans Symbols2 and Noto Color Emoji. The first interactive run
asks which font to use. The choice is saved in `~/.config/shell-backup/profile`,
and later runs (including `--ci`) reuse it until you pass another `--font`.

Icons are drawn by the terminal you are looking at, not by the host. A remote
client (TermRover, Termux, another laptop) needs a Nerd Font of its own, or the
plain prompt described under [Remote clients](#remote-clients).

Reruns update managed tools below target and preserve compatible newer versions.
The same inputs (flags, saved choices, system, and upstream packages/plugins)
always end in the same state, and a rerun with nothing new changes nothing:
generated files are only rewritten when their content differs. A replaced or
tool-modified file is backed up in `~/.backup` only when it actually changed; results and versions are
logged in `~/.setup.log`. A failed required stage produces a nonzero exit status.
See [DEPENDENCIES.md](./DEPENDENCIES.md) for versions, checksums and platform limits.

## Neovim

Two configs live side by side through `NVIM_APPNAME`, each with its own
plugins, state and cache:

| Config | Folder | Base |
|---|---|---|
| `nvim-lazyvim` (default) | `~/.config/nvim-lazyvim` | [LazyVim starter](https://github.com/LazyVim/starter) and language extras |
| `nvim-kickstart` | `~/.config/nvim-kickstart` | [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim), a single `init.lua` to read and change |

```bash
vi file          # The config named in NVIM_CONFIG (default nvim-lazyvim)
lv file; kv file # Force LazyVim / kickstart
nvims file       # Pick one with fzf
```

`vi` is `~/.local/bin/vi`. Git (commit messages, `git mergetool`,
`git difftool`) and Yazi (text and code files) open Neovim through it, so
`NVIM_CONFIG` decides the config everywhere. Set another default in
`~/.zshrc.local` or `~/.env`; plain `nvim` still uses `~/.config/nvim`.

Both configs add the same Git workflow: gitsigns, lazygit (`<leader>gg`) and
diffview (`<leader>gv` for changes and 3-way conflict resolution, `<leader>gV`
and `<leader>gH` for history), plus LSP, formatting and Treesitter for Python,
JS/TS, Bash/zsh, JSON, YAML, TOML, Markdown, Docker and Ansible. Learning
helpers: hardtime hints, precognition and, when `~/Proyectos/tips.nvim`
exists, tips.nvim. Git uses `zdiff3` conflict markers (`diff3` before Git 2.35).

Setup clones a missing starter at an audited commit and applies its managed
changes with `git apply`; reruns leave applied changes and your own edits
alone (conflicting edits are reported, not overwritten). Plugins, language
servers and parsers install on the first start. Update plugins with `:Lazy`
(LazyVim) or `:lua vim.pack.update()` (kickstart), and the starters themselves
with `git pull` in their folders.

## Herdr

```bash
herdr session attach personal  # Create or resume this computer's named session
herdr session list
herdr integration status
```

Setup configures the prefix as **Ctrl+Space** and installs
`~/.local/bin/shell-backup-attach [session]`, the single remote command for every
client (default session `personal`). Press it, then `q`, to detach and
leave pane processes running; `?` shows bindings. Reload Herdr's configuration or
reattach after changing the prefix. `exit` closes the pane's shell.

After verifying Herdr, interactive setup offers missing OpenCode, Hermes, Codex
and Claude Code integrations. Select numbers, `all`, or Enter/`q` to skip.
Harnesses and their initialized configurations must already exist. Existing
integrations are preserved; unknown or outdated states are reported for review.
CI and runs without a controlling terminal skip this selector.

## Remote clients

Every client uses the same thing on the host: SSH (or Mosh) and a Herdr session.

```bash
ssh -t laptop shell-backup-attach personal
mosh laptop -- shell-backup-attach personal
```

- **Network:** set up SSH access, and Tailscale if you use it, yourself. Setup
  never installs Tailscale or changes firewall rules. Mosh also needs UDP
  60000–61000 reachable from the client.
- **Host side, done by setup:** `mosh-server`, a working UTF-8 locale (Linux
  generates `en_US.UTF-8`; `~/.zshenv` repairs a missing or forwarded locale in
  SSH and interactive shells, falling back to `C.UTF-8`), extra terminfo
  (`ncurses-term`), and a `TERM=xterm-256color` fallback when the client's
  terminal type is unknown. Ghostty and cmux clients copy their own terminfo
  to SSH hosts (`ssh-terminfo`).
- **TermRover** (Android/iPad, [guide](https://termrover.sh/guide)): add the
  host, choose Herdr in the session picker or as the host default, and switch
  to Mosh if you like. Prefix macros expect Ctrl+Space.
- **Termux:** see [TERMUX.md](./TERMUX.md) for the widget, touch buttons and a
  Nerd Font for `~/.termux/font.ttf`.
- **Client without a Nerd Font:** on the host, add
  `export STARSHIP_CONFIG="$HOME/.config/starship-plain.toml"` to `~/.zshrc.local`.
  Herdr sessions are shared by every attached client, so this applies per host.

Each computer keeps its own sessions; cmux workspaces remain local to the Mac.

## Customize

| File | Purpose |
|---|---|
| `~/.zshrc.local` | Local aliases and shell preferences; preserved on reruns |
| `~/.env` | Local environment variables, loaded by generated `~/.zshenv` |
| `~/.config/ghostty/config.local` | Local rendering overrides for Ghostty/cmux |
| `~/.config/starship.toml` | Prompt theme (Nerd Font); `starship-plain.toml` is the plain-symbol variant |
| `~/.config/shell-backup/profile` | Saved setup choices (`FONT=iosevka` or `FONT=jetbrains`) |
| `~/.config/yazi/{init.lua,yazi.toml}` | File manager configuration |
| `~/.config/nvim-lazyvim`, `~/.config/nvim-kickstart` | Neovim configs; yours to edit (setup only patches the lines it manages) |
| `~/.gitconfig` | Setup sets the editor, merge and diff tool to Neovim; other keys are untouched |
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
| `vi`, `lv`, `kv`, `nvims` | Neovim (see [Neovim](#neovim)) |
| `git mergetool` | Resolve conflicts in a 4-pane nvimdiff |
| `Ctrl+R` / `Ctrl+T` | Search history / files with fzf |
| Up / Down after typing | Search history containing that text |
| `Cmd+Shift+F` (macOS), `Alt+Shift+F` (Linux) | Toggle fullscreen |
| `Shift+Enter` | Send escaped newline |

Zinit plugins update in the background once per day. To update manually, run
`zinit self-update` and `zinit update --all`; use `ya pkg upgrade` for Yazi plugins.
Managed plugins are Git clones, so a failed update keeps the installed version.

## Check or troubleshoot

Start with `~/.setup.log`, fix the reported failure and rerun setup. For shell
plugins, run `exec zsh`, then `zinit list` interactively. Check Yazi with
`yazi --version` and `ya pkg list`. If glyphs show as boxes, check which
terminal draws them: the setup summary reports any code points no installed font
covers (Linux), and remote clients need their own Nerd Font or the plain prompt.
Run `locale` over SSH if box drawing or Mosh fails. For widget connection
failures, first run `ssh laptop` in Termux.

Repository checks use temporary homes and mock commands; they do not install software:

```bash
bash -n setup.sh
bash -n termux-shortcuts/Herdr
python3 -m unittest discover -s tests -v
```

Full installation, upgrades and visual checks on target machines remain manual;
see the [validation limits](./DEPENDENCIES.md#validation-performed-and-pending).
