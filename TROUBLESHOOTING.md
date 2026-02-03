# Troubleshooting Guide

## Common Issues & Solutions

### Installation Issues

#### ❌ "Permission denied" when running setup.sh

**Problem:** Script is not executable

**Solution:**
```bash
chmod +x setup.sh
./setup.sh
```

---

#### ❌ "curl: command not found" or "wget: command not found"

**Problem:** No downloader available

**Solutions:**
- **macOS:** Install Homebrew first: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
- **Ubuntu/Debian:** `sudo apt update && sudo apt install -y curl`
- **Fedora/RHEL:** `sudo dnf install -y curl`
- **Arch:** `sudo pacman -S curl`

---

#### ❌ "No internet connection" warning appears

**Problem:** Script cannot download packages

**Solutions:**
1. Check your internet connection: `ping google.com`
2. Check if proxy is needed: Contact your IT
3. For macOS behind proxy, set: `export https_proxy=http://proxy.company.com:8080`
4. Try again: `./setup.sh`

---

#### ❌ "Homebrew not found" on macOS

**Problem:** Homebrew didn't install properly

**Solutions:**
```bash
# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Add to PATH (Apple Silicon Macs)
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

# Verify
brew --version
```

---

#### ❌ "Command 'git' not found"

**Problem:** Git not installed

**Solutions:**
- **macOS:** `brew install git`
- **Ubuntu:** `sudo apt install -y git`
- **Fedora:** `sudo dnf install -y git`
- **Arch:** `sudo pacman -S git`

---

### Shell Configuration Issues

#### ❌ Plugins not loading after install

**Problem:** New shell needs to reload configuration

**Solution:**
```bash
# Reload zsh
exec zsh

# Or manually source config
source ~/.zshrc
```

**If plugins still not loading:**
```bash
# Check if plugins installed
zinit list

# Reinstall plugins
zinit self-update
zinit update --all
```

---

#### ❌ "command not found: zinit"

**Problem:** Zinit not initialized in .zshrc

**Solution:**
```bash
# Check if .zshrc has zinit init
grep "zinit init" ~/.zshrc

# If not found, re-run setup
./setup.sh
```

---

#### ❌ zsh not the default shell

**Problem:** System still using bash by default

**Solution:**
```bash
# Check current shell
echo $SHELL

# Change default (macOS/Linux)
chsh -s /bin/zsh

# Verify
echo $SHELL  # Should show /bin/zsh
```

---

#### ❌ "command not found: gcof" (git checkout fuzzy)

**Problem:** Custom function not loaded

**Solutions:**
1. Reload shell: `exec zsh`
2. Check if file exists: `ls ~/.zsh/gcof.zsh`
3. If missing, re-run setup: `./setup.sh`

---

### Prompt & Theme Issues

#### ❌ Starship not displaying correctly

**Problem:** Prompt not showing or showing `?` symbols

**Solutions:**
```bash
# Verify Starship installed
starship --version

# Check config exists
ls ~/.config/starship.toml

# Reload
exec zsh
```

---

#### ❌ Special symbols showing as boxes or question marks

**Problem:** Font not installed or terminal not configured for Iosevka

**Solutions:**

**macOS (Alacritty/Terminal):**
1. Check font installed: `ls ~/Library/Fonts/Iosevka*`
2. In Terminal/Alacritty: Settings → Font → Select "Iosevka Nerd Font"
3. Restart terminal
4. Check: Verify symbols display (should see git branch symbol)

**Linux:**
1. Check font installed: `fc-list | grep -i iosevka`
2. Update font cache: `fc-cache -fv ~/.local/share/fonts`
3. In terminal settings: Font → Select "Iosevka Nerd Font Mono"
4. Restart terminal

**If fonts still not showing:**
```bash
# Reinstall fonts
rm -rf ~/Library/Fonts/Iosevka* # macOS
# OR
rm -rf ~/.local/share/fonts/Iosevka* # Linux
./setup.sh  # Re-run setup
```

---

#### ❌ Starship shows "unknown" for git status

**Problem:** Git status parsing issue

**Solutions:**
```bash
# Check git config
git config --global --list

# Reset git config
git config --global --unset core.pager
git config --global core.pager "less -FR"

# Reload
exec zsh
```

---

### Tmux Issues

#### ❌ "command not found: tmux"

**Problem:** tmux not installed

**Solutions:**
- **macOS:** `brew install tmux`
- **Ubuntu:** `sudo apt install -y tmux`
- **Fedora:** `sudo dnf install -y tmux`
- **Arch:** `sudo pacman -S tmux`

---

#### ❌ tmux plugins not loading

**Problem:** tpm (tmux plugin manager) not initialized

**Solutions:**
```bash
# Check if tpm exists
ls ~/.tmux/plugins/tpm/bin/

# Install plugins manually
~/.tmux/plugins/tpm/bin/install_plugins

# Or use tmux key binding
tmux source ~/.tmux.conf
# Then Ctrl+B Shift+I (capital I) to install
```

