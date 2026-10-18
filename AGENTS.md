# AGENTS.md

This file provides guidance to AI coding agents (Codex, Claude Code, etc.) when working with code in this repository.

## Project Overview

`setup.sh` is a single-file script that provisions a development environment (zsh, Ghostty and Herdr on both platforms plus optional cmux on macOS, Starship, Yazi, fzf, etc.) on Apple Silicon macOS and apt-based Linux on amd64/arm64. It must keep working when piped via `curl | bash`, so every deployed config file is embedded in it as a heredoc.

The script is split into numbered sections (`grep -n '^# [0-9]*\. ' setup.sh`) whose stages run in order from `main()`. Target versions, checksums, plugin sources and what has or has not been validated are documented in `DEPENDENCIES.md`.

Pinned downloads live in two manifests: `release_asset` (Linux CLIs) and `font_asset` (font archives, digests from each release's `assets[].digest`). Saved setup choices (`--font`) are in `~/.config/shell-backup/profile`. Remote clients attach through the generated `~/.local/bin/shell-backup-attach`; keep `termux-shortcuts/Herdr` compatible with hosts that lack it.

## Design Constraints

- Platform branching uses `OS_TYPE` (`darwin`/`linux`) and `PKG_MANAGER` (`brew`/`apt`). Architecture support is intentionally narrow: macOS arm64 only, Linux amd64/x86_64 and arm64/aarch64 only.
- Bash errexit (`set -euo pipefail`) stays active; `run_stage` isolates a failing stage and records its real outcome so later stages still run.
- Idempotent and convergent: the same inputs (script, flags, saved profile, system, and upstream state such as package repositories and plugin default branches) end in the same state, and a rerun with nothing new changes nothing. Check versions and real integration status before installing. Write generated files with `deploy_file` (unchanged content is left alone; changed content is backed up, then replaced). For files edited by external tools use `snapshot_file`/`keep_snapshot_if_changed`, so a backup exists only when the tool changed the file. Skip tool commands that rewrite files without a change (see `yazi_packages_to_upgrade` and the up-to-date check in the Zinit updater). `tests/test_setup.py` asserts that a rerun keeps content, mode and mtime identical.
- Yazi comes from Homebrew on macOS and from pinned official GitHub release binaries on Linux, so plugin minimum versions are satisfied.
- Missing Herdr integrations are installed automatically when their harness is initialized; existing integrations (current, outdated or unknown) must never be rewritten. The only `/dev/tty` prompt is the first-run font question.
- Neovim: LazyVim and kickstart.nvim are cloned at audited commits (`neovim_starters`) only when missing, then changed by `git apply` patches (`neovim_starter_patch`): an applied patch is left alone and conflicting user edits are kept and reported. Files added to the starters go through `deploy_file` (`deploy_neovim_files`). `vi` (`~/.local/bin/vi`) maps `NVIM_CONFIG` to `NVIM_APPNAME`; Git and Yazi open Neovim through it.
- Zinit plugins must be Git plugins, never URL snippets: Zinit's snippet updater deletes the file when a download fails. The managed list lives in the `ZINIT_UPDATE_EOF` heredoc; adding a plugin also needs its load line in `ZSHRC_EOF`.

## Editing Embedded Configs

Edit the heredocs inside `setup.sh`, not separate files. List them with `grep -n "<< *'\?[A-Z_]*EOF" setup.sh`. A quoted marker (`<< 'ZSHRC_EOF'`) writes literal content; an unquoted one (`GHOSTTY_EOF`) expands variables. `.zshrc` contains `PNPM_HOME_PLACEHOLDER`, which `sed` fills in before the result is compared with the deployed file. To change a starter patch, edit the file in a clone at the pinned commit and paste `git diff` without `index` lines and with the trailing space removed from empty context lines (`sed 's/^ $//'`).

## Testing

Run `bash -n setup.sh` and `python3 -m unittest discover -s tests -v`. The tests in `tests/test_setup.py` use temporary homes and mock binaries and install nothing. Platform validation is manual, on a disposable machine; the release checklist is at the end of `DEPENDENCIES.md`.
