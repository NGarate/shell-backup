#!/bin/bash

################################################################################
# SHELL-BACKUP: Development Environment Setup
# Supports: macOS Apple Silicon (arm64), Ubuntu/Debian Linux (amd64/arm64)
# Version: 3.0.0
################################################################################

set -euo pipefail

################################################################################
# 1. CONFIGURATION & CONSTANTS
################################################################################

readonly SETUP_LOG="${HOME}/.setup.log"
readonly BACKUP_DIR="${HOME}/.backup"
# Saved choices reused by later runs, including --ci (KEY=value lines).
readonly PROFILE_FILE="${HOME}/.config/shell-backup/profile"
readonly FONT_MARKER_DIR="${HOME}/.local/share/shell-backup/fonts"
readonly FONTCONFIG_FILE="${HOME}/.config/fontconfig/conf.d/60-shell-backup.conf"
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Version requirements
readonly MIN_ZSH_VERSION="5.9"
readonly MIN_YAZI_VERSION="26.9.1"

# Tool versions
readonly NVM_INSTALL_VERSION="0.40.7"
readonly YAZI_VERSION="26.9.1"

# Non-interactive flag (will be parsed after functions are defined)
NON_INTERACTIVE=false
WITH_CMUX=false
FONT_CHOICE=""
HERDR_BIN=""
HERDR_READY=false
SETUP_FAILED=false
RESULTS=()
readonly HERDR_VERSION="0.8.2"
readonly STARSHIP_VERSION="1.26.0"
readonly PNPM_VERSION="12.3.4"
readonly NODE_VERSION="24.20.0"
readonly GHOSTTY_VERSION="1.3.1"
readonly CMUX_VERSION="0.64.22"
readonly NEOVIM_VERSION="0.12.6"
readonly LAZYGIT_VERSION="0.66.2"
readonly TREE_SITTER_VERSION="0.27.1"

################################################################################
# 2. UTILITY FUNCTIONS
################################################################################

# Timestamp helper
_ts() {
    date '+%H:%M:%S'
}

log() {
    echo -e "${BLUE}[$(_ts)][INFO]${NC} $1" | tee -a "$SETUP_LOG"
}

success() {
    echo -e "${GREEN}[$(_ts)]✓${NC} $1" | tee -a "$SETUP_LOG"
}

error() {
    echo -e "${RED}[$(_ts)]✗${NC} $1" | tee -a "$SETUP_LOG" >&2
    exit 1
}

warning() {
    echo -e "${YELLOW}[$(_ts)]⚠${NC} $1" | tee -a "$SETUP_LOG"
}

parse_args() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            --ci|--non-interactive) NON_INTERACTIVE=true ;;
            --with-cmux) WITH_CMUX=true ;;
            # Herdr is installed on both platforms now; old invocations keep working.
            --with-herdr) warning '--with-herdr is no longer needed and is ignored (Herdr is installed by default)' ;;
            --font=iosevka|--font=jetbrains) FONT_CHOICE="${arg#--font=}" ;;
            --font=*) error "Unknown font: ${arg#--font=} (use iosevka or jetbrains)" ;;
            --help|-h)
                printf '%s\n' 'Usage: setup.sh [--ci|--non-interactive] [--with-cmux] [--font=iosevka|jetbrains]' \
                    'Ghostty + Herdr on Linux and macOS. --with-cmux adds cmux on macOS; an installed cmux stays managed; --with-herdr is accepted and ignored.' \
                    'Terminal font: Iosevka Term SS05 (default) or JetBrainsMono Nerd Font; the choice is saved.'
                exit 0 ;;
            *) error "Unknown option: $arg" ;;
        esac
    done
}

command_exists() {
    command -v "$1" &>/dev/null
}

ensure_user_local_bin_on_path() {
    mkdir -p "$HOME/.local/bin"
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) export PATH="$HOME/.local/bin:$PATH" ;;
    esac
}

brew_install_or_upgrade() {
    local package_name="$1"
    local command_name="${2:-$1}"
    local outdated

    if ! command_exists brew; then
        error "Homebrew is required to install $package_name"
    fi

    if brew list "$package_name" &>/dev/null; then
        outdated=$(brew outdated --quiet "$package_name" 2>/dev/null || true)
        if [[ -n "$outdated" ]]; then
            log "Upgrading $package_name via Homebrew..."
            if ! brew upgrade "$package_name"; then
                warning "$package_name upgrade via Homebrew failed"
                return 1
            fi
            success "$package_name upgraded via Homebrew"
        else
            success "$package_name already current via Homebrew"
        fi
    elif command_exists "$command_name"; then
        warning "$command_name exists outside Homebrew; skipping Homebrew-managed update for $package_name"
    else
        log "Installing $package_name via Homebrew..."
        if ! brew install "$package_name"; then
            warning "$package_name installation via Homebrew failed"
            return 1
        fi
        success "$package_name installed via Homebrew"
    fi
}

# Numeric release versions only; unknown output never counts as a working tool.
tool_version() {
    local output
    output=$("$1" --version 2>/dev/null) || return 0
    # lazygit prints key=value pairs that start with a commit hash.
    [[ "$output" != *", version="* ]] || output="${output#*, version=}"
    printf '%s\n' "$output" | sed -nE 's/^[^0-9]*([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/p' | head -1
}

require_version() {
    local version
    version=$(tool_version "$1")
    if [[ -n "$version" ]] && version_gte "$version" "$2"; then
        success "$1 verified ($version, target $2)"
        return 0
    fi
    warning "$1 ${version:-absent/unusable} does not meet $2; component blocked"
    return 1
}

record_result() {
    RESULTS+=("$1: $2${3:+ — $3}")
    log "${RESULTS[${#RESULTS[@]}-1]}"
    [[ "$2" != failed && "$2" != blocked ]] || SETUP_FAILED=true
    return 0
}

# Run fallible stages in a child shell with errexit active. Calling a function
# directly in an `if` would disable errexit throughout that function.
run_stage() {
    local label="$1" pid status=0
    shift
    ( set -e; "$@" ) &
    pid=$!
    wait "$pid" || status=$?
    if [[ "$status" == 0 ]]; then
        record_result "$label" verified
    elif [[ "$status" == 3 ]]; then
        record_result "$label" skipped "see $SETUP_LOG"
    else
        record_result "$label" failed "exit $status; see $SETUP_LOG"
    fi
}

can_prompt() {
    [[ "$NON_INTERACTIVE" != true ]] && ( : </dev/tty >/dev/tty ) 2>/dev/null
}

read_tty() (
    trap 'exit 130' INT
    local answer
    exec 9<>/dev/tty || exit 1
    printf '%s' "$1" >&9
    IFS= read -r answer <&9 || exit 1
    printf '%s\n' "$answer"
)

# Keep Ctrl+C scoped to the prompt, including the parent shell waiting for
# command substitution. Restore any caller-provided handler afterwards.
prompt_tty() {
    local previous_int
    previous_int=$(trap -p INT)
    trap ':' INT
    TTY_ANSWER=$(read_tty "$1") || TTY_ANSWER=""
    if [[ -n "$previous_int" ]]; then
        eval "$previous_int"
    else
        trap - INT
    fi
}

sha256_file() {
    if command_exists sha256sum; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

verified_download() {
    local url="$1" checksum="$2" destination="$3" max_time="${4:-180}" actual
    [[ "$checksum" =~ ^[a-f0-9]{64}$ ]] || return 1
    retry curl -fL --silent --show-error --connect-timeout 15 --max-time "$max_time" "$url" -o "$destination" || return 1
    actual=$(sha256_file "$destination") || return 1
    if [[ "$actual" != "$checksum" ]]; then
        warning "SHA-256 mismatch: $url"
        return 1
    fi
}

# All records below come from the official release asset digests, audited
# 2026-09-07. musl archives avoid distro glibc requirements for Rust CLIs.
release_asset() {
    local name="$1" platform="$2" arch="$3"
    case "$name:$platform:$arch" in
        herdr:linux:amd64) printf '%s\n' 'https://github.com/herdrdev/herdr/releases/download/v0.8.2/herdr-linux-x86_64|976150a14d490c94b243ea2e1a7eb2dfb67f12e36b182db90936f6728e6aecf4' ;;
        herdr:linux:arm64) printf '%s\n' 'https://github.com/herdrdev/herdr/releases/download/v0.8.2/herdr-linux-aarch64|f55610658e1c2e0d2aaef730b4b2ab885f7f8ba00285ab372bfb14f2e3d5b40d' ;;
        herdr:darwin:arm64) printf '%s\n' 'https://github.com/herdrdev/herdr/releases/download/v0.8.2/herdr-macos-aarch64|a5d4f4d504d8b309c91f811050559300faba31258425f53c50852fc96f6ae574' ;;
        yazi:linux:amd64) printf '%s\n' 'https://github.com/sxyazi/yazi/releases/download/v26.9.1/yazi-x86_64-unknown-linux-musl.zip|9b9c39decccf8cb0ff53a7d637d38f8a79d93bbd0099f4ea9c619ef6bb392f5d' ;;
        yazi:linux:arm64) printf '%s\n' 'https://github.com/sxyazi/yazi/releases/download/v26.9.1/yazi-aarch64-unknown-linux-musl.zip|dd569daecaae914185f295634109295ccd25c1b42b02eb89a74f651970024f2e' ;;
        starship:linux:amd64) printf '%s\n' 'https://github.com/starship/starship/releases/download/v1.26.0/starship-x86_64-unknown-linux-musl.tar.gz|b7c232b0e8249d8e55a40beb79c5c43a7d370f3f9408bd215deb0170daeaadf3' ;;
        starship:linux:arm64) printf '%s\n' 'https://github.com/starship/starship/releases/download/v1.26.0/starship-aarch64-unknown-linux-musl.tar.gz|dc30189378d2f2e287384e8a692d3f95ad1df64cf0e8c36aa9201516028aed6b' ;;
        fzf:linux:amd64) printf '%s\n' 'https://github.com/junegunn/fzf/releases/download/v0.74.3/fzf-0.74.3-linux_amd64.tar.gz|3501a595e4b5c40a6b047340a0e8f805c46fd4e61ef95ef8a136ba8c61cf6f22' ;;
        fzf:linux:arm64) printf '%s\n' 'https://github.com/junegunn/fzf/releases/download/v0.74.3/fzf-0.74.3-linux_arm64.tar.gz|4a17a17b46bd0c4873e995533de508995c11572c0be0664a5dbcf13f60463046' ;;
        fd:linux:amd64) printf '%s\n' 'https://github.com/sharkdp/fd/releases/download/v10.5.0/fd-v10.5.0-x86_64-unknown-linux-musl.tar.gz|761c72dc8e120d85b22292063be8a796e2eeb20eb3e4f38b8fa2343ccf3514a7' ;;
        fd:linux:arm64) printf '%s\n' 'https://github.com/sharkdp/fd/releases/download/v10.5.0/fd-v10.5.0-aarch64-unknown-linux-musl.tar.gz|d76c4317f7d5dba69f8a2a15856c90c777e7f0dd4e85f0de8c76de6992c374d4' ;;
        zoxide:linux:amd64) printf '%s\n' 'https://github.com/ajeetdsouza/zoxide/releases/download/v0.10.0/zoxide-0.10.0-x86_64-unknown-linux-musl.tar.gz|2d93385b99f3e82cf2701609a1bffcad863fbeb75aa3fe7eb6be4d29be68b1ae' ;;
        zoxide:linux:arm64) printf '%s\n' 'https://github.com/ajeetdsouza/zoxide/releases/download/v0.10.0/zoxide-0.10.0-aarch64-unknown-linux-musl.tar.gz|f1f16c5d6298d63dee467eedea1cdcd8490e43e493bea43acd416dc9033ef641' ;;
        rg:linux:amd64) printf '%s\n' 'https://github.com/BurntSushi/ripgrep/releases/download/15.2.0/ripgrep-15.2.0-x86_64-unknown-linux-musl.tar.gz|33e15bcf1624b25cdd2a55813a47a2f95dbe126268203e76aa6a585d1e7b149c' ;;
        rg:linux:arm64) printf '%s\n' 'https://github.com/BurntSushi/ripgrep/releases/download/15.2.0/ripgrep-15.2.0-aarch64-unknown-linux-musl.tar.gz|800b1e7206afe799dfb5a6901f23147cfaabe0e52210538100f61e86e1740915' ;;
        pnpm:linux:amd64) printf '%s\n' 'https://github.com/pnpm/pnpm/releases/download/v12.3.4/pnpm-linux-x64-musl.tar.gz|e4c4f54599627cc0646fbb2ea8103bd6c88634533fbd6c6f5ca0f6fe7d6f5d9c' ;;
        pnpm:linux:arm64) printf '%s\n' 'https://github.com/pnpm/pnpm/releases/download/v12.3.4/pnpm-linux-arm64-musl.tar.gz|75c0b268cedbf9b57b69dcef576b9b307dd5b7650c1f967ac1b8f8d6afc1ca25' ;;
        # Neovim tools, audited 2026-10-16. nvim is a relocatable tree (bin, lib, share).
        nvim:linux:amd64) printf '%s\n' 'https://github.com/neovim/neovim/releases/download/v0.12.6/nvim-linux-x86_64.tar.gz|474430d53e6264f6d6dd18db42d6dc9df3a1b56ca9e88a325bbf860e1a811d87' ;;
        nvim:linux:arm64) printf '%s\n' 'https://github.com/neovim/neovim/releases/download/v0.12.6/nvim-linux-arm64.tar.gz|8f1f64a0bdb97247034038c3823c6cbad5bdf9ecd5751b85494b71c3ee04c815' ;;
        lazygit:linux:amd64) printf '%s\n' 'https://github.com/jesseduffield/lazygit/releases/download/v0.66.2/lazygit_0.66.2_linux_x86_64.tar.gz|158efc9ddfa1241fab5fb3526bb442c8dc6c4b1904d73213b9e4e93e03c52034' ;;
        lazygit:linux:arm64) printf '%s\n' 'https://github.com/jesseduffield/lazygit/releases/download/v0.66.2/lazygit_0.66.2_linux_arm64.tar.gz|79a3161eeb642f0473e23db6341f7baabd4a5933e921a9c1167c5d5c765c41a4' ;;
        tree-sitter:linux:amd64) printf '%s\n' 'https://github.com/tree-sitter/tree-sitter/releases/download/v0.27.1/tree-sitter-cli-linux-x64.zip|c7e686aec16ba17053c2e6fd87600ccb10cf8ba3d055756b17e756d538e11114' ;;
        tree-sitter:linux:arm64) printf '%s\n' 'https://github.com/tree-sitter/tree-sitter/releases/download/v0.27.1/tree-sitter-cli-linux-arm64.zip|3c0d0113cae3fea36f2336c271cbdacbcdb349edb006319155652b9386803c55' ;;
        *) return 1 ;;
    esac
}

install_release_tool() {
    local name="$1" target_version="$2" before after asset url checksum
    before=$(tool_version "$name")
    if [[ -n "$before" ]] && version_gte "$before" "$target_version"; then
        if [[ "$name" != yazi ]] || { [[ "$(tool_version ya)" == "$before" ]]; }; then
            success "$name retained ($before)"
            return 0
        fi
        # Avoid downgrading yazi just to repair a mismatched companion CLI.
        if [[ "$before" != "$target_version" ]]; then
            warning 'Newer Yazi has mismatched ya; repair that installation first'
            return 1
        fi
    fi
    asset=$(release_asset "$name" "$OS_TYPE" "$ARCH") || return 1
    IFS='|' read -r url checksum <<< "$asset"
    (
        local temp_dir binary source_binary
        temp_dir=$(mktemp -d) || exit 1
        trap 'rm -rf "$temp_dir"' EXIT
        verified_download "$url" "$checksum" "$temp_dir/asset" || exit 1
        case "$url" in
            *.tar.gz) tar -xzf "$temp_dir/asset" -C "$temp_dir" || exit 1 ;;
            *.zip) unzip -q "$temp_dir/asset" -d "$temp_dir" || exit 1 ;;
            *) mv "$temp_dir/asset" "$temp_dir/$name" || exit 1 ;;
        esac
        for binary in "$name"; do
            source_binary=$(find "$temp_dir" -type f -name "$binary" -print -quit)
            [[ -n "$source_binary" ]] || exit 1
            chmod 755 "$source_binary" || exit 1
            require_version "$source_binary" "$target_version" || exit 1
        done
        # Verify both Yazi executables before replacing either one.
        if [[ "$name" == yazi ]]; then
            source_binary=$(find "$temp_dir" -type f -name ya -print -quit)
            [[ -n "$source_binary" ]] || exit 1
            chmod 755 "$source_binary" || exit 1
            require_version "$source_binary" "$target_version" || exit 1
        fi
        mkdir -p "$HOME/.local/bin" || exit 1
        local binaries=("$name")
        [[ "$name" != yazi ]] || binaries+=(ya)
        for binary in "${binaries[@]}"; do
            source_binary=$(find "$temp_dir" -type f -name "$binary" -print -quit)
            # Rename avoids truncating binaries used by live sessions.
            install -m 755 "$source_binary" "$HOME/.local/bin/.$binary.setup" || exit 1
            mv -f "$HOME/.local/bin/.$binary.setup" "$HOME/.local/bin/$binary" || exit 1
        done
    ) || return 1
    hash -r
    after=$(tool_version "$name")
    log "$name ${before:-absent} -> ${after:-unusable} (target $target_version)"
    require_version "$name" "$target_version"
}

