# shell-backup

A unified, cross-platform automation script that replicates a complete professional development environment with zsh, tmux, Ghostty, Starship, and 15+ essential tools in one command.

## Quick Start

```bash
# Download and run
curl -fsSL https://raw.githubusercontent.com/ngarate/shell-backup/main/setup.sh | bash

# Or clone and run locally
git clone https://github.com/ngarate/shell-backup.git
cd shell-backup
chmod +x setup.sh
./setup.sh
```

## Quick Reference

- **[SHORTCUTS.md](./SHORTCUTS.md)** - Complete reference for all aliases, keybindings, and shortcuts
- **[TROUBLESHOOTING.md](./TROUBLESHOOTING.md)** - Common issues and solutions

## What Gets Installed

### Shell & Configuration

- **zsh** - Modern shell with Zinit plugin manager (9 plugins)
- **Starship** - Fast, customizable shell prompt
- **Custom functions** - Git fuzzy checkout (`gcof`), aliases, and utilities

### Terminal & Multiplexing

- **tmux** - Terminal multiplexer with session management (6 plugins)
- **Ghostty** - GPU-accelerated terminal emulator with session recovery

### Developer Tools

- **fzf** - Fuzzy finder for files and commands
- **zoxide** - Smarter `cd` command with frecency
- **ripgrep (rg)** - Fast text search
- **fd** - User-friendly `find` alternative
- **NVM** - Node.js version manager
- **pnpm** - Fast, disk-efficient package manager

### Fonts & Theme

- **JetBrains Mono** - Beautiful monospace font
- **Starship theme** - Custom prompt with git integration

### Productivity Features

- **Auto-save/restore tmux sessions** - Via tmux-resurrect + continuum
- **Auto-update plugins** - Updates once per day when you open a new shell
- **Clipboard integration** - tmux-yank for copy/paste
- **Git shortcuts** - 40+ aliases + fuzzy branch checkout

## System Requirements

### Minimum

- **macOS 10.15+** (Intel or Apple Silicon) or **Ubuntu 20.04+**
- **curl** or **wget**
- **git**
- **~500MB** disk space

### Recommended

- **macOS 12+** or **Ubuntu 22.04+**
- **2GB+ RAM**

## Platform Support

| OS | Version | Status | Notes |
|---|---|---|---|
| macOS | 10.15+ | ✅ Supported | Homebrew required |
| Ubuntu | 20.04+ | ✅ Supported | apt-based |
| Debian | 11+ | ✅ Supported | apt-based |
| Fedora | 35+ | ✅ Supported | dnf-based |
| Arch Linux | Latest | ✅ Supported | pacman-based |

## First Time After Installation

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

# Try custom gcof (git checkout fuzzy)
gcof    # Interactively select git branch to checkout
```

## Common Commands

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
Ctrl+A D                  # Detach from session
Ctrl+A S                  # Browse sessions

# Navigate faster
z <folder>   # Jump to frequently used folder
cd -         # Go to previous directory

# Search files
rg "pattern" # ripgrep search
fd "*.ts"    # Find TypeScript files
```

**📚 See [SHORTCUTS.md](./SHORTCUTS.md) for complete reference of all aliases, keybindings, and shortcuts.**

## Configuration Files

```
~/.zshrc                    # Zsh configuration
~/.tmux.conf                # Tmux configuration
~/.config/starship.toml     # Starship prompt theme
~/.zsh/gcof.zsh             # Custom functions
~/.config/ghostty/config    # Ghostty terminal config
```

### Customize After Installation

**Edit shell config:**

```bash
vim ~/.zshrc
source ~/.zshrc  # Reload
```

**Edit prompt theme:**

```bash
vim ~/.config/starship.toml
exec zsh  # Reload
```

**Edit tmux config:**

```bash
vim ~/.tmux.conf
tmux source ~/.tmux.conf  # Reload configuration
```

**Important:** Config reload only affects the current session. For a fresh start:

```bash
# Detach and reattach
Ctrl+A D                    # Detach from session
tmux attach                 # Reattach (applies new config)

# Or kill and recreate session
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

**Add your own aliases:**

```bash
# Add to ~/.zshrc before the last line
alias myalias="my command"
```

## Auto-Update

Plugins are automatically updated **once per day** when you open a new shell:

- Checks for updates on shell startup
- Runs in background (doesn't block your prompt)
- Updates Zinit itself, all plugins, and OMZ snippets
- Uses timestamp file to track last update (`~/.zinit-last-update`)

### Manual Update

```bash
# Update all zsh plugins
zinit update --all

# Update Zinit itself
zinit self-update

# Update all tmux plugins
cd ~/.tmux/plugins/tpm && ./bin/update_plugins all

# Update Starship
starship self update
```

## Troubleshooting

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
# Restart terminal, then check: Settings > Font > JetBrains Mono

# Check installation status
./setup.sh  # Run again - it's idempotent!
```

## How It Works

The setup script:

1. Detects your OS and architecture
2. Installs/updates package managers (Homebrew, apt)
3. Installs zsh, tmux, starship, and 10+ dev tools
4. Downloads and installs JetBrains Mono font
5. Creates/deploys configuration files
6. Initializes Zinit and installs plugins
7. Sets up tmux plugin manager and plugins
8. Configures auto-update on shell startup (once per day)
9. Verifies all installations
10. Prints summary with next steps

**Key features:**

- ✅ Idempotent - Safe to run multiple times
- ✅ Error recovery - Shows what failed, lets you fix and re-run
- ✅ Backup strategy - Backs up existing configs before overwriting
- ✅ Platform aware - Different paths for macOS vs Linux

## Installation Time

- **First time:** 10-15 minutes (includes downloads and Homebrew setup on macOS)
- **Subsequent runs:** 2-3 minutes (checks for updates)
- **On faster internet:** 5-8 minutes

## License

MIT

## Contributing

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
- [ ] Tmux plugins load (check with `Ctrl+A U`)
- [ ] Starship prompt displays correctly
- [ ] Fonts render correctly
- [ ] Auto-update works (check logs after 24 hours)

## Support

- 📖 See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for common issues
- 💬 Open an issue on GitHub
- 📝 Check logs: `~/.setup.log`

## Roadmap

- [ ] Interactive installer with prompts
- [ ] Desktop environment detection (GNOME, KDE, etc.)
- [ ] Optional tools menu (Neovim, Lazygit, etc.)
- [ ] Backup and restore configs to cloud
- [ ] Automated testing on multiple platforms

## Learn More

- [Zinit documentation](https://github.com/zdharma-continuum/zinit)
- [Tmux guide](https://github.com/tmux/tmux/wiki)
- [Starship configuration](https://starship.rs/config/)
- [fzf examples](https://github.com/junegunn/fzf)

---

**Happy coding!**
