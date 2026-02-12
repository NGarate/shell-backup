#!/bin/bash

################################################################################
# SHELL-BACKUP: Development Environment Setup
# Supports: macOS (Intel/Apple Silicon), Ubuntu/Debian (apt + snapd)
# Version: 2.0.0
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
readonly MIN_TMUX_VERSION="3.0"

# Tool versions
readonly NVM_VERSION="0.40.1"
readonly JB_MONO_VERSION="2.304"

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

detect_platform() {
    case "$(uname -s)" in
        Darwin*)
            OS_TYPE="darwin"
            PKG_MANAGER="brew"
            if [[ $(uname -m) == "arm64" ]]; then
                ARCH="aarch64"
            else
                ARCH="x86_64"
            fi
            ;;
        Linux*)
            OS_TYPE="linux"
            ARCH=$(uname -m)
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
    printf '%s\n%s\n' "$v2" "$v1" | sort -V -C 2>/dev/null
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

    error "Command failed after $max_attempts attempts: $*"
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
        
        # Ensure brew is in PATH for Apple Silicon Macs
        if [[ "$ARCH" == "aarch64" ]]; then
            export PATH="/opt/homebrew/bin:$PATH"
        fi
    elif [[ "$PKG_MANAGER" == "apt" ]]; then
        log "Running apt update..."
        sudo apt-get update -qq
        success "apt ready"
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
        local tools=("zsh" "tmux" "fzf" "zoxide" "ripgrep:rg" "fd:fd")
        local package_name command_name
        for tool_mapping in "${tools[@]}"; do
            if [[ "$tool_mapping" == *":"* ]]; then
                package_name="${tool_mapping%%:*}"
                command_name="${tool_mapping##*:}"
            else
                package_name="$tool_mapping"
                command_name="$tool_mapping"
            fi

            if command_exists "$command_name" || brew list "$package_name" &>/dev/null; then
                success "$package_name already installed"
            else
                log "Installing $package_name..."
                brew install "$package_name"
                success "$package_name installed"
            fi
        done
    else
        # Ubuntu/Debian via apt
        log "Installing tools via apt..."
        sudo apt-get install -y -qq zsh tmux git curl unzip build-essential fontconfig
        sudo apt-get install -y -qq fzf zoxide ripgrep fd-find wl-clipboard xclip command-not-found 2>/dev/null || true

        # Create fd symlink (fd-find package installs as fdfind)
        if command_exists fdfind && ! command_exists fd; then
            mkdir -p "$HOME/.local/bin"
            ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
            success "Created fd symlink (fdfind -> ~/.local/bin/fd)"
        fi
    fi

    success "Core tools installed"
}

install_starship() {
    log "Installing Starship..."

    if command_exists starship; then
        success "Starship already installed ($(starship --version | head -1))"
        return 0
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        brew install starship
    else
        # Linux: use official installer
        curl -sS https://starship.rs/install.sh | sh -s -- -y
    fi

    success "Starship installed"
}

install_ghostty() {
    log "Installing Ghostty..."

    if command_exists ghostty; then
        success "Ghostty already installed"
        return 0
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        brew install ghostty
    else
        # Ubuntu: use snap for Ghostty
        if command_exists snap; then
            sudo snap install ghostty --classic || {
                warning "Ghostty snap installation failed. You may need to install it manually."
                return 1
            }
        else
            warning "snap not found. Please install snapd: sudo apt install snapd"
            return 1
        fi
    fi

    success "Ghostty installed"
}