---

#### ❌ "Sessions won't restore" or saved sessions lost

**Problem:** tmux-resurrect/continuum not working

**Solutions:**
```bash
# Check resurrection dir exists
ls ~/.local/share/tmux/resurrect/

# Manual save before closing tmux
tmux send-keys -t <session> "run-shell ~/.tmux/plugins/tmux-resurrect/scripts/save.sh" Enter

# Manually restore
run-shell ~/.tmux/plugins/tmux-resurrect/scripts/restore.sh
```

---

#### ❌ Copy/paste not working in tmux

**Problem:** tmux-yank not configured properly

**Solutions:**
```bash
# Manual copy to clipboard
tmux show-buffer | pbcopy  # macOS
tmux show-buffer | xclip   # Linux (need xclip)

# For Linux, install xclip
sudo apt install -y xclip  # Ubuntu
sudo dnf install -y xclip  # Fedora
sudo pacman -S xclip       # Arch

# Reload tmux
tmux source ~/.tmux.conf
```

---

### Node/Package Manager Issues

#### ❌ "command not found: node" or nvm not working

**Problem:** NVM not loaded in shell

**Solutions:**
```bash
# Check if NVM installed
ls ~/.nvm/nvm.sh

# Source nvm manually
source ~/.nvm/nvm.sh

# Install Node.js
nvm install --lts
nvm use --lts

# Verify
node --version
npm --version
```

---

#### ❌ pnpm aliases not working (p, pa, pi, etc.)

**Problem:** Aliases not loaded

**Solutions:**
```bash
# Reload shell
exec zsh

# Check if aliases set
alias p

# Manually set if missing
alias p='pnpm'
alias pa='pnpm add'
alias pi='pnpm install'
alias pd='pnpm remove'
alias pr='pnpm run'
alias prd='pnpm run dev'
alias pup='pnpm update'
alias ps='pnpm start'
alias pt='pnpm test'
alias pb='pnpm build'
```

---

#### ❌ "pnpm: command not found"

**Problem:** pnpm not installed

**Solutions:**
```bash
# Via npm
npm install -g pnpm

# Or reinstall via NVM
nvm install-latest-npm
npm install -g pnpm

# Verify
pnpm --version
```

---

### Git Issues

#### ❌ Git aliases not working (gst, gco, etc.)

**Problem:** Oh-My-Zsh git plugin not loaded

**Solutions:**
```bash
# Reload shell
exec zsh

# Check if plugin loaded
zinit list | grep git

# Manually reload plugins
zinit update --all
```

---

#### ❌ "SSH key permission denied" when using gcof or git push

**Problem:** SSH key permissions incorrect

**Solutions:**
```bash
# Check key permissions
ls -la ~/.ssh/

# Fix permissions
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub

# Add key to ssh-agent
ssh-add ~/.ssh/id_rsa

# Verify
ssh -T git@github.com
```

---

#### ❌ gcof (git checkout fuzzy) not working

**Problem:** fzf or git not available

**Solutions:**
```bash
# Check fzf installed
fzf --version

# Check git
git --version

# Reload gcof function
source ~/.zsh/gcof.zsh

# Try again
gcof
```

---

### Fuzzy Finder (fzf) Issues

#### ❌ Ctrl+R (history search) not working

**Problem:** fzf not integrated in shell

**Solutions:**
```bash
# Check fzf installed
fzf --version

# Check fzf integration in .zshrc
grep -i fzf ~/.zshrc

# Reload shell
exec zsh

# Try again
Ctrl+R
```

---

#### ❌ Ctrl+T (file browser) not working

**Problem:** fzf file integration not enabled

**Solutions:**
```bash
# Ensure fzf installed
brew install fzf  # macOS
sudo apt install -y fzf  # Ubuntu

# Source fzf key bindings
source <(fzf --zsh)

# Add to .zshrc if not already there
echo 'source <(fzf --zsh)' >> ~/.zshrc
exec zsh
```

---

### Zoxide Issues

#### ❌ "command not found: z"

**Problem:** zoxide not installed

**Solutions:**
```bash
# Install zoxide
brew install zoxide  # macOS
sudo apt install -y zoxide  # Ubuntu
sudo dnf install -y zoxide  # Fedora
sudo pacman -S zoxide  # Arch

# Add to .zshrc
eval "$(zoxide init zsh)"

# Reload
exec zsh
```

---

#### ❌ "z" command not jumping to frecent directories

**Problem:** zoxide database empty

**Solutions:**
```bash
# Use z normally for a while to build history
# First visit some directories
cd ~/projects
cd ~/Documents
cd /tmp

# Then try jumping
z proj  # Should jump to ~/projects

# Check database
zoxide query --list

# Reset if corrupted
rm ~/.local/share/zoxide/db.zo
```

