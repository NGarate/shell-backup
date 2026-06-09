#!/bin/bash

################################################################################
# SHELL-BACKUP: Development Environment Setup
# Supports: macOS Apple Silicon (arm64), Ubuntu/Debian Linux (amd64/arm64)
# Version: 2.1.0
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
readonly MIN_ZSH_VERSION="5.8"
readonly MIN_YAZI_VERSION="26.5.6"

# Tool versions
readonly NVM_INSTALL_VERSION="0.40.1"
readonly JB_MONO_VERSION="2.304"
readonly YAZI_VERSION="26.5.6"

# Non-interactive flag (will be parsed after functions are defined)
NON_INTERACTIVE=false

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

# Parse command line arguments (after functions are defined)
for arg in "$@"; do
    case "$arg" in
        --ci|--non-interactive)
            NON_INTERACTIVE=true
            log "Running in non-interactive mode"
            ;;
    esac
done

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
    elif [[ -t 0 ]] && [[ "$NON_INTERACTIVE" != true ]]; then
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

    # GNU sort supports -V, BSD sort (macOS default) does not.
    if sort -V </dev/null >/dev/null 2>&1; then
        printf '%s\n%s\n' "$v2" "$v1" | sort -V -C
        return
    fi

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

    if ! command_exists curl && ! command_exists wget; then
        error "Neither curl nor wget found. Please install one of them."
    fi
    success "curl/wget available"

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
        local tools=("git" "zsh" "fzf" "zoxide" "ripgrep:rg" "fd:fd")
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
        local base_packages=(zsh git curl file unzip build-essential fontconfig)
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

    success "Core tools installed"
}

install_pnpm() {
    log "Installing pnpm..."

    local version

    if [[ "$OS_TYPE" == "darwin" ]]; then
        if ! brew_install_or_upgrade pnpm pnpm; then
            return 1
        fi
    else
        if command_exists apt-cache && apt-cache show pnpm &>/dev/null; then
            log "Installing/updating pnpm via apt..."
            if ! run_with_sudo "pnpm apt package installation" apt-get install -y -qq pnpm; then
                warning "pnpm installation via apt failed. Re-run with interactive sudo if pnpm is missing."
                return 1
            fi
        elif command_exists corepack; then
            log "Installing/updating pnpm via Corepack..."
            if ! corepack enable >/dev/null 2>&1 || ! corepack prepare pnpm@latest --activate; then
                warning "pnpm setup via Corepack failed"
                if command_exists npm; then
                    warning "Falling back to npm global pnpm installation"
                    if ! npm install -g pnpm; then
                        warning "pnpm installation via npm failed"
                        return 1
                    fi
                else
                    return 1
                fi
            fi
        elif command_exists pnpm; then
            success "pnpm already installed ($(pnpm --version 2>/dev/null || true))"
            return 0
        elif command_exists npm; then
            warning "corepack not found; installing pnpm globally with npm"
            if ! npm install -g pnpm; then
                warning "pnpm installation via npm failed"
                return 1
            fi
        else
            warning "pnpm is not available from apt and neither corepack nor npm is installed"
            return 1
        fi
    fi

    version=$(pnpm --version 2>/dev/null || true)
    if [[ -z "$version" ]]; then
        warning "pnpm installation completed, but pnpm was not found in PATH"
        return 1
    fi

    success "pnpm installed ($version)"
}

install_starship() {
    log "Installing Starship..."

    if [[ "$OS_TYPE" == "darwin" ]]; then
        brew_install_or_upgrade starship starship
        return 0
    fi

    if command_exists starship; then
        success "Starship already installed ($(starship --version | head -1))"
        return 0
    fi

    # Linux: install to ~/.local/bin to avoid sudo prompts in non-interactive runs.
    ensure_user_local_bin_on_path
    (
        local temp_dir
        temp_dir=$(mktemp -d)
        trap "rm -rf '$temp_dir'" EXIT

        if ! retry curl -fsSL https://starship.rs/install.sh -o "$temp_dir/starship-install.sh"; then
            error "Failed to download Starship installer"
        fi

        sh "$temp_dir/starship-install.sh" -y -b "$HOME/.local/bin"
    )

    success "Starship installed"
}