find_herdr() {
    local candidate
    candidate=$(command -v herdr 2>/dev/null || true)
    if [[ -n "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi
    for candidate in "${HERDR_INSTALL_DIR:-$HOME/.local/bin}/herdr" \
        "$HOME/.local/bin/herdr" /opt/homebrew/bin/herdr /usr/local/bin/herdr \
        "$HOME/.cargo/bin/herdr" "$HOME/.local/share/mise/shims/herdr" \
        "$HOME/.nix-profile/bin/herdr" /run/current-system/sw/bin/herdr; do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done
    return 1
}

setup_herdr() {
    HERDR_READY=false
    HERDR_BIN=$(find_herdr || true)
    local before=""
    [[ -z "$HERDR_BIN" ]] || before=$(tool_version "$HERDR_BIN")
    if [[ -z "$HERDR_BIN" ]]; then
        if ! install_release_tool herdr "$HERDR_VERSION"; then
            record_result Herdr failed 'installation failed; no integration selector'
            return 0
        fi
        HERDR_BIN="$HOME/.local/bin/herdr"
    elif [[ -n "$before" ]] && ! version_gte "$before" "$HERDR_VERSION"; then
        if [[ "$HERDR_BIN" == "$HOME/.local/bin/herdr" && ! -L "$HERDR_BIN" ]]; then
            if ! install_release_tool herdr "$HERDR_VERSION"; then
                record_result Herdr failed 'update failed; no integration selector'
                return 0
            fi
        elif [[ "$OS_TYPE" == darwin && "$HERDR_BIN" == /opt/homebrew/bin/herdr ]] && brew list herdr >/dev/null 2>&1; then
            if ! brew_install_or_upgrade herdr herdr; then
                record_result Herdr failed 'Homebrew update failed'
                return 0
            fi
        else
            record_result Herdr blocked "version $before; update through its owning package manager to $HERDR_VERSION+"
            return 0
        fi
    fi
    if ! require_version "$HERDR_BIN" "$HERDR_VERSION" || ! "$HERDR_BIN" --help >/dev/null 2>&1; then
        record_result Herdr failed 'verification failed; no integration selector'
        return 0
    fi
    export PATH="$(dirname "$HERDR_BIN"):$PATH"
    HERDR_READY=true
    record_result Herdr verified "${before:-absent} -> $(tool_version "$HERDR_BIN"); running sessions left intact"
    run_stage 'Herdr prefix' configure_herdr_prefix
    [[ "$OS_TYPE" != darwin ]] || free_macos_ctrl_space
    run_stage 'Herdr attach helper' deploy_attach_helper
    setup_herdr_integrations
}

# One remote command for every client (TermRover, Termux, Blink, plain ssh):
#   ssh -t host shell-backup-attach [session]   or   mosh host -- shell-backup-attach
deploy_attach_helper() {
    deploy_file "$HOME/.local/bin/shell-backup-attach" 755 << 'ATTACH_EOF'
#!/usr/bin/env bash
# shell-backup-attach [session]: attach this terminal to the host's Herdr
# session. Generated by shell-backup setup.sh; reruns replace this file.
set -euo pipefail

session="${1:-${SHELL_BACKUP_SESSION:-personal}}"
if [[ ! "$session" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$ ]]; then
    printf '%s\n' "shell-backup-attach: invalid session name: $session" >&2
    exit 2
fi

# Non-login SSH commands may lack the user's PATH.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

# Keep a working UTF-8 locale even when the client forwarded one this host
# lacks (zsh users already get this from ~/.zshenv).
normalized() { printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -d '-'; }
current="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
known=$(locale -a 2>/dev/null | tr 'A-Z' 'a-z' | tr -d '-' || true)
if [[ -n "$known" ]] && { [[ "$(normalized "$current")" != *utf8* ]] ||
    ! grep -qx -- "$(normalized "$current")" <<< "$known"; }; then
    for candidate in en_US.UTF-8 C.UTF-8; do
        if grep -qx -- "$(normalized "$candidate")" <<< "$known"; then
            unset LC_ALL LC_CTYPE
            export LANG="$candidate"
            break
        fi
    done
fi

# Unknown client TERM values (no terminfo here) break full-screen programs.
if command -v infocmp >/dev/null 2>&1 && ! infocmp -- "${TERM:-dumb}" >/dev/null 2>&1; then
    export TERM=xterm-256color
fi
export COLORTERM="${COLORTERM:-truecolor}"

if ! command -v herdr >/dev/null 2>&1; then
    printf '%s\n' 'shell-backup-attach: herdr not found; run setup.sh on this host' >&2
    exit 127
fi
exec herdr session attach "$session"
ATTACH_EOF
    success "Attach helper deployed: ssh -t <host> shell-backup-attach [session]"
}

# macOS binds Ctrl+Space (space key code 49, Control modifier 262144) to
# "Select the previous input source" (hotkey 60), which swallows Herdr's
# prefix. An absent entry 60 means the system default, which is enabled, and so
# does an unreadable hotkey list. Parsed with awk: setup needs no Python.
macos_ctrl_space_taken() {
    local hotkeys
    hotkeys=$(defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys 2>/dev/null || true)
    printf '%s\n' "$hotkeys" | awk '
    BEGIN { depth = 0; seen60 = 0; taken = 0; expect = ""; last = ""; inparams = 0 }
    {
        gsub(/[{}();,=]/, " & ")
        n = split($0, t, /[ \t]+/)
        for (i = 1; i <= n; i++) {
            tok = t[i]
            if (tok == "") continue
            gsub(/"/, "", tok)
            if (tok == "{") {
                depth++
                if (depth == 2) { entry = last; enabled = ""; np = 0 }
                expect = ""
            } else if (tok == "}") {
                if (depth == 2) {
                    if (entry == "60") seen60 = 1
                    if (enabled == "1" && np == 3 && p[2] == 49 && p[3] == 262144) taken = 1
                }
                depth--
            } else if (tok == "(") {
                if (depth == 3 && expect == "parameters") inparams = 1
                expect = ""
            } else if (tok == ")") {
                inparams = 0
            } else if (tok == "=") {
                expect = last
            } else if (tok == ";" || tok == ",") {
                expect = ""
            } else {
                if (inparams) p[++np] = tok
                else if (expect == "enabled" && depth == 2) enabled = tok
                last = tok
            }
        }
    }
    END { exit (!seen60 || taken) ? 0 : 1 }'
}

# Herdr keeps Ctrl+Space; offer to open Keyboard settings so the user can free
# it now. Settings are never changed by the script.
free_macos_ctrl_space() {
    macos_ctrl_space_taken || return 0
    warning 'macOS uses Ctrl+Space to switch input sources, so the Herdr prefix never reaches Ghostty.'
    log 'To free it: System Settings > Keyboard > Keyboard Shortcuts… > Input Sources, uncheck "Select the previous input source".'
    if ! can_prompt; then
        record_result 'Ctrl+Space for Herdr' skipped 'still bound by macOS; free it in Keyboard Shortcuts'
        return 0
    fi
    local answer
    while true; do
        prompt_tty 'Open Keyboard settings now? y = open and wait, n = continue without changing it [y/N]: '
        answer="$TTY_ANSWER"
        case "$answer" in
            y|Y|n|N|'') break ;;
        esac
    done
    if [[ "$answer" != [yY] ]]; then
        record_result 'Ctrl+Space for Herdr' skipped 'kept bound by macOS at your choice'
        return 0
    fi
    if ! open 'x-apple.systempreferences:com.apple.Keyboard-Settings.extension'; then
        record_result 'Ctrl+Space for Herdr' skipped 'could not open System Settings'
        return 0
    fi
    prompt_tty 'Click "Keyboard Shortcuts…", then Input Sources, uncheck "Select the previous input source", and press Enter here: '
    if macos_ctrl_space_taken; then
        record_result 'Ctrl+Space for Herdr' skipped 'still bound by macOS; rerun setup or free it in Keyboard Shortcuts'
    else
        record_result 'Ctrl+Space for Herdr' verified 'freed for Herdr'
    fi
}

# Mode of a file, following symlinks (GNU stat on Linux, BSD stat on macOS).
file_mode() {
    stat -L -c %a "$1" 2>/dev/null || stat -L -f %Lp "$1" 2>/dev/null
}

# Set [keys].prefix = "ctrl+space" in Herdr's TOML config, in awk so that
# curl | bash needs nothing beyond bash and awk. Edits are limited to ordinary
# tables and single-line strings: ambiguous layouts fail with the file kept.
configure_herdr_prefix() {
    # No server commands: existing clients can reload config or reattach later.
    local path="${HERDR_CONFIG_PATH:-$HOME/.config/herdr/config.toml}" source=/dev/null
    local mode=644 crlf=0 trailing=1 temp errors reason program
    if [[ -e "$path" ]]; then
        if [[ ! -f "$path" ]]; then
            warning "Herdr prefix: $path is not a regular file; file preserved."
            return 1
        fi
        source="$path"
        mode=$(file_mode "$path")
        ! grep -q $'\r' "$path" || crlf=1
        if [[ -s "$path" && -n "$(tail -c1 "$path")" ]]; then
            trailing=0
        fi
    fi
    read -r -d '' program <<'HERDR_PREFIX_AWK' || true
function fail(message) { print message > "/dev/stderr"; exit 1 }
{
    line = $0
    E[NR] = sub(/\r$/, "", line) ? "\r\n" : "\n"
    L[NR] = line
}
END {
    n = NR
    nl = crlf ? "\r\n" : "\n"
    sections = 0
    for (i = 1; i <= n; i++) {
        if (index(L[i], "\"\"\"") || index(L[i], "'''"))
            fail("multiline TOML strings require a manual prefix edit")
        if (L[i] ~ /^[ \t]*(keys|"keys"|'keys')[ \t]*[.=]/)
            fail("inline/dotted keys table requires a manual prefix edit")
        if (L[i] ~ /^[ \t]*\[[ \t]*(keys|"keys"|'keys')[ \t]*\][ \t]*(#.*)?$/) { sections++; header = i }
    }
    if (sections > 1) fail("duplicate keys tables")
    out = 0
    if (sections == 1) {
        start = header + 1
        end = n + 1
        for (i = start; i <= n; i++) if (L[i] ~ /^[ \t]*\[/) { end = i; break }
        candidates = 0
        for (i = start; i < end; i++)
            if (L[i] ~ /^[ \t]*(prefix|"prefix"|'prefix')[ \t]*=/) { candidates++; found = i }
        if (candidates > 1) fail("duplicate prefix entries")
        if (candidates == 1) {
            line = L[found]
            match(line, /^[ \t]*(prefix|"prefix"|'prefix')[ \t]*=[ \t]*/)
            head = substr(line, 1, RLENGTH)
            rest = substr(line, RLENGTH + 1)
            if (rest ~ /^"/) { if (!match(rest, /^"([^"\\]|\\.)*"/)) fail("unsupported prefix value") }
            else if (rest ~ /^'/) { if (!match(rest, /^'[^']*'/)) fail("unsupported prefix value") }
            else fail("unsupported prefix value")
            value = substr(rest, 1, RLENGTH)
            tail = substr(rest, RLENGTH + 1)
            if (tail !~ /^[ \t]*(#.*)?$/) fail("unsupported prefix value")
            if (value != "\"ctrl+space\"" && value != "'ctrl+space'") L[found] = head "\"ctrl+space\"" tail
            for (i = 1; i <= n; i++) { O[++out] = L[i]; ORIG[out] = i }
        } else {
            for (i = 1; i <= header; i++) { O[++out] = L[i]; ORIG[out] = i }
            O[++out] = "prefix = \"ctrl+space\""; ORIG[out] = 0
            for (i = header + 1; i <= n; i++) { O[++out] = L[i]; ORIG[out] = i }
        }
    } else {
        for (i = 1; i <= n; i++) { O[++out] = L[i]; ORIG[out] = i }
        if (n > 0) { O[++out] = ""; ORIG[out] = 0 }
        O[++out] = "[keys]"; ORIG[out] = 0
        O[++out] = "prefix = \"ctrl+space\""; ORIG[out] = 0
    }
    for (j = 1; j <= out; j++) {
        i = ORIG[j]
        if (i == 0) ending = nl
        else if (i == n && !trailing) ending = (j < out) ? nl : ""
        else ending = E[i]
        printf "%s%s", O[j], ending
    }
}
HERDR_PREFIX_AWK
    temp=$(mktemp) || return 1
    errors=$(mktemp) || { rm -f "$temp"; return 1; }
    if ! awk -v crlf="$crlf" -v trailing="$trailing" "$program" "$source" > "$temp" 2> "$errors"; then
        reason=$(cat "$errors")
        rm -f "$temp" "$errors"
        warning "Herdr prefix: ${reason:-config could not be edited}; file preserved."
        return 1
    fi
    rm -f "$errors"
    if [[ -f "$path" ]] && cmp -s "$temp" "$path"; then
        rm -f "$temp"
        log 'Herdr prefix already set to ctrl+space; config preserved.'
    elif deploy_file "$path" "${mode:-644}" < "$temp"; then
        rm -f "$temp"
        success "Herdr prefix saved as ctrl+space: $path"
    else
        rm -f "$temp"
        return 1
    fi
    log 'Herdr prefix: Ctrl+Space. Reload config in Herdr or reattach the client to apply.'
}

# Herdr 0.8.2 provides all four installers, but none of these four
# session/lifecycle integrations is active merely by installing Herdr itself.
# Official protocol: src/cli/integration.rs at v0.8.2 (no server required).
integration_state() {
    local target="$1" snapshot="$2" line count
    count=$(printf '%s\n' "$snapshot" | awk -v p="$target: " 'index($0,p)==1 {n++} END {print n+0}')
    [[ "$count" == 1 ]] || { printf '%s\n' unknown; return; }
    line=$(printf '%s\n' "$snapshot" | sed -n "s/^$target: //p")
    case "$line" in
        'not installed ('*) printf '%s\n' missing ;;
        'current ('*) printf '%s\n' installed ;;
        'outdated ('*|'needs repair ('*) printf '%s\n' incompatible ;;
        *) printf '%s\n' unknown ;;
    esac
}

integration_home() {
    local directory
    case "$1" in
        opencode) directory="$HOME/.config/opencode" ;;
        hermes) directory="${HERMES_HOME:-$HOME/.hermes}" ;;
        codex) directory="${CODEX_HOME:-$HOME/.codex}" ;;
        claude) directory="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ;;
    esac
    case "$directory" in '~/'*) directory="$HOME/${directory:2}" ;; esac
    printf '%s\n' "$directory"
}

install_herdr_integration() {
    local target="$1" directory snapshot state index
    # Re-check immediately before mutation.
    if ! snapshot=$("$HERDR_BIN" integration status 2>/dev/null); then
        record_result "Herdr/$target" skipped 'state indeterminate'
        return 0
    fi
    state=$(integration_state "$target" "$snapshot")
    if [[ "$state" != missing ]]; then
        record_result "Herdr/$target" skipped "state changed to $state; preserved"
        return 0
    fi
    directory=$(integration_home "$target")
    if ! command_exists "$target" || [[ ! -d "$directory" ]]; then
        record_result "Herdr/$target" skipped 'harness or its initialized configuration is absent'
        return 0
    fi
    # Back up only files potentially edited by the official installer, and only
    # if it changed them. Never back up whole harness homes (credentials,
    # sessions and projects live there).
    local file install_status=0
    local -a files=() snapshots=()
    case "$target" in
        opencode) files=("$directory/tui.json" "$directory/tui.jsonc") ;;
        hermes) files=("$directory/config.yaml") ;;
        codex) files=("$directory/config.toml" "$directory/hooks.json") ;;
        claude) files=("$directory/settings.json") ;;
    esac
    for file in "${files[@]}"; do
        snapshots+=("$(snapshot_file "$file")")
    done
    "$HERDR_BIN" integration install "$target" </dev/null || install_status=$?
    for ((index = 0; index < ${#files[@]}; index++)); do
        keep_snapshot_if_changed "${files[index]}" "${snapshots[index]}"
    done
    if [[ "$install_status" != 0 ]]; then
        record_result "Herdr/$target" failed 'official installer failed; rerun setup to retry'
        return 0
    fi
    if snapshot=$("$HERDR_BIN" integration status 2>/dev/null) && \
       [[ "$(integration_state "$target" "$snapshot")" == installed ]]; then
        record_result "Herdr/$target" installed 'verified by Herdr; restart the harness to load it'
    else
        record_result "Herdr/$target" failed 'post-install verification failed'
    fi
}

# Every missing integration whose harness is initialized is installed without
# asking; existing ones (current, outdated or unknown) are never rewritten.
setup_herdr_integrations() {
    [[ "$HERDR_READY" == true ]] || return 0
    local snapshot target
    if ! snapshot=$("$HERDR_BIN" integration status 2>/dev/null); then
        record_result 'Herdr integrations' skipped 'state indeterminate; status command unavailable or failed'
        return 0
    fi
    for target in opencode hermes codex claude; do
        case "$(integration_state "$target" "$snapshot")" in
            missing) install_herdr_integration "$target" ;;
            installed) record_result "Herdr/$target" installed 'preserved' ;;
            incompatible) record_result "Herdr/$target" blocked 'existing integration outdated or needs repair; preserved' ;;
            *) record_result "Herdr/$target" skipped 'state indeterminate; preserved' ;;
        esac
    done
}

# Official release digests (assets[].digest), audited 2026-10-14.
# Format: tag|url|sha256|files copied from the archive. Nerd Fonts publishes
# no patched SS05, so Iosevka takes its icons from the Symbols fallback.
font_asset() {
    case "$1" in
        iosevka-term-ss05) printf '%s\n' 'v34.9.0|https://github.com/be5invis/Iosevka/releases/download/v34.9.0/PkgTTF-IosevkaTermSS05-34.9.0.zip|f1cf472e2552477b71cb397a770e41ae78035e24bca4c7235c4324137b314835|IosevkaTermSS05-Regular.ttf IosevkaTermSS05-Italic.ttf IosevkaTermSS05-Bold.ttf IosevkaTermSS05-BoldItalic.ttf' ;;
        jetbrains-nerd) printf '%s\n' 'v3.5.1|https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/JetBrainsMono.tar.xz|04d5e8f903693f9dd13e16f867e994834e681eb3c72c0d337a770dcda09010cf|JetBrainsMonoNerdFont-Regular.ttf JetBrainsMonoNerdFont-Italic.ttf JetBrainsMonoNerdFont-Bold.ttf JetBrainsMonoNerdFont-BoldItalic.ttf JetBrainsMonoNerdFontMono-Regular.ttf JetBrainsMonoNerdFontMono-Italic.ttf JetBrainsMonoNerdFontMono-Bold.ttf JetBrainsMonoNerdFontMono-BoldItalic.ttf' ;;
        symbols-nerd) printf '%s\n' 'v3.5.1|https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/NerdFontsSymbolsOnly.tar.xz|01172f37db8543edb102e5cb5c64101c9f4686630804d49b419aa07b23a69996|SymbolsNerdFont-Regular.ttf SymbolsNerdFontMono-Regular.ttf' ;;
        *) return 1 ;;
    esac
}

readonly FONT_IDS="iosevka-term-ss05 jetbrains-nerd symbols-nerd"

font_family() {
    case "${1:-$FONT_CHOICE}" in
        jetbrains) printf '%s\n' 'JetBrainsMono Nerd Font' ;;
        *) printf '%s\n' 'Iosevka Term SS05' ;;
    esac
}

font_install_dir() {
    if [[ "$OS_TYPE" == darwin ]]; then
        printf '%s\n' "$HOME/Library/Fonts"
    else
        printf '%s\n' "$HOME/.local/share/fonts/shell-backup/$1"
    fi
}

font_installed() {
    local id="$1" asset tag url checksum files dir file
    asset=$(font_asset "$id") || return 1
    IFS='|' read -r tag url checksum files <<< "$asset"
    [[ "$(cat "$FONT_MARKER_DIR/$id.version" 2>/dev/null)" == "$tag $checksum" ]] || return 1
    dir=$(font_install_dir "$id")
    for file in $files; do
        [[ -s "$dir/$file" ]] || return 1
    done
}

install_font_archive() {
    local id="$1" asset tag url checksum files dir
    asset=$(font_asset "$id") || return 1
    IFS='|' read -r tag url checksum files <<< "$asset"
    if font_installed "$id"; then
        success "Font $id retained ($tag)"
        return 0
    fi
    dir=$(font_install_dir "$id")
    log "Installing font $id $tag..."
    (
        local temp_dir file source_file
        temp_dir=$(mktemp -d) || exit 1
        trap 'rm -rf "$temp_dir"' EXIT
        verified_download "$url" "$checksum" "$temp_dir/asset" 900 || exit 1
        mkdir "$temp_dir/extracted" || exit 1
        case "$url" in
            *.zip) unzip -q "$temp_dir/asset" -d "$temp_dir/extracted" || exit 1 ;;
            *.tar.xz) tar -xJf "$temp_dir/asset" -C "$temp_dir/extracted" || exit 1 ;;
            *) exit 1 ;;
        esac
        # Check every file before replacing any installed one.
        for file in $files; do
            [[ -n "$(find "$temp_dir/extracted" -type f -name "$file" -print -quit)" ]] || {
                warning "$file missing from $url"
                exit 1
            }
        done
        mkdir -p "$dir" "$FONT_MARKER_DIR" || exit 1
        for file in $files; do
            source_file=$(find "$temp_dir/extracted" -type f -name "$file" -print -quit)
            install -m 644 "$source_file" "$dir/.$file.setup" || exit 1
            mv -f "$dir/.$file.setup" "$dir/$file" || exit 1
        done
        printf '%s %s\n' "$tag" "$checksum" > "$FONT_MARKER_DIR/$id.version" || exit 1
    ) || return 1
    FONTS_CHANGED=true
    success "Font $id installed ($tag)"
}

# Code points used by Claude Code (⏺ ⎿ ⏵ ✻), Starship/Herdr powerline
# separators () and Nerd Font icons (󰍟).
readonly GLYPH_CODEPOINTS="23fa 23bf 23f5 273b e0b6 f0349"

