# AGENTS.md

This file provides guidance to AI coding agents (Codex, Claude Code, etc.) when working with code in this repository.

## Project Overview

This is a single-file shell automation script (`setup.sh`) that provisions a complete development environment (zsh, tmux, Ghostty, Starship, fzf, etc.) on macOS and Linux. The script is self-contained: all configuration files (`.zshrc`, `.tmux.conf`, `starship.toml`, Ghostty config) are embedded as heredocs within `setup.sh` itself, making it work when piped via `curl | bash`.

## Architecture

`setup.sh` is organized into numbered sections (1–16) that execute sequentially via `main()`:

1. **Configuration & constants** — color codes, version requirements, paths
2. **Utility functions** — logging (`log`, `success`, `error`, `warning`), `command_exists`, OS/arch detection, file backup
3. **Prerequisite checks** — curl/wget and git
4. **Package manager setup** — Homebrew (macOS) or apt (Linux)
5. **Core tool installation** — uses `package:command` mapping format for brew; raw apt packages for Linux
6. **Font installation** — JetBrains Mono from GitHub releases
7. **Shell configuration** — deploys embedded `.zshrc` with Zinit plugins, NVM, pnpm, env file loading, tmux auto-attach
8. **Starship configuration** — deploys embedded `starship.toml` with multiple color palettes (`old`, `normal`, `light`)
9. **Custom functions** — deploys `~/.zsh/gcof.zsh` (fuzzy git branch checkout)
10. **Shell setup** — sets zsh as default via `chsh`
11. **NVM setup** — installs NVM + Node LTS
12. **Zinit plugins** — bootstraps Zinit and installs all plugins
13. **Tmux plugins** — installs TPM and plugins
14. **Verification** — checks all components installed correctly
15–16. **Summary and execution**

Key design decisions:
- Platform branching via `OS_TYPE` (`darwin`/`linux`) and `PKG_MANAGER` (`brew`/`apt`)
- Clipboard detection cascades through Wayland (`wl-copy`) -> X11 (`xclip`) -> `xsel` fallbacks
- The `.zshrc` uses `PNPM_HOME_PLACEHOLDER` which gets `sed`-replaced after heredoc deployment
- Script uses `set -euo pipefail` — any unhandled failure exits immediately
- Idempotent: checks if tools/configs exist before installing

## Testing

There is no automated test suite. To verify changes:

```bash
# Run the script (idempotent, safe to re-run)
./setup.sh

# Check installation log
cat ~/.setup.log

# Verify plugins load
zsh -c 'source ~/.zshrc && zinit list'
```

Before submitting a PR, manually verify on target OS: script runs without errors, all plugins load (`zinit list`), tmux plugins load, Starship prompt renders, and fonts display correctly.

## Editing Embedded Configs

When modifying configuration for zsh, tmux, Starship, Ghostty, or custom functions, edit the heredoc blocks **inside `setup.sh`**, not separate config files. The heredoc markers are:
- `ZSHRC_EOF` — `.zshrc` content (section 7)
- `TMUX_EOF` — `.tmux.conf` content (section 7)
- `GHOSTTY_EOF` — Ghostty config (section 7)
- `STARSHIP_EOF` — `starship.toml` (section 8)
- `GCOF_EOF` — gcof function (section 9)

Note: `TMUX_EOF` and `GHOSTTY_EOF` are **unquoted** heredocs (variable interpolation is active), while `ZSHRC_EOF`, `STARSHIP_EOF`, and `GCOF_EOF` are **single-quoted** (literal content, no interpolation).