install_yazi() {
    log "Installing Yazi..."

    if [[ "$OS_TYPE" == "linux" ]]; then
        ensure_user_local_bin_on_path
    fi

    local installed_version
    installed_version=$(yazi --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)

    if [[ "$OS_TYPE" != "darwin" ]] && command_exists yazi && command_exists ya && [[ -n "$installed_version" ]] && version_gte "$installed_version" "$MIN_YAZI_VERSION"; then
        success "Yazi already installed ($installed_version)"
        return 0
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        brew_install_or_upgrade yazi yazi
    else
        local target
        case "$ARCH" in
            amd64)
                target="x86_64-unknown-linux-gnu"
                ;;
            arm64)
                target="aarch64-unknown-linux-gnu"
                ;;
            *)
                error "Unsupported Linux architecture for Yazi release install: $ARCH"
                ;;
        esac

        (
            local download_url="https://github.com/sxyazi/yazi/releases/download/v${YAZI_VERSION}/yazi-${target}.zip"
            local temp_dir
            temp_dir=$(mktemp -d)
            trap "rm -rf '$temp_dir'" EXIT

            log "Downloading Yazi ${YAZI_VERSION}..."
            if ! retry curl -fsSL "$download_url" -o "$temp_dir/yazi.zip"; then
                error "Failed to download Yazi ${YAZI_VERSION}"
            fi

            log "Installing Yazi binaries..."
            unzip -q "$temp_dir/yazi.zip" -d "$temp_dir"
            ensure_user_local_bin_on_path
            cp "$temp_dir/yazi-${target}/yazi" "$HOME/.local/bin/yazi"
            cp "$temp_dir/yazi-${target}/ya" "$HOME/.local/bin/ya"
            chmod 755 "$HOME/.local/bin/yazi" "$HOME/.local/bin/ya"
        )
    fi

    installed_version=$(yazi --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
    if ! command_exists yazi || ! command_exists ya || [[ -z "$installed_version" ]] || ! version_gte "$installed_version" "$MIN_YAZI_VERSION"; then
        error "Yazi ${MIN_YAZI_VERSION}+ and matching ya CLI are required"
    fi

    success "Yazi installed ($installed_version)"
}