report_glyph_coverage() {
    command_exists fc-list || return 0
    local codepoint missing=""
    for codepoint in $GLYPH_CODEPOINTS; do
        [[ -n "$(fc-list ":charset=$codepoint" family 2>/dev/null)" ]] || missing+=" U+$codepoint"
    done
    if [[ -n "$missing" ]]; then
        warning "No installed font covers:$missing; icons may show as boxes"
    else
        success 'Installed fonts cover the agent, prompt and icon glyphs'
    fi
}

load_profile() {
    local line
    [[ -r "$PROFILE_FILE" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            FONT=iosevka|FONT=jetbrains) [[ -n "$FONT_CHOICE" ]] || FONT_CHOICE="${line#FONT=}" ;;
        esac
    done < "$PROFILE_FILE"
}

# Flag > saved profile > one interactive question > Iosevka default.
resolve_font_choice() {
    load_profile
    if [[ -z "$FONT_CHOICE" ]] && can_prompt; then
        prompt_tty $'Terminal font:\n1) Iosevka Term SS05 (default)\n2) JetBrainsMono Nerd Font\nChoose 1-2 [1]: '
        case "$TTY_ANSWER" in 2|jetbrains) FONT_CHOICE=jetbrains ;; esac
    fi
    FONT_CHOICE="${FONT_CHOICE:-iosevka}"
    {
        grep -v '^FONT=' "$PROFILE_FILE" 2>/dev/null || true
        printf 'FONT=%s\n' "$FONT_CHOICE"
    } | deploy_file "$PROFILE_FILE" 644
    log "Terminal font: $(font_family)"
}

version_inventory() {
    local name version
    for name in git zsh fzf zoxide rg fd starship yazi ya pnpm node python3 ghostty mosh-server nvim lazygit tree-sitter; do
        version=$(tool_version "$name")
        printf '  %s: %s\n' "$name" "${version:-absent/unknown}"
    done
    for name in $FONT_IDS; do
        version=$(cut -d' ' -f1 "$FONT_MARKER_DIR/$name.version" 2>/dev/null || true)
        printf '  font %s: %s\n' "$name" "${version:-absent}"
    done
    if [[ -n "${HERDR_BIN:-}" ]]; then
        printf '  Herdr: %s (%s)\n' "$(tool_version "$HERDR_BIN")" "$HERDR_BIN"
    fi
    local asset path revision
    while IFS='|' read -r asset path; do
        revision=$(git -C "$path" rev-parse --short HEAD 2>/dev/null || true)
        printf '  %s: %s\n' "$asset" "${revision:-unavailable}"
    done < <(zinit_expected_assets)
    if [[ -f "$HOME/.local/share/zinit/zinit.git/VERSION" ]]; then
        printf '  Zinit: %s\n' "$(cat "$HOME/.local/share/zinit/zinit.git/VERSION")"
    fi
    if command_exists ya; then
        ya pkg list 2>/dev/null || true
    fi
    local package
    if [[ "$PKG_MANAGER" == apt ]]; then
        for package in zsh git curl ca-certificates file unzip tar xz-utils build-essential fontconfig python3 \
            locales wl-clipboard xclip command-not-found mosh ncurses-term fonts-noto-core \
            fonts-noto-color-emoji fonts-symbola python3-venv snapd; do
            dpkg-query -W -f='  ${Package}: ${Version}\n' "$package" 2>/dev/null || true
        done
    elif command_exists brew; then
        brew list --versions git zsh fzf zoxide ripgrep fd starship yazi pnpm python mosh neovim lazygit tree-sitter-cli 2>/dev/null || true
    fi
}

get_zsh_path() {
    local zsh_path
    zsh_path=$(command -v zsh 2>/dev/null || true)

    if [[ -z "$zsh_path" ]]; then
        error "zsh not found in PATH"
    fi

    printf '%s\n' "$zsh_path"
}

run_with_sudo() {
    local description="$1"
    shift

    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    elif sudo -n true 2>/dev/null; then
        sudo "$@"
    elif can_prompt; then
        sudo "$@"
    else
        warning "Skipping ${description}; sudo requires a password and no interactive TTY is available."
        return 1
    fi
}

detect_platform() {
    local machine
    machine=$(uname -m)

    case "$(uname -s)" in
        Darwin*)
            if [[ "$machine" != "arm64" && "$machine" != "aarch64" ]]; then
                error "Unsupported macOS architecture: $machine. Only Apple Silicon (arm64) Macs are supported."
            fi
            OS_TYPE="darwin"
            PKG_MANAGER="brew"
            ARCH="arm64"
            ;;
        Linux*)
            OS_TYPE="linux"
            case "$machine" in
                x86_64|amd64)
                    ARCH="amd64"
                    ;;
                aarch64|arm64)
                    ARCH="arm64"
                    ;;
                *)
                    error "Unsupported Linux architecture: $machine. Only amd64/x86_64 and arm64/aarch64 are supported."
                    ;;
            esac
            if command_exists apt-get; then
                PKG_MANAGER="apt"
            else
                error "No supported package manager found. This script requires apt (Ubuntu/Debian)."
            fi
            ;;
        *)
            error "Unsupported operating system: $(uname -s)"
            ;;
    esac
}

