# AGENTS.md

This file provides guidance to AI coding agents (Codex, Claude Code, etc.) when working with code in this repository.

## Project Overview

This is a single-file shell automation script (`setup.sh`) that provisions a complete development environment (zsh, platform terminal (Ghostty on Linux / cmux on macOS), Herdr, Starship, Yazi, fzf, etc.) on Apple Silicon macOS and apt-based Linux on amd64/arm64. The script is self-contained: all configuration files (`.zshrc`, Yazi config, `starship.toml`, Ghostty config) are embedded as heredocs within `setup.sh` itself, making it work when piped via `curl | bash`.

## Architecture

`setup.sh` is organized into numbered sections (1–17) that execute sequentially via `main()`:

1. **Configuration & constants** — color codes, version requirements, paths
2. **Utility functions** — logging (`log`, `success`, `error`, `warning`), `command_exists`, OS/arch detection, file backup
3. **Prerequisite checks** — curl/wget and git
4. **Package manager setup** — Homebrew (macOS) or apt (Linux)
5. **Core tool installation** — uses `package:command` mapping format for brew; raw apt packages for Linux, plus pinned Yazi release binaries on Linux
6. **Font installation** — JetBrains Mono from GitHub releases
7. **Shell configuration** — deploys embedded `.zshrc` with Zinit plugins, NVM, pnpm, env file loading, per-terminal history, and Ghostty config
8. **Yazi configuration** — deploys embedded `init.lua` and `yazi.toml` for Git status and Starship prompt plugins
9. **Starship configuration** — deploys embedded `starship.toml` with multiple color palettes (`old`, `normal`, `light`)
10. **Custom functions** — deploys `~/.zsh/gswf.zsh` (fuzzy git branch switching)
11. **Shell setup** — sets zsh as default via `chsh`
12. **NVM setup** — installs NVM + Node LTS
13. **Zinit plugins** — bootstraps Zinit and installs all plugins
14. **Yazi plugins** — installs `yazi-rs/plugins:git` and `Rolv-Apneseth/starship` via `ya pkg`
15. **Verification** — checks all components installed correctly
16–17. **Summary and execution**

Key design decisions:
- Platform branching via `OS_TYPE` (`darwin`/`linux`) and `PKG_MANAGER` (`brew`/`apt`)
- Architecture support is intentionally narrow: macOS arm64 only, Linux amd64/x86_64 and arm64/aarch64 only
- Yazi uses Homebrew on macOS and pinned official GitHub release binaries on Linux so plugin minimum versions are satisfied
- The `.zshrc` uses `PNPM_HOME_PLACEHOLDER` which gets `sed`-replaced after heredoc deployment
- Script uses `set -euo pipefail` — any unhandled failure exits immediately
- Idempotent: checks versions and real integration status before installing; Herdr selection reads `/dev/tty`.
- Herdr integrations are optional and existing integrations must never be rewritten automatically.
- `run_stage` isolates failures while keeping Bash errexit active, then records actual outcomes.
- Target versions, checksums, dependencies and validation limitations are documented in `DEPENDENCIES.md`.

## Testing

Isolated acceptance tests are in `tests/test_setup.py`. Run `bash -n setup.sh` and `python3 -m unittest discover -s tests -v`; they do not install software. Platform validation remains manual; see `DEPENDENCIES.md`. To verify on a disposable target machine:

```bash
# Run the script (idempotent, safe to re-run)
./setup.sh

# Check installation log
cat ~/.setup.log

# Verify plugins load
zsh -c 'source ~/.zshrc && zinit list'
ya pkg list
```

Before submitting a PR, manually verify on target OS: script runs without errors, all plugins load (`zinit list`, `ya pkg list`), Starship prompt renders, Yazi starts, Ghostty config loads, and fonts display correctly.

## Editing Embedded Configs

When modifying configuration for zsh, Yazi, Starship, Ghostty, or custom functions, edit the heredoc blocks **inside `setup.sh`**, not separate config files. The heredoc markers are:
- `ZSHRC_EOF` — `.zshrc` content (section 7)
- `GHOSTTY_EOF` — Ghostty config (section 7)
- `YAZI_INIT_EOF` — Yazi `init.lua` content (section 8)
- `YAZI_TOML_EOF` — Yazi `yazi.toml` content (section 8)
- `STARSHIP_EOF` — `starship.toml` (section 9)
- `GSWF_EOF` — gswf function (section 10)

Note: `GHOSTTY_EOF` is an **unquoted** heredoc (variable interpolation is active), while `ZSHRC_EOF`, `YAZI_INIT_EOF`, `YAZI_TOML_EOF`, `STARSHIP_EOF`, and `GSWF_EOF` are **single-quoted** (literal content, no interpolation).