---

### Ripgrep (rg) Issues

#### ❌ "command not found: rg"

**Problem:** ripgrep not installed

**Solutions:**
```bash
# Install ripgrep
brew install ripgrep  # macOS
sudo apt install -y ripgrep  # Ubuntu
sudo dnf install -y ripgrep  # Fedora
sudo pacman -S ripgrep  # Arch

# Verify
rg --version
```

---

### Auto-Update Issues

#### ❌ Plugins not updating automatically

**Problem:** LaunchAgent/Systemd timer not running

**Solutions:**

**macOS:**
```bash
# Check LaunchAgent loaded
launchctl list | grep zinit

# Load if not running
launchctl load ~/Library/LaunchAgents/com.ngarate.zinit-update.plist

# Check logs
tail -f /tmp/zinit-update.log

# Check next scheduled run
launchctl list | grep zinit
```

**Linux:**
```bash
# Check Systemd timer
systemctl --user list-timers | grep zinit

# Enable if not running
systemctl --user enable zinit-update.timer
systemctl --user start zinit-update.timer

# Check logs
journalctl --user -u zinit-update -f

# Check next scheduled run
systemctl --user list-timers zinit-update.timer
```

---

#### ❌ Update errors in logs

**Problem:** Network or permission issues during update

**Solutions:**
```bash
# Manual update
zinit update --all

# Clear cache if corrupted
rm -rf ~/.cache/zinit/*

# Re-initialize zinit
zinit self-update
zinit update --all
```

---

### Platform-Specific Issues

#### macOS: ❌ "Homebrew: command not found"

**Problem:** Homebrew not in PATH

**Solutions:**
```bash
# Add Homebrew to PATH
# For Apple Silicon (M1/M2/M3)
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

# For Intel Macs
echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.zprofile
source ~/.zprofile

# Verify
brew --version
```

---

#### Linux: ❌ "sudo: command not found" or permission denied

**Problem:** Running with wrong user or sudo not configured

**Solutions:**
```bash
# Check if sudo available
which sudo

# If not, use su instead
su -c "./setup.sh"

# Or give user sudo access (requires admin)
# Contact your system administrator
```

---

#### Linux: ❌ systemd timer not working (non-systemd systems)

**Problem:** System uses OpenRC (Alpine) or other init

**Solutions:**
- Alpine Linux is not fully supported
- Use cron instead:
```bash
# Add to crontab
crontab -e

# Add line:
0 2 * * * /home/user/.local/bin/zinit update --all >> /tmp/zinit-update.log 2>&1
```

---

### Alacritty Issues

#### ❌ "Alacritty not installed" or command not found

**Problem:** Alacritty not installed (it's optional)

**Note:** Alacritty is optional. Use your preferred terminal (Terminal.app, iTerm2, Kitty, etc.)

**Solutions (if you want Alacritty):**
```bash
# macOS
brew install --cask alacritty

# Ubuntu (needs to compile from source)
git clone https://github.com/alacritty/alacritty.git
cd alacritty
cargo build --release
sudo mv target/release/alacritty /usr/local/bin/

# Fedora
sudo dnf install alacritty
```

---

### Verification Issues

#### ❌ Verification fails at end of setup

**Problem:** Some components didn't install properly

**Solutions:**
1. Read the error messages carefully
2. Follow the specific fix for that component above
3. Run setup again: `./setup.sh` (it's idempotent and safe)

---

## When All Else Fails

### Full Reinstall

```bash
# Backup current config (optional)
cp ~/.zshrc ~/.zshrc.backup
cp ~/.tmux.conf ~/.tmux.conf.backup

# Remove all installed components
rm ~/.zshrc ~/.zshenv ~/.tmux.conf ~/.config/starship.toml ~/.zsh/gcof.zsh 2>/dev/null

# Remove plugin managers
rm -rf ~/.local/share/zinit ~/.tmux/plugins ~/.config/systemd/user/zinit-update.* 2>/dev/null

# Reinstall
./setup.sh
```

### Check Logs

```bash
# Main setup log
cat ~/.setup.log

# Recent errors
tail -50 ~/.setup.log | grep -i error

# Check specific component
grep "zsh" ~/.setup.log
grep "tmux" ~/.setup.log
grep "starship" ~/.setup.log
```

### Collect Diagnostic Info

Before opening an issue, gather:
```bash
# System info
uname -a

# Shell version
zsh --version

# Component versions
tmux -V
starship --version
git --version

# Check setup.log
cat ~/.setup.log

# Paste the above when reporting issue
```

---

## Getting Help

1. **Check this guide** - Most issues covered above
2. **Read logs** - `~/.setup.log` has detailed error info
3. **Search issues** - Check GitHub issues for your problem
4. **Report issue** - Include system info and logs from above

---

**Happy troubleshooting! 🔧**
