# shell-backup

A unified, cross-platform automation script that replicates a complete professional development environment with zsh, tmux, Alacritty, Starship, and 15+ essential tools in one command.

## 🚀 Quick Start

```bash
# Download and run
curl -fsSL https://raw.githubusercontent.com/ngarate/shell-backup/main/setup.sh | bash

# Or clone and run locally
git clone https://github.com/ngarate/shell-backup.git
cd shell-backup
chmod +x setup.sh
./setup.sh
```

## 📖 Quick Reference

- **[SHORTCUTS.md](./SHORTCUTS.md)** - Complete reference for all aliases, keybindings, and shortcuts
- **[TROUBLESHOOTING.md](./TROUBLESHOOTING.md)** - Common issues and solutions

## ✨ What Gets Installed

### Shell & Configuration
- **zsh** - Modern shell with powerful scripting
- **Oh-My-Zsh plugins** - 9 curated plugins for productivity
- **Starship** - Fast, customizable shell prompt
- **Custom functions** - Git fuzzy checkout (`gcof`), aliases, and utilities

### Terminal & Multiplexing
- **tmux** - Terminal multiplexer with session management
- **tmux plugin manager (tpm)** - 5 tmux plugins for enhanced functionality
- **Alacritty** - GPU-accelerated terminal emulator (optional)

### Developer Tools
- **fzf** - Fuzzy finder for files and commands
- **zoxide** - Smarter `cd` command with frecency
- **ripgrep (rg)** - Fast text search
- **fd** - User-friendly `find` alternative
- **NVM** - Node.js version manager
- **pnpm** - Fast, disk-efficient package manager
- **bun** - Fast JavaScript runtime (optional)

### Fonts & Theme
- **Iosevka Nerd Font** - Beautiful monospace font with nerd symbols
- **Starship theme** - Custom prompt with git integration

### Productivity Features
- **Auto-save/restore tmux sessions** - Via tmux-resurrect + continuum
- **Auto-update plugins daily** - Via LaunchAgent (macOS) or Systemd (Linux)
- **Clipboard integration** - tmux-yank for copy/paste
- **Git shortcuts** - 40+ aliases + fuzzy branch checkout

## 📋 System Requirements

### Minimum
- **macOS 10.15+** (Intel or Apple Silicon)
- **Ubuntu 20.04+** / **Fedora 35+** / **Arch Linux**
- **curl** or **wget**
- **git**
- **~500MB** disk space
- **Internet connection** (for downloads)

### Recommended
- **macOS 12+** or **Ubuntu 22.04+**
- **2GB+ RAM**
- **50MB/s+ internet speed** (for faster installation)

## 🌍 Platform Support

| OS | Version | Status | Tested | Notes |
|---|---|---|---|---|
| macOS | 10.15+ | ✅ Supported | Intel, M1/M2/M3 | Homebrew required |
| macOS | 13+ | ✅ Full Support | ✅ All architectures | Recommended |
| Ubuntu | 20.04+ | ✅ Supported | 20.04, 22.04 | apt-based |
| Debian | 11+ | ✅ Supported | ✅ Bullseye+ | apt-based |
| Fedora | 35+ | ✅ Supported | ✅ 37+ | dnf-based |
| RHEL/CentOS | 8+ | ✅ Supported | ⚠️ Limited testing | dnf-based |
| Arch Linux | Latest | ✅ Supported | ✅ Rolling | pacman-based |
| Alpine | Latest | ⚠️ Partial | ❌ Not tested | apk (not supported) |

## 📦 What's Installed (Detailed)

### Zsh Plugins (9 total)

**Core plugins (loaded immediately):**
1. **git** - 40+ git aliases (`gst`, `gcb`, `gco`, etc.)
2. **zsh-autosuggestions** - Command history suggestions
3. **zsh-syntax-highlighting** - Syntax highlighting in editor
4. **juneguun/fzf** - Fuzzy finder integration (Ctrl+R, Ctrl+T)
5. **node** - NVM auto-loading and npm integration
6. **command-not-found** - Suggests packages for missing commands