# Check if version1 >= version2
version_gte() {
    local v1="$1"
    local v2="$2"

    [[ "$v1" =~ ^[0-9]+(\.[0-9]+)*$ && "$v2" =~ ^[0-9]+(\.[0-9]+)*$ ]] || return 1

    local IFS='.'
    local i
    local -a a b
    read -r -a a <<< "$v1"
    read -r -a b <<< "$v2"

    for ((i = ${#a[@]}; i < ${#b[@]}; i++)); do a[i]=0; done
    for ((i = ${#b[@]}; i < ${#a[@]}; i++)); do b[i]=0; done

    for ((i = 0; i < ${#a[@]}; i++)); do
        ((10#${a[i]} > 10#${b[i]})) && return 0
        ((10#${a[i]} < 10#${b[i]})) && return 1
    done

    return 0
}

# Retry a command up to 3 times with 5s delay
retry() {
    local max_attempts=3
    local delay=5
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if "$@"; then
            return 0
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            warning "Attempt $attempt failed. Retrying in ${delay}s..."
            sleep $delay
        fi
        attempt=$((attempt + 1))
    done

    warning "Command failed after $max_attempts attempts: $*"
    return 1
}

# A free backup path for this run. Files that share a basename (the git.lua of
# each Neovim config) get a numeric suffix instead of overwriting each other.
backup_path() {
    local base="${BACKUP_DIR}/$(basename "$1").backup.${TIMESTAMP}" candidate n=1
    candidate="$base"
    while [[ -e "$candidate" ]]; do
        candidate="$base.$n"
        n=$((n + 1))
    done
    printf '%s\n' "$candidate"
}

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        mkdir -p "$BACKUP_DIR"
        local backup_name
        backup_name=$(backup_path "$file")
        cp "$file" "$backup_name"
        success "Backed up $file to $backup_name"
    fi
}

# Install stdin as a generated file with the given mode. Unchanged content is
# left alone (no rewrite, no new backup), so reruns converge; changed content
# is backed up first and replaced by rename. Symlinked targets are written
# through, keeping dotfile-manager links intact.
deploy_file() {
    local target="$1" mode="$2" temp
    mkdir -p "$(dirname "$target")" || return 1
    temp=$(mktemp "$(dirname "$target")/.$(basename "$target").XXXXXX") || return 1
    if ! cat > "$temp"; then
        rm -f "$temp"
        return 1
    fi
    if [[ -f "$target" ]] && cmp -s "$temp" "$target"; then
        rm -f "$temp"
        chmod "$mode" "$target"
        return 0
    fi
    backup_file "$target"
    if [[ -L "$target" ]]; then
        cat "$temp" > "$target" && rm -f "$temp" && chmod "$mode" "$target"
    else
        chmod "$mode" "$temp" && mv -f "$temp" "$target"
    fi
}

# Files edited by external tools (ya, official Herdr installers): copy the file
# before the tool runs and keep that copy as a backup only if the tool changed it.
snapshot_file() {
    local snapshot
    [[ -f "$1" ]] || return 0
    snapshot=$(mktemp) || return 1
    cp -p "$1" "$snapshot" || { rm -f "$snapshot"; return 1; }
    printf '%s\n' "$snapshot"
}

keep_snapshot_if_changed() {
    local file="$1" snapshot="$2" backup_name
    [[ -n "$snapshot" ]] || return 0
    if cmp -s "$snapshot" "$file"; then
        rm -f "$snapshot"
        return 0
    fi
    mkdir -p "$BACKUP_DIR"
    backup_name=$(backup_path "$file")
    mv -f "$snapshot" "$backup_name"
    success "Backed up previous $file to $backup_name"
}

initialize_log() {
    # Rotate previous log if it exists
    if [[ -f "$SETUP_LOG" ]]; then
        mv "$SETUP_LOG" "${SETUP_LOG}.prev"
    fi

    cat > "$SETUP_LOG" << 'EOF'
================================================================================
SHELL-BACKUP: Installation Log
================================================================================
EOF
    log "Starting setup on $(date)"
}

################################################################################
# 3. PREREQUISITE CHECKS
################################################################################

check_prerequisites() {
    log "Checking prerequisites..."

    if ! command_exists curl; then
        error "curl is required for verified release downloads."
    fi
    success "curl available"

    if ! command_exists git; then
        if [[ "$PKG_MANAGER" == "apt" || "$PKG_MANAGER" == "brew" ]]; then
            warning "git not found. It will be installed during core tool setup."
            return 0
        fi
        error "git not found. Please install git."
    fi
    success "git available"
}

################################################################################
# 4. PACKAGE MANAGER SETUP
################################################################################

setup_package_manager() {
    log "Setting up package manager..."

    if [[ "$PKG_MANAGER" == "brew" ]]; then
        export PATH="/opt/homebrew/bin:$PATH"

        if ! command_exists brew; then
            log "Installing Homebrew..."
            if [[ "$NON_INTERACTIVE" == true ]]; then
                NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            else
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            success "Homebrew installed"
        else
            success "Homebrew already available"
        fi

        log "Updating Homebrew metadata..."
        if brew update; then
            success "Homebrew metadata updated"
        else
            warning "Homebrew metadata update failed; continuing with existing metadata"
        fi
    elif [[ "$PKG_MANAGER" == "apt" ]]; then
        log "Running apt update..."
        if run_with_sudo "apt update" apt-get update -qq; then
            success "apt ready"
        else
            warning "Continuing without refreshing apt metadata"
        fi
    fi
}

# mosh-server and multi-byte glyphs need a UTF-8 locale. C.UTF-8 always
# exists on current Debian/Ubuntu; en_US.UTF-8 matches what clients usually
# forward. Failure only warns: ~/.zshenv falls back to C.UTF-8.
ensure_utf8_locale() {
    [[ "$PKG_MANAGER" == apt ]] || return 0
    utf8_locale_available en_US.UTF-8 && { success 'en_US.UTF-8 locale available'; return 0; }
    if ! command_exists locale-gen; then
        warning 'locale-gen unavailable; shells fall back to C.UTF-8'
        return 3
    fi
    # Debian reads /etc/locale.gen; Ubuntu also accepts the argument.
    if ! run_with_sudo 'en_US.UTF-8 locale' sh -c \
        "grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen 2>/dev/null || echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen" || \
       ! run_with_sudo 'en_US.UTF-8 locale generation' locale-gen en_US.UTF-8; then
        warning 'Could not generate en_US.UTF-8; shells fall back to C.UTF-8'
        return 3
    fi
    utf8_locale_available en_US.UTF-8 || return 3
    success 'en_US.UTF-8 locale generated'
}

utf8_locale_available() {
    local wanted
    wanted=$(printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -d '-')
    locale -a 2>/dev/null | tr 'A-Z' 'a-z' | tr -d '-' | grep -qx "$wanted"
}

################################################################################
# 5. CORE TOOL INSTALLATION
################################################################################

install_core_tools() {
    log "Installing core tools..."

    if [[ "$OS_TYPE" == "darwin" ]]; then
        # macOS via Homebrew
        # Format: "package_name:command_name" - if no colon, command_name = package_name
        local tools=("git" "zsh" "fzf" "zoxide" "ripgrep:rg" "fd:fd" "python:python3" "mosh:mosh-server")
        local package_name command_name
        for tool_mapping in "${tools[@]}"; do
            if [[ "$tool_mapping" == *":"* ]]; then
                package_name="${tool_mapping%%:*}"
                command_name="${tool_mapping##*:}"
            else
                package_name="$tool_mapping"
                command_name="$tool_mapping"
            fi

            brew_install_or_upgrade "$package_name" "$command_name"
        done
    else
        # Ubuntu/Debian via apt
        local base_packages=(zsh git curl ca-certificates file unzip tar xz-utils build-essential fontconfig python3 locales)
        # mosh: server side for TermRover/Termux/any Mosh client. ncurses-term:
        # terminfo for client TERMs. Noto: Unicode symbols/emoji fallbacks.
        # python3-venv: Mason installs Python tools (ruff) in a virtualenv.
        local extra_packages=(fzf zoxide ripgrep fd-find wl-clipboard xclip command-not-found
            mosh ncurses-term fonts-noto-core fonts-noto-color-emoji fonts-symbola python3-venv)
        local available_extra_packages=()
        local base_tools_missing=false
        local extra_tools_missing=false
        local package

        if ! command_exists zsh || ! command_exists git || ! command_exists curl || \
           ! command_exists file || ! command_exists xz || \
           ! command_exists unzip || ! command_exists cc || ! command_exists make || ! command_exists fc-cache; then
            base_tools_missing=true
        fi

        if ! command_exists fzf || ! command_exists zoxide || ! command_exists rg || \
           { ! command_exists fd && ! command_exists fdfind; }; then
            extra_tools_missing=true
        fi

        log "Installing/updating base tools via apt..."
        if ! run_with_sudo "base apt package installation/update" apt-get install -y -qq "${base_packages[@]}"; then
            if [[ "$base_tools_missing" == true ]]; then
                error "Required packages are missing and could not be installed without interactive sudo."
            else
                warning "Base apt packages are installed, but updates were skipped."
            fi
        else
            success "Base apt packages installed/updated"
        fi

        for package in "${extra_packages[@]}"; do
            if apt-cache show "$package" &>/dev/null; then
                available_extra_packages+=("$package")
            else
                warning "Optional apt package '$package' is not available from configured repositories"
            fi
        done

        if [[ ${#available_extra_packages[@]} -eq 0 ]]; then
            warning "No optional apt packages are available from configured repositories"
        else
            log "Installing/updating additional tools via apt..."
            if ! run_with_sudo "additional apt package installation/update" apt-get install -y -qq "${available_extra_packages[@]}"; then
                if [[ "$extra_tools_missing" == true ]]; then
                    warning "Optional apt packages were not installed. Re-run with interactive sudo if any are missing."
                else
                    warning "Optional apt packages are installed, but updates were skipped."
                fi
            else
                success "Additional apt packages installed/updated"
            fi
        fi

        # Create fd symlink (fd-find package installs as fdfind)
        if command_exists fdfind && ! command_exists fd; then
            ensure_user_local_bin_on_path
            ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
            success "Created fd symlink (fdfind -> ~/.local/bin/fd)"
        fi
    fi

    if [[ "$OS_TYPE" == linux ]]; then
        install_release_tool fzf 0.74.3 || return 1
        install_release_tool zoxide 0.10.0 || return 1
        install_release_tool rg 15.2.0 || return 1
        install_release_tool fd 10.5.0 || return 1
    fi
    require_version zsh "$MIN_ZSH_VERSION" || return 1
    success "Core tools installed"
}

install_pnpm() {
    if [[ "$OS_TYPE" == darwin ]]; then
        brew_install_or_upgrade pnpm pnpm || return 1
    else
        install_release_tool pnpm "$PNPM_VERSION" || return 1
    fi
    require_version pnpm "$PNPM_VERSION"
}

install_starship() {
    if [[ "$OS_TYPE" == darwin ]]; then
        brew_install_or_upgrade starship starship || return 1
    else
        install_release_tool starship "$STARSHIP_VERSION" || return 1
    fi
    require_version starship "$STARSHIP_VERSION"
}

install_yazi() {
    if [[ "$OS_TYPE" == darwin ]]; then
        brew_install_or_upgrade yazi yazi || return 1
    else
        install_release_tool yazi "$YAZI_VERSION" || return 1
    fi
    require_version yazi "$MIN_YAZI_VERSION" || return 1
    require_version ya "$MIN_YAZI_VERSION" || return 1
    [[ "$(tool_version yazi)" == "$(tool_version ya)" ]] || {
        warning 'Yazi and ya versions differ; plugin setup blocked'
        return 1
    }
}

# Linux: the official tree goes to ~/.local/opt/nvim-<version>, with
# ~/.local/opt/nvim and ~/.local/bin/nvim as symlinks. Older trees are kept,
# so a rollback is relinking ~/.local/opt/nvim.
install_neovim() {
    if [[ "$OS_TYPE" == darwin ]]; then
        brew_install_or_upgrade neovim nvim || return 1
        require_version nvim "$NEOVIM_VERSION"
        return
    fi
    local before opt="$HOME/.local/opt" target asset url checksum
    target="$opt/nvim-$NEOVIM_VERSION"
    before=$(tool_version nvim)
    if [[ -n "$before" ]] && version_gte "$before" "$NEOVIM_VERSION"; then
        success "nvim retained ($before)"
        return 0
    fi
    # A verified tree that is only unlinked needs no download.
    if [[ "$(tool_version "$target/bin/nvim")" != "$NEOVIM_VERSION" ]]; then
        asset=$(release_asset nvim "$OS_TYPE" "$ARCH") || return 1
        IFS='|' read -r url checksum <<< "$asset"
        mkdir -p "$opt" || return 1
        (
            local temp_dir root
            temp_dir=$(mktemp -d "$opt/.nvim-setup.XXXXXX") || exit 1
            trap 'rm -rf "$temp_dir"' EXIT
            verified_download "$url" "$checksum" "$temp_dir/asset" 600 || exit 1
            mkdir "$temp_dir/extracted" || exit 1
            tar -xzf "$temp_dir/asset" -C "$temp_dir/extracted" || exit 1
            root=$(find "$temp_dir/extracted" -mindepth 1 -maxdepth 1 -type d -print -quit)
            [[ -n "$root" && -x "$root/bin/nvim" ]] || exit 1
            require_version "$root/bin/nvim" "$NEOVIM_VERSION" || exit 1
            rm -rf "$target" || exit 1
            mv "$root" "$target" || exit 1
        ) || return 1
    fi
    mkdir -p "$HOME/.local/bin" || return 1
    # `ln -sfn` into a real directory would create the link inside it: a manual
    # unpack at ~/.local/opt/nvim is moved into the backup directory first, and
    # a real ~/.local/bin/nvim is backed up before the link replaces it.
    if [[ -e "$opt/nvim" && ! -L "$opt/nvim" ]]; then
        local aside
        mkdir -p "$BACKUP_DIR" || return 1
        aside=$(backup_path "$opt/nvim")
        mv "$opt/nvim" "$aside" || return 1
        warning "Moved the unmanaged $opt/nvim to $aside"
    fi
    if [[ -e "$HOME/.local/bin/nvim" && ! -L "$HOME/.local/bin/nvim" ]]; then
        backup_file "$HOME/.local/bin/nvim"
    fi
    ln -sfn "$target" "$opt/nvim" || return 1
    ln -sfn "$opt/nvim/bin/nvim" "$HOME/.local/bin/nvim" || return 1
    hash -r
    log "nvim ${before:-absent} -> $(tool_version nvim) (target $NEOVIM_VERSION)"
    require_version nvim "$NEOVIM_VERSION"
}

# lazygit (Git UI inside Neovim) and the tree-sitter CLI, which the
# nvim-treesitter main branch needs to build parsers.
install_neovim_tools() {
    if [[ "$OS_TYPE" == darwin ]]; then
        brew_install_or_upgrade lazygit lazygit || return 1
        brew_install_or_upgrade tree-sitter-cli tree-sitter || return 1
    else
        install_release_tool lazygit "$LAZYGIT_VERSION" || return 1
        install_release_tool tree-sitter "$TREE_SITTER_VERSION" || return 1
    fi
    require_version lazygit "$LAZYGIT_VERSION" || return 1
    require_version tree-sitter "$TREE_SITTER_VERSION"
}

find_ghostty_app() {
    local app
    for app in /Applications/Ghostty.app "$HOME/Applications/Ghostty.app"; do
        if [[ -x "$app/Contents/MacOS/ghostty" ]]; then
            printf '%s\n' "$app"
            return 0
        fi
    done
    return 1
}

# The Ghostty this setup manages: the app bundle on macOS; on Linux the Snap
# when present, otherwise whichever ghostty is on PATH (apt, a local build).
ghostty_bin() {
    if [[ "$OS_TYPE" == darwin ]]; then
        printf '%s\n' "$(find_ghostty_app || printf '/missing-ghostty')/Contents/MacOS/ghostty"
    elif [[ -x "$GHOSTTY_SNAP_BIN" ]]; then
        printf '%s\n' "$GHOSTTY_SNAP_BIN"
    else
        command -v ghostty 2>/dev/null || printf '%s\n' /missing-ghostty
    fi
}

# Where the classic Snap puts its command (tests point this at a mock).
GHOSTTY_SNAP_BIN="${GHOSTTY_SNAP_BIN:-/snap/bin/ghostty}"

# snapd is reachable (installed and its daemon answering), which WSL without
# systemd and containers lack even after `apt-get install snapd`.
snapd_available() {
    command_exists snap && snap version 2>/dev/null | grep -qE '^snapd +[0-9]'
}

# The version apt would install, without the Debian revision.
apt_candidate_version() {
    apt-cache policy "$1" 2>/dev/null | sed -nE 's/^ *Candidate: *([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/p' | head -1
}

# Linux: a Ghostty that meets the target (Snap, apt or a local build) is kept.
# Otherwise the classic Snap, which tracks the latest stable release and
# refreshes itself; where snapd cannot run, apt when its candidate meets the
# target. An apt package is removed once a Snap verifies, because /usr/bin
# precedes /snap/bin in PATH and Ubuntu's package lags behind.
# macOS: the Homebrew cask; a Ghostty.app from the DMG keeps its own updater.
install_ghostty() {
    local before candidate
    before=$(tool_version "$(ghostty_bin)")
    if [[ -n "$before" ]] && version_gte "$before" "$GHOSTTY_VERSION"; then
        success "Ghostty retained ($before)"
    elif [[ "$OS_TYPE" == darwin ]]; then
        if brew list --cask ghostty >/dev/null 2>&1; then
            brew upgrade --cask ghostty || return 1
        elif find_ghostty_app >/dev/null; then
            warning 'Ghostty outside Homebrew is below target; update it using Ghostty > Check for Updates'
            return 1
        else
            brew install --cask ghostty || return 1
        fi
    else
        if ! command_exists snap; then
            run_with_sudo 'snapd prerequisite for Ghostty' apt-get install -y snapd || true
        fi
        if snapd_available; then
            if snap list ghostty >/dev/null 2>&1; then
                run_with_sudo 'Ghostty stable update' snap refresh ghostty --channel=latest/stable || return 1
            else
                run_with_sudo 'Ghostty installation' snap install ghostty --classic --channel=latest/stable || return 1
            fi
        else
            candidate=$(apt_candidate_version ghostty)
            if [[ -n "$candidate" ]] && version_gte "$candidate" "$GHOSTTY_VERSION"; then
                warning "snapd is not available here; installing Ghostty $candidate from apt instead"
                run_with_sudo 'Ghostty apt installation' apt-get install -y ghostty || return 1
            else
                warning "Ghostty needs snapd (not available here) or an apt package at $GHOSTTY_VERSION or newer (candidate: ${candidate:-none})"
                return 1
            fi
        fi
    fi
    require_version "$(ghostty_bin)" "$GHOSTTY_VERSION" || return 1
    if [[ "$OS_TYPE" == linux && "$(ghostty_bin)" == "$GHOSTTY_SNAP_BIN" &&
        "$(dpkg-query -W -f='${Status}' ghostty 2>/dev/null || true)" == 'install ok installed' ]]; then
        run_with_sudo 'removal of the apt Ghostty package' apt-get remove -y ghostty || return 1
        success 'Removed the apt Ghostty package; the Snap is the only Ghostty'
    fi
}

find_cmux() {
    local app
    for app in /Applications/cmux.app "$HOME/Applications/cmux.app"; do
        if [[ -x "$app/Contents/Resources/bin/cmux" ]]; then
            printf '%s\n' "$app"
            return 0
        fi
    done
    return 1
}

# cmux is an optional macOS extra next to Ghostty: requested with --with-cmux,
# and kept up to date once installed.
cmux_wanted() {
    [[ "$OS_TYPE" == darwin ]] && { [[ "$WITH_CMUX" == true ]] || find_cmux >/dev/null; }
}

install_cmux() {
    local app before="" system_version
    system_version=$(sw_vers -productVersion)
    if ! version_gte "$system_version" 14.0; then
        warning "cmux requires macOS 14+; profile blocked on $system_version"
        return 1
    fi
    app=$(find_cmux || true)
    if [[ -n "$app" ]]; then
        before=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null || true)
    fi
    if [[ -z "$before" ]] || ! version_gte "$before" "$CMUX_VERSION"; then
        brew tap manaflow-ai/cmux || return 1
        if brew list --cask cmux >/dev/null 2>&1; then
            brew upgrade --cask cmux || return 1
        elif [[ -n "$app" ]]; then
            warning 'cmux outside Homebrew is below target; update it using cmux > Check for Updates'
            return 1
        else
            brew install --cask cmux || return 1
        fi
    fi
    app=$(find_cmux) || return 1
    local after
    after=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist") || return 1
    version_gte "$after" "$CMUX_VERSION" || return 1
    "$app/Contents/Resources/bin/cmux" --version || return 1
    success "cmux ${before:-absent} -> $after"
}

################################################################################
# 6. FONT INSTALLATION
################################################################################

install_fonts() {
    local id failed=0 conf_before
    FONTS_CHANGED=false
    # Both terminal fonts are installed so switching needs no download.
    for id in $FONT_IDS; do
        install_font_archive "$id" || failed=1
    done

    if [[ "$OS_TYPE" == linux ]]; then
        conf_before=$(cksum < "$FONTCONFIG_FILE" 2>/dev/null || true)
        deploy_fontconfig || failed=1
        [[ "$(cksum < "$FONTCONFIG_FILE" 2>/dev/null || true)" == "$conf_before" ]] || FONTS_CHANGED=true
        # Refresh only after a change, or to repair a cache missing the font.
        if command_exists fc-cache && { [[ "$FONTS_CHANGED" == true ]] ||
            ! command_exists fc-list || [[ -z "$(fc-list "$(font_family)" family 2>/dev/null)" ]]; }; then
            log "Refreshing font cache..."
            fc-cache -f "$HOME/.local/share/fonts" &>/dev/null || true
        fi
        report_glyph_coverage
    fi
    [[ "$failed" == 0 ]]
}

# Fallback order for fontconfig applications (other terminals, editors):
# the chosen font, Nerd icons, then Unicode symbols and emoji.
deploy_fontconfig() {
    local family managed
    family=$(font_family)
    {
        cat << FONTCONFIG_EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<!-- Managed by shell-backup setup.sh; put local rules in another conf.d file. -->
<fontconfig>
  <alias>
    <family>monospace</family>
    <prefer>
      <family>${family}</family>
      <family>Symbols Nerd Font Mono</family>
      <family>Noto Sans Symbols2</family>
      <family>Noto Color Emoji</family>
    </prefer>
  </alias>
FONTCONFIG_EOF
        # accept appends after the requested family, so its own glyphs win.
        for managed in 'Iosevka Term SS05' 'JetBrainsMono Nerd Font'; do
            cat << FONTCONFIG_FAMILY_EOF
  <alias>
    <family>${managed}</family>
    <accept>
      <family>Symbols Nerd Font Mono</family>
      <family>Noto Sans Symbols2</family>
      <family>Noto Color Emoji</family>
    </accept>
  </alias>
FONTCONFIG_FAMILY_EOF
        done
        printf '%s\n' '</fontconfig>'
    } | deploy_file "$FONTCONFIG_FILE" 644
    success "Font fallback configuration deployed ($FONTCONFIG_FILE)"
}

# The managed plugin list lives in the deployed ~/.zsh/zinit-update.zsh.
zinit_expected_assets() {
    local helper="$HOME/.zsh/zinit-update.zsh" plugin
    [[ -r "$helper" ]] && command_exists zsh || return 0
    while IFS= read -r plugin; do
        printf 'zinit plugin %s|%s\n' "${plugin#*/}" "$HOME/.local/share/zinit/plugins/${plugin//\//---}"
    done < <(zsh -fc 'source "$1" && print -rl -- $shell_backup_zinit_plugins' zsh "$helper")
}

verify_zinit_assets() {
    local name path missing=0

    if [[ ! -r "$HOME/.zsh/zinit-update.zsh" ]]; then
        warning "Zinit plugin list missing at $HOME/.zsh/zinit-update.zsh"
        return 1
    fi

    while IFS='|' read -r name path; do
        [[ -n "$name" ]] || continue
        if [[ ! -e "$path" ]]; then
            warning "$name missing at $path"
            missing=$((missing + 1))
        fi
    done < <(zinit_expected_assets)

    [[ $missing -eq 0 ]]
}

yazi_expected_assets() {
    printf '%s|%s\n' \
        "Yazi git plugin" "$HOME/.config/yazi/plugins/git.yazi/main.lua" \
        "Yazi starship plugin" "$HOME/.config/yazi/plugins/starship.yazi/main.lua"
}

verify_yazi_assets() {
    local name path missing=0

    while IFS='|' read -r name path; do
        [[ -n "$name" ]] || continue
        if [[ ! -e "$path" ]]; then
            warning "$name missing at $path"
            missing=$((missing + 1))
        fi
    done < <(yazi_expected_assets)

    [[ $missing -eq 0 ]]
}

################################################################################
# 7. SHELL CONFIGURATION
################################################################################

deploy_zshenv() {
    log "Deploying .zshenv configuration..."

    deploy_file "$HOME/.zshenv" 600 << 'ZSHENV_EOF'
# ============================================================================
# ZSH Environment Configuration
# ============================================================================
# Keep this file lightweight: it is loaded by every zsh invocation, including
# non-interactive shells used by automation and helper scripts.

# SSH and Mosh clients may forward a locale this host lacks, which silently
# falls back to C: icons and box drawing break and mosh-server refuses to
# start. Only interactive and SSH shells are adjusted (scripts may set
# LC_ALL=C on purpose); ~/.env is loaded afterwards and still wins.
shell_backup_utf8_locale() {
    emulate -L zsh
    [[ -o interactive || -n "${SSH_CONNECTION:-}" ]] || return 0
    local current="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" var candidate
    [[ -z "${SSH_CONNECTION:-}" && "${(L)current}" == *utf(-|)8* ]] && return 0
    local -a known
    known=(${(f)"$(locale -a 2>/dev/null)"})
    (( ${#known} )) || return 0
    known=(${${(L)known}//-/})
    for var in LC_ALL LC_CTYPE; do
        [[ -n "${(P)var:-}" ]] || continue
        (( ${known[(Ie)${${(L)${(P)var}}//-/}]} )) || unset "$var"
    done
    current="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    if [[ "${(L)current}" == *utf(-|)8* ]] && (( ${known[(Ie)${${(L)current}//-/}]} )); then
        return 0
    fi
    # A valid non-UTF-8 LC_ALL/LC_CTYPE was chosen explicitly; keep it.
    [[ -z "${LC_ALL:-}${LC_CTYPE:-}" ]] || return 0
    for candidate in en_US.UTF-8 C.UTF-8; do
        if (( ${known[(Ie)${${(L)candidate}//-/}]} )); then
            export LANG="$candidate"
            return 0
        fi
    done
}

shell_backup_utf8_locale
unfunction shell_backup_utf8_locale

load_env_files() {
    local line

    # Load only ~/.env so startup stays predictable and lightweight.
    if [[ -f "$HOME/.env" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$line" ]] && continue
            [[ "$line" =~ ^[a-zA-Z_][a-zA-Z0-9_]*= ]] || continue
            export "$line" 2>/dev/null || true
        done < "$HOME/.env"
    fi
}

load_env_files

ensure_path_entry() {
    local path_entry="$1"

    [[ -d "$path_entry" ]] || return 0
    case ":${PATH:-}:" in
        *":$path_entry:"*) ;;
        *) PATH="${PATH:+$PATH:}$path_entry" ;;
    esac
}

# ~/.env may define PATH. Keep user-provided entries, but always restore the
# system paths required by zsh startup and command-not-found handlers.
for path_entry in \
    "$HOME/.local/bin" \
    /opt/homebrew/bin \
    /opt/homebrew/sbin \
    /usr/local/bin \
    /usr/local/sbin \
    /usr/bin \
    /bin \
    /usr/sbin \
    /sbin
do
    ensure_path_entry "$path_entry"
done
export PATH
unset path_entry
unfunction ensure_path_entry 2>/dev/null || true

# Derive npm's global root from its location instead of running `npm root -g`,
# which starts Node on every zsh invocation (<prefix>/bin/npm ->
# <prefix>/lib/node_modules for NVM and Homebrew).
if (( $+commands[npm] )); then
    node_global_root="${commands[npm]:h:h}/lib/node_modules"
    if [[ -d "$node_global_root" && ":${NODE_PATH:-}:" != *":$node_global_root:"* ]]; then
        export NODE_PATH="${NODE_PATH:+$NODE_PATH:}$node_global_root"
    fi
    unset node_global_root
fi

ZSHENV_EOF
    success ".zshenv deployed"
}

deploy_zinit_updater() {
    deploy_file "$HOME/.zsh/zinit-update.zsh" 600 << 'ZINIT_UPDATE_EOF'
# Zinit plugins managed by shell-backup; updates touch only these.
# Keep every entry a Git plugin: `git pull --ff-only` leaves installed files
# intact on failure, while Zinit's URL-snippet updater deletes the snippet.
shell_backup_zinit_plugins=(
    zsh-users/zsh-completions
    zsh-users/zsh-autosuggestions
    zsh-users/zsh-syntax-highlighting
    zsh-users/zsh-history-substring-search
    ohmyzsh/ohmyzsh
    ntnyq/omz-plugin-pnpm
    ntnyq/omz-plugin-bun
    MichaelAquilina/zsh-you-should-use
)

shell_backup_update_zinit() {
    emulate -L zsh
    local plugin dir head failed=0
    zinit self-update -q || return 1
    for plugin in $shell_backup_zinit_plugins; do
        dir="${ZINIT[PLUGINS_DIR]}/${plugin//\//---}"
        # `zinit update` succeeds even when its fetch fails; fetch first so
        # network and remote errors are reported.
        if ! command git -C "$dir" fetch --quiet origin; then
            failed=1
            continue
        fi
        # Already at upstream: `zinit update` would only rewrite its metadata.
        head=$(command git -C "$dir" rev-parse HEAD 2>/dev/null)
        [[ -n "$head" && "$head" == "$(command git -C "$dir" rev-parse '@{u}' 2>/dev/null)" ]] && continue
        zinit update -q "$plugin" || failed=1
    done
    return "$failed"
}
ZINIT_UPDATE_EOF
}

deploy_zshrc() {
    log "Deploying .zshrc configuration..."

    deploy_zinit_updater

    # Set platform-specific paths
    local pnpm_home

    if [[ "$OS_TYPE" == "darwin" ]]; then
        pnpm_home="${HOME}/Library/pnpm"
    else
        pnpm_home="${HOME}/.local/share/pnpm"
    fi

    # PNPM_HOME_PLACEHOLDER is filled in before comparing with the deployed file.
    sed "s|PNPM_HOME_PLACEHOLDER|$pnpm_home|g" << 'ZSHRC_EOF' | deploy_file "$HOME/.zshrc" 600
# ============================================================================
# ZSH Configuration with Zinit Plugin Manager
# ============================================================================

# Keep PATH entries unique across nested shells and `exec zsh`.
typeset -U path PATH

# The UTF-8 locale fallback for SSH/Mosh lives in ~/.zshenv, so it also applies
# to the non-interactive shell that starts mosh-server.

# SSH clients may announce a TERM without terminfo on this host (for example
# xterm-ghostty from an older Ghostty); fall back to a universal entry.
if [[ -n "${SSH_CONNECTION:-}" ]] && (( $+commands[infocmp] )) && ! infocmp -- "$TERM" >/dev/null 2>&1; then
    export TERM=xterm-256color
fi

# ============================================================================
# Command Paths (before plugins, which check for these commands)
# ============================================================================

# pnpm
export PNPM_HOME="PNPM_HOME_PLACEHOLDER"
path=("$PNPM_HOME" $path)

# bun
export BUN_INSTALL="$HOME/.bun"
[[ -d "$BUN_INSTALL/bin" ]] && path=("$BUN_INSTALL/bin" $path)

# User-local binaries (Yazi and Herdr on Linux, Claude Code, etc.)
path=("$HOME/.local/bin" $path)

# ============================================================================
# Zinit Initialization
# ============================================================================

if [[ ! -f $HOME/.local/share/zinit/zinit.git/zinit.zsh ]]; then
    print -P "%F{33} %F{220}Installing %F{33}ZDHARMA-CONTINUUM%F{220} Initiative Plugin Manager (%F{33}zdharma-continuum/zinit%F{220})…%f"
    command mkdir -p "$HOME/.local/share/zinit" && command chmod g-rwX "$HOME/.local/share/zinit"
    command git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git" && \
        print -P "%F{33} %F{34}Installation successful.%f%b" || \
        print -P "%F{160} The clone has failed.%f%b"
fi

source "$HOME/.local/share/zinit/zinit.git/zinit.zsh"
autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit
export ZSH_CACHE_DIR="${ZSH_CACHE_DIR:-$HOME/.cache/zsh}"
mkdir -p "$ZSH_CACHE_DIR/completions" 2>/dev/null || true

# ============================================================================
# Completion System
# ============================================================================

# Extra completion definitions; blockf lets Zinit manage fpath itself.
zinit ice blockf
zinit light zsh-users/zsh-completions

# Cached compinit: full check (new functions, insecure directories) at most
# once a day; otherwise reuse the dump.
autoload -Uz compinit
() {
    setopt localoptions extendedglob
    local dump="$ZSH_CACHE_DIR/zcompdump-$ZSH_VERSION"
    if [[ -n $dump(#qN.mh-24) ]]; then
        compinit -C -d "$dump"
    else
        compinit -i -d "$dump"
        command touch "$dump" 2>/dev/null
    fi
}
zinit cdreplay -q

# ============================================================================
# Node (NVM)
# ============================================================================

export NVM_DIR="$HOME/.nvm"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    # --no-use skips nvm's slow startup resolution. Follow the default alias
    # (for example default -> lts/* -> lts/krypton -> v24.x) and put that
    # installed version on PATH; `nvm use` keeps working as usual.
    \. "$NVM_DIR/nvm.sh" --no-use
    () {
        local target="default" hops
        local -a versions
        for hops in 1 2 3 4 5; do
            [[ -r "$NVM_DIR/alias/$target" ]] || break
            target=$(<"$NVM_DIR/alias/$target")
        done
        if [[ "$target" == (v|)[0-9]* ]]; then
            versions=("$NVM_DIR"/versions/node/v${target#v}(|.*)(N/nOn))
        fi
        if (( ${#versions} )); then
            path=("${versions[1]}/bin" $path)
            export NVM_BIN="${versions[1]}/bin"
        else
            nvm use default --silent >/dev/null 2>&1 || true
        fi
    }
fi
# nvm's completion runs compinit only when it is not defined yet.
[[ -s "$NVM_DIR/bash_completion" ]] && \. "$NVM_DIR/bash_completion"

# bun completions
[[ -s "$HOME/.bun/_bun" ]] && source "$HOME/.bun/_bun"

# ============================================================================
# Core Plugins (loaded immediately for essential functionality)
# ============================================================================

# Autosuggestions - show command completions based on history
zinit light zsh-users/zsh-autosuggestions

# Syntax highlighting - highlight commands as you type
zinit light zsh-users/zsh-syntax-highlighting

# FZF - use the package-managed binary and shell integration
load_fzf_integration() {
    command -v fzf >/dev/null 2>&1 || return 0

    if fzf --zsh >/dev/null 2>&1; then
        source <(fzf --zsh)
        return 0
    fi

    local fzf_script

    for fzf_script in \
        "${FZF_BASE:-}/shell/completion.zsh" \
        /usr/share/fzf/completion.zsh \
        /usr/share/doc/fzf/examples/completion.zsh \
        /opt/homebrew/opt/fzf/shell/completion.zsh \
        /usr/local/opt/fzf/shell/completion.zsh
    do
        [[ -f "$fzf_script" ]] || continue
        source "$fzf_script"
        break
    done

    for fzf_script in \
        "${FZF_BASE:-}/shell/key-bindings.zsh" \
        /usr/share/fzf/key-bindings.zsh \
        /usr/share/doc/fzf/examples/key-bindings.zsh \
        /opt/homebrew/opt/fzf/shell/key-bindings.zsh \
        /usr/local/opt/fzf/shell/key-bindings.zsh
    do
        [[ -f "$fzf_script" ]] || continue
        source "$fzf_script"
        break
    done
}

load_fzf_integration

# Node.js helper - keep the useful node docs command without relying on the
# unstable OMZP::node snippet update path.
node-docs() {
    local section=${1:-all}

    if ! command -v node >/dev/null 2>&1; then
        echo "node is not installed" >&2
        return 1
    fi

    local url="https://nodejs.org/docs/$(node --version)/api/${section}.html"

    if command -v open >/dev/null 2>&1; then
        open "$url"
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url" >/dev/null 2>&1
    else
        printf '%s\n' "$url"
    fi
}

# Command not found helper - suggests packages for missing commands.
# macOS uses the OMZ command-not-found plugin loaded below.
if [[ "$(uname -s)" != "Darwin" && -f /usr/lib/command-not-found ]]; then
    command_not_found_handler() {
        /usr/lib/command-not-found -- "$1" || return 127
    }
fi

# ============================================================================
# Optional/Secondary Plugins (turbo mode for faster startup)
# ============================================================================

# Load immediately (not async) so that keybindings work correctly
zinit light zsh-users/zsh-history-substring-search

# History settings (local to each terminal session)
mkdir -p "$HOME/.cache/zsh" 2>/dev/null || true
zsh_history_tty="${TTY:-session-$$}"
zsh_history_tty="${zsh_history_tty#/dev/}"
zsh_history_tty="${zsh_history_tty//\//_}"
export HISTFILE="$HOME/.cache/zsh/history-${zsh_history_tty}"
unset zsh_history_tty
export HISTSIZE=100000
export SAVEHIST=100000
unsetopt SHARE_HISTORY
unsetopt INC_APPEND_HISTORY
unsetopt INC_APPEND_HISTORY_TIME
setopt APPEND_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS

# Bind up/down arrows to history substring search (search history based on typed prefix)
# Use both standard and application cursor escape sequences across common keymaps.
for keymap in emacs viins vicmd; do
    bindkey -M "$keymap" '^[[A' history-substring-search-up
    bindkey -M "$keymap" '^[[B' history-substring-search-down
    bindkey -M "$keymap" '^[OA' history-substring-search-up
    bindkey -M "$keymap" '^[OB' history-substring-search-down
done

# Optional OMZ plugins from a shallow clone of the official repository.
# `wait` keeps startup fast, `silent` suppresses normal output, and `notify""`
# only surfaces a message if a plugin fails to load. `pick"/dev/null"` skips the
# OMZ framework and `nocompletions` skips completions for unused plugins.
omz_plugin_files="plugins/git/git.plugin.zsh plugins/alias-finder/alias-finder.plugin.zsh"
(( $+commands[bun] )) && omz_plugin_files+=" plugins/bun/bun.plugin.zsh"
if [[ "$(uname -s)" == "Darwin" ]]; then
    omz_plugin_files+=" plugins/command-not-found/command-not-found.plugin.zsh"
fi
zinit ice wait lucid silent notify"" depth"1" pick"/dev/null" nocompletions multisrc"$omz_plugin_files"
zinit light ohmyzsh/ohmyzsh
unset omz_plugin_files

# pnpm/bun aliases and completions load only when the command exists.
zinit ice wait lucid silent notify"" light-mode has"pnpm"
zinit light ntnyq/omz-plugin-pnpm
zinit ice wait lucid silent notify"" light-mode has"bun"
zinit light ntnyq/omz-plugin-bun

# You Should Use - reminds you of existing aliases
zinit ice wait lucid silent notify"" light-mode
zinit light MichaelAquilina/zsh-you-should-use

# ============================================================================
# User Configuration
# ============================================================================

# Git uses ~/.ssh/config and the SSH agent (including keys forwarded from
# other devices); ssh already tries ~/.ssh/id_ed25519 by default.

# Custom git function - fuzzy switch branch
[[ -f ~/.zsh/gswf.zsh ]] && source ~/.zsh/gswf.zsh

# Yazi launcher - keep shell in the directory where Yazi exits
[[ -f ~/.zsh/y.zsh ]] && source ~/.zsh/y.zsh

# Neovim launchers (lv, kv, nvims) and the NVIM_CONFIG default used by vi
[[ -f ~/.zsh/nvim.zsh ]] && source ~/.zsh/nvim.zsh

# Load aliases file
[[ -f ~/.zsh_aliases ]] && source ~/.zsh_aliases

# ============================================================================
# Prompt and Command Navigation
# ============================================================================

# Zoxide - smarter cd command
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init zsh)"
fi

# Starship prompt - modern, fast prompt
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
fi

# ============================================================================
# Environment Variables
# ============================================================================

# Environment variables are loaded from ~/.zshenv (using only ~/.env) so they
# are available to both interactive shells and zsh-launched automation helpers.

# ============================================================================
# Auto-update Zinit plugins (once per day)
# ============================================================================

# Check for updates once per day using a timestamp file.
# The installer sets SHELL_BACKUP_SKIP_ZINIT_AUTO_UPDATE=1 to avoid racing a
# background update while it is still provisioning plugins. The updater is
# only sourced by the background job, keeping it out of shell startup.
if [[ -z "${SHELL_BACKUP_SKIP_ZINIT_AUTO_UPDATE:-}" && -r "$HOME/.zsh/zinit-update.zsh" ]] &&
    command -v zinit >/dev/null 2>&1; then
    zinit_update_dir="$HOME/.cache/shell-backup"
    zinit_update_stamp="$HOME/.zinit-last-update"
    zinit_update_lock="$zinit_update_dir/zinit-update.lock"
    zinit_update_log="$zinit_update_dir/zinit-update.log"
    zinit_update_failed="$zinit_update_dir/zinit-update.failed"
    update_interval=$((24 * 60 * 60)) # 24 hours in seconds
    lock_ttl=$((60 * 60)) # 1 hour; stale locks are removed
    current_time=$(date +%s)
    last_update=0

    shell_backup_mtime() {
        local target_path="$1"
        if [[ ! -e "$target_path" ]]; then
            print 0
            return 0
        fi

        if [[ "$(uname -s)" == "Darwin" ]]; then
            stat -f %m "$target_path" 2>/dev/null || print 0
        else
            stat -c %Y "$target_path" 2>/dev/null || print 0
        fi
    }

    mkdir -p "$zinit_update_dir" 2>/dev/null || true

    if [[ -f "$zinit_update_failed" ]]; then
        zinit_failed_at=""
        IFS= read -r zinit_failed_at < "$zinit_update_failed" 2>/dev/null || true
        print -P "%F{220}[shell-backup] Last Zinit auto-update failed${zinit_failed_at:+ at $zinit_failed_at}. See $zinit_update_log%f"
    fi

    if [[ -f "$zinit_update_stamp" ]]; then
        last_update=$(shell_backup_mtime "$zinit_update_stamp")
    fi

    # Touch the stamp before starting the background job so failed/offline
    # updates are throttled too. This prevents every new terminal from spawning
    # another updater when network or plugin hosts are unavailable.
    if (( current_time - last_update > update_interval )); then
        if [[ -d "$zinit_update_lock" ]]; then
            lock_time=$(shell_backup_mtime "$zinit_update_lock")
            if (( current_time - lock_time > lock_ttl )); then
                command rm -rf "$zinit_update_lock" 2>/dev/null || true
            fi
        fi

        if command mkdir "$zinit_update_lock" 2>/dev/null; then
            command touch "$zinit_update_stamp" 2>/dev/null || true
            (
                {
                    print "[$(date)] Starting Zinit update"
                    if source "$HOME/.zsh/zinit-update.zsh" && shell_backup_update_zinit; then
                        print "[$(date)] Zinit update completed"
                        command rm -f "$zinit_update_failed" 2>/dev/null || true
                    else
                        print "[$(date)] Zinit update failed"
                        date '+%Y-%m-%d %H:%M:%S' > "$zinit_update_failed" 2>/dev/null || true
                    fi
                } >> "$zinit_update_log" 2>&1
                command rmdir "$zinit_update_lock" 2>/dev/null || command rm -rf "$zinit_update_lock" 2>/dev/null || true
            ) &!
        fi
    fi

    unfunction shell_backup_mtime 2>/dev/null || true
    unset zinit_update_dir zinit_update_stamp zinit_update_lock zinit_update_log zinit_update_failed zinit_failed_at update_interval lock_ttl current_time last_update lock_time
fi

# Machine-local preferences survive setup reruns.
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

ZSHRC_EOF
    success ".zshrc deployed"
}

deploy_ghostty_config() {
    log "Deploying Ghostty configuration..."


    # Platform-specific fullscreen keybinding
    local fullscreen_keybind
    local platform_config
    local font_family_name font_size
    font_family_name=$(font_family)
    # Iosevka is narrower, so it gets a slightly larger size.
    case "$FONT_CHOICE" in
        jetbrains) font_size=13.5 ;;
        *) font_size=14 ;;
    esac
    if [[ "$OS_TYPE" == "darwin" ]]; then
        fullscreen_keybind="keybind = cmd+shift+f=toggle_fullscreen"
        platform_config=$'# macOS rendering, also read by cmux when installed.\nfont-thicken = true'
    else
        fullscreen_keybind="keybind = alt+shift+f=toggle_fullscreen"
        platform_config="# Linux: Ghostty state restore is macOS-only, so no window-save-state is set."
    fi

    deploy_file "$HOME/.config/ghostty/config" 644 << GHOSTTY_EOF
# Font configuration (setup.sh --font=iosevka|jetbrains). Later families are
# fallbacks; calt keeps programming ligatures on.
font-family = ${font_family_name}
font-family = Symbols Nerd Font Mono
font-size = ${font_size}
font-feature = +calt

${platform_config}
shell-integration = detect
# Install Ghostty's terminfo on SSH hosts and fall back to xterm-256color.
shell-integration-features = ssh-terminfo,ssh-env

# Fullscreen toggle (platform-specific)
${fullscreen_keybind}

# Fix new line for OpenCode
keybind = shift+enter=text:\x1b\r

# Remove padding
window-padding-x = 0
window-padding-y = 0

# Optional, machine-local overrides (never overwritten by setup).
config-file = ?config.local

GHOSTTY_EOF
    success "Ghostty configuration deployed"
}

################################################################################
# 8. YAZI CONFIGURATION
################################################################################

deploy_yazi_config() {
    log "Deploying Yazi configuration..."

    # Remove the previously generated keymap override so files keep Yazi's
    # native direct opener behavior. Directory editor selection is handled via
    # [open] rules below and existing default keybindings.
    if [[ -f "$HOME/.config/yazi/keymap.toml" ]] && grep -q 'Open selected/hovered with editor' "$HOME/.config/yazi/keymap.toml"; then
        backup_file "$HOME/.config/yazi/keymap.toml"
        rm -f "$HOME/.config/yazi/keymap.toml"
        success "Removed generated Yazi keymap override"
    fi

    deploy_file "$HOME/.config/yazi/init.lua" 644 << 'YAZI_INIT_EOF'
require("git"):setup {
    order = 1500,
}

require("starship"):setup()
YAZI_INIT_EOF

    local dev_openers=()
    if command_exists code; then
        dev_openers+=("    { run = \"code -r %s\", orphan = true, desc = \"VS Code\", for = \"unix\" },")
    fi
    if command_exists codium; then
        dev_openers+=("    { run = \"codium -r %s\", orphan = true, desc = \"VSCodium\", for = \"unix\" },")
    fi
    if command_exists cursor; then
        dev_openers+=("    { run = \"cursor -r %s\", orphan = true, desc = \"Cursor\", for = \"unix\" },")
    fi
    if command_exists zed; then
        dev_openers+=("    { run = \"zed %s\", orphan = true, desc = \"Zed\", for = \"unix\" },")
    fi

    if [[ ${#dev_openers[@]} -eq 0 ]]; then
        warning "No GUI editor CLI found for Yazi dev opener (checked: code, codium, cursor, zed)"
    fi

    {
        cat << 'YAZI_TOML_EOF'
[[plugin.prepend_fetchers]]
url = "*"
run = "git"
group = "git"

[[plugin.prepend_fetchers]]
url = "*/"
run = "git"
group = "git"

# Text, code and empty files open in Neovim through ~/.local/bin/vi, so the
# config named in NVIM_CONFIG is used (LazyVim by default). This replaces
# Yazi's ${EDITOR:-vi} opener, which every built-in edit rule refers to.
[opener]
edit = [
    { run = '"$HOME/.local/bin/vi" %s', block = true, desc = "Neovim (vi)", for = "unix" },
]
YAZI_TOML_EOF
        if [[ ${#dev_openers[@]} -gt 0 ]]; then
            printf 'dev_open = [\n'
            printf '%s\n' "${dev_openers[@]}"
            printf ']\n'
        fi
        printf '\n[open]\nprepend_rules = [\n'
        if [[ ${#dev_openers[@]} -gt 0 ]]; then
            printf '%s\n' '    { url = "*/", use = "dev_open" },'
        fi
        cat << 'YAZI_OPEN_RULES_EOF'
    # Code and config files whose MIME type is not text/*.
    { mime = "application/{toml,yaml,x-yaml,xml,x-sh,x-shellscript,sql,x-ndjson,x-subrip,*+json,*+xml}", use = [ "edit", "reveal" ] },
]
YAZI_OPEN_RULES_EOF
    } | deploy_file "$HOME/.config/yazi/yazi.toml" 644

    deploy_file "$HOME/.config/yazi/theme.toml" 644 << 'YAZI_THEME_EOF'
# Palette synced with starship.toml [palettes.old]

[mgr]
cwd = { fg = "#EDF2F4", bg = "#3F37C9", bold = true }
find_keyword = { fg = "#FF4089", bold = true }
find_position = { fg = "#177E89", italic = true }
symlink_target = { fg = "#177E89" }
marker_copied = { fg = "#417E38", bg = "#417E38" }
marker_cut = { fg = "#8B1D2C", bg = "#8B1D2C" }
marker_marked = { fg = "#FF4089", bg = "#FF4089" }
marker_selected = { fg = "#B02B10", bg = "#B02B10" }
count_copied = { fg = "#EDF2F4", bg = "#417E38" }
count_cut = { fg = "#EDF2F4", bg = "#8B1D2C" }
count_selected = { fg = "#EDF2F4", bg = "#B02B10" }
border_symbol = "│"
border_style = { fg = "#3D3D3D" }

[indicator]
parent = { fg = "#3D3D3D" }
current = { fg = "#3F37C9" }
preview = { fg = "#B02B10" }
padding = { open = "▐", close = "▌" }

[tabs]
active = { fg = "#EDF2F4", bg = "#3F37C9", bold = true }
inactive = { fg = "#EDF2F4", bg = "#3D3D3D" }
sep_inner = { open = "", close = "" }
sep_outer = { open = "", close = "" }

[mode]
normal_main = { fg = "#EDF2F4", bg = "#3F37C9", bold = true }
normal_alt = { fg = "#3F37C9", bg = "reset" }
select_main = { fg = "#EDF2F4", bg = "#B02B10", bold = true }
select_alt = { fg = "#B02B10", bg = "reset" }
unset_main = { fg = "#EDF2F4", bg = "#8B1D2C", bold = true }
unset_alt = { fg = "#8B1D2C", bg = "reset" }

[status]
overall = { fg = "#EDF2F4", bg = "reset" }
sep_left = { open = "", close = "" }
sep_right = { open = "", close = "" }
perm_type = { fg = "#EDF2F4", bg = "#3F37C9" }
perm_read = { fg = "#EDF2F4", bg = "#417E38" }
perm_write = { fg = "#EDF2F4", bg = "#B02B10" }
perm_exec = { fg = "#EDF2F4", bg = "#C33C00" }
perm_sep = { fg = "#3D3D3D" }
progress_label = { fg = "#EDF2F4", bold = true }
progress_normal = { fg = "#3F37C9", bg = "#3D3D3D" }
progress_error = { fg = "#8B1D2C", bg = "#3D3D3D" }

[which]
cols = 3
mask = { bg = "#3D3D3D" }
cand = { fg = "#3F37C9", bold = true }
rest = { fg = "#EDF2F4" }
desc = { fg = "#EDF2F4" }
separator = "    "
separator_style = { fg = "#3D3D3D" }

[confirm]
border = { fg = "#3F37C9" }
title = { fg = "#EDF2F4", bg = "#3F37C9", bold = true }
body = { fg = "#EDF2F4" }
list = { fg = "#EDF2F4" }
btn_yes = { fg = "#EDF2F4", bg = "#B02B10", bold = true }
btn_no = { fg = "#EDF2F4", bg = "#3D3D3D" }
btn_labels = [" Yes ", " No "]

[spot]
border = { fg = "#3F37C9" }
title = { fg = "#EDF2F4", bg = "#3F37C9", bold = true }
tbl_col = { fg = "#EDF2F4", bg = "#3F37C9" }
tbl_cell = { fg = "#EDF2F4", bg = "#3D3D3D" }

[notify]
title_info = { fg = "#EDF2F4", bg = "#3F37C9", bold = true }
title_warn = { fg = "#EDF2F4", bg = "#C33C00", bold = true }
title_error = { fg = "#EDF2F4", bg = "#8B1D2C", bold = true }

[pick]
border = { fg = "#3F37C9" }
active = { fg = "#EDF2F4", bg = "#3F37C9", bold = true }
inactive = { fg = "#EDF2F4" }

[input]
border = { fg = "#3F37C9" }
title = { fg = "#EDF2F4", bg = "#3F37C9", bold = true }
value = { fg = "#EDF2F4" }
selected = { fg = "#EDF2F4", bg = "#B02B10" }

[cmp]
border = { fg = "#3F37C9" }
active = { fg = "#EDF2F4", bg = "#3F37C9", bold = true }
inactive = { fg = "#EDF2F4" }
icon_file = "󰈔"
icon_folder = ""
icon_command = ""

[tasks]
border = { fg = "#3F37C9" }
title = { fg = "#EDF2F4", bg = "#3F37C9", bold = true }
hovered = { fg = "#EDF2F4", bg = "#3D3D3D" }

[help]
on = { fg = "#3F37C9", bold = true }
run = { fg = "#B02B10" }
desc = { fg = "#EDF2F4" }
hovered = { fg = "#EDF2F4", bg = "#3D3D3D" }
footer = { fg = "#EDF2F4", bg = "#3F37C9", bold = true }
icon_info = "󰋼"
icon_warn = ""
icon_error = ""

[filetype]
rules = [
    { url = "*/", fg = "#3F37C9", bold = true },
    { url = "*", is = "exec", fg = "#417E38" },
    { url = "*", is = "link", fg = "#177E89" },
    { url = "*", is = "orphan", fg = "#8B1D2C" },
    { mime = "image/*", fg = "#FF4089" },
    { mime = "{audio,video}/*", fg = "#B02B10" },
    { mime = "application/{zip,gzip,x-tar,x-bzip*,x-7z-compressed,x-rar}", fg = "#C33C00" },
    { url = "*", fg = "#EDF2F4" },
]
YAZI_THEME_EOF
    success "Yazi configuration deployed"
}

################################################################################
# 9. STARSHIP CONFIGURATION
################################################################################

deploy_starship_config() {
    log "Deploying Starship configuration..."

    mkdir -p "$HOME/.config"

    deploy_file "$HOME/.config/starship.toml" 644 << 'STARSHIP_EOF'
format = """\
[╭╴](fg:arrow)\
$os\
$directory\
(\
    $git_branch\
    $git_status\
)\
$cmd_duration\
$fill\
[$battery](fg:text_color)\
[$java](fg:text_color)\
[$nodejs](fg:text_color)\
[$python](fg:text_color)\
[$conda](fg:text_color)\
[$rust](fg:text_color)\
[$golang](fg:text_color)\
[$bun](fg:text_color)\
[$docker_context](fg:text_color)
[╰─](fg:arrow)$character"""

add_newline = true

palette = "old"

[palettes.old]
arrow = "#FFFFFF"
os = "#3778BF"
directory = "#3F37C9"
node = "#417E38"
bun = "#FF4089"
time = "#177E89"
git = "#B02B10"
git_status = "#8B1D2C"
python = "#3776AB"
conda = "#3EB049"
java = "#861215"
rust = "#C33C00"
clang = "#00599D"
duration = "#3D3D3D"
text_color = "#EDF2F4"
text_light = "#EDF2F4"

[palettes.normal]
arrow = "#FFFFFF"
os = "#2C3032"
directory = "#363C3E"
time = "#474D5C"
node = "#417E38"
bun = "#FF4089"
git = "#D0DBDA"
git_status = "#DFEBED"
python = "#F5CB5C"
conda = "#3EB049"
java = "#861215"
rust = "#C33C00"
clang = "#00599D"
duration = "#F4FBFF"
text_color = "#EDF2F4"
text_light = "#26272A"

[palettes.light]
arrow = "#FFFFFF"
os = "#F7768E"
directory = "#FF9578"
time = "#FFDC72"
git = "#F5F5F5"
git_status = "#72FFD5"
clang = "#67E3FF"
java = "#FF52A3"
python = "#B4F9F8"
node = "#417E38"
bun = "#FF4089"
conda = "#BAF5C0"
duration = "#91FFE7"
text_color = "#26272A"
text_light = "#26272A"

[character]
success_symbol = "[󰍟](fg:arrow)"
error_symbol = "[󰍟](fg:red)"

[directory]
format = " [](fg:directory)[  $path ]($style)[$read_only]($read_only_style)[](fg:directory)"
truncation_length = 2
style = "fg:text_color bg:directory"
read_only_style = "fg:text_color bg:directory"
before_repo_root_style = "fg:text_color bg:directory"
truncation_symbol = "…/"
truncate_to_repo = true
read_only ="  "

[time]
disabled = false
format = " [](fg:time)[ $time]($style)[](fg:time)"
time_format = "%H:%M"
style = "fg:text_color bg:time"

[cmd_duration]
format = " [](fg:duration)[ $duration]($style)[](fg:duration)"
style = "fg:text_light bg:duration"
min_time = 500

[fill]
symbol = " "

[git_branch]
format = " [](fg:git)[$symbol$branch](fg:text_light bg:git)[](fg:git)"
symbol = " "

[git_status]
format = '([ ](fg:git_status)[ $all_status$ahead_behind ]($style)[](fg:git_status))'
style = "fg:text_light bg:git_status"

[docker_context]
disabled=true
symbol = " "

[package]
disabled=true

[java]
format = "[ ](fg:java)[$symbol$version](bg:java fg:text_color)[](fg:java)"
version_format = "${raw}"
symbol = " "
disabled = false

[nodejs]
format = "[ ](fg:node)[$symbol$version]($style)[](fg:node)"
style = "bg:node fg:text_light"
symbol = " "
version_format = "${raw}"
disabled = false

[rust]
format = "[ ](fg:rust)[$symbol$version](bg:rust fg:text_color)[](fg:rust)"
symbol = " "
version_format = "${raw}"
disabled = false

[python]
disabled = false
format = '[ ](fg:python)[${symbol}${pyenv_prefix}(${version} )(\($virtualenv\))]($style)[](fg:python)'
symbol = " "
version_format = "${raw}"
style = "fg:text_light bg:python"

[conda]
format = "[ ](fg:conda)[$symbol$environment]($style)[](fg:conda)"
style = "bg:conda fg:text_color"
ignore_base = false
disabled = false
symbol = " "

[golang]
format = "[ ](fg:clang)[$symbol($version(-$name) )](bg:clang fg:text_color)[](fg:clang)"
symbol = " "
version_format = "${raw}"
disabled = false

[bun]
format = "[ ](fg:bun)[$symbol$version](bg:bun fg:text_color)[](fg:bun)"
symbol = "🫓 "
version_format = "${raw}"
disabled = false

[battery]
full_symbol = "󰁹 "
charging_symbol = "󰢝 "
discharging_symbol = "󰁼 "
unknown_symbol = "󰂑 "
empty_symbol = "󰂎 "
disabled = false
format = "[$symbol$percentage]($style)"

[[battery.display]]
threshold = 10
style = "bold red"

[[battery.display]]
threshold = 30
style = "bold yellow"

[[battery.display]]
threshold = 100
style = "bold green"

[os]
disabled = false
format = "[](fg:os)[$symbol](bg:os fg:text_color)[](fg:os)"

[os.symbols]
Alpine = ""
Amazon = ""
Android = ""
Arch = ""
CentOS = ""
Debian = ""
DragonFly = ""
Emscripten = ""
EndeavourOS = ""
Fedora = ""
FreeBSD = ""
Gentoo = ""
Linux = ""
Macos = ""
Manjaro = ""
Mariner = ""
MidnightBSD = ""
Mint = ""
NetBSD = ""
NixOS = ""
openSUSE = ""
Pop = ""
Raspbian = ""
Redhat = ""
RedHatEnterprise = ""
Redox = ""
SUSE = ""
Ubuntu = ""
Unknown = ""
Windows = ""
STARSHIP_EOF

    deploy_file "$HOME/.config/starship-plain.toml" 644 << 'STARSHIP_PLAIN_EOF'
# Prompt without Nerd Font glyphs, for clients that cannot render them.
# Select it per host in ~/.zshrc.local:
#   export STARSHIP_CONFIG="$HOME/.config/starship-plain.toml"
# Herdr sessions are shared by every attached client, so this is per host.
format = """\
[╭╴](fg:arrow)\
$directory\
(\
    $git_branch\
    $git_status\
)\
$cmd_duration\
$fill\
$nodejs\
$python\
$conda\
$rust\
$golang\
$java\
$bun\
$docker_context
[╰─](fg:arrow)$character"""

add_newline = true

palette = "old"

[palettes.old]
arrow = "#FFFFFF"
directory = "#3F37C9"
node = "#417E38"
bun = "#FF4089"
git = "#B02B10"
git_status = "#8B1D2C"
python = "#3776AB"
conda = "#3EB049"
java = "#861215"
rust = "#C33C00"
clang = "#00599D"
duration = "#3D3D3D"
text_color = "#EDF2F4"

[character]
success_symbol = "[❯](fg:arrow)"
error_symbol = "[❯](fg:red)"

[directory]
format = "[ $path ]($style)[$read_only]($read_only_style)"
truncation_length = 2
style = "fg:text_color bg:directory"
read_only_style = "fg:text_color bg:directory"
before_repo_root_style = "fg:text_color bg:directory"
truncation_symbol = "…/"
truncate_to_repo = true
read_only = "ro "

[cmd_duration]
format = " [ $duration ]($style)"
style = "fg:text_color bg:duration"
min_time = 500

[fill]
symbol = " "

[git_branch]
format = " [ $symbol$branch ](fg:text_color bg:git)"
symbol = "git:"

[git_status]
format = '([ $all_status$ahead_behind ]($style))'
style = "fg:text_color bg:git_status"

[docker_context]
disabled = true

[package]
disabled = true

[nodejs]
format = " [ node $version ]($style)"
style = "fg:text_color bg:node"
version_format = "${raw}"

[python]
format = ' [ py ${pyenv_prefix}(${version} )(\($virtualenv\) )]($style)'
style = "fg:text_color bg:python"
version_format = "${raw}"

[conda]
format = " [ conda $environment ]($style)"
style = "fg:text_color bg:conda"
ignore_base = false

[rust]
format = " [ rs $version ]($style)"
style = "fg:text_color bg:rust"
version_format = "${raw}"

[golang]
format = " [ go $version ]($style)"
style = "fg:text_color bg:clang"
version_format = "${raw}"

[java]
format = " [ java $version ]($style)"
style = "fg:text_color bg:java"
version_format = "${raw}"

[bun]
format = " [ bun $version ]($style)"
style = "fg:text_color bg:bun"
version_format = "${raw}"
STARSHIP_PLAIN_EOF
    success "Starship configs deployed (Nerd Font and plain)"
}

################################################################################
# 10. CUSTOM FUNCTIONS
################################################################################

deploy_custom_functions() {
    log "Deploying custom functions..."

    mkdir -p "$HOME/.zsh"

    deploy_file "$HOME/.zsh/gswf.zsh" 644 << 'GSWF_EOF'
# gswf - Git Switch Fuzzy
# Fuzzy find and switch git branches

# Remove any existing alias to prevent conflicts
unalias gswf 2>/dev/null || true

gswf() {
    local query="${1:-}"
    local refs
    refs=$(git for-each-ref --format='%(refname)%09%(upstream)%09%(symref)' \
        refs/heads/ refs/remotes/) || return

    # Use plain ref names, and represent a tracked remote by its local branch.
    # This also avoids counting origin/foo and foo as separate matches.
    local branches
    branches=$(
        printf '%s\n' "$refs" | awk -F '\t' '
            $1 ~ /^refs\/heads\// {
                name = substr($1, 12)
                print name
                if ($2 != "") tracked[$2] = 1
            }
            $1 ~ /^refs\/remotes\// && $3 == "" {
                remote[$1] = 1
            }
            END {
                for (ref in remote) {
                    if (!(ref in tracked)) {
                        sub(/^refs\/remotes\/[^/]*\//, "", ref)
                        print ref
                    }
                }
            }
        ' \
        | sort -u
    )

    local filtered
    if [[ -n "$query" ]]; then
        filtered=$(printf '%s\n' "$branches" | grep -iF -- "$query" || true)
    else
        filtered="$branches"
    fi

    local count
    if [[ -z "$filtered" ]]; then
        count=0
    else
        count=$(printf '%s\n' "$filtered" | wc -l | tr -d ' ')
    fi

    local branch
    if (( count == 0 )); then
        echo "gswf: no branches matching '$query'" >&2
        return 1
    elif (( count == 1 )); then
        branch="$filtered"
        echo "gswf: switching to '$branch'" >&2
    else
        if ! command -v fzf >/dev/null 2>&1; then
            echo "gswf: fzf is required when multiple branches match" >&2
            return 1
        fi
        # fzf's query/options can narrow the prefiltered list to one match.
        branch=$(printf '%s\n' "$filtered" | fzf --select-1 --query "$query" --preview 'git log -n 20 --color --oneline {}') || return 0
        if [[ -z "$branch" ]]; then
            return 0
        fi
    fi

    git switch -- "$branch"
}
GSWF_EOF
    success "gswf.zsh function deployed"

    deploy_file "$HOME/.zsh/y.zsh" 644 << 'Y_EOF'
# y - Yazi with cwd restore
# Open Yazi and cd to the directory where it exits.

# Remove any existing alias to prevent conflicts
unalias y 2>/dev/null || true

y() {
    if ! command -v yazi >/dev/null 2>&1; then
        echo "y: yazi is not installed" >&2
        return 1
    fi

    local cwd_file cwd
    cwd_file=$(mktemp "${TMPDIR:-/tmp}/yazi-cwd.XXXXXX") || return 1

    yazi "$@" --cwd-file="$cwd_file"

    if [[ -f "$cwd_file" ]]; then
        cwd=$(<"$cwd_file")
        rm -f "$cwd_file"

        if [[ -n "$cwd" && "$cwd" != "$PWD" ]]; then
            builtin cd -- "$cwd"
        fi
    fi
}
Y_EOF
    success "y.zsh function deployed"
}

################################################################################
# 11. NEOVIM CONFIGURATION
################################################################################

# LazyVim and kickstart.nvim live side by side as NVIM_APPNAME configs in
# ~/.config/<name>, and `vi` opens the one named in NVIM_CONFIG. A missing
# starter is cloned at its audited commit; later upstream updates are up to
# the user (`git pull` inside the config). Format: name|repository|commit.
neovim_starters() {
    printf '%s\n' \
        'nvim-lazyvim|https://github.com/LazyVim/starter|803bc181d7c0d6d5eeba9274d9be49b287294d99' \
        'nvim-kickstart|https://github.com/nvim-lua/kickstart.nvim|8e35dbedb7966e3a95e1f26f9fc1179ab6c68db4'
}

# Managed edits to files owned by each starter, as patches for `git apply`
# (empty context lines carry no trailing space).
neovim_starter_patch() {
    case "$1" in
        nvim-lazyvim) cat << 'LAZYVIM_PATCH_EOF'
diff --git a/lua/config/lazy.lua b/lua/config/lazy.lua
--- a/lua/config/lazy.lua
+++ b/lua/config/lazy.lua
@@ -18,6 +18,16 @@ require("lazy").setup({
   spec = {
     -- add LazyVim and import its plugins
     { "LazyVim/LazyVim", import = "lazyvim.plugins" },
+    -- official extras (the same as enabling them in :LazyExtras)
+    { import = "lazyvim.plugins.extras.lang.python" },
+    { import = "lazyvim.plugins.extras.lang.typescript" },
+    { import = "lazyvim.plugins.extras.lang.json" },
+    { import = "lazyvim.plugins.extras.lang.yaml" },
+    { import = "lazyvim.plugins.extras.lang.toml" },
+    { import = "lazyvim.plugins.extras.lang.markdown" },
+    { import = "lazyvim.plugins.extras.lang.docker" },
+    { import = "lazyvim.plugins.extras.lang.ansible" },
+    { import = "lazyvim.plugins.extras.lang.git" },
     -- import/override with your plugins
     { import = "plugins" },
   },
@@ -45,7 +55,7 @@ require("lazy").setup({
         -- "netrwPlugin",
         "tarPlugin",
         "tohtml",
-        "tutor",
+        -- "tutor", -- enabled so :Tutor works
         "zipPlugin",
       },
     },
LAZYVIM_PATCH_EOF
            ;;
        nvim-kickstart) cat << 'KICKSTART_PATCH_EOF'
diff --git a/init.lua b/init.lua
--- a/init.lua
+++ b/init.lua
@@ -99,7 +99,7 @@ do
   vim.g.maplocalleader = ' '

   -- Set to true if you have a Nerd Font installed and selected in the terminal
-  vim.g.have_nerd_font = false
+  vim.g.have_nerd_font = true

   -- [[ Setting options ]]
   --  See `:help vim.o`
@@ -735,8 +735,17 @@ do
   local servers = {
     -- clangd = {},
     -- gopls = {},
-    -- pyright = {},
-    -- tsc = {},
+    pyright = {}, -- Python
+    ruff = {}, -- Python: lint + format
+    ts_ls = {}, -- JavaScript / TypeScript
+    bashls = { filetypes = { 'sh', 'bash', 'zsh' } },
+    jsonls = {},
+    yamlls = {},
+    taplo = {}, -- TOML
+    marksman = {}, -- Markdown
+    dockerls = {},
+    docker_compose_language_service = {},
+    ansiblels = {},
     --
     -- Some languages (like rust) have entire language plugins that can be useful:
     --    https://github.com/mrcjkb/rustaceanvim
@@ -804,6 +813,8 @@ do
   local ensure_installed = vim.tbl_keys(servers or {})
   vim.list_extend(ensure_installed, {
     -- You can add other tools here that you want Mason to install
+    'shellcheck', -- shell linter (used by bashls)
+    'shfmt', -- shell formatter
   })

   require('mason-tool-installer').setup { ensure_installed = ensure_installed }
@@ -826,8 +837,9 @@ do
     format_on_save = function(bufnr)
       -- You can specify filetypes to autoformat on save here:
       local enabled_filetypes = {
-        -- lua = true,
-        -- python = true,
+        lua = true,
+        python = true,
+        sh = true,
       }
       if enabled_filetypes[vim.bo[bufnr].filetype] then
         return { timeout_ms = 500 }
@@ -840,6 +852,9 @@ do
     },
     -- You can also specify external formatters in here.
     formatters_by_ft = {
+      lua = { 'stylua' },
+      python = { 'ruff_format' },
+      sh = { 'shfmt' },
       -- rust = { 'rustfmt' },
       -- Conform can also run multiple formatters sequentially
       -- python = { "isort", "black" },
@@ -868,8 +883,8 @@ do
   --    See the README about individual language/framework/plugin snippets:
   --    https://github.com/rafamadriz/friendly-snippets
   --
-  -- vim.pack.add { gh 'rafamadriz/friendly-snippets' }
-  -- require('luasnip.loaders.from_vscode').lazy_load()
+  vim.pack.add { gh 'rafamadriz/friendly-snippets' }
+  require('luasnip.loaders.from_vscode').lazy_load()

   -- [[ Autocomplete Engine ]]
   vim.pack.add { { src = gh 'saghen/blink.cmp', version = vim.version.range '1.*' } }
@@ -948,7 +963,11 @@ do
   vim.pack.add { { src = gh 'nvim-treesitter/nvim-treesitter', version = 'main' } }

   -- Ensure basic parsers are installed
-  local parsers = { 'bash', 'c', 'diff', 'html', 'lua', 'luadoc', 'markdown', 'markdown_inline', 'query', 'vim', 'vimdoc' }
+  local parsers = {
+    'bash', 'c', 'diff', 'html', 'lua', 'luadoc', 'markdown', 'markdown_inline', 'query', 'vim', 'vimdoc',
+    'python', 'javascript', 'typescript', 'tsx', 'json', 'yaml', 'toml', 'dockerfile',
+    'gitcommit', 'git_rebase', 'git_config', 'gitignore',
+  }
   require('nvim-treesitter').install(parsers)

   ---@param buf integer
@@ -1015,15 +1034,15 @@ do
   --  Uncomment any of the lines below to enable them (you will need to restart nvim).
   --
   -- require 'kickstart.plugins.debug'
-  -- require 'kickstart.plugins.indent_line'
+  require 'kickstart.plugins.indent_line'
   -- require 'kickstart.plugins.lint'
-  -- require 'kickstart.plugins.autopairs'
-  -- require 'kickstart.plugins.neo-tree'
+  require 'kickstart.plugins.autopairs'
+  require 'kickstart.plugins.neo-tree'

   -- NOTE: You can add your own plugins, configuration, etc. in `lua/custom/plugins/*.lua`.
   --
   -- For independent modules, uncomment the convenience loader:
-  -- require 'custom.plugins'
+  require 'custom.plugins' -- git.lua (diffview, lazygit), learning.lua (hardtime, precognition, tips)
   --
   -- `custom.plugins` automatically loads files from that directory, but their
   -- order is unspecified. If plugins depend on each other, keep them in the same
KICKSTART_PATCH_EOF
            ;;
        *) return 1 ;;
    esac
}

# Files added to each starter. deploy_file keeps reruns convergent.
# A generated file in a directory the user also writes to: an existing file
# without the managed header is theirs and is left alone.
deploy_added_file() {
    local target="$1" mode="$2"
    if [[ -f "$target" ]] && ! head -5 "$target" | grep -q 'Managed by shell-backup'; then
        warning "$target is not managed by setup; left as is"
        cat > /dev/null
        return 0
    fi
    deploy_file "$target" "$mode"
}

deploy_neovim_files() {
    local dir="$2"
    case "$1" in
        nvim-lazyvim)
            deploy_added_file "$dir/lua/plugins/git.lua" 644 << 'LAZYVIM_GIT_EOF' || return 1
-- Managed by shell-backup setup.sh.
-- Git: LazyVim already ships gitsigns and lazygit. diffview adds side-by-side
-- review of changes and history, and a 3-way merge tool for conflicts.
return {
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewToggleFiles" },
    keys = {
      { "<leader>gv", "<cmd>DiffviewOpen<cr>", desc = "Diffview: changes / conflicts" },
      { "<leader>gV", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview: file history" },
      { "<leader>gH", "<cmd>DiffviewFileHistory<cr>", desc = "Diffview: repo history" },
    },
    opts = {
      enhanced_diff_hl = true,
      view = {
        -- conflicts: OURS | result | THEIRS, with the common ancestor available
        merge_tool = { layout = "diff3_mixed", disable_diagnostics = true },
      },
      keymaps = {
        view = { { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close Diffview" } } },
        file_panel = { { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close Diffview" } } },
        file_history_panel = { { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close Diffview" } } },
      },
    },
  },
}
LAZYVIM_GIT_EOF
            deploy_added_file "$dir/lua/plugins/bash.lua" 644 << 'LAZYVIM_BASH_EOF' || return 1
-- Managed by shell-backup setup.sh.
-- Bash/zsh: LazyVim has no shell extra, so it is added here.
return {
  {
    "neovim/nvim-lspconfig",
    opts = { servers = { bashls = { filetypes = { "sh", "bash", "zsh" } } } },
  },
  { "mason-org/mason.nvim", opts = { ensure_installed = { "shellcheck", "shfmt" } } },
  { "nvim-treesitter/nvim-treesitter", opts = { ensure_installed = { "bash" } } },
  { "stevearc/conform.nvim", opts = { formatters_by_ft = { sh = { "shfmt" }, bash = { "shfmt" } } } },
}
LAZYVIM_BASH_EOF
            deploy_added_file "$dir/lua/plugins/learning.lua" 644 << 'LAZYVIM_LEARNING_EOF' || return 1
-- Managed by shell-backup setup.sh.
-- Helpers to learn a little at a time while using Neovim.
local tips_dir = vim.fn.expand("~/Proyectos/tips.nvim")

return {
  -- Hints when a motion could be shorter (jjjj -> 4j). Hints only, nothing is blocked.
  {
    "m4xshen/hardtime.nvim",
    event = "VeryLazy",
    dependencies = { "MunifTanjim/nui.nvim" },
    opts = {
      restriction_mode = "hint",
      disable_mouse = false,
      -- keep the arrow keys (blocked by default)
      disabled_keys = { ["<Up>"] = false, ["<Down>"] = false, ["<Left>"] = false, ["<Right>"] = false },
    },
    keys = {
      { "<leader>uH", "<cmd>Hardtime toggle<cr>", desc = "Toggle Hardtime (hints)" },
    },
  },
  -- Shows on the line where w/b/e/$/^/{/} and friends would jump.
  {
    "tris203/precognition.nvim",
    event = "VeryLazy",
    opts = { startVisible = false },
    keys = {
      { "<leader>uP", function() require("precognition").toggle() end, desc = "Toggle Precognition (motions)" },
    },
  },
  -- tips.nvim (local project): daily tip, a tip when each tool opens and
  -- :TipQuiz. Loaded at startup to detect `git mergetool`; skipped if absent.
  {
    dir = tips_dir,
    name = "tips.nvim",
    lazy = false,
    cond = vim.uv.fs_stat(tips_dir) ~= nil,
    opts = { preset = "lazyvim", key = "<leader>T" },
  },
}
LAZYVIM_LEARNING_EOF
            ;;
        nvim-kickstart)
            deploy_added_file "$dir/lua/custom/plugins/git.lua" 644 << 'KICKSTART_GIT_EOF' || return 1
-- Managed by shell-backup setup.sh.
-- Git: gitsigns is already set up in init.lua (<leader>h...). Added here:
--   diffview.nvim  side-by-side changes, history and a 3-way merge tool
--   lazygit.nvim   lazygit in a floating window
-- Same keymaps as the LazyVim config.

vim.pack.add {
  'https://github.com/nvim-lua/plenary.nvim',
  'https://github.com/sindrets/diffview.nvim',
  'https://github.com/kdheepak/lazygit.nvim',
}

require('diffview').setup {
  enhanced_diff_hl = true,
  view = {
    -- conflicts: OURS | result | THEIRS, with the common ancestor available
    merge_tool = { layout = 'diff3_mixed', disable_diagnostics = true },
  },
  keymaps = {
    view = { { 'n', 'q', '<cmd>DiffviewClose<cr>', { desc = 'Close Diffview' } } },
    file_panel = { { 'n', 'q', '<cmd>DiffviewClose<cr>', { desc = 'Close Diffview' } } },
    file_history_panel = { { 'n', 'q', '<cmd>DiffviewClose<cr>', { desc = 'Close Diffview' } } },
  },
}

require('which-key').add { { '<leader>g', group = '[G]it' } }

vim.keymap.set('n', '<leader>gg', '<cmd>LazyGit<cr>', { desc = '[G]it: lazygit' })
vim.keymap.set('n', '<leader>gs', require('telescope.builtin').git_status, { desc = '[G]it [S]tatus' })
vim.keymap.set('n', '<leader>gv', '<cmd>DiffviewOpen<cr>', { desc = 'Diffview: changes / conflicts' })
vim.keymap.set('n', '<leader>gV', '<cmd>DiffviewFileHistory %<cr>', { desc = 'Diffview: file history' })
vim.keymap.set('n', '<leader>gH', '<cmd>DiffviewFileHistory<cr>', { desc = 'Diffview: repo history' })
KICKSTART_GIT_EOF
            deploy_added_file "$dir/lua/custom/plugins/learning.lua" 644 << 'KICKSTART_LEARNING_EOF' || return 1
-- Managed by shell-backup setup.sh.
-- Helpers to learn a little at a time while using Neovim.

vim.pack.add {
  'https://github.com/MunifTanjim/nui.nvim',
  'https://github.com/m4xshen/hardtime.nvim',
  'https://github.com/tris203/precognition.nvim',
}

-- Hints when a motion could be shorter (jjjj -> 4j). Hints only, nothing is blocked.
require('hardtime').setup {
  restriction_mode = 'hint',
  disable_mouse = false,
  -- keep the arrow keys (blocked by default)
  disabled_keys = { ['<Up>'] = false, ['<Down>'] = false, ['<Left>'] = false, ['<Right>'] = false },
}
vim.keymap.set('n', '<leader>tH', '<cmd>Hardtime toggle<cr>', { desc = '[T]oggle [H]ardtime (hints)' })

-- Shows on the line where w/b/e/$/^/{/} and friends would jump.
require('precognition').setup { startVisible = false }
vim.keymap.set('n', '<leader>tp', function() require('precognition').toggle() end, { desc = '[T]oggle [P]recognition (motions)' })

-- tips.nvim (local project): daily tip, a tip when each tool opens and
-- :TipQuiz to memorise keymaps. Skipped if the project is absent.
local tips_dir = vim.fn.expand '~/Proyectos/tips.nvim'
if vim.uv.fs_stat(tips_dir) then
  vim.opt.rtp:prepend(tips_dir)
  require('tips').setup { preset = 'kickstart', key = '<leader>T' }
end
KICKSTART_LEARNING_EOF
            ;;
        *) return 1 ;;
    esac
}

# Starters are cloned and patched by Git without looking in parent
# directories, so a dotfiles repository around ~/.config is never used. Git
# discovers repositories from the physical path, so the ceiling is derived
# from it too (a config symlinked into a dotfiles repository by stow), and an
# exported GIT_DIR/GIT_WORK_TREE must not redirect the edit.
starter_git() {
    local dir
    dir=$(cd "$1" && pwd -P) || return 1
    shift
    (
        unset GIT_DIR GIT_WORK_TREE
        GIT_CEILING_DIRECTORIES="$(dirname "$dir")" exec git -C "$dir" "$@"
    )
}

# The repository Git would edit for a config, if it is not the config itself.
starter_enclosing_repository() {
    local dir top
    dir=$(cd "$1" && pwd -P) || return 1
    top=$(starter_git "$dir" rev-parse --show-toplevel 2>/dev/null || true)
    [[ -n "$top" && "$top" != "$dir" ]] || return 1
    printf '%s\n' "$top"
}

fresh_clone() {
    rm -rf "$2"
    git clone --quiet "$1" "$2"
}

# Clone next to the target and rename it into place, so an interrupted run
# never leaves a partial config behind.
clone_neovim_starter() {
    local repository="$1" commit="$2" target="$3" temp
    mkdir -p "$(dirname "$target")" || return 1
    temp=$(mktemp -d "$(dirname "$target")/.$(basename "$target").XXXXXX") || return 1
    if retry fresh_clone "$repository" "$temp/repo" &&
        starter_git "$temp/repo" reset --quiet --hard "$commit" &&
        mv "$temp/repo" "$target"; then
        rmdir "$temp"
    else
        rm -rf "$temp"
        return 1
    fi
}

# Apply the managed patch once: an already patched file is left alone, and
# local edits that conflict with it are kept and reported (the user owns the
# config). A pre-existing config is backed up before it is patched.
apply_neovim_starter_patch() {
    local name="$1" dir="$2" fresh="$3" patch file status=0 enclosing
    if enclosing=$(starter_enclosing_repository "$dir"); then
        # Inside another work tree, git apply would silently skip every path.
        warning "$name: $dir is inside the repository $enclosing; not patched"
        return 1
    fi
    patch=$(mktemp) || return 1
    if ! neovim_starter_patch "$name" > "$patch"; then
        rm -f "$patch"
        return 1
    fi
    if starter_git "$dir" apply --reverse --check "$patch" 2>/dev/null; then
        success "$name managed edits already present"
    elif starter_git "$dir" apply --check "$patch" 2>/dev/null; then
        if [[ "$fresh" != true ]]; then
            while IFS= read -r file; do
                backup_file "$dir/$file"
            done < <(sed -n 's|^+++ b/||p' "$patch")
        fi
        if starter_git "$dir" apply "$patch"; then
            success "$name managed edits applied"
        else
            status=1
        fi
    else
        warning "$name: local edits conflict with the managed changes; $dir left as is"
        status=3
    fi
    rm -f "$patch"
    return "$status"
}

setup_neovim_configs() {
    log "Setting up Neovim configs..."
    command_exists git || return 1
    local name repository commit dir fresh patched status=0
    while IFS='|' read -r name repository commit; do
        dir="$HOME/.config/$name"
        fresh=false
        if [[ ! -e "$dir" ]]; then
            log "Cloning $name (${repository#https://github.com/} at ${commit:0:7})..."
            if ! clone_neovim_starter "$repository" "$commit" "$dir"; then
                warning "Could not clone $repository"
                status=1
                continue
            fi
            fresh=true
        elif [[ ! -f "$dir/init.lua" ]]; then
            warning "$dir has no init.lua; not treated as a $name config"
            status=1
            continue
        fi
        # Added files belong only in a starter that carries the managed edits:
        # a config whose patch conflicts (or an older starter generation) is
        # left entirely alone.
        patched=0
        apply_neovim_starter_patch "$name" "$dir" "$fresh" || patched=$?
        if [[ "$patched" == 0 ]]; then
            deploy_neovim_files "$name" "$dir" || status=1
        elif [[ "$patched" == 3 ]]; then
            log "$name: added plugin files not deployed while the managed edits are missing"
        else
            status=1
        fi
    done < <(neovim_starters)
    [[ "$status" == 0 ]] && success "Neovim configs ready (plugins install on first start)"
    return "$status"
}

deploy_neovim_launchers() {
    log "Deploying Neovim launchers..."

    deploy_file "$HOME/.local/bin/vi" 755 << 'NVIM_VI_EOF'
#!/bin/sh
# Managed by shell-backup setup.sh.
# vi: Neovim with the config named in NVIM_CONFIG (default nvim-lazyvim),
# passed as NVIM_APPNAME. Configs: ~/.config/nvim-lazyvim, ~/.config/nvim-kickstart.
# Example: NVIM_CONFIG=nvim-kickstart vi file.txt
# The managed Neovim comes first, so callers with a minimal PATH (GUI apps,
# cron, launchd) still get it; without any nvim the system vi opens instead.
for nvim in "$HOME/.local/opt/nvim/bin/nvim" /opt/homebrew/bin/nvim nvim; do
    case "$nvim" in
        */*) [ -x "$nvim" ] || continue ;;
        *) command -v "$nvim" >/dev/null 2>&1 || continue ;;
    esac
    NVIM_APPNAME="${NVIM_CONFIG:-nvim-lazyvim}" exec "$nvim" "$@"
done
echo 'vi: nvim not found (run setup.sh); opening the system vi' >&2
for editor in /usr/bin/vim /usr/bin/vi /bin/vi; do
    [ -x "$editor" ] && exec "$editor" "$@"
done
echo 'vi: no editor found' >&2
exit 127
NVIM_VI_EOF

    deploy_file "$HOME/.zsh/nvim.zsh" 644 << 'NVIM_ZSH_EOF'
# Neovim: LazyVim and kickstart.nvim side by side (NVIM_APPNAME).
# `vi` (~/.local/bin/vi) opens the config named in NVIM_CONFIG, and so do Git
# and Yazi. Change the default in ~/.zshrc.local or ~/.env.
export NVIM_CONFIG="${NVIM_CONFIG:-nvim-lazyvim}"
export EDITOR="${EDITOR:-vi}"
export VISUAL="${VISUAL:-vi}"

# Remove any existing aliases to prevent conflicts
unalias lv kv nvims 2>/dev/null || true

alias lv='NVIM_CONFIG=nvim-lazyvim vi'
alias kv='NVIM_CONFIG=nvim-kickstart vi'

# nvims - pick a config with fzf, then open it (files may follow)
nvims() {
    if ! command -v fzf >/dev/null 2>&1; then
        echo "nvims: fzf is required" >&2
        return 1
    fi

    local config
    config=$(printf '%s\n' nvim-lazyvim nvim-kickstart |
        fzf --prompt='Neovim config > ' --height='~50%' --layout=reverse --border) || return 0
    [[ -n "$config" ]] || return 0
    NVIM_CONFIG="$config" vi "$@"
}
NVIM_ZSH_EOF
    success "Neovim launchers deployed (vi, lv, kv, nvims)"
}

# Git opens Neovim through vi (so NVIM_CONFIG applies) for commit messages,
# `git mergetool` and `git difftool`. Only keys with another value are
# written, and ~/.gitconfig is backed up only when Git changed it.
# The Neovim the vi launcher runs: the managed tree, Homebrew, then PATH.
launcher_nvim() {
    local candidate
    for candidate in "$HOME/.local/opt/nvim/bin/nvim" /opt/homebrew/bin/nvim nvim; do
        if [[ "$candidate" == */* ]]; then
            [[ -x "$candidate" ]] || continue
        else
            command_exists "$candidate" || continue
        fi
        printf '%s\n' "$candidate"
        return 0
    done
    return 1
}

# Git settings point at the vi launcher only once it has a Neovim that meets
# the target; otherwise the stage is skipped and Git keeps its own editor.
configure_git_editor() {
    command_exists git || return 1
    local vi="$HOME/.local/bin/vi" style=diff3 file="$HOME/.gitconfig" nvim
    local xdg_file="${XDG_CONFIG_HOME:-$HOME/.config}/git/config" entry snapshot status=0
    local pending=()
    if ! nvim=$(launcher_nvim) || ! version_gte "$(tool_version "$nvim")" "$NEOVIM_VERSION"; then
        warning "Git editor: no Neovim $NEOVIM_VERSION for the vi launcher; Git settings left alone"
        return 3
    fi
    # zdiff3 (Git 2.35+) moves lines common to both sides out of the conflict.
    if version_gte "$(tool_version git)" 2.35; then
        style=zdiff3
    fi
    local settings=(
        "core.editor=$vi"
        "merge.tool=nvimdiff"
        "merge.conflictstyle=$style"
        "mergetool.nvimdiff.path=$vi"
        "mergetool.keepBackup=false"
        "mergetool.prompt=false"
        "diff.tool=nvimdiff"
        "difftool.nvimdiff.path=$vi"
        "difftool.prompt=false"
    )
    # `git config --global` writes the XDG file when only that one exists.
    if [[ ! -f "$file" && -f "$xdg_file" ]]; then
        file="$xdg_file"
    fi
    for entry in "${settings[@]}"; do
        if [[ "$(git config --global --get "${entry%%=*}" 2>/dev/null || true)" != "${entry#*=}" ]]; then
            pending+=("$entry")
        fi
    done
    if [[ ${#pending[@]} -eq 0 ]]; then
        success "Git already uses Neovim (vi) as editor, merge and diff tool"
        return 0
    fi
    snapshot=$(snapshot_file "$file") || return 1
    for entry in "${pending[@]}"; do
        git config --global "${entry%%=*}" "${entry#*=}" || status=1
    done
    keep_snapshot_if_changed "$file" "$snapshot"
    [[ "$status" == 0 ]] || return 1
    success "Git uses Neovim (vi) as editor, merge and diff tool"
}

################################################################################
# 12. SHELL SETUP
################################################################################

login_shell() {
    local user
    user=$(id -un)
    if [[ "$OS_TYPE" == darwin ]]; then
        dscl . -read "/Users/$user" UserShell 2>/dev/null | awk '{print $2}'
    elif command_exists getent; then
        getent passwd "$user" 2>/dev/null | cut -d: -f7
    fi
}

setup_shell() {
    log "Setting up zsh as default shell..."

    # Make zsh default shell
    local zsh_path
    zsh_path=$(get_zsh_path)

    # Check the account's login shell, not $SHELL: after chsh the running
    # session keeps the old $SHELL until the next login, and a rerun must not
    # ask again or report a different result.
    local current_shell
    current_shell=$(login_shell) || current_shell=""
    if [[ "${current_shell:-${SHELL:-}}" == *"zsh"* ]]; then
        success "zsh is already the default shell"
    elif ! can_prompt; then
        # Non-interactive: skip chsh to avoid hang (tty check OR explicit flag)
        warning "Non-interactive mode detected. Skipping 'chsh' (would prompt for password)."
        warning "To change shell manually, run: chsh -s $zsh_path"
        return 3
    else
        log "Changing default shell to $zsh_path..."
        chsh -s "$zsh_path" </dev/tty
        success "Default shell changed to zsh"
    fi
}

################################################################################
# 13. NVM SETUP
################################################################################

setup_nvm() {
    export NVM_DIR="$HOME/.nvm"
    local before="" node_before="" restore_nounset=false
    if [[ -s "$NVM_DIR/nvm.sh" ]]; then
        before=$( (set +u; . "$NVM_DIR/nvm.sh"; nvm --version) )
    fi
    if [[ -z "$before" ]] || ! version_gte "$before" "$NVM_INSTALL_VERSION"; then
        (
            local temp_dir
            temp_dir=$(mktemp -d)
            trap 'rm -rf "$temp_dir"' EXIT
            verified_download "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_INSTALL_VERSION}/install.sh" \
                "066ce4eaf4d78eaa6410433bc9ba58faaba646157cbbed6109153e6c24c5f8a5" "$temp_dir/install.sh" || exit 1
            PROFILE=/dev/null bash "$temp_dir/install.sh" || exit 1
        ) || return 1
    fi
    [[ ! -o nounset ]] || { set +u; restore_nounset=true; }
    . "$NVM_DIR/nvm.sh"
    version_gte "$(nvm --version)" "$NVM_INSTALL_VERSION" || return 1
    node_before=$(node --version 2>/dev/null || true)
    if [[ -n "$node_before" ]] && version_gte "${node_before#v}" "$NODE_VERSION"; then
        success "Active newer Node retained ($node_before)"
    else
        # nvm verifies Node's published checksum. Do not migrate global npm
        # packages: they may include harnesses outside this script's scope.
        nvm install "$NODE_VERSION" || return 1
        nvm alias default "$NODE_VERSION" || return 1
        nvm use "$NODE_VERSION" || return 1
    fi
    [[ "$restore_nounset" != true ]] || set -u
    log "NVM ${before:-absent} -> $(nvm --version); Node ${node_before:-absent} -> $(node --version)"
    require_version node "$NODE_VERSION"
}

################################################################################
# 14. ZINIT PLUGINS SETUP
################################################################################

setup_zinit_plugins() {
    log "Setting up Zinit plugins..."

    # First, ensure zinit is installed
    require_version zsh "$MIN_ZSH_VERSION" || return 1
    if [[ ! -f $HOME/.local/share/zinit/zinit.git/zinit.zsh ]]; then
        log "Installing Zinit plugin manager..."
        command mkdir -p "$HOME/.local/share/zinit" && command chmod g-rwX "$HOME/.local/share/zinit"
        if ! retry git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git"; then
            error "Failed to install Zinit plugin manager"
        fi
    fi

    require_version zsh "$MIN_ZSH_VERSION" || return 1

    # Run zsh to download and install all plugins
    log "Installing plugins (this may take a minute)..."
    if ! SHELL_BACKUP_SKIP_ZINIT_AUTO_UPDATE=1 zsh -c '
        source "$HOME/.local/share/zinit/zinit.git/zinit.zsh"
        mkdir -p "${ZSH_CACHE_DIR:-$HOME/.cache/zsh}/completions"

        source "$HOME/.zsh/zinit-update.zsh" || exit 1
        for plugin in $shell_backup_zinit_plugins; do
            # Clone only missing plugins: loading an installed one rewrites
            # Zinit metadata, and the updater below handles existing clones.
            [[ -d "${ZINIT[PLUGINS_DIR]}/${plugin//\//---}" ]] && continue
            if [[ "$plugin" == ohmyzsh/ohmyzsh ]]; then
                # Same clone ices as ~/.zshrc; never source the OMZ framework.
                zinit ice silent depth"1" pick"/dev/null" nocompletions
            else
                zinit ice silent light-mode
            fi
            zinit light "$plugin" >/dev/null
        done
        shell_backup_update_zinit || exit 1

        # Earlier versions loaded OMZ plugins as URL snippets. Remove them once
        # the Git clone exists, so `zinit update --all` never downloads them.
        if [[ -f "${ZINIT[PLUGINS_DIR]}/ohmyzsh---ohmyzsh/plugins/git/git.plugin.zsh" ]]; then
            command rm -rf -- "${ZINIT[SNIPPETS_DIR]}"/OMZP::{git,bun,alias-finder,command-not-found}
        fi
        exit 0
    '; then
        error "Zinit plugin bootstrap failed"
    fi

    if ! verify_zinit_assets; then
        error "Zinit plugin bootstrap incomplete"
    fi

    local zinit_version
    zinit_version=$(cat "$HOME/.local/share/zinit/zinit.git/VERSION")
    version_gte "$zinit_version" 3.17.0 || return 1
    success "Zinit $zinit_version and managed plugins installed"
}

################################################################################
# 15. YAZI PLUGINS SETUP
################################################################################

# Managed Yazi packages: ya id|upstream repository|entry file.
yazi_managed_packages() {
    printf '%s\n' \
        "yazi-rs/plugins:git|https://github.com/yazi-rs/plugins|$HOME/.config/yazi/plugins/git.yazi/main.lua" \
        "Rolv-Apneseth/starship|https://github.com/Rolv-Apneseth/starship.yazi|$HOME/.config/yazi/plugins/starship.yazi/main.lua"
}

# The rev recorded by ya for one package in package.toml ("=..." is a pin).
yazi_recorded_rev() {
    awk -v id="\"$1\"" '
        /^\[/ { current = 0 }
        /^use[[:space:]]*=/ && index($0, id) { current = 1 }
        current && /^rev[[:space:]]*=/ {
            sub(/^rev[[:space:]]*=[[:space:]]*"/, ""); sub(/".*$/, ""); print; exit
        }' "$2" 2>/dev/null
}

# Print the managed packages that need `ya pkg upgrade`: missing files, no
# recorded rev, or a recorded rev that is not upstream's HEAD. Pinned packages
# and packages already at HEAD are left untouched. Unknown upstream state
# (offline) keeps the previous behaviour of asking ya.
yazi_packages_to_upgrade() {
    local package_file="$1" package repo entry rev head
    while IFS='|' read -r package repo entry; do
        rev=$(yazi_recorded_rev "$package" "$package_file") || rev=""
        if [[ "$rev" == =* && -f "$entry" ]]; then
            continue
        fi
        head=$(git ls-remote "$repo" HEAD 2>/dev/null | cut -f1) || head=""
        if [[ -f "$entry" && -n "$rev" && -n "$head" && "$head" == "$rev"* ]]; then
            continue
        fi
        printf '%s\n' "$package"
    done < <(yazi_managed_packages)
}

setup_yazi_plugins() {
    log "Setting up Yazi plugins..."
    require_version yazi "$MIN_YAZI_VERSION" || return 1
    require_version ya "$MIN_YAZI_VERSION" || return 1
    require_version starship "$STARSHIP_VERSION" || return 1
    [[ "$(tool_version yazi)" == "$(tool_version ya)" ]] || return 1
    command_exists git || return 1
    # Check current upstream requirements before changing installed plugins.
    local metadata required plugin_url
    for plugin_url in \
        https://raw.githubusercontent.com/yazi-rs/plugins/main/git.yazi/main.lua \
        https://raw.githubusercontent.com/Rolv-Apneseth/starship.yazi/main/main.lua; do
        metadata=$(curl -fsSL --connect-timeout 15 --max-time 30 "$plugin_url") || return 1
        required=$(printf '%s\n' "$metadata" | sed -nE 's/^--- @since ([0-9.]+).*/\1/p' | head -1)
        [[ -z "$required" ]] || require_version yazi "$required" || return 1
    done

    if [[ "$OS_TYPE" == "linux" ]]; then
        ensure_user_local_bin_on_path
    fi
    mkdir -p "$HOME/.config/yazi"

    if ! command_exists ya; then
        error "ya CLI not found; cannot install Yazi plugins"
    fi

    local package_file="$HOME/.config/yazi/package.toml"
    local missing_plugins=()

    if [[ ! -f "$package_file" ]] || ! grep -qE 'use[[:space:]]*=[[:space:]]*"yazi-rs/plugins:git"' "$package_file"; then
        missing_plugins+=("yazi-rs/plugins:git")
    fi

    if [[ ! -f "$package_file" ]] || ! grep -qE 'use[[:space:]]*=[[:space:]]*"Rolv-Apneseth/starship"' "$package_file"; then
        missing_plugins+=("Rolv-Apneseth/starship")
    fi

    local snapshot package status=0
    snapshot=$(snapshot_file "$package_file") || return 1
    if [[ ${#missing_plugins[@]} -gt 0 ]]; then
        log "Adding Yazi plugin packages..."
        ya pkg add "${missing_plugins[@]}" || status=1
    else
        success "Yazi plugin packages already listed"
    fi

    # Upgrade only our two packages, and only when upstream moved or files are
    # missing: `ya pkg upgrade` rewrites them even when nothing changed. The
    # manager preserves pinned revisions and refuses to discard local edits.
    # Never install/upgrade other entries.
    local outdated=()
    if [[ "$status" == 0 ]]; then
        while IFS= read -r package; do
            [[ -z "$package" ]] || outdated+=("$package")
        done < <(yazi_packages_to_upgrade "$package_file")
        if [[ ${#outdated[@]} -gt 0 ]]; then
            ya pkg upgrade "${outdated[@]}" || status=1
        else
            success "Yazi plugins already at their upstream revisions"
        fi
    fi
    keep_snapshot_if_changed "$package_file" "$snapshot"
    [[ "$status" == 0 ]] || return 1
    verify_yazi_assets || return 1
    local plugin_file required
    for plugin_file in "$HOME/.config/yazi/plugins/git.yazi/main.lua" "$HOME/.config/yazi/plugins/starship.yazi/main.lua"; do
        required=$(sed -nE 's/^--- @since ([0-9.]+).*/\1/p' "$plugin_file" | head -1)
        [[ -z "$required" ]] || require_version yazi "$required" || return 1
    done
    ya pkg list
    success "Yazi plugins installed"
}

################################################################################
# 16. VERIFICATION
################################################################################

verify_installation() {
    log "Verifying installation..."

    local checks_passed=0
    local checks_total=0

    check_cmd() {
        checks_total=$((checks_total + 1))
        if command_exists "$1"; then
            success "$1 installed"
            checks_passed=$((checks_passed + 1))
        else
            warning "$1 not found"
        fi
    }

    # A fourth argument names the binary to look for when it is not on PATH
    # (the Ghostty inside an app bundle or the Snap).
    check_versioned_cmd() {
        local name="$1" min_ver="$2" ver="$3" path="${4:-$1}"
        checks_total=$((checks_total + 1))
        if [[ "$path" == */* ]]; then
            [[ -x "$path" ]] || { warning "$name not found"; return; }
        elif ! command_exists "$path"; then
            warning "$name not found"
            return
        fi
        if [[ -z "$ver" ]]; then
            warning "$name version could not be detected"
            return
        fi
        if version_gte "$ver" "$min_ver"; then
            success "$name installed ($ver)"
            checks_passed=$((checks_passed + 1))
        else
            warning "$name version $ver < minimum $min_ver"
        fi
    }

    check_path() {
        checks_total=$((checks_total + 1))
        if [[ -e "$2" ]]; then
            success "$1 installed"
            checks_passed=$((checks_passed + 1))
        else
            warning "$1 not found"
        fi
    }

    check_versioned_cmd "zsh" "$MIN_ZSH_VERSION" \
        "$(zsh --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
    check_versioned_cmd "yazi" "$MIN_YAZI_VERSION" \
        "$(yazi --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"

    local item name minimum
    for item in "node:$NODE_VERSION" "pnpm:$PNPM_VERSION" "starship:$STARSHIP_VERSION" \
        fzf:0.74.3 zoxide:0.10.0 rg:15.2.0 fd:10.5.0 "ya:$MIN_YAZI_VERSION" \
        "nvim:$NEOVIM_VERSION" "lazygit:$LAZYGIT_VERSION" "tree-sitter:$TREE_SITTER_VERSION"; do
        name="${item%%:*}"; minimum="${item#*:}"
        check_versioned_cmd "$name" "$minimum" "$(tool_version "$name")"
    done
    check_versioned_cmd ghostty "$GHOSTTY_VERSION" "$(tool_version "$(ghostty_bin)")" "$(ghostty_bin)"
    if cmux_wanted; then
        check_path cmux "$(find_cmux || printf '/missing-cmux')"
    fi
    check_path 'Terminal rendering config' "$HOME/.config/ghostty/config"
    check_versioned_cmd "${HERDR_BIN:-herdr}" "$HERDR_VERSION" "$(tool_version "${HERDR_BIN:-herdr}")"

    check_path "Zinit" "$HOME/.local/share/zinit/zinit.git"
    check_path ".zshenv" "$HOME/.zshenv"
    check_path ".zshrc" "$HOME/.zshrc"
    check_path "Zinit plugin list" "$HOME/.zsh/zinit-update.zsh"
    check_path "Yazi init.lua" "$HOME/.config/yazi/init.lua"
    check_path "Yazi yazi.toml" "$HOME/.config/yazi/yazi.toml"
    check_path "Yazi theme.toml" "$HOME/.config/yazi/theme.toml"
    check_path "vi launcher" "$HOME/.local/bin/vi"
    check_path "Neovim launchers" "$HOME/.zsh/nvim.zsh"
    while IFS='|' read -r asset_name _; do
        check_path "Neovim config $asset_name" "$HOME/.config/$asset_name/init.lua"
    done < <(neovim_starters)
    while IFS='|' read -r asset_name asset_path; do
        [[ -n "$asset_name" ]] || continue
        check_path "$asset_name" "$asset_path"
    done < <(zinit_expected_assets)
    while IFS='|' read -r asset_name asset_path; do
        [[ -n "$asset_name" ]] || continue
        check_path "$asset_name" "$asset_path"
    done < <(yazi_expected_assets)

    check_versioned_cmd mosh-server 1.3.2 "$(tool_version mosh-server)"
    if [[ "$HERDR_READY" == true ]]; then
        check_path 'Attach helper' "$HOME/.local/bin/shell-backup-attach"
    fi

    local font_id family
    for font_id in $FONT_IDS; do
        checks_total=$((checks_total + 1))
        if font_installed "$font_id"; then
            success "Font $font_id installed"
            checks_passed=$((checks_passed + 1))
        else
            warning "Font $font_id missing or not at its pinned release"
        fi
    done
    if [[ "$OS_TYPE" == linux ]] && command_exists fc-list; then
        family=$(font_family)
        checks_total=$((checks_total + 1))
        if [[ -n "$(fc-list "$family" family 2>/dev/null)" ]]; then
            success "fontconfig resolves $family"
            checks_passed=$((checks_passed + 1))
        else
            warning "fontconfig does not list $family; run fc-cache -f"
        fi
        report_glyph_coverage
    fi
    local current_locale="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    if [[ "$(printf '%s' "$current_locale" | tr 'A-Z' 'a-z')" == *utf*8* ]] && \
       utf8_locale_available "$current_locale"; then
        log "Locale: $current_locale"
    else
        warning "Setup ran with locale '${current_locale:-unset}'; interactive and SSH zsh shells select a UTF-8 locale"
    fi

    log "Verification: $checks_passed/$checks_total checks passed"
    [[ "$checks_passed" == "$checks_total" ]]

}

################################################################################
# 17. POST-INSTALLATION SUMMARY
################################################################################

print_summary() {
    printf '\nSetup results (%s/%s):\n' "$OS_TYPE" "$ARCH"
    if [[ ${#RESULTS[@]} -gt 0 ]]; then
        printf '  %s\n' "${RESULTS[@]}"
    fi
    printf '\nVersions before setup:\n%s\n' "${VERSIONS_BEFORE:-not captured}"
    printf '\nVersions after setup:\n'
    version_inventory
    printf '\nLogs: %s\nBackups: %s\n' "$SETUP_LOG" "$BACKUP_DIR"
    printf '%s\n' 'Reload: exec zsh | Plugins: zinit list; ya pkg list' \
        "Terminal font: $(font_family) (switch: setup.sh --font=iosevka|jetbrains)" \
        'Local preferences: ~/.zshrc.local and ~/.config/ghostty/config.local' \
        'Neovim: vi opens NVIM_CONFIG (nvim-lazyvim or nvim-kickstart); lv, kv, nvims. Plugins install on first start' \
        'Any SSH/Mosh client: ssh -t <host> shell-backup-attach [session] (see README.md)' \
        'Client without Nerd Font: STARSHIP_CONFIG=~/.config/starship-plain.toml in ~/.zshrc.local'
    if [[ "$SETUP_FAILED" == true ]]; then
        warning 'Setup finished with failures or blocked requirements; review the results above'
    else
        success 'Setup finished; see skipped optional components above'
    fi
}

################################################################################
# 18. MAIN EXECUTION
################################################################################

main() {
    parse_args "$@"
    initialize_log

    # Warn if running as root (configs will go to root's $HOME)
    if [[ "$(id -u)" -eq 0 ]]; then
        warning "Running as root. Configuration files will be installed to root's home directory ($HOME)."
    fi

    log "=== SHELL-BACKUP: Setup Starting ==="

    detect_platform
    log "Detected system: $OS_TYPE ($ARCH) | Package manager: $PKG_MANAGER"

    check_prerequisites
    resolve_font_choice
    setup_package_manager
    ensure_user_local_bin_on_path
    export PATH="$HOME/.local/bin:/snap/bin:$PATH"
    VERSIONS_BEFORE=$(version_inventory)
    log 'Versions before setup:'
    printf '%s\n' "$VERSIONS_BEFORE" | tee -a "$SETUP_LOG"
    run_stage 'Core tools' install_core_tools
    run_stage 'UTF-8 locale' ensure_utf8_locale
    run_stage Starship install_starship
    run_stage Yazi install_yazi
    run_stage Neovim install_neovim
    run_stage 'Neovim tools' install_neovim_tools
    run_stage Ghostty install_ghostty
    if cmux_wanted; then
        run_stage cmux install_cmux
    elif [[ "$OS_TYPE" == darwin ]]; then
        record_result cmux skipped 'optional extra; pass --with-cmux'
    else
        record_result cmux skipped 'macOS only'
    fi
    setup_herdr
    run_stage Fonts install_fonts

    run_stage '.zshenv' deploy_zshenv
    run_stage '.zshrc' deploy_zshrc
    run_stage 'Terminal config' deploy_ghostty_config
    run_stage 'Yazi config' deploy_yazi_config
    run_stage 'Starship config' deploy_starship_config
    run_stage 'Custom functions' deploy_custom_functions
    run_stage 'Neovim launchers' deploy_neovim_launchers
    run_stage 'Neovim configs' setup_neovim_configs
    run_stage 'Git editor' configure_git_editor
    run_stage 'Default shell' setup_shell
    run_stage 'NVM / Node' setup_nvm
    # Activate NVM's selected default for subsequent verification in this shell.
    if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
        set +u
        if ! . "$HOME/.nvm/nvm.sh"; then
            record_result 'NVM activation' failed 'could not load installed NVM'
        fi
        set -u
    fi
    run_stage pnpm install_pnpm
    run_stage 'Zinit plugins' setup_zinit_plugins
    run_stage 'Yazi plugins' setup_yazi_plugins
    run_stage Verification verify_installation
    print_summary
    [[ "$SETUP_FAILED" != true ]]

}

# Run main function
if [[ "${BASH_SOURCE[0]:-}" == "$0" || -z "${BASH_SOURCE[0]:-}" ]]; then
    main "$@"
fi