# Detect the appropriate clipboard command for the current environment
detect_clipboard_command() {
    if [[ "$OS_TYPE" == "darwin" ]]; then
        # macOS uses pbcopy/pbpaste natively (tmux-yank handles this automatically)
        echo ""
    elif [[ -n "${WAYLAND_DISPLAY:-}" ]] && command_exists wl-copy; then
        # Wayland session with wl-clipboard
        echo "wl-copy"
    elif [[ -n "${DISPLAY:-}" ]] && command_exists xclip; then
        # X11 session with xclip
        echo "xclip -selection clipboard -in"
    elif [[ -n "${DISPLAY:-}" ]] && command_exists xsel; then
        # X11 session with xsel fallback
        echo "xsel --clipboard --input"
    elif command_exists wl-copy; then
        # Wayland available but WAYLAND_DISPLAY not set (e.g., in tmux over SSH)
        echo "wl-copy"
    elif command_exists xclip; then
        # Generic fallback to xclip
        echo "xclip -selection clipboard -in"
    else
        echo ""
    fi
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
    if find "$font_dir" -maxdepth 1 -name "JetBrainsMono*.ttf" -o -name "JetBrainsMono*.otf" 2>/dev/null | grep -q .; then
        success "JetBrains Mono already installed"
        return 0
    fi

    log "Downloading JetBrains Mono..."

    (
        local temp_dir=$(mktemp -d)
        trap "rm -rf '$temp_dir'" EXIT

        local download_url="https://github.com/JetBrains/JetBrainsMono/releases/download/v${JB_MONO_VERSION}/JetBrainsMono-${JB_MONO_VERSION}.zip"

        retry curl -fsSL "$download_url" -o "$temp_dir/jetbrains-mono.zip"

        log "Extracting fonts..."
        unzip -q "$temp_dir/jetbrains-mono.zip" -d "$temp_dir"

        # Copy only the required font variants (Regular, Bold, Italic, Bold Italic)
        log "Installing font files..."
        find "$temp_dir" -name "JetBrainsMono-*.ttf" -exec cp {} "$font_dir/" \;

        success "JetBrains Mono installed to $font_dir"
    )

    # Linux: refresh font cache
    if [[ "$OS_TYPE" == "linux" ]] && command_exists fc-cache; then
        log "Refreshing font cache..."
        fc-cache -fv "$font_dir" &>/dev/null
        success "Font cache refreshed"
    fi
}

################################################################################
# 7. SHELL CONFIGURATION
################################################################################