install_ghostty() {
    log "Installing Ghostty..."

    if [[ "$OS_TYPE" == "darwin" ]]; then
        brew_install_or_upgrade ghostty ghostty
        return 0
    fi

    if command_exists ghostty; then
        success "Ghostty already installed"
        return 0
    fi

    # Ubuntu: use snap for Ghostty
    if command_exists snap; then
        run_with_sudo "Ghostty snap installation" snap install ghostty --classic || {
            warning "Ghostty snap installation failed. You may need to install it manually."
            return 1
        }
    else
        warning "snap not found. Please install snapd: sudo apt install snapd"
        return 1
    fi

    success "Ghostty installed"
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

    # Check if JetBrains Mono is already installed
    if find "$font_dir" -maxdepth 1 \( -name "JetBrainsMono*.ttf" -o -name "JetBrainsMono*.otf" \) 2>/dev/null | grep -q .; then
        success "JetBrains Mono already installed"
        return 0
    fi

    log "Downloading JetBrains Mono..."

    if ! (
        local temp_dir
        temp_dir=$(mktemp -d)
        trap "rm -rf '$temp_dir'" EXIT

        local download_url="https://github.com/JetBrains/JetBrainsMono/releases/download/v${JB_MONO_VERSION}/JetBrainsMono-${JB_MONO_VERSION}.zip"

        if ! retry curl -fsSL "$download_url" -o "$temp_dir/jetbrains-mono.zip"; then
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
                    if zinit self-update -q && zinit update --all -q; then
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
        platform_config=$'# macOS UI state restore: windows, tabs, splits, and working directories.\n# This does not resurrect running shell processes or command output.\nwindow-save-state = always\n\n# macOS specific\nfont-thicken = true'
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
    local branches
    branches=$(
        git pull --quiet 2>/dev/null;
        git branch --all \
        | grep -v 'HEAD' \
        | sed 's/^[* ]*//' \
        | sed 's|^remotes/[^/]*/||' \
        | sort -u
    )

    local filtered
    if [[ -n "$query" ]]; then
        filtered=$(echo "$branches" | grep -iF -- "$query" || true)
    else
        filtered="$branches"
    fi

    local count
    if [[ -z "$filtered" ]]; then
        count=0
    else
        count=$(echo "$filtered" | wc -l | tr -d ' ')
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
        branch=$(echo "$filtered" | fzf --query "$query" --preview 'git log -n 20 --color --oneline {}')
        if [[ -z "$branch" ]]; then
            return 0
        fi
    fi

    git switch "$branch"
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
    elif [[ ! -t 0 ]] || [[ "$NON_INTERACTIVE" == true ]]; then
        # Non-interactive: skip chsh to avoid hang (tty check OR explicit flag)
        warning "Non-interactive mode detected. Skipping 'chsh' (would prompt for password)."
        warning "To change shell manually, run: chsh -s $zsh_path"
    else
        log "Changing default shell to $zsh_path..."
        chsh -s "$zsh_path"
        success "Default shell changed to zsh"
    fi
}

################################################################################
# 12. NVM SETUP
################################################################################

setup_nvm() {
    log "Setting up NVM (Node Version Manager)..."

    export NVM_DIR="$HOME/.nvm"
    local restore_nounset=false

    if [[ ! -d "$NVM_DIR" ]]; then
        log "Installing NVM..."
        (
            local temp_dir
            temp_dir=$(mktemp -d)
            trap "rm -rf '$temp_dir'" EXIT

            if ! retry curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_INSTALL_VERSION}/install.sh" -o "$temp_dir/nvm-install.sh"; then
                error "Failed to download NVM installer"
            fi

            bash "$temp_dir/nvm-install.sh"
        )
    else
        success "NVM already installed"
    fi

    if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
        error "NVM installation is incomplete: $NVM_DIR/nvm.sh not found"
    fi

    # nvm.sh is not nounset-safe, so temporarily relax `set -u` while sourcing
    # it and running the initial `nvm` commands.
    if [[ -o nounset ]]; then
        set +u
        restore_nounset=true
    fi

    # Source NVM for current session
    # shellcheck disable=SC1090
    \. "$NVM_DIR/nvm.sh"

    if ! command -v nvm >/dev/null 2>&1; then
        error "Failed to load NVM from $NVM_DIR/nvm.sh"
    fi

    local installed_lts_version current_version latest_lts_version package_source_version node_version_after
    installed_lts_version=$(nvm version 'lts/*' 2>/dev/null || echo "N/A")
    current_version=$(nvm current 2>/dev/null || echo "none")
    latest_lts_version=$(nvm ls-remote --lts 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | tail -1 || true)
    package_source_version=""

    if [[ "$installed_lts_version" != "N/A" ]]; then
        package_source_version="$installed_lts_version"
    elif [[ "$current_version" == v* ]]; then
        package_source_version="$current_version"
    fi

    if [[ -z "$latest_lts_version" ]]; then
        if [[ "$installed_lts_version" == "N/A" ]]; then
            warning "Could not determine latest remote Node LTS. Falling back to nvm install --lts."
            nvm install --lts
        else
            warning "Could not determine latest remote Node LTS. Keeping installed LTS $installed_lts_version."
        fi
    elif [[ "$installed_lts_version" == "$latest_lts_version" ]]; then
        success "Latest Node LTS already installed ($installed_lts_version)"
    elif [[ -n "$package_source_version" ]]; then
        warning "Node LTS will change from ${installed_lts_version} to ${latest_lts_version}. Global npm packages will be reinstalled from ${package_source_version} where possible."
        nvm install "$latest_lts_version" --reinstall-packages-from="$package_source_version"
    else
        log "Installing latest Node LTS via NVM ($latest_lts_version)..."
        nvm install "$latest_lts_version"
    fi

    nvm alias default 'lts/*' >/dev/null 2>&1 || true
    nvm use --lts >/dev/null

    if [[ "$restore_nounset" == true ]]; then
        set -u
    fi

    if ! command -v node >/dev/null 2>&1; then
        error "Node LTS is still unavailable after NVM setup"
    fi

    node_version_after=$(node --version)
    if [[ -n "$package_source_version" ]] && [[ "$package_source_version" != "$node_version_after" ]]; then
        success "NVM and latest Node LTS active ($node_version_after)"
        warning "Node changed from $package_source_version to $node_version_after. Review global packages with: npm list -g --depth=0"
    else
        success "NVM and Node LTS installed ($node_version_after)"
    fi
}

