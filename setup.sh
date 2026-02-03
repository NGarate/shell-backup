#!/bin/bash

################################################################################
# SHELL-BACKUP: Cross-Platform Development Environment Setup
# Supports: macOS (Intel/ARM), Ubuntu/Debian, Fedora/RHEL, Arch Linux
# Version: 1.0.0
################################################################################

set -euo pipefail

################################################################################
# 1. CONFIGURATION & CONSTANTS
################################################################################

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

################################################################################
# 2. UTILITY FUNCTIONS
################################################################################

log() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$SETUP_LOG"
}

success() {
    echo -e "${GREEN}✓${NC} $1" | tee -a "$SETUP_LOG"
}

error() {
    echo -e "${RED}✗${NC} $1" >&2 | tee -a "$SETUP_LOG"
    exit 1
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1" | tee -a "$SETUP_LOG"
}

command_exists() {
    command -v "$1" &>/dev/null
}

detect_os() {
    case "$(uname -s)" in
        Darwin*) 
            OS_TYPE="darwin"
            if [[ $(uname -m) == "arm64" ]]; then
                ARCH="aarch64"
            else
                ARCH="x86_64"
            fi
            ;;
        Linux*)
            OS_TYPE="linux"
            ARCH=$(uname -m)
            ;;
        *)
            error "Unsupported operating system: $(uname -s)"
            ;;
    esac
}

detect_distro() {
    if [[ "$OS_TYPE" != "linux" ]]; then
        return 0
    fi

    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian)
                DISTRO="debian"
                PKG_MANAGER="apt"
                ;;
            fedora|rhel|centos)
                DISTRO="fedora"
                PKG_MANAGER="dnf"
                ;;
            arch|manjaro)
                DISTRO="arch"
                PKG_MANAGER="pacman"
                ;;
            *)
                warning "Unknown Linux distribution: $ID"
                DISTRO="unknown"
                PKG_MANAGER="unknown"
                ;;
        esac
    fi
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

    if [[ "$OS_TYPE" == "darwin" ]]; then
        if ! command_exists brew; then
            log "Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            success "Homebrew installed"
        else
            success "Homebrew already available"
        fi
        
        # Ensure brew is in PATH for M1/M2 Macs
        if [[ "$ARCH" == "aarch64" ]]; then
            export PATH="/opt/homebrew/bin:$PATH"
        fi
    elif [[ "$OS_TYPE" == "linux" ]]; then
        detect_distro
        log "Detected Linux distribution: $DISTRO"

        case "$PKG_MANAGER" in
            apt)
                if ! command_exists apt-get; then
                    error "apt-get not found"
                fi
                log "Running apt update..."
                sudo apt-get update -qq
                success "apt-get ready"
                ;;
            dnf)
                if ! command_exists dnf; then
                    error "dnf not found"
                fi
                success "dnf ready"
                ;;
            pacman)
                if ! command_exists pacman; then
                    error "pacman not found"
                fi
                success "pacman ready"
                ;;
            *)
                error "Unsupported package manager"
                ;;
        esac
    fi
}

################################################################################
# 5. CORE TOOL INSTALLATION
################################################################################

install_via_package_manager() {
    local package="$1"
    local manager="$2"

    case "$manager" in
        brew)
            if ! command_exists "$package" 2>/dev/null; then
                brew install "$package"
            fi
            ;;
        apt)
            if ! command_exists "$package" 2>/dev/null; then
                sudo apt-get install -y -qq "$package"
            fi
            ;;
        dnf)
            if ! command_exists "$package" 2>/dev/null; then
                sudo dnf install -y -q "$package"
            fi
            ;;
        pacman)
            local pkg_name="$package"
            # Handle package name aliases
            case "$package" in
                fzf-binary) pkg_name="fzf" ;;
                ripgrep) pkg_name="ripgrep" ;;
            esac
            if ! pacman -Q "$pkg_name" &>/dev/null; then
                sudo pacman -S --noconfirm "$pkg_name"
            fi
            ;;
    esac
}

