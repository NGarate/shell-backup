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
readonly JB_MONO_VERSION="2.304"
readonly YAZI_VERSION="26.9.1"

# Non-interactive flag (will be parsed after functions are defined)
NON_INTERACTIVE=false
WITH_HERDR=false
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
            --with-herdr) WITH_HERDR=true ;;
            --help|-h)
                printf '%s\n' 'Usage: setup.sh [--ci|--non-interactive] [--with-herdr]' \
                    'Linux: Ghostty + Herdr. macOS: cmux; --with-herdr opts into Herdr.'
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
    local url="$1" checksum="$2" destination="$3" actual
    [[ "$checksum" =~ ^[a-f0-9]{64}$ ]] || return 1
    retry curl -fL --silent --show-error --connect-timeout 15 --max-time 180 "$url" -o "$destination" || return 1
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
    local answer before
    if [[ -z "$HERDR_BIN" && "$OS_TYPE" == darwin && "$WITH_HERDR" != true ]]; then
        if can_prompt; then
            prompt_tty 'Install optional Herdr for mobile sessions? [y/N] '
            answer="$TTY_ANSWER"
            case "$answer" in y|Y|yes|si|sí) WITH_HERDR=true ;; esac
        fi
        if [[ "$WITH_HERDR" != true ]]; then
            record_result Herdr skipped 'optional macOS component; not selected'
            return 0
        fi
    fi
    before=""
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
    setup_herdr_integrations
}

configure_herdr_prefix() {
    # Keep this editor embedded so curl | bash remains self-contained.
    # No server commands: existing clients can reload config or reattach later.
    python3 - "${HERDR_CONFIG_PATH:-$HOME/.config/herdr/config.toml}" "$BACKUP_DIR" <<'HERDR_CONFIG_EOF'
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import tempfile

path = Path(sys.argv[1]).expanduser().resolve()
backup_dir = Path(sys.argv[2])
original = path.read_bytes() if path.exists() else b''
text = original.decode('utf-8')

# Restrict edits to ordinary TOML tables/scalar strings. Refuse ambiguous
# layouts instead of interpreting a table-looking line inside a string.
if '\"\"\"' in text or "'''" in text:
    sys.exit('Herdr prefix: multiline TOML strings require a manual prefix edit; file preserved.')
if re.search(r'''(?m)^\s*(?:keys|"keys"|'keys')\s*[.=]''', text):
    sys.exit('Herdr prefix: inline/dotted keys table requires a manual prefix edit; file preserved.')

newline = '\r\n' if '\r\n' in text else '\n'
lines = text.splitlines(keepends=True)
header = re.compile(r'''^\s*\[\s*(?:keys|"keys"|'keys')\s*\]\s*(?:#.*)?$''')
sections = [i for i, line in enumerate(lines) if header.fullmatch(line.rstrip('\r\n'))]
if len(sections) > 1:
    sys.exit('Herdr prefix: duplicate keys tables; file preserved.')
if sections:
    start = sections[0] + 1
    end = next((i for i in range(start, len(lines)) if lines[i].lstrip().startswith('[')), len(lines))
    assignment = re.compile(r'''^(\s*(?:prefix|"prefix"|'prefix')\s*=\s*)("(?:[^"\\\r\n]|\\.)*"|'[^'\r\n]*')([ \t]*(?:#[^\r\n]*)?)(\r?\n)?$''')
    candidates = [i for i in range(start, end)
                  if re.match(r'''^\s*(?:prefix|"prefix"|'prefix')\s*=''', lines[i])]
    if len(candidates) > 1:
        sys.exit('Herdr prefix: duplicate prefix entries; file preserved.')
    if candidates:
        i = candidates[0]
        match = assignment.fullmatch(lines[i])
        if not match:
            sys.exit('Herdr prefix: unsupported prefix value; file preserved.')
        if match[2] not in ('"ctrl+space"', "'ctrl+space'"):
            lines[i] = match[1] + '"ctrl+space"' + match[3] + (match[4] or '')
    else:
        if not lines[start - 1].endswith('\n'):
            lines[start - 1] += newline
        lines.insert(start, 'prefix = "ctrl+space"' + newline)
else:
    if text and not text.endswith('\n'):
        lines.append(newline)
    lines.extend([newline if text else '', '[keys]' + newline, 'prefix = "ctrl+space"' + newline])

updated = ''.join(lines).encode('utf-8')
if updated == original:
    print('Herdr prefix already set to ctrl+space; config preserved.')
    sys.exit(0)

# When provided by Python (3.11+), validate the entire document too.
try:
    import tomllib
except ImportError:
    pass
else:
    tomllib.loads(updated.decode('utf-8'))

path.parent.mkdir(parents=True, exist_ok=True)
if path.exists():
    backup_dir.mkdir(parents=True, exist_ok=True)
    fd, backup = tempfile.mkstemp(prefix='herdr-config.toml.backup.', dir=str(backup_dir))
    os.close(fd)
    shutil.copy2(str(path), backup)
    print('Herdr config backup: ' + backup)
fd, temporary = tempfile.mkstemp(prefix='.herdr-config-', dir=str(path.parent))
try:
    with os.fdopen(fd, 'wb') as output:
        output.write(updated)
    if path.exists():
        os.chmod(temporary, stat.S_IMODE(path.stat().st_mode))
    os.replace(temporary, str(path))
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
print('Herdr prefix saved as ctrl+space: ' + str(path))
HERDR_CONFIG_EOF
    log 'Herdr prefix: Ctrl+Space. Reload config in Herdr or reattach the client to apply.'
}

