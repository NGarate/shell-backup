# Dependency inventory and validation

Audited against upstream releases/source on **2026-09-07**. The installer remains a single self-contained `setup.sh`; this file is documentation, not an installation dependency.

## Version policy

Numeric targets are minimums for the managed commands. Compatible newer versions are retained. Linux CLI release assets, NVM's installer and the font archive have SHA-256 digests embedded in `setup.sh`. Release digests were read from each official GitHub release's `assets[].digest`; the font and NVM installer hashes were calculated from the official fixed URLs. Package managers verify their own artifacts. No checksums are fetched from a moving `latest` URL at installation time.

Homebrew installs/upgrades only the listed formulae/casks and their required dependencies. apt installs/upgrades only named packages from configured repositories; it never runs `apt upgrade`. The package-manager candidate is the target for system libraries/utilities with distribution-specific ABI/security backports. Their package versions are included in the before/after inventory; they are not replaced with arbitrary upstream libraries. Offline metadata or a repository that cannot satisfy a command's target produces a warning/failure, not an OS upgrade.

Linux release CLIs are installed in `~/.local/bin`, ahead of distro binaries, when the existing command is below target. Downloads are verified and executed with `--version` before replacement; binaries are replaced by rename so running processes are not truncated. Old package-managed copies are left to their manager. Unrecognized/unusable version output cannot pass verification. Yazi and `ya` must have exactly matching versions; a newer Yazi with mismatched `ya` is blocked instead of downgraded.

Herdr is additionally found in `HERDR_INSTALL_DIR`, Homebrew, Cargo, mise and Nix locations. Existing direct `~/.local/bin/herdr` and Homebrew installs can be updated; other managers/custom paths are identified and reported for an update through their owner. No running Herdr server is stopped or restarted. Existing integrations are never automatically rewritten during an update.

After binary verification, setup sets `[keys].prefix = "ctrl+space"` in `${HERDR_CONFIG_PATH:-~/.config/herdr/config.toml}`. The embedded Python editor preserves other settings, comments, permissions and symlinks; it makes a uniquely named backup before atomic replacement and leaves an already matching file untouched. Inline/dotted keys tables, multiline strings, duplicate keys tables/prefix entries and unsupported prefix values fail the stage with the original file preserved. Python 3.11+ additionally validates the resulting document with `tomllib`; older Python uses the conservative editor without full TOML validation. Reload configuration in Herdr or reattach clients to apply the saved prefix.

## Managed commands and runtimes