**Turbo/Lazy plugins (after prompt appears):**
7. **zsh-history-substring-search** - Search history with arrow keys
8. **tmux** - tmux integration and helpers
9. **alias-finder** - Shows aliases when typing full commands

**Custom pnpm aliases:**
```bash
p, pa, pad, pi, pr, prd, pup, ps, pt, pb
pnpm  # typed as 'pnpm'
```

### Tmux Plugins (6 total)

1. **tpm** - Tmux Plugin Manager (required for others)
2. **tmux-sensible** - Sensible defaults
3. **tmux-continuum** - Auto-save and restore sessions every 15min
4. **tmux-resurrect** - Save/restore tmux panes and windows
5. **tmux-yank** - Clipboard integration (copy to system clipboard)

### Developer Tools

| Tool | Purpose | Installation |
|---|---|---|
| **fzf** | Fuzzy finder | Homebrew / apt / dnf / pacman |
| **zoxide** | Smart cd | Homebrew / apt / dnf / pacman |
| **ripgrep** | Fast grep | Homebrew / apt / dnf / pacman |
| **fd** | Smart find | Homebrew / apt / dnf / pacman |
| **NVM** | Node version manager | Official installer |
| **pnpm** | Package manager | npm via NVM |
| **bun** | JS runtime | Official installer |

## 🔧 Usage

### First Time After Installation

```bash
# Reload shell to activate plugins
exec zsh

# Verify installation
zsh --version
tmux -V
starship --version

# Try fuzzy finder
Ctrl+R  # Search command history
Ctrl+T  # Browse files

# Try zoxide
z --version
z some-frecent-folder

# Try custom gcof (git checkout fuzzy)
gcof    # Interactively select git branch to checkout
```

### Common Commands

```bash
# Git shortcuts (Oh-My-Zsh)
gst          # git status
gco <branch> # git checkout
gcb          # git checkout -b
gca          # git commit --amend
gp           # git push
gpu          # git pull

# Tmux
tmux new-session -s dev   # Create new session
tmux attach -t dev        # Attach to session
Ctrl+B D                  # Detach from session
Ctrl+B S                  # Browse sessions
# Status bar shows: session name | windows | Day DD Mon HH:MM

# Navigate faster
z <folder>   # Jump to frequently used folder
cd -         # Go to previous directory (built-in)

# Search files
rg "pattern" # ripgrep search
fd "*.ts"    # Find TypeScript files

# History navigation (type prefix then use arrows)
git <up-arrow>    # Shows only git commands from history
docker <up-arrow> # Shows only docker commands from history
<down-arrow>      # Navigate forward in filtered history
```

**📚 See [SHORTCUTS.md](./SHORTCUTS.md) for complete reference of all aliases, keybindings, and shortcuts.**

## 📝 Configuration Files

All configuration files are installed to their standard locations:

```
~/.zshrc                          # Zsh configuration
~/.tmux.conf                      # Tmux configuration
~/.config/starship.toml           # Starship prompt theme
~/.zsh/gcof.zsh                   # Custom functions
~/.config/alacritty/alacritty.toml # Alacritty config (if installed)
```

### Customize After Installation

1. **Edit shell config:**
   ```bash
   vim ~/.zshrc
   source ~/.zshrc  # Reload
   ```

2. **Edit prompt theme:**
   ```bash
   vim ~/.config/starship.toml
   exec zsh  # Reload
   ```

3. **Edit tmux config:**
   ```bash
   vim ~/.tmux.conf
   tmux source ~/.tmux.conf  # Reload configuration
   ```

   **Important:** Config reload only affects the current session. For a fresh start:
   ```bash
   # Option 1: Detach and reattach
   Ctrl+A D                    # Detach from session
   tmux attach                 # Reattach (applies new config)

   # Option 2: Kill and recreate session
   tmux kill-session -t <name> # Kill specific session
   tmux new                    # Create new session
   ```

   **Customize status bar:**
   ```bash
   # Change date/time format (default: Day DD Mon HH:MM)
   set -g status-right " %a %d %b %H:%M "
   
   # Alternative formats:
   # 12-hour time: set -g status-right " %a %d %b %I:%M %p "
   # With seconds: set -g status-right " %a %d %b %H:%M:%S "
   # US format:     set -g status-right " %a %m/%d %H:%M "
   ```