# Herdr 0.8.2 provides all four installers, but none of these four optional
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
    local target="$1" directory snapshot state
    # Re-check immediately before mutation, including selections made minutes ago.
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
    # Back up only files potentially edited by the official installer. Never
    # back up whole harness homes (credentials, sessions and projects live there).
    case "$target" in
        opencode) backup_file "$directory/tui.json"; backup_file "$directory/tui.jsonc" ;;
        hermes) backup_file "$directory/config.yaml" ;;
        codex) backup_file "$directory/config.toml"; backup_file "$directory/hooks.json" ;;
        claude) backup_file "$directory/settings.json" ;;
    esac
    if ! "$HERDR_BIN" integration install "$target" </dev/null; then
        record_result "Herdr/$target" failed 'official installer failed; retry requires a new selection'
        return 0
    fi
    if snapshot=$("$HERDR_BIN" integration status 2>/dev/null) && \
       [[ "$(integration_state "$target" "$snapshot")" == installed ]]; then
        record_result "Herdr/$target" installed 'verified by Herdr; restart the harness to load it'
    else
        record_result "Herdr/$target" failed 'post-install verification failed'
    fi
}

setup_herdr_integrations() {
    [[ "$HERDR_READY" == true ]] || return 0
    local snapshot target state choice token index found
    local pending=() selected=() tokens=()
    if ! snapshot=$("$HERDR_BIN" integration status 2>/dev/null); then
        record_result 'Herdr integrations' skipped 'state indeterminate; status command unavailable or failed'
        return 0
    fi
    for target in opencode hermes codex claude; do
        state=$(integration_state "$target" "$snapshot")
        case "$state" in
            missing) pending+=("$target") ;;
            installed) record_result "Herdr/$target" installed 'preserved' ;;
            incompatible) record_result "Herdr/$target" blocked 'existing integration outdated or needs repair; preserved' ;;
            *) record_result "Herdr/$target" skipped 'state indeterminate; preserved' ;;
        esac
    done
    [[ ${#pending[@]} -gt 0 ]] || return 0
    if ! can_prompt; then
        for target in "${pending[@]}"; do
            record_result "Herdr/$target" skipped 'non-interactive or no controlling terminal'
        done
        return 0
    fi
    local menu=$'Optional Herdr integrations (none selected):\n'
    for ((index=0; index<${#pending[@]}; index++)); do
        menu+="$((index+1))) ${pending[index]}"$'\n'
    done
    menu+=$'Enter numbers separated by spaces, all, or Enter/q to skip: '
    prompt_tty "$menu"
    choice="$TTY_ANSWER"
    case "$choice" in
        ''|q|Q|cancel) ;;
        all) selected=("${pending[@]}") ;;
        *)
            read -r -a tokens <<< "$choice"
            if [[ ${#tokens[@]} -gt 0 ]]; then
                for token in "${tokens[@]}"; do
                    if [[ ! "$token" =~ ^[1-4]$ ]] || ((token > ${#pending[@]})); then
                        selected=()
                        warning 'Invalid selection; no integrations selected'
                        break
                    fi
                    target="${pending[token-1]}"
                    found=false
                    if [[ ${#selected[@]} -gt 0 ]]; then
                        for state in "${selected[@]}"; do
                            [[ "$state" != "$target" ]] || found=true
                        done
                    fi
                    [[ "$found" == true ]] || selected+=("$target")
                done
            fi ;;
    esac
    for target in "${pending[@]}"; do
        found=false
        if [[ ${#selected[@]} -gt 0 ]]; then
            for state in "${selected[@]}"; do
                [[ "$state" != "$target" ]] || found=true
            done
        fi
        if [[ "$found" == true ]]; then
            install_herdr_integration "$target"
        else
            record_result "Herdr/$target" skipped 'not selected'
        fi
    done
}

font_version() {
    [[ -r "$1" ]] || return 0
    python3 - "$1" <<'FONT_VERSION_EOF'
import struct, sys
try:
    with open(sys.argv[1], 'rb') as stream:
        data = stream.read()
    count = struct.unpack_from('>H', data, 4)[0]
    for index in range(count):
        tag, _, offset, _ = struct.unpack_from('>4sIII', data, 12 + 16 * index)
        if tag == b'head':
            print('%.3f' % (struct.unpack_from('>I', data, offset + 4)[0] / 65536))
            break
except (OSError, struct.error):
    pass
FONT_VERSION_EOF
}

require_font_version() {
    local version
    version=$(font_version "$1")
    [[ -n "$version" ]] && version_gte "$version" "$JB_MONO_VERSION"
}

version_inventory() {
    local name version
    for name in git zsh fzf zoxide rg fd starship yazi ya pnpm node python3 ghostty; do
        version=$(tool_version "$name")
        printf '  %s: %s\n' "$name" "${version:-absent/unknown}"
    done
    if [[ -n "${HERDR_BIN:-}" ]]; then
        printf '  Herdr: %s (%s)\n' "$(tool_version "$HERDR_BIN")" "$HERDR_BIN"
    fi
    local asset path revision
    while IFS='|' read -r asset path; do
        revision=$(git -C "$path" rev-parse --short HEAD 2>/dev/null || true)
        printf '  %s: %s\n' "$asset" "${revision:-snippet/unavailable}"
    done < <(zinit_expected_assets)
    if [[ -f "$HOME/.local/share/zinit/zinit.git/VERSION" ]]; then
        printf '  Zinit: %s\n' "$(cat "$HOME/.local/share/zinit/zinit.git/VERSION")"
    fi
    if command_exists ya; then
        ya pkg list 2>/dev/null || true
    fi
    local package
    if [[ "$PKG_MANAGER" == apt ]]; then
        for package in zsh git curl ca-certificates file unzip tar build-essential fontconfig python3 \
            wl-clipboard xclip command-not-found snapd; do
            dpkg-query -W -f='  ${Package}: ${Version}\n' "$package" 2>/dev/null || true
        done
    elif command_exists brew; then
        brew list --versions git zsh fzf zoxide ripgrep fd starship yazi pnpm python 2>/dev/null || true
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

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        mkdir -p "$BACKUP_DIR"
        local backup_name="${BACKUP_DIR}/$(basename "$file").backup.${TIMESTAMP}"
        cp "$file" "$backup_name"
        success "Backed up $file to $backup_name"
    fi
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

################################################################################
# 5. CORE TOOL INSTALLATION
################################################################################

install_core_tools() {
    log "Installing core tools..."

    if [[ "$OS_TYPE" == "darwin" ]]; then
        # macOS via Homebrew
        # Format: "package_name:command_name" - if no colon, command_name = package_name
        local tools=("git" "zsh" "fzf" "zoxide" "ripgrep:rg" "fd:fd" "python:python3")
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
        local base_packages=(zsh git curl ca-certificates file unzip tar build-essential fontconfig python3)
        local extra_packages=(fzf zoxide ripgrep fd-find wl-clipboard xclip command-not-found)
        local available_extra_packages=()
        local base_tools_missing=false
        local extra_tools_missing=false
        local package

        if ! command_exists zsh || ! command_exists git || ! command_exists curl || \
           ! command_exists file || \
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

install_ghostty() {
    local before
    before=$(tool_version ghostty)
    if [[ -n "$before" ]] && version_gte "$before" "$GHOSTTY_VERSION"; then
        success "Ghostty retained ($before)"
        return 0
    fi
    if apt-cache show ghostty >/dev/null 2>&1; then
        run_with_sudo 'Ghostty apt installation' apt-get install -y ghostty || return 1
    else
        if ! command_exists snap; then
            run_with_sudo 'snapd prerequisite for Ghostty' apt-get install -y snapd || return 1
        fi
        if snap list ghostty >/dev/null 2>&1; then
            run_with_sudo 'Ghostty stable update' snap refresh ghostty --channel=latest/stable || return 1
        else
            run_with_sudo 'Ghostty installation' snap install ghostty --classic --channel=latest/stable || return 1
        fi
    fi
    require_version ghostty "$GHOSTTY_VERSION"
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
    log "Installing JetBrains Mono..."

    local font_dir
    if [[ "$OS_TYPE" == "darwin" ]]; then
        font_dir="$HOME/Library/Fonts"
    else
        font_dir="$HOME/.local/share/fonts"
    fi
    mkdir -p "$font_dir"

    local installed_font_version
    installed_font_version=$(font_version "$font_dir/JetBrainsMono-Regular.ttf")
    if [[ -n "$installed_font_version" ]] && version_gte "$installed_font_version" "$JB_MONO_VERSION"; then
        success "JetBrains Mono retained ($installed_font_version)"
        return 0
    fi
    log "Downloading JetBrains Mono..."

    if ! (
        local temp_dir
        temp_dir=$(mktemp -d)
        trap "rm -rf '$temp_dir'" EXIT

        local download_url="https://github.com/JetBrains/JetBrainsMono/releases/download/v${JB_MONO_VERSION}/JetBrainsMono-${JB_MONO_VERSION}.zip"

        if ! verified_download "$download_url" "6f6376c6ed2960ea8a963cd7387ec9d76e3f629125bc33d1fdcd7eb7012f7bbf" "$temp_dir/jetbrains-mono.zip"; then
            warning "JetBrains Mono download failed"
            exit 1
        fi

        log "Extracting fonts..."
        unzip -q "$temp_dir/jetbrains-mono.zip" -d "$temp_dir"

        # Copy only the required font variants (Regular, Bold, Italic, Bold Italic)
        log "Installing font files..."
        find "$temp_dir" -name "JetBrainsMono-*.ttf" -exec cp {} "$font_dir/" \;

        success "JetBrains Mono installed to $font_dir"
    ); then
        warning "JetBrains Mono installation failed"
        return 1
    fi

    require_font_version "$font_dir/JetBrainsMono-Regular.ttf" || return 1
    log "JetBrains Mono ${installed_font_version:-unknown/absent} -> $(font_version "$font_dir/JetBrainsMono-Regular.ttf")"

    # Linux: refresh font cache
    if [[ "$OS_TYPE" == "linux" ]] && command_exists fc-cache; then
        log "Refreshing font cache..."
        fc-cache -fv "$font_dir" &>/dev/null
        success "Font cache refreshed"
    fi
}

zinit_expected_assets() {
    printf '%s|%s\n' \
        "zinit plugin zsh-autosuggestions" "$HOME/.local/share/zinit/plugins/zsh-users---zsh-autosuggestions" \
        "zinit plugin zsh-syntax-highlighting" "$HOME/.local/share/zinit/plugins/zsh-users---zsh-syntax-highlighting" \
        "zinit plugin zsh-history-substring-search" "$HOME/.local/share/zinit/plugins/zsh-users---zsh-history-substring-search" \
        "zinit plugin omz-plugin-pnpm" "$HOME/.local/share/zinit/plugins/ntnyq---omz-plugin-pnpm" \
        "zinit plugin omz-plugin-bun" "$HOME/.local/share/zinit/plugins/ntnyq---omz-plugin-bun" \
        "zinit plugin zsh-you-should-use" "$HOME/.local/share/zinit/plugins/MichaelAquilina---zsh-you-should-use" \
        "zinit snippet OMZP::git" "$HOME/.local/share/zinit/snippets/OMZP::git" \
        "zinit snippet OMZP::bun" "$HOME/.local/share/zinit/snippets/OMZP::bun" \
        "zinit snippet OMZP::alias-finder" "$HOME/.local/share/zinit/snippets/OMZP::alias-finder"

    if [[ "$OS_TYPE" == "darwin" ]]; then
        printf '%s|%s\n' \
            "zinit snippet OMZP::command-not-found" "$HOME/.local/share/zinit/snippets/OMZP::command-not-found"
    fi
}

verify_zinit_assets() {
    local name path missing=0

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

    backup_file "$HOME/.zshenv"

    cat > "$HOME/.zshenv" << 'ZSHENV_EOF'
# ============================================================================
# ZSH Environment Configuration
# ============================================================================
# Keep this file lightweight: it is loaded by every zsh invocation, including
# non-interactive shells used by automation and helper scripts.

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

if command -v npm >/dev/null 2>&1; then
    node_global_root=$(npm root -g 2>/dev/null || true)
    if [[ -n "$node_global_root" ]] && [[ ":${NODE_PATH:-}:" != *":$node_global_root:"* ]]; then
        export NODE_PATH="${NODE_PATH:+$NODE_PATH:}$node_global_root"
    fi
fi

ZSHENV_EOF

    chmod 600 "$HOME/.zshenv"
    success ".zshenv deployed"
}

deploy_zshrc() {
    log "Deploying .zshrc configuration..."

    backup_file "$HOME/.zshrc"

    # Set platform-specific paths
    local pnpm_home

    if [[ "$OS_TYPE" == "darwin" ]]; then
        pnpm_home="${HOME}/Library/pnpm"
    else
        pnpm_home="${HOME}/.local/share/pnpm"
    fi

    cat > "$HOME/.zshrc" << 'ZSHRC_EOF'
# ============================================================================
# ZSH Configuration with Zinit Plugin Manager
# ============================================================================

# Fix for mosh not working
export LC_ALL="en_US.UTF-8"

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
# Environment Setup (NVM, etc.)
# ============================================================================

# Path to your nvm installation
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

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

# Command not found helper - suggests packages for missing commands
if [[ "$(uname -s)" == "Darwin" ]]; then
    zinit snippet OMZP::command-not-found
else
    # Linux: Use system command-not-found
    if [[ -f /usr/lib/command-not-found ]]; then
        command_not_found_handler() {
            /usr/lib/command-not-found -- "$1" || return 127
        }
    fi
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

# Optional OMZ helpers.
# `wait` keeps startup fast, `silent` suppresses normal output, and `notify""`
# only surfaces a message if the snippet fails to load.
for snippet in \
    OMZP::git \
    OMZP::bun \
    OMZP::alias-finder
do
    zinit ice wait lucid silent notify""
    zinit snippet "$snippet"
done

# You Should Use - reminds you of existing aliases
# pnpm support - aliases and completions (lazy loaded)
for plugin in \
    ntnyq/omz-plugin-pnpm \
    ntnyq/omz-plugin-bun \
    MichaelAquilina/zsh-you-should-use
do
    zinit ice wait lucid silent notify"" light-mode
    zinit light "$plugin"
done

# ============================================================================
# User Configuration
# ============================================================================

# Configure Git to use SSH instead of HTTPS (required for GitHub SSH keys)
# Only set if the SSH key exists (checked at shell startup)
[[ -f ~/.ssh/id_ed25519 ]] && export GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes"

# Custom git function - fuzzy switch branch
[[ -f ~/.zsh/gswf.zsh ]] && source ~/.zsh/gswf.zsh

# Yazi launcher - keep shell in the directory where Yazi exits
[[ -f ~/.zsh/y.zsh ]] && source ~/.zsh/y.zsh

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
# Package Manager Setup
# ============================================================================

# pnpm
export PNPM_HOME="PNPM_HOME_PLACEHOLDER"
case ":$PATH:" in
  *":$PNPM_HOME:") ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# User-local binaries (Yazi on Linux, Claude Code, etc.)
export PATH="$HOME/.local/bin:$PATH"

# ============================================================================
# Environment Variables
# ============================================================================

# Environment variables are loaded from ~/.zshenv (using only ~/.env) so they
# are available to both interactive shells and zsh-launched automation helpers.

# ============================================================================
# Auto-update Zinit plugins (once per day)
# ============================================================================

shell_backup_update_zinit() {
    local plugin failed=0
    zinit self-update -q || return 1
    for plugin in zsh-users/zsh-autosuggestions zsh-users/zsh-syntax-highlighting zsh-users/zsh-history-substring-search ntnyq/omz-plugin-pnpm ntnyq/omz-plugin-bun MichaelAquilina/zsh-you-should-use OMZP::git OMZP::bun OMZP::alias-finder; do
        zinit update -q "$plugin" || failed=1
    done
    if [[ "$(uname -s)" == Darwin ]]; then
        zinit update -q OMZP::command-not-found || failed=1
    fi
    return "$failed"
}

# Check for updates once per day using a timestamp file.
# The installer sets SHELL_BACKUP_SKIP_ZINIT_AUTO_UPDATE=1 to avoid racing a
# background update while it is still provisioning plugins.
if [[ -z "${SHELL_BACKUP_SKIP_ZINIT_AUTO_UPDATE:-}" ]] && command -v zinit >/dev/null 2>&1; then
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
                    if shell_backup_update_zinit; then
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

    # Replace placeholders (OS-specific sed syntax)
    if [[ "$OS_TYPE" == "darwin" ]]; then
        sed -i '' "s|PNPM_HOME_PLACEHOLDER|$pnpm_home|g" "$HOME/.zshrc"
    else
        sed -i "s|PNPM_HOME_PLACEHOLDER|$pnpm_home|g" "$HOME/.zshrc"
    fi

    chmod 600 "$HOME/.zshrc"
    success ".zshrc deployed"
}

deploy_ghostty_config() {
    log "Deploying Ghostty configuration..."

    mkdir -p "$HOME/.config/ghostty"
    
    backup_file "$HOME/.config/ghostty/config"

    # Platform-specific fullscreen keybinding
    local fullscreen_keybind
    local platform_config
    if [[ "$OS_TYPE" == "darwin" ]]; then
        fullscreen_keybind="keybind = cmd+shift+f=toggle_fullscreen"
        platform_config=$'# Shared rendering configuration read by cmux.\nfont-thicken = true'
    else
        fullscreen_keybind="keybind = alt+shift+f=toggle_fullscreen"
        platform_config="# Linux: Ghostty state restore is macOS-only, so no window-save-state is set."
    fi

    cat > "$HOME/.config/ghostty/config" << GHOSTTY_EOF
# Font configuration
font-family = JetBrains Mono
font-size = 13.5
font-feature = +calt

${platform_config}
shell-integration = detect

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

    chmod 644 "$HOME/.config/ghostty/config"
    success "Ghostty configuration deployed"
}

################################################################################
# 8. YAZI CONFIGURATION
################################################################################

deploy_yazi_config() {
    log "Deploying Yazi configuration..."

    mkdir -p "$HOME/.config/yazi"

    backup_file "$HOME/.config/yazi/init.lua"
    backup_file "$HOME/.config/yazi/yazi.toml"
    backup_file "$HOME/.config/yazi/theme.toml"

    # Remove the previously generated keymap override so files keep Yazi's
    # native direct opener behavior. Directory editor selection is handled via
    # [open] rules below and existing default keybindings.
    if [[ -f "$HOME/.config/yazi/keymap.toml" ]] && grep -q 'Open selected/hovered with editor' "$HOME/.config/yazi/keymap.toml"; then
        backup_file "$HOME/.config/yazi/keymap.toml"
        rm -f "$HOME/.config/yazi/keymap.toml"
        success "Removed generated Yazi keymap override"
    fi

    cat > "$HOME/.config/yazi/init.lua" << 'YAZI_INIT_EOF'
require("git"):setup {
    order = 1500,
}

require("starship"):setup()
YAZI_INIT_EOF

    cat > "$HOME/.config/yazi/yazi.toml" << 'YAZI_TOML_EOF'
[[plugin.prepend_fetchers]]
url = "*"
run = "git"
group = "git"

[[plugin.prepend_fetchers]]
url = "*/"
run = "git"
group = "git"
YAZI_TOML_EOF

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

    if [[ ${#dev_openers[@]} -gt 0 ]]; then
        {
            printf '\n[opener]\n'
            printf 'dev_open = [\n'
            printf '%s\n' "${dev_openers[@]}"
            printf ']\n\n'
            cat << 'YAZI_OPEN_RULES_EOF'
[open]
prepend_rules = [
    { url = "*/", use = "dev_open" },
]
YAZI_OPEN_RULES_EOF
        } >> "$HOME/.config/yazi/yazi.toml"
    else
        warning "No GUI editor CLI found for Yazi dev opener (checked: code, codium, cursor, zed)"
    fi

    cat > "$HOME/.config/yazi/theme.toml" << 'YAZI_THEME_EOF'
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

    chmod 644 "$HOME/.config/yazi/init.lua" "$HOME/.config/yazi/yazi.toml" "$HOME/.config/yazi/theme.toml"
    success "Yazi configuration deployed"
}

################################################################################
# 9. STARSHIP CONFIGURATION
################################################################################

deploy_starship_config() {
    log "Deploying Starship configuration..."

    mkdir -p "$HOME/.config"

    cat > "$HOME/.config/starship.toml" << 'STARSHIP_EOF'
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

    chmod 644 "$HOME/.config/starship.toml"
    success "Starship config deployed"
}

################################################################################
# 10. CUSTOM FUNCTIONS
################################################################################

deploy_custom_functions() {
    log "Deploying custom functions..."

    mkdir -p "$HOME/.zsh"

    cat > "$HOME/.zsh/gswf.zsh" << 'GSWF_EOF'
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
        branch=$(printf '%s\n' "$filtered" | fzf --query "$query" --preview 'git log -n 20 --color --oneline {}') || return 0
        if [[ -z "$branch" ]]; then
            return 0
        fi
    fi

    git switch -- "$branch"
}
GSWF_EOF
    chmod 644 "$HOME/.zsh/gswf.zsh"
    success "gswf.zsh function deployed"

    cat > "$HOME/.zsh/y.zsh" << 'Y_EOF'
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
    chmod 644 "$HOME/.zsh/y.zsh"
    success "y.zsh function deployed"
}

################################################################################
# 11. SHELL SETUP
################################################################################

setup_shell() {
    log "Setting up zsh as default shell..."

    # Make zsh default shell
    local zsh_path
    zsh_path=$(get_zsh_path)

    # Check if zsh is already the default (handle different path formats)
    if [[ "${SHELL:-}" == *"zsh"* ]]; then
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
# 12. NVM SETUP
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
# 13. ZINIT PLUGINS SETUP
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

        zinit light zsh-users/zsh-autosuggestions
        zinit light zsh-users/zsh-syntax-highlighting
        zinit light zsh-users/zsh-history-substring-search

        for snippet in OMZP::git OMZP::bun OMZP::alias-finder; do
            zinit ice silent
            zinit snippet "$snippet" >/dev/null
        done

        if [[ "$(uname -s)" == "Darwin" ]]; then
            zinit ice silent
            zinit snippet OMZP::command-not-found >/dev/null
        fi

        for plugin in ntnyq/omz-plugin-pnpm ntnyq/omz-plugin-bun MichaelAquilina/zsh-you-should-use; do
            zinit ice silent light-mode
            zinit light "$plugin" >/dev/null
        done

        zinit self-update -q || exit 1
        for plugin in zsh-users/zsh-autosuggestions zsh-users/zsh-syntax-highlighting zsh-users/zsh-history-substring-search ntnyq/omz-plugin-pnpm ntnyq/omz-plugin-bun MichaelAquilina/zsh-you-should-use OMZP::git OMZP::bun OMZP::alias-finder; do
            zinit update -q "$plugin" || exit 1
        done
        if [[ "$(uname -s)" == Darwin ]]; then
            zinit update -q OMZP::command-not-found || exit 1
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
# 14. YAZI PLUGINS SETUP
################################################################################

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

    backup_file "$package_file"

    if [[ ! -f "$package_file" ]] || ! grep -qE 'use[[:space:]]*=[[:space:]]*"yazi-rs/plugins:git"' "$package_file"; then
        missing_plugins+=("yazi-rs/plugins:git")
    fi

    if [[ ! -f "$package_file" ]] || ! grep -qE 'use[[:space:]]*=[[:space:]]*"Rolv-Apneseth/starship"' "$package_file"; then
        missing_plugins+=("Rolv-Apneseth/starship")
    fi

    if [[ ${#missing_plugins[@]} -gt 0 ]]; then
        log "Adding Yazi plugin packages..."
        ya pkg add "${missing_plugins[@]}"
    else
        success "Yazi plugin packages already listed"
    fi

    # Upgrade only our two packages. The manager preserves pinned revisions
    # and refuses to discard local edits. Never install/upgrade other entries.
    ya pkg upgrade yazi-rs/plugins:git Rolv-Apneseth/starship || return 1
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
# 15. VERIFICATION
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

    check_versioned_cmd() {
        local name="$1" min_ver="$2" ver="$3"
        checks_total=$((checks_total + 1))
        if ! command_exists "$name"; then
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
        fzf:0.74.3 zoxide:0.10.0 rg:15.2.0 fd:10.5.0 "ya:$MIN_YAZI_VERSION"; do
        name="${item%%:*}"; minimum="${item#*:}"
        check_versioned_cmd "$name" "$minimum" "$(tool_version "$name")"
    done
    if [[ "$OS_TYPE" == linux ]]; then
        check_versioned_cmd ghostty "$GHOSTTY_VERSION" "$(tool_version ghostty)"
    else
        check_path cmux "$(find_cmux || printf '/missing-cmux')"
    fi
    check_path 'Terminal rendering config' "$HOME/.config/ghostty/config"
    if [[ "$OS_TYPE" == linux || "$HERDR_READY" == true || "$WITH_HERDR" == true ]]; then
        check_versioned_cmd "${HERDR_BIN:-herdr}" "$HERDR_VERSION" "$(tool_version "${HERDR_BIN:-herdr}")"
    fi

    check_path "Zinit" "$HOME/.local/share/zinit/zinit.git"
    check_path ".zshenv" "$HOME/.zshenv"
    check_path ".zshrc" "$HOME/.zshrc"
    check_path "Yazi init.lua" "$HOME/.config/yazi/init.lua"
    check_path "Yazi yazi.toml" "$HOME/.config/yazi/yazi.toml"
    check_path "Yazi theme.toml" "$HOME/.config/yazi/theme.toml"
    while IFS='|' read -r asset_name asset_path; do
        [[ -n "$asset_name" ]] || continue
        check_path "$asset_name" "$asset_path"
    done < <(zinit_expected_assets)
    while IFS='|' read -r asset_name asset_path; do
        [[ -n "$asset_name" ]] || continue
        check_path "$asset_name" "$asset_path"
    done < <(yazi_expected_assets)

    # Font check
    local font_dir
    if [[ "$OS_TYPE" == "darwin" ]]; then
        font_dir="$HOME/Library/Fonts"
    else
        font_dir="$HOME/.local/share/fonts"
    fi
    checks_total=$((checks_total + 1))
    if require_font_version "$font_dir/JetBrainsMono-Regular.ttf"; then
        success "JetBrains Mono installed"
        checks_passed=$((checks_passed + 1))
    else
        warning "JetBrains Mono not found"
    fi

    log "Verification: $checks_passed/$checks_total checks passed"
    [[ "$checks_passed" == "$checks_total" ]]

}

################################################################################
# 16. POST-INSTALLATION SUMMARY
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
        'Local preferences: ~/.zshrc.local and ~/.config/ghostty/config.local' \
        'Mobile: TermRover -> SSH/Mosh host -> Herdr session (see README.md)'
    if [[ "$SETUP_FAILED" == true ]]; then
        warning 'Setup finished with failures or blocked requirements; review the results above'
    else
        success 'Setup finished; see skipped optional components above'
    fi
}

################################################################################
# 17. MAIN EXECUTION
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
    setup_package_manager
    ensure_user_local_bin_on_path
    export PATH="$HOME/.local/bin:/snap/bin:$PATH"
    VERSIONS_BEFORE=$(version_inventory)
    log 'Versions before setup:'
    printf '%s\n' "$VERSIONS_BEFORE" | tee -a "$SETUP_LOG"
    run_stage 'Core tools' install_core_tools
    run_stage Starship install_starship
    run_stage Yazi install_yazi
    if [[ "$OS_TYPE" == darwin ]]; then
        run_stage cmux install_cmux
        record_result Ghostty skipped 'macOS uses cmux; shared rendering config is deployed'
    else
        run_stage Ghostty install_ghostty
        record_result cmux skipped 'Linux uses Ghostty'
    fi
    setup_herdr
    run_stage Fonts install_fonts

    run_stage '.zshenv' deploy_zshenv
    run_stage '.zshrc' deploy_zshrc
    run_stage 'Terminal config' deploy_ghostty_config
    run_stage 'Yazi config' deploy_yazi_config
    run_stage 'Starship config' deploy_starship_config
    run_stage 'Custom functions' deploy_custom_functions
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