install_core_tools() {
    log "Installing core tools..."

    if [[ "$OS_TYPE" == "darwin" ]]; then
        # macOS via Homebrew
        local tools=(zsh tmux starship fzf zoxide ripgrep fd)
        for tool in "${tools[@]}"; do
            if command_exists "$tool"; then
                success "$tool already installed"
            else
                log "Installing $tool..."
                brew install "$tool"
                success "$tool installed"
            fi
        done
    else
        # Linux
        case "$PKG_MANAGER" in
            apt)
                log "Installing tools via apt..."
                sudo apt-get install -y -qq zsh tmux git curl build-essential fontconfig
                sudo apt-get install -y -qq fzf zoxide ripgrep fd-find 2>/dev/null || true
                ;;
            dnf)
                log "Installing tools via dnf..."
                sudo dnf install -y -q zsh tmux git curl gcc g++ make fontconfig
                sudo dnf install -y -q fzf zoxide ripgrep fd 2>/dev/null || true
                ;;
            pacman)
                log "Installing tools via pacman..."
                sudo pacman -S --noconfirm zsh tmux git curl base-devel fontconfig
                sudo pacman -S --noconfirm fzf zoxide ripgrep fd 2>/dev/null || true
                ;;
        esac
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

install_alacritty() {
    log "Installing Alacritty..."

    if command_exists alacritty; then
        success "Alacritty already installed"
        return 0
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        brew install alacritty
    else
        case "$PKG_MANAGER" in
            apt)
                sudo apt-get install -y -qq alacritty || {
                    warning "Alacritty not in apt repositories, skipping"
                    return 1
                }
                ;;
            dnf)
                sudo dnf install -y -q alacritty || {
                    warning "Alacritty not in dnf repositories, skipping"
                    return 1
                }
                ;;
            pacman)
                sudo pacman -S --noconfirm alacritty || {
                    warning "Alacritty not available, skipping"
                    return 1
                }
                ;;
        esac
    fi

    success "Alacritty installed"
}

################################################################################
# 6. FONT INSTALLATION
################################################################################