4. **Add your own aliases:**
   ```bash
   # Add to ~/.zshrc before the last line
   alias myalias="my command"
   ```

## 🔄 Auto-Update

Plugins are automatically updated daily at **2:00 AM**:

- **macOS:** Via LaunchAgent (`~/Library/LaunchAgents/com.ngarate.zinit-update.plist`)
- **Linux:** Via Systemd timer (`~/.config/systemd/user/zinit-update.timer`)

### Manual Update

```bash
# Update all zsh plugins
zinit update --all

# Update all tmux plugins
cd ~/.tmux/plugins/tpm && ./bin/update_plugins all

# Update Starship
starship self update
```

### View Update Logs

```bash
# macOS
tail -f /tmp/zinit-update.log

# Linux
journalctl --user -u zinit-update -f
```

## 🐛 Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for:
- Plugins not loading
- Font display issues
- SSH key errors
- Permission denied errors
- Platform-specific issues

### Quick Fixes

```bash
# Plugins not loading after install?
exec zsh

# Tmux plugins not showing?
cd ~/.tmux/plugins/tpm && ./bin/install_plugins

# Font looks wrong?
# Restart terminal, then check: Settings > Font > Iosevka Nerd Font

# Check installation status
./setup.sh  # Run again - it's idempotent!
```

## ⚙️ How It Works

The setup script:
1. Detects your OS and architecture
2. Installs/updates package managers (Homebrew, apt, dnf, pacman)
3. Installs zsh, tmux, starship, and 10+ dev tools
4. Downloads and installs Iosevka Nerd Font
5. Creates/deploys configuration files
6. Initializes Zinit and installs 9 plugins
7. Sets up tmux plugin manager and 6 plugins
8. Configures daily auto-update schedule
9. Verifies all installations
10. Prints summary with next steps

**Key features:**
- ✅ Idempotent - Safe to run multiple times
- ✅ Error recovery - Shows what failed, lets you fix and re-run
- ✅ Backup strategy - Backs up existing configs before overwriting
- ✅ Platform aware - Different paths for macOS vs Linux
- ✅ Network aware - Handles connection issues gracefully

## 📊 Installation Time

- **First time:** 10-15 minutes (includes downloads and Homebrew setup on macOS)
- **Subsequent runs:** 2-3 minutes (checks for updates)
- **On faster internet:** 5-8 minutes

## 📄 License

MIT

## 🤝 Contributing

Found a bug? Want to add a feature?

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make changes and test on your OS
4. Commit with clear messages: `git commit -m "Add: description"`
5. Push and open a pull request

### Testing Checklist

Before submitting a PR, verify on your OS:
- [ ] Script runs without errors
- [ ] All plugins load (check with `zinit list`)
- [ ] Tmux plugins load (check with `tmux list-plugins` or `Ctrl+B U`)
- [ ] Starship prompt displays correctly
- [ ] Fonts render correctly (special symbols visible)
- [ ] Auto-update works (check logs after 24 hours)

## 📞 Support

- 📖 See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for common issues
- 💬 Open an issue on GitHub
- 📝 Check logs: `~/.setup.log`

## 🎯 Roadmap

- [ ] Interactive installer with prompts
- [ ] Desktop environment detection (GNOME, KDE, etc.)
- [ ] Optional tools menu (Neovim, Lazygit, etc.)
- [ ] Backup and restore configs to cloud
- [ ] macOS Monterey+ window manager (yabai)
- [ ] Automated testing on multiple platforms

## 📚 Learn More

- [Zinit documentation](https://github.com/zdharma-continuum/zinit)
- [Tmux guide](https://github.com/tmux/tmux/wiki)
- [Starship configuration](https://starship.rs/config/)
- [fzf examples](https://github.com/juneguun/fzf)
- [Alacritty configuration](https://github.com/alacritty/alacritty)

---

**Happy coding! 🎉**
