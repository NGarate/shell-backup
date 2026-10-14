# AGENTS.md

This file provides guidance to AI coding agents (Codex, Claude Code, etc.) when working with code in this repository.

## Project Overview

`setup.sh` is a single-file script that provisions a development environment (zsh, Ghostty on Linux / cmux on macOS, Herdr, Starship, Yazi, fzf, etc.) on Apple Silicon macOS and apt-based Linux on amd64/arm64. It must keep working when piped via `curl | bash`, so every deployed config file is embedded in it as a heredoc.

The script is split into numbered sections (`grep -n '^# [0-9]*\. ' setup.sh`) whose stages run in order from `main()`. Target versions, checksums, plugin sources and what has or has not been validated are documented in `DEPENDENCIES.md`.

## Design Constraints

- Platform branching uses `OS_TYPE` (`darwin`/`linux`) and `PKG_MANAGER` (`brew`/`apt`). Architecture support is intentionally narrow: macOS arm64 only, Linux amd64/x86_64 and arm64/aarch64 only.
- Bash errexit (`set -euo pipefail`) stays active; `run_stage` isolates a failing stage and records its real outcome so later stages still run.
- Idempotent: check versions and real integration status before installing. Back up files with `backup_file` before overwriting them.
- Yazi comes from Homebrew on macOS and from pinned official GitHub release binaries on Linux, so plugin minimum versions are satisfied.
- Herdr integrations are optional, selected through `/dev/tty`, and existing integrations must never be rewritten automatically.
- Zinit plugins must be Git plugins, never URL snippets: Zinit's snippet updater deletes the file when a download fails. The managed list lives in the `ZINIT_UPDATE_EOF` heredoc; adding a plugin also needs its load line in `ZSHRC_EOF`.

## Editing Embedded Configs

Edit the heredocs inside `setup.sh`, not separate files. List them with `grep -n "<< *'\?[A-Z_]*EOF" setup.sh`. A quoted marker (`<< 'ZSHRC_EOF'`) writes literal content; an unquoted one (`GHOSTTY_EOF`) expands variables. `.zshrc` contains `PNPM_HOME_PLACEHOLDER`, which is `sed`-replaced after deployment.

## Testing

Run `bash -n setup.sh` and `python3 -m unittest discover -s tests -v`. The tests in `tests/test_setup.py` use temporary homes and mock binaries and install nothing. Platform validation is manual, on a disposable machine; the release checklist is at the end of `DEPENDENCIES.md`.