################################################################################
# 13. ZINIT PLUGINS SETUP
################################################################################

setup_zinit_plugins() {
    log "Setting up Zinit plugins..."

    # First, ensure zinit is installed
    if [[ ! -f $HOME/.local/share/zinit/zinit.git/zinit.zsh ]]; then
        log "Installing Zinit plugin manager..."
        command mkdir -p "$HOME/.local/share/zinit" && command chmod g-rwX "$HOME/.local/share/zinit"
        if ! retry git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git"; then
            error "Failed to install Zinit plugin manager"
        fi
    fi

    if verify_zinit_assets; then
        success "Zinit plugins already installed"
        return 0
    fi

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

        exit 0
    '; then
        error "Zinit plugin bootstrap failed"
    fi

    if ! verify_zinit_assets; then
        error "Zinit plugin bootstrap incomplete"
    fi

    success "Zinit plugins installed"
}

################################################################################
# 14. YAZI PLUGINS SETUP
################################################################################

setup_yazi_plugins() {
    log "Setting up Yazi plugins..."

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

    if [[ ${#missing_plugins[@]} -gt 0 ]] || ! verify_yazi_assets; then
        log "Installing locked Yazi plugin packages..."
        ya pkg install
    else
        success "Yazi plugin assets already installed"
    fi

    if ! verify_yazi_assets; then
        error "Yazi plugin bootstrap incomplete"
    fi

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

    check_cmd "node"
    check_cmd "pnpm"
    check_cmd "starship"
    check_cmd "fzf"
    check_cmd "ghostty"
    check_cmd "ya"

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
    if find "$font_dir" -maxdepth 1 \( -name "JetBrainsMono*.ttf" -o -name "JetBrainsMono*.otf" \) 2>/dev/null | grep -q .; then
        success "JetBrains Mono installed"
        checks_passed=$((checks_passed + 1))
    else
        warning "JetBrains Mono not found"
    fi

    log "Verification: $checks_passed/$checks_total checks passed"
}

################################################################################
# 16. POST-INSTALLATION SUMMARY
################################################################################

print_summary() {
    cat << 'SUMMARY_EOF'

═══════════════════════════════════════════════════════════════════════════════
                           ✓ SETUP COMPLETE
═══════════════════════════════════════════════════════════════════════════════

Installed Components:
  ✓ zsh (default shell)
  ✓ Zinit plugin manager (9 plugins)
  ✓ Ghostty terminal with tabs and splits
  ✓ Starship modern prompt
  ✓ Yazi file manager with git + Starship plugins and Starship-matched theme
  ✓ fzf, zoxide, ripgrep, fd
  ✓ NVM + Node.js LTS
  ✓ pnpm package manager
  ✓ JetBrains Mono font
  ✓ Auto-update on shell startup (once per day)
  ✓ Custom functions (gswf, y)

Quick Start:
  1. Close and reopen your terminal (or: exec zsh)
  2. Test shell: zinit plugins
  3. Try git alias: ga status
  4. Try pnpm shortcut: p --version
  5. Try Yazi: yazi
  6. Try fuzzy finder: Ctrl+T in file path

Useful Commands:
  - View plugins: zinit plugins
  - View plugin report: zinit report
  - View Yazi plugins: ya pkg list

Documentation & Logs:
  - Installation log: ~/.setup.log
  - Backup configs: ~/.backup/
  - Repository: https://github.com/ngarate/shell-backup
  - Troubleshooting: See TROUBLESHOOTING.md in repo

═══════════════════════════════════════════════════════════════════════════════

SUMMARY_EOF
}

################################################################################
# 17. MAIN EXECUTION
################################################################################

main() {
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
    install_core_tools
    install_starship
    install_yazi
    install_ghostty || true
    install_fonts || true

    deploy_zshenv
    deploy_zshrc
    deploy_ghostty_config
    deploy_yazi_config
    deploy_starship_config
    deploy_custom_functions

    setup_shell
    setup_nvm
    install_pnpm || true
    setup_zinit_plugins
    setup_yazi_plugins

    verify_installation

    print_summary

    log "=== SHELL-BACKUP: Setup Complete ==="
    success "All done!"
}

# Run main function
main