| Component | Target | Installation and requirements | Official source |
|---|---|---|---|
| Bash | System Bash, compatible syntax with 3.2+ | Script host; Bash syntax checked on Linux. Bash 3.2 execution still needs a Mac validation. | [Bash](https://www.gnu.org/software/bash/) |
| Homebrew | Current metadata/formulae | Apple Silicon; no system-wide upgrade. cmux requires macOS 14+. | [Homebrew](https://docs.brew.sh/Installation) |
| apt | Distribution candidate | apt-based amd64/arm64; configured repositories and sudo/root for packages | [Debian apt](https://manpages.debian.org/stable/apt/apt-get.8.en.html) |
| Git | Distribution/Homebrew candidate | Git operations for shell and Yazi plugins; system libcurl/TLS from package manager | [Git](https://git-scm.com/install/) |
| zsh | 5.9 | apt/Homebrew; ncurses supplied by manager. Repositories with older zsh leave this requirement blocked. | [zsh](https://www.zsh.org/) |
| fzf | 0.74.3 | Homebrew / official Linux archive; includes `--zsh` integration, older integration fallback retained | [release](https://github.com/junegunn/fzf/releases/tag/v0.74.3) |
| zoxide | 0.10.0 | Homebrew / official musl Linux archive | [release](https://github.com/ajeetdsouza/zoxide/releases/tag/v0.10.0) |
| ripgrep | 15.2.0 | Homebrew / official musl Linux archive; command `rg` | [release](https://github.com/BurntSushi/ripgrep/releases/tag/15.2.0) |
| fd | 10.5.0 | Homebrew / official musl Linux archive; apt `fd-find` fallback naming handled | [release](https://github.com/sharkdp/fd/releases/tag/v10.5.0) |
| Starship | 1.26.0 | Homebrew / official musl Linux archive; must work before Yazi Starship plugin | [release](https://github.com/starship/starship/releases/tag/v1.26.0) |
| Yazi + ya | 26.9.1 | Homebrew / official musl Linux ZIP; matching pair, `file`, Git and Starship | [release](https://github.com/sxyazi/yazi/releases/tag/v26.9.1), [CLI](https://yazi-rs.github.io/docs/cli/) |
| Ghostty | 1.3.1 | Linux only: apt package when available, otherwise snapd + stable classic Snap. Snap/service availability is checked by the install command. | [tags](https://github.com/ghostty-org/ghostty/tags), [packages](https://ghostty.org/docs/install/binary) |
| cmux native macOS | 0.64.22 | `manaflow-ai/cmux` tap/cask; macOS 14+, Apple Silicon. Bundle version and bundled CLI are checked; a cmux TUI on PATH is not accepted. | [release](https://github.com/manaflow-ai/cmux/releases/tag/v0.64.22), [requirements](https://cmux.com/docs/getting-started) |
| Herdr | 0.8.2 | Official Linux x86_64/aarch64 and macOS aarch64 binaries; verify `--version`, `--help`, then integrations without starting a server | [release](https://github.com/herdrdev/herdr/releases/tag/v0.8.2), [install](https://herdr.dev/docs/install/) |
| NVM | 0.40.7 | Fixed installer + checksum; Git/curl; writes no shell profile | [release](https://github.com/nvm-sh/nvm/releases/tag/v0.40.7) |
| Node.js | 24.20.0 LTS | NVM's checksum-verified release; higher active compatible versions retained. Global npm packages are **not migrated**, since they may contain harnesses. npm ships with Node. | [distribution index](https://nodejs.org/dist/index.json), [release files](https://nodejs.org/dist/v24.20.0/) |
| pnpm | 12.3.4 | Homebrew / official standalone musl Linux archive. pnpm 12 is native; no Corepack/npm bootstrap or extra Node dependency on Linux. | [release](https://github.com/pnpm/pnpm/releases/tag/v12.3.4), [installation](https://pnpm.io/installation) |
| JetBrains Mono | 2.304 | Official ZIP + checksum; actual TTF `head.fontRevision` inspected on every run | [release](https://github.com/JetBrains/JetBrainsMono/releases/tag/v2.304) |
| Python 3 | Distribution/Homebrew candidate | stdlib only, used for TTF version metadata and targeted Herdr prefix configuration; no pip packages. Tests require Python 3.8+. | [Python](https://www.python.org/downloads/) |

### System packages and optional capabilities

Linux base packages: `zsh`, `git`, `curl`, `ca-certificates`, `file`, `unzip`, `tar`, `build-essential` (compiler, make and libc development prerequisites), `fontconfig` (font cache), `python3`. Additional distro packages: `fzf`, `zoxide`, `ripgrep`, `fd-find`, `wl-clipboard`, `xclip`, `command-not-found`. `snapd` is added only if needed for Ghostty. GTK/Wayland/X11 and runtime libraries for Ghostty come from its apt/Snap package, not from a parallel custom library installation. macOS equivalents needed by formulae are resolved by Homebrew; system unzip/tar/shasum are used there.

Optional Yazi preview helpers such as ffmpeg, 7zip, jq, Poppler and ImageMagick were not installed by the previous script and remain optional; basic file navigation plus Git/Starship integration does not depend on them. Bun is not installed: the Bun shell plugins are conveniences if the user installs Bun separately. Corepack is no longer an installation dependency. SSH, Mosh, network services and mobile apps are prepared separately.

## Plugins and compatibility

Plugins without a stable release contract track their official default branches through their existing managers. This preserves the repository's daily shell-plugin update convention. Revisions are reported rather than pretending they have numeric releases. Local edits and explicit Yazi revision pins are not discarded. Only named managed plugins are updated; unrelated user plugins are not selected.

| Plugin/library | Target/source | Requirements and verification |
|---|---|---|
| Zinit | 3.17.0+, [official main](https://github.com/zdharma-continuum/zinit) | zsh 5.9, Git; self-update and check `VERSION` |
| zsh-autosuggestions | [zsh-users](https://github.com/zsh-users/zsh-autosuggestions) default branch | zsh; loaded by Zinit |
| zsh-syntax-highlighting | [zsh-users](https://github.com/zsh-users/zsh-syntax-highlighting) default branch | zsh; loaded by Zinit |
| zsh-history-substring-search | [zsh-users](https://github.com/zsh-users/zsh-history-substring-search) default branch | zsh and configured widgets |
| omz-plugin-pnpm | [ntnyq](https://github.com/ntnyq/omz-plugin-pnpm) default branch | pnpm for its commands |
| omz-plugin-bun | [ntnyq](https://github.com/ntnyq/omz-plugin-bun) default branch | optional user-installed Bun |
| zsh-you-should-use | [MichaelAquilina](https://github.com/MichaelAquilina/zsh-you-should-use) default branch | zsh and aliases |
| OMZ snippets | [Oh My Zsh](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins): git, bun, alias-finder; command-not-found on macOS | Git; optional Bun; platform command-not-found helper. No full OMZ framework installation. |
| Yazi Git | [yazi-rs/plugins:git](https://github.com/yazi-rs/plugins/tree/main/git.yazi), audited `4dc7f1b` | Current `@since` is **26.8.15**, above the former 26.5.6 target. Fetch current minimum before any plugin mutation and check deployed minimum afterwards. |
| Yazi Starship | [Rolv-Apneseth/starship](https://github.com/Rolv-Apneseth/starship.yazi), audited `ea92cf4` | Yazi 25.4.8+ and working Starship; managed via `ya pkg` |

Yazi's two plugins use targeted `ya pkg upgrade <id> <id>`, with the resulting revisions in `package.toml` and the version inventory. Current upstream requirements are checked before upgrades. If a later plugin needs a Yazi newer than the fixed target/installed version, setup reports a blocked stage for review; it does not force incompatible code to count as installed.

## Herdr integration contract

The implementation was checked against the **v0.8.2 source**, especially [CLI status](https://github.com/herdrdev/herdr/blob/v0.8.2/src/cli/integration.rs), [registry](https://github.com/herdrdev/herdr/blob/v0.8.2/src/integration/registry.rs) and [official documentation](https://herdr.dev/docs/integrations/). `integration status` runs without a live server. Its `not installed`, `current`, `outdated` and `needs repair` records are parsed conservatively; failed commands, missing/duplicate target records and future unknown formats are indeterminate, never silently “missing”.

| Harness | Official command | Effective location |
|---|---|---|
| OpenCode | `herdr integration install opencode` | `~/.config/opencode/plugins/herdr-agent-state.js`; 0.8.2 also installs its official TUI session plugin/config registration |
| Hermes | `herdr integration install hermes` | `${HERMES_HOME:-~/.hermes}/plugins/herdr-agent-state`, enabled in `config.yaml` |
| Codex | `herdr integration install codex` | `${CODEX_HOME:-~/.codex}/herdr-agent-state.sh`, `hooks.json`, hooks feature in `config.toml` |
| Claude Code | `herdr integration install claude` | `${CLAUDE_CONFIG_DIR:-~/.claude}/hooks/herdr-agent-state.sh`, `settings.json` registration |

All four official installers are shipped in 0.8.2; none of the four optional integrations is active by binary installation alone. Native detection is incorporated in Herdr and needs no extra component. The summary distinguishes installed, skipped prerequisites/selection, indeterminate/unavailable status, failed, and blocked existing incompatible integrations. There is no fabricated “built-in hook installed” result. Missing harnesses are skipped and never installed. Only the official installer edits selected integration entries; its affected config files are backed up first. Models, providers, accounts, skills, harness updates and T3 Code remain out of scope.

## Validation performed and pending

Executed in a restricted Linux amd64 workspace:

- `bash -n setup.sh` and `git diff --check`.
- `python3 -m unittest discover -s tests -v`: isolated status/selector/profile/version tests, with temporary homes and inert binaries. Includes fresh install and old-version upgrade paths, repeated runs, partial/all/empty selections, missing harnesses, failed installs/checks, Ctrl+C/EOF cancellation, CI/no terminal, actual pipe + controlling PTY, checksums, retaining newer versions, and failed stages continuing without disabling Bash errexit.
- Official Linux amd64 Herdr 0.8.2 `--version` and `integration status` in a temporary home; output matches the tested status protocol.
- Official Linux amd64 Yazi 26.9.1, Starship 1.26.0 and pnpm 12.3.4 version probes from temporary extracted binaries.
- Deployment into a temporary home, parsing all generated TOML with Python's `tomllib`, successful Starship prompt generation, and TTF revision detection returning 2.304.

**Not validated here:** full apt/Snap/Homebrew provisioning (fresh or existing desktop), macOS arm64/Bash 3.2, Linux arm64 binaries, actual GUI rendering in Ghostty/cmux, font appearance, Zinit interactive plugin loading, real harness lifecycle/resume hooks, TermRover devices and remote reconnect. An attempted headless Yazi PTY launch did not complete reliably; Yazi's interactive Git/Starship rendering remains a manual check. No GUI/profile is claimed manually verified by the unit tests.

Before release, run both fresh provisioning and an existing-environment upgrade on Linux amd64, Linux arm64 and macOS arm64. Confirm `zinit list`, `ya pkg list`, Yazi Git/Starship rendering, the terminal's config/fonts, a selected official Herdr integration, detach/reattach and TermRover reconnect. Keep these platform checks pending until actually performed.