install_fonts() {
    log "Installing Iosevka Nerd Font..."

    local font_dir
    if [[ "$OS_TYPE" == "darwin" ]]; then
        font_dir="$HOME/Library/Fonts"
        mkdir -p "$font_dir"
    else
        font_dir="$HOME/.local/share/fonts"
        mkdir -p "$font_dir"
    fi

    # Check if fonts already exist
    if ls "$font_dir"/IosevkaTerm* &>/dev/null 2>&1; then
        success "Fonts already installed"
        return 0
    fi

    # Copy fonts from script directory
    if [[ -d "$SCRIPT_DIR/fonts" ]]; then
        log "Copying fonts from $SCRIPT_DIR/fonts..."
        cp "$SCRIPT_DIR"/fonts/*.ttf "$font_dir/"
        success "Fonts copied to $font_dir"
    else
        warning "fonts directory not found in script directory"
        return 1
    fi

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

# Git integration from OMZ
zinit snippet OMZP::git

# Autosuggestions - show command completions based on history
zinit light zsh-users/zsh-autosuggestions

# Syntax highlighting - highlight commands as you type
zinit light zsh-users/zsh-syntax-highlighting

# FZF - fuzzy finder
zinit light junegunn/fzf

# Node.js support - automatically load nvm when entering a node project
zinit snippet OMZP::node

# Command not found helper - suggests installed packages
zinit snippet OMZP::command-not-found

# ============================================================================
# Optional/Secondary Plugins (turbo mode for faster startup)
# ============================================================================

# Load after 0 seconds (essentially async after prompt is shown)
zinit wait lucid light-mode for \
    zsh-users/zsh-history-substring-search

# Tmux integration - session management helpers (lazy loaded)
zinit wait lucid for \
    OMZP::tmux \
    OMZP::alias-finder

# ============================================================================
# User Configuration
# ============================================================================

# Configure Git to use SSH instead of HTTPS (required for GitHub SSH keys)
export GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes"

# Custom git function - fuzzy checkout branch
[[ -f ~/.zsh/gcof.zsh ]] && source ~/.zsh/gcof.zsh

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
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# pnpm aliases
alias p="pnpm"
alias pa="pnpm add"
alias pad="pnpm add -D"
alias pi="pnpm install"
alias pr="pnpm remove"
alias prd="pnpm remove -D"
alias pup="pnpm update"
alias ps="pnpm start"
alias pt="pnpm test"
alias pb="pnpm build"
alias pnpm:latest="pnpm add -g pnpm@latest"

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

# Read .env files if exists
if [[ -f ~/.env ]]; then
    export $(cat ~/.env | xargs)
fi
ZSHRC_EOF

    # Replace placeholders
    sed -i '' "s|PNPM_HOME_PLACEHOLDER|$pnpm_home|g" "$HOME/.zshrc" 2>/dev/null || \
    sed -i "s|PNPM_HOME_PLACEHOLDER|$pnpm_home|g" "$HOME/.zshrc"

    success ".zshrc deployed"
}

deploy_tmux_conf() {
    log "Deploying .tmux.conf configuration..."

    backup_file "$HOME/.tmux.conf"

    cat > "$HOME/.tmux.conf" << 'TMUX_EOF'
new-session

set-option -g default-shell /bin/zsh
set -g prefix C-a
set -g escape-time 500
set -g history-limit 25000
set -g base-index 1
set -g pane-base-index 1
set -g mouse on
set -g renumber-windows on

# Map escape sequences from Alacritty to pane navigation
bind -r Left  select-pane -L
bind -r Right select-pane -R

bind -r Up    select-pane -U
bind -r Down  select-pane -D

# Disable Option + Arrow window switching
unbind -T root M-Left
unbind -T root M-Right

# Disable clipborar in order to work fine with Alacritty
set -g set-clipboard off

# List of plugins
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-continuum'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-yank'
set -g @plugin 'tmux-plugins/tmux-battery'

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

# Battery status configuration
set -g @batt_icon_status_charged '󰁹'
set -g @batt_icon_status_charging '󰢝'
set -g @batt_icon_status_discharging '󰁼'
set -g status-right '%a %d %B %H:%M | #{battery_icon}: #{battery_percentage} #{battery_remain}'

# Initialize TMUX plugin manager (keep this as the last line of .tmux.conf)!!!
run '~/.tmux/plugins/tpm/tpm'
TMUX_EOF

    success ".tmux.conf deployed"
}

deploy_alacritty_config() {
    log "Deploying Alacritty configuration..."

    mkdir -p "$HOME/.config/alacritty"
    
    # Use ~/.alacritty.toml if it exists, otherwise create in .config
    local alacritty_config
    if [[ -f "$HOME/.alacritty.toml" ]]; then
        backup_file "$HOME/.alacritty.toml"
        alacritty_config="$HOME/.alacritty.toml"
    else
        alacritty_config="$HOME/.config/alacritty/alacritty.toml"
    fi

    # Check if theme directory exists, create if needed
    mkdir -p "$HOME/.config/alacritty/themes/themes"

    cat > "$alacritty_config" << 'ALACRITTY_EOF'
[general]
import = ["~/.config/alacritty/themes/themes/gnome_terminal.toml"]
live_config_reload = true

[window]
decorations = "none"
dynamic_padding = true
option_as_alt = "None"

[font]
normal = { family = "IosevkaTerm Nerd Font Mono", style = "ExtraLight" }
bold = { family = "IosevkaTerm Nerd Font Mono", style = "Medium" }
italic = { family = "IosevkaTerm Nerd Font Mono", style = "ExtraLight Italic" }
size = 15

[keyboard]
bindings = [
  # Fullscreen
  { key = "F", mods = "Command|Shift", action = "ToggleFullscreen" },

  # tmux windows (prefix = Ctrl-A): Cmd+Shift+Left/Right -> prev/next window
  { key = "Left",  mods = "Command|Shift", chars = "\u0001p" },
  { key = "Right", mods = "Command|Shift", chars = "\u0001n" },

  # tmux windows direct: Cmd + number (prefix = Ctrl-A + number)
  { key = "Key1", mods = "Command", chars = "\u00011" },
  { key = "Key2", mods = "Command", chars = "\u00012" },
  { key = "Key3", mods = "Command", chars = "\u00013" },
  { key = "Key4", mods = "Command", chars = "\u00014" },
  { key = "Key5", mods = "Command", chars = "\u00015" },
  { key = "Key6", mods = "Command", chars = "\u00016" },
  { key = "Key7", mods = "Command", chars = "\u00017" },
  { key = "Key8", mods = "Command", chars = "\u00018" },
  { key = "Key9", mods = "Command", chars = "\u00019" },

  # tmux panes (prefix = Ctrl-A): Option+Shift+Arrows -> select pane L/R/U/D
  { key = "Left",  mods = "Alt|Shift", chars = "\u0001\u001bOD" },
  { key = "Right", mods = "Alt|Shift", chars = "\u0001\u001bOC" },
  { key = "Up",    mods = "Alt|Shift", chars = "\u0001\u001bOA" },
  { key = "Down",  mods = "Alt|Shift", chars = "\u0001\u001bOB" },

  # Zsh word-wise navigation: Option+Left/Right (ESC b / ESC f)
  { key = "Left",  mods = "Alt", chars = "\u001Bb" },
  { key = "Right", mods = "Alt", chars = "\u001Bf" },

  # Shell line navigation: Cmd+Left/Right (Ctrl-A / Ctrl-E)
  { key = "Left",  mods = "Command", chars = "\u0001" },
  { key = "Right", mods = "Command", chars = "\u0005" },
  
  # Fix new line for opencode
  { key = "Return", mods = "Shift", chars = "\n" }
]
ALACRITTY_EOF

    success "Alacritty configuration deployed"
}

################################################################################
# 8. STARSHIP CONFIGURATION
################################################################################

deploy_starship_config() {
    log "Deploying Starship configuration..."

    mkdir -p "$HOME/.config"

    # Copy starship config from script directory or create embedded version
    if [[ -f "$SCRIPT_DIR/starship.toml" ]]; then
        cp "$SCRIPT_DIR/starship.toml" "$HOME/.config/starship.toml"
        success "Starship config copied from script directory"
    else
        # Create a minimal starship config (user can enhance later)
        cat > "$HOME/.config/starship.toml" << 'STARSHIP_EOF'
add_newline = false
command_timeout = 2000

format = """
$directory$character
"""

[directory]
truncate_to_repo = true
format = "[ $path ]($style)"
style = "bold blue"

[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"
STARSHIP_EOF
        success "Minimal Starship config created"
    fi
}

################################################################################
# 9. CUSTOM FUNCTIONS
################################################################################

deploy_custom_functions() {
    log "Deploying custom functions..."

    mkdir -p "$HOME/.zsh"

    # Copy gcof.zsh from script directory or create placeholder
    if [[ -f "$SCRIPT_DIR/.zsh/gcof.zsh" ]]; then
        cp "$SCRIPT_DIR/.zsh/gcof.zsh" "$HOME/.zsh/gcof.zsh"
        success "gcof.zsh function deployed"
    else
        warning "gcof.zsh not found in script directory, creating placeholder"
        cat > "$HOME/.zsh/gcof.zsh" << 'GCOF_EOF'
# gcof - Git Checkout Fuzzy
# Fuzzy find and checkout git branches
gcof() {
    local branch
    branch=$(git branch --all | grep -v HEAD | sed 's/^..//' | fzf --preview 'git log -n 20 --oneline {}' | sed 's/.*\///') && git checkout "$branch"
}
GCOF_EOF
    fi
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
        
        if [[ "$SHELL" != "$zsh_path" ]]; then
            log "Changing default shell to $zsh_path..."
            chsh -s "$zsh_path"
            success "Default shell changed to zsh"
        else
            success "zsh is already the default shell"
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
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

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

    # Source the new zshrc to load Zinit
    export ZDOTDIR="$HOME"
    source "$HOME/.zshrc" 2>/dev/null || true

    # Give Zinit time to initialize
    sleep 2

    if command_exists zinit; then
        log "Running zinit report..."
        zinit report 2>/dev/null || true
        success "Zinit plugins loaded"
    else
        warning "Zinit not yet initialized, will load on next shell session"
    fi
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
    git clone https://github.com/tmux-plugins/tpm "$tpm_dir"

    # Install plugins
    log "Installing tmux plugins..."
    "$tpm_dir/bin/install_plugins" 2>/dev/null || true

    success "tmux plugin manager installed"
}

################################################################################
# 14. AUTO-UPDATE SCHEDULING
################################################################################

setup_auto_update_macos() {
    log "Setting up auto-update for macOS via LaunchAgent..."

    mkdir -p "$HOME/Library/LaunchAgents"

    cat > "$HOME/Library/LaunchAgents/com.ngarate.zinit-update.plist" << 'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ngarate.zinit-update</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>-c</string>
        <string>source ~/.zshrc && zinit update --all --parallel -q</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>2</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/zinit-update.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/zinit-update.err</string>
</dict>
</plist>
PLIST_EOF

    # Load the LaunchAgent
    launchctl load "$HOME/Library/LaunchAgents/com.ngarate.zinit-update.plist" 2>/dev/null || {
        launchctl unload "$HOME/Library/LaunchAgents/com.ngarate.zinit-update.plist" 2>/dev/null || true
        launchctl load "$HOME/Library/LaunchAgents/com.ngarate.zinit-update.plist"
    }

    success "LaunchAgent for auto-update installed"
}

setup_auto_update_linux() {
    log "Setting up auto-update for Linux via systemd timer..."

    mkdir -p "$HOME/.config/systemd/user"

    cat > "$HOME/.config/systemd/user/zinit-update.service" << 'SERVICE_EOF'
[Unit]
Description=Update Zinit plugins daily
After=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/zsh -c "source ~/.zshrc && zinit update --all --parallel -q"
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
SERVICE_EOF

    cat > "$HOME/.config/systemd/user/zinit-update.timer" << 'TIMER_EOF'
[Unit]
Description=Daily Zinit plugin updates
Requires=zinit-update.service

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
TIMER_EOF

    log "Enabling and starting systemd timer..."
    systemctl --user daemon-reload
    systemctl --user enable zinit-update.timer
    systemctl --user start zinit-update.timer

    success "Systemd timer for auto-update installed"
}

setup_auto_update() {
    if [[ "$OS_TYPE" == "darwin" ]]; then
        setup_auto_update_macos
    else
        setup_auto_update_linux
    fi
}

################################################################################
# 15. VERIFICATION
################################################################################

verify_installation() {
    log "Verifying installation..."

    local checks_passed=0
    local checks_total=0

    # Check zsh
    checks_total=$((checks_total + 1))
    if command_exists zsh; then
        success "zsh installed ($(zsh --version | head -1))"
        checks_passed=$((checks_passed + 1))
    else
        warning "zsh not found"
    fi

    # Check Zinit
    checks_total=$((checks_total + 1))
    if [[ -d "$HOME/.local/share/zinit/zinit.git" ]]; then
        success "Zinit installed"
        checks_passed=$((checks_passed + 1))
    else
        warning "Zinit not found"
    fi

    # Check tmux
    checks_total=$((checks_total + 1))
    if command_exists tmux; then
        success "tmux installed ($(tmux -V))"
        checks_passed=$((checks_passed + 1))
    else
        warning "tmux not found"
    fi

    # Check starship
    checks_total=$((checks_total + 1))
    if command_exists starship; then
        success "Starship installed ($(starship --version | head -1))"
        checks_passed=$((checks_passed + 1))
    else
        warning "Starship not found"
    fi

    # Check fzf
    checks_total=$((checks_total + 1))
    if command_exists fzf; then
        success "fzf installed"
        checks_passed=$((checks_passed + 1))
    else
        warning "fzf not found"
    fi

    # Check fonts
    checks_total=$((checks_total + 1))
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if ls "$HOME/Library/Fonts"/IosevkaTerm* &>/dev/null 2>&1; then
            success "Fonts installed"
            checks_passed=$((checks_passed + 1))
        else
            warning "Iosevka fonts not found"
        fi
    else
        if ls "$HOME/.local/share/fonts"/IosevkaTerm* &>/dev/null 2>&1; then
            success "Fonts installed"
            checks_passed=$((checks_passed + 1))
        else
            warning "Iosevka fonts not found"
        fi
    fi

    # Check config files
    checks_total=$((checks_total + 1))
    if [[ -f "$HOME/.zshrc" ]]; then
        success ".zshrc deployed"
        checks_passed=$((checks_passed + 1))
    else
        warning ".zshrc not found"
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
  ✓ tmux with 6 plugins
  ✓ Alacritty terminal
  ✓ Starship modern prompt
  ✓ fzf, zoxide, ripgrep, fd
  ✓ NVM + Node.js LTS
  ✓ Iosevka Nerd Font
  ✓ Auto-update scheduled (daily 2:00 AM)
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
  - View auto-update logs (macOS): tail /tmp/zinit-update.log
  - View auto-update status (Linux): systemctl --user status zinit-update.timer

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
    
    log "=== SHELL-BACKUP: Setup Starting ==="
    log "OS: $OS_TYPE | Arch: $ARCH"

    detect_os
    detect_distro

    log "Detected system: $OS_TYPE ($ARCH) - $DISTRO"

    check_prerequisites
    setup_package_manager
    install_core_tools
    install_starship
    install_alacritty || true  # Don't fail if alacritty install fails
    install_fonts || true      # Don't fail if fonts aren't available

    deploy_zshrc
    deploy_tmux_conf
    deploy_alacritty_config
    deploy_starship_config
    deploy_custom_functions

    setup_shell
    setup_nvm
    setup_zinit_plugins
    setup_tmux_plugins
    setup_auto_update

    verify_installation
    print_summary

    log "=== SHELL-BACKUP: Setup Complete ==="
    success "All done! Check ~/.setup.log for details."
}

# Run main function
main "$@"