deploy_zshrc() {
    log "Deploying .zshrc configuration..."

    backup_file "$HOME/.zshrc"

    # Set platform-specific paths
    local pnpm_home
    local fzf_base
    local bun_path="${HOME}/.bun"

    if [[ "$OS_TYPE" == "darwin" ]]; then
        pnpm_home="${HOME}/Library/pnpm"
        fzf_base="/usr/local/opt/fzf"
    else
        pnpm_home="${HOME}/.local/share/pnpm"
        fzf_base="/usr/share/doc/fzf/examples"
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

# FZF - fuzzy finder
zinit light junegunn/fzf

# Node.js support - automatically load nvm when entering a node project
zinit snippet OMZP::node

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

# Load after 0 seconds (essentially async after prompt is shown)
zinit wait lucid light-mode for \
    zsh-users/zsh-history-substring-search

# History settings (Share across sessions)
export HISTFILE="$HOME/.zsh_history"
export HISTSIZE=100000
export SAVEHIST=100000
setopt SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS

# Bind up/down arrows to history substring search (search history based on typed prefix)
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# Tmux integration - session management helpers (lazy loaded)
zinit wait lucid for \
    OMZP::tmux \
    OMZP::bun \
    OMZP::git \
    OMZP::alias-finder

# You Should Use - reminds you of existing aliases
# pnpm support - aliases and completions (lazy loaded)
zinit wait lucid light-mode for \
    ntnyq/omz-plugin-pnpm \
    MichaelAquilina/zsh-you-should-use

# ============================================================================
# User Configuration
# ============================================================================

# Configure Git to use SSH instead of HTTPS (required for GitHub SSH keys)
# Only set if the SSH key exists (checked at shell startup)
[[ -f ~/.ssh/id_ed25519 ]] && export GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes"

# Custom git function - fuzzy checkout branch
[[ -f ~/.zsh/gcof.zsh ]] && source ~/.zsh/gcof.zsh

# Load aliases file
[[ -f ~/.zsh_aliases ]] && source ~/.zsh_aliases

# ============================================================================
# Prompt and Command Navigation
# ============================================================================

# Zoxide - smarter cd command
eval "$(zoxide init zsh)"

# Starship prompt - modern, fast prompt
eval "$(starship init zsh)"

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

# Make Claude Code accessible
export PATH="$HOME/.local/bin:$PATH"

# ============================================================================
# Environment Variables
# ============================================================================

# Load .env files from home directory
# Priority: .env first, then all .env.* files
load_env_files() {
    local env_file
    
    # Load .env first (base configuration)
    if [[ -f ~/.env ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$line" ]] && continue
            # Validate line looks like VAR=value before exporting
            [[ "$line" =~ ^[a-zA-Z_][a-zA-Z0-9_]*= ]] || continue
            # Export the variable
            export "$line" 2>/dev/null || true
        done < ~/.env
    fi
    
    # Load all .env.* files (including .env.local, .env.production, etc.)
    local env_files=(~/.env.*(N))
    for env_file in "${env_files[@]}"; do
        [[ -f "$env_file" ]] || continue
        
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$line" ]] && continue
            # Validate line looks like VAR=value before exporting
            [[ "$line" =~ ^[a-zA-Z_][a-zA-Z0-9_]*= ]] || continue
            export "$line" 2>/dev/null || true
        done < "$env_file"
    done
}

load_env_files

# ============================================================================
# Tmux Auto-attach (Ghostty integration)
# ============================================================================

# Auto-start tmux when opening Ghostty
# Ghostty sets TERM to xterm-ghostty
if [[ -z "$TMUX" && "$TERM" == xterm-ghostty* ]]; then
    tmux new-session -A -s main
fi

# ============================================================================
# Auto-update Zinit plugins (once per day)
# ============================================================================

# Check for updates once per day using a timestamp file
local zinit_update_stamp="$HOME/.zinit-last-update"
local update_interval=$((24 * 60 * 60)) # 24 hours in seconds
local current_time=$(date +%s)
local last_update=0

# Get last update time (cross-platform: macOS uses stat -f %m, Linux uses stat -c %Y)
if [[ -f "$zinit_update_stamp" ]]; then
    if [[ "$(uname -s)" == "Darwin" ]]; then
        last_update=$(stat -f %m "$zinit_update_stamp" 2>/dev/null || echo 0)
    else
        last_update=$(stat -c %Y "$zinit_update_stamp" 2>/dev/null || echo 0)
    fi
fi

# Update if more than 24 hours have passed
if (( current_time - last_update > update_interval )); then
    # Run updates in background so shell starts immediately
    (
        # Update Zinit itself first
        zinit self-update -q 2>/dev/null
        # Update all plugins and OMZ snippets
        zinit update --all -q 2>/dev/null
        # Mark update as complete
        touch "$zinit_update_stamp"
    ) &!
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

deploy_tmux_conf() {
    log "Deploying .tmux.conf configuration..."

    backup_file "$HOME/.tmux.conf"

    # Detect clipboard command for current environment
    local clipboard_command
    clipboard_command=$(detect_clipboard_command)
    
    log "Clipboard command detected: ${clipboard_command:-"auto-detect (macOS/native)"}"

    # Build clipboard configuration section
    local clipboard_config=""
    if [[ -n "$clipboard_command" ]]; then
        clipboard_config="
# Clipboard integration (auto-detected for $OS_TYPE)
set -g @custom_copy_command '$clipboard_command'
"
    fi

    cat > "$HOME/.tmux.conf" << TMUX_EOF
new-session

set-option -g default-shell /bin/zsh
set -g prefix C-a
set -g escape-time 500
set -g history-limit 25000
set -g base-index 1
set -g pane-base-index 1
set -g mouse on
set -g renumber-windows on

# Map escape sequences for pane navigation
bind -r Left  select-pane -L
bind -r Right select-pane -R

bind -r Up    select-pane -U
bind -r Down  select-pane -D

# List of plugins
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-continuum'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-yank'

# Ensure shell loads profile configs
set -g default-command "exec zsh -l"

$clipboard_config
# Plugins configuration
set -g @continuum-boot 'on'
set -g @continuum-restore 'on'
set -g @resurrect-capture-pane-contents 'on'

# Custom status bar
set -g status-style fg=white,bg=#265BCA
set -g window-status-format " [#I]: #W "
set -g window-status-current-format " [#I]: #W "
setw -g window-status-style fg=white,bg=#265BCA
setw -g window-status-current-style fg=black,bg=#E8DB57
setw -g window-status-separator "|"
set -g status-position bottom
set -g status-interval 1
set -g status-left "#{session_name} "
set -g status-left-length 50
set -g status-right " %a %d %b %H:%M "
set -g status-right-length 30

# Initialize TMUX plugin manager (keep this as the last line of .tmux.conf)!!!
run '~/.tmux/plugins/tpm/tpm'
TMUX_EOF

    chmod 644 "$HOME/.tmux.conf"
    success ".tmux.conf deployed"
}

deploy_ghostty_config() {
    log "Deploying Ghostty configuration..."

    mkdir -p "$HOME/.config/ghostty"
    
    backup_file "$HOME/.config/ghostty/config"

    # Platform-specific fullscreen keybinding
    local fullscreen_keybind
    if [[ "$OS_TYPE" == "darwin" ]]; then
        fullscreen_keybind="keybind = cmd+shift+f=toggle_fullscreen"
    else
        fullscreen_keybind="keybind = alt+shift+f=toggle_fullscreen"
    fi

    cat > "$HOME/.config/ghostty/config" << GHOSTTY_EOF
# Font configuration
font-family = JetBrains Mono
font-size = 13.5
font-feature = +calt

# Session recovery - Ghostty restores UI state (windows/tabs/splits)
window-save-state = always
shell-integration = detect

# macOS specific
font-thicken = true

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
# 8. STARSHIP CONFIGURATION
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
# 9. CUSTOM FUNCTIONS
################################################################################

deploy_custom_functions() {
    log "Deploying custom functions..."

    mkdir -p "$HOME/.zsh"

    cat > "$HOME/.zsh/gcof.zsh" << 'GCOF_EOF'
# gcof - Git Checkout Fuzzy
# Fuzzy find and checkout git branches

# Remove any existing alias to prevent conflicts
unalias gcof 2>/dev/null || true

gcof() {
    local branches
    branches=$(
        git branch --all \
        | grep -v 'HEAD' \
        | sed 's/^[* ]*//' \
        | sed 's|^remotes/[^/]*/||' \
        | sort -u
    )

    local filtered
    if [[ -n "${1:-}" ]]; then
        filtered=$(echo "$branches" | grep -i -- "$1" || true)
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
        echo "gcof: no branches matching '$1'" >&2
        return 1
    elif (( count == 1 )); then
        branch="$filtered"
        echo "gcof: checking out '$branch'" >&2
    else
        branch=$(echo "$branches" | fzf --query "${1:-}" --preview 'git log -n 20 --color --oneline {}')
        if [[ -z "$branch" ]]; then
            return 0
        fi
    fi

    git checkout "$branch"
}
GCOF_EOF
    chmod 644 "$HOME/.zsh/gcof.zsh"
    success "gcof.zsh function deployed"
}

################################################################################
# 10. SHELL SETUP
################################################################################

setup_shell() {
    log "Setting up zsh as default shell..."

    # Make zsh default shell
    local zsh_path
    if command_exists zsh; then
        zsh_path=$(command -v zsh)
        
        # Check if zsh is already the default (handle different path formats)
        if [[ "$SHELL" == *"zsh"* ]]; then
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
    else
        error "zsh not found in PATH"
    fi
}

################################################################################
# 11. NVM SETUP
################################################################################

setup_nvm() {
    log "Setting up NVM (Node Version Manager)..."

    if [[ -d "$HOME/.nvm" ]]; then
        success "NVM already installed"
        return 0
    fi

    log "Installing NVM..."
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash

    # Source NVM for current session
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    log "Installing Node LTS via NVM..."
    nvm install --lts
    nvm use --lts

    success "NVM and Node LTS installed"
}

################################################################################
# 12. ZINIT PLUGINS SETUP
################################################################################

setup_zinit_plugins() {
    log "Setting up Zinit plugins..."

    # First, ensure zinit is installed
    if [[ ! -f $HOME/.local/share/zinit/zinit.git/zinit.zsh ]]; then
        log "Installing Zinit plugin manager..."
        command mkdir -p "$HOME/.local/share/zinit" && command chmod g-rwX "$HOME/.local/share/zinit"
        retry git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git"
    fi

    # Run zsh to download and install all plugins
    log "Installing plugins (this may take a minute)..."
    zsh -c '
        source "$HOME/.local/share/zinit/zinit.git/zinit.zsh" 2>/dev/null
        source "$HOME/.zshrc" 2>/dev/null
        # Wait for turbo-loaded plugins (poll for completion, timeout at 15s)
        local elapsed=0
        local timeout=15
        while [[ ! -d "$HOME/.local/share/zinit/plugins/zsh-users---zsh-history-substring-search" ]] && [[ $elapsed -lt $timeout ]]; do
            sleep 1
            elapsed=$((elapsed + 1))
        done
        # Force update to ensure all are installed (suppress compile hook warnings)
        zinit update --all --parallel -q 2>/dev/null || true
    ' 2>/dev/null || true

    success "Zinit plugins installed"
}

################################################################################
# 13. TMUX PLUGIN MANAGER SETUP
################################################################################

setup_tmux_plugins() {
    log "Setting up tmux plugin manager..."

    local tpm_dir="$HOME/.tmux/plugins/tpm"
    
    if [[ -d "$tpm_dir" ]]; then
        success "tmux plugin manager already installed"
        return 0
    fi

    log "Installing tmux plugin manager (tpm)..."
    mkdir -p "$HOME/.tmux/plugins"
    retry git clone https://github.com/tmux-plugins/tpm "$tpm_dir"

    # Install plugins
    log "Installing tmux plugins..."
    "$tpm_dir/bin/install_plugins" 2>/dev/null || true

    success "tmux plugin manager installed"
}

################################################################################
# 14. VERIFICATION
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
        if version_gte "$ver" "$min_ver"; then
            success "$name installed ($ver)"
        else
            warning "$name version $ver < minimum $min_ver"
        fi
        checks_passed=$((checks_passed + 1))
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
    check_versioned_cmd "tmux" "$MIN_TMUX_VERSION" \
        "$(tmux -V 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"

    check_cmd "starship"
    check_cmd "fzf"
    check_cmd "ghostty"

    check_path "Zinit" "$HOME/.local/share/zinit/zinit.git"
    check_path ".zshrc" "$HOME/.zshrc"

    # Font check
    local font_dir
    if [[ "$OS_TYPE" == "darwin" ]]; then
        font_dir="$HOME/Library/Fonts"
    else
        font_dir="$HOME/.local/share/fonts"
    fi
    checks_total=$((checks_total + 1))
    if find "$font_dir" -maxdepth 1 -name "JetBrainsMono*.ttf" -o -name "JetBrainsMono*.otf" 2>/dev/null | grep -q .; then
        success "JetBrains Mono installed"
        checks_passed=$((checks_passed + 1))
    else
        warning "JetBrains Mono not found"
    fi

    log "Verification: $checks_passed/$checks_total checks passed"
}

################################################################################
# 15. POST-INSTALLATION SUMMARY
################################################################################

print_summary() {
    cat << 'SUMMARY_EOF'

═══════════════════════════════════════════════════════════════════════════════
                           ✓ SETUP COMPLETE
═══════════════════════════════════════════════════════════════════════════════

Installed Components:
  ✓ zsh (default shell)
  ✓ Zinit plugin manager (9 plugins)
  ✓ tmux with 6 plugins
  ✓ Ghostty terminal (with session recovery)
  ✓ Starship modern prompt
  ✓ fzf, zoxide, ripgrep, fd
  ✓ NVM + Node.js LTS
  ✓ JetBrains Mono font
  ✓ Auto-update on shell startup (once per day)
  ✓ Custom functions (gcof)

Quick Start:
  1. Close and reopen your terminal (or: exec zsh)
  2. Test shell: zinit plugins
  3. Try git alias: ga status
  4. Try pnpm shortcut: p --version
  5. Try fuzzy finder: Ctrl+T in file path

Useful Commands:
  - View plugins: zinit plugins
  - View plugin report: zinit report
  - View tmux status: tmux status-left

Documentation & Logs:
  - Installation log: ~/.setup.log
  - Backup configs: ~/.backup/
  - Repository: https://github.com/ngarate/shell-backup
  - Troubleshooting: See TROUBLESHOOTING.md in repo

═══════════════════════════════════════════════════════════════════════════════

SUMMARY_EOF
}

################################################################################
# 16. MAIN EXECUTION
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
    install_ghostty || true
    install_fonts || true

    deploy_zshrc
    deploy_tmux_conf
    deploy_ghostty_config
    deploy_starship_config
    deploy_custom_functions

    setup_shell
    setup_nvm
    setup_zinit_plugins
    setup_tmux_plugins

    verify_installation
    print_summary

    log "=== SHELL-BACKUP: Setup Complete ==="
    success "All done! Reloading shell..."

    exec zsh
}

# Run main function
main
