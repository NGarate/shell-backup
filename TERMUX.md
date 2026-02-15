# Using shell-backup via SSH from Termux (Android)

This guide documents how to connect from an Android phone using Termux to a laptop/server running the shell-backup configuration, ensuring icons, colors, and fonts render correctly.

## Prerequisites

- Ubuntu laptop/server with shell-backup script already installed and running
- Android phone with Termux installed (from F-Droid recommended)

---

## Step 1: Install Termux

**Recommended:** Install from F-Droid (more up-to-date than Play Store)

1. Install F-Droid app from https://f-droid.org/
2. Search for "Termux" and install

**Alternative:** Install from Play Store (may be outdated)

---

## Step 2: Install Required Packages in Termux

Open Termux and run:

```bash
# Update packages
pkg update

# Install SSH client
pkg install openssh

# Install tools needed for font installation
pkg install curl unzip
```

---

## Step 3: Install Nerd Font in Termux

The Starship prompt and other tools use Nerd Font icons. Without these, you'll see "tofu" boxes (□) instead of icons.

Install JetBrains Mono Nerd Font manually:

```bash
# Create termux config directory if it doesn't exist
mkdir -p ~/.termux

# Install required packages
pkg install unzip curl

# Change to the termux config directory
cd ~/.termux

# Download JetBrains Mono Nerd Font (v3.4.0)
curl -L -o JetBrainsMono.zip \
  "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip"

# Extract the ZIP file
unzip -o JetBrainsMono.zip

# Move the Regular variant to font.ttf (required filename)
mv JetBrainsMonoNerdFont-Regular.ttf font.ttf

# Clean up downloaded and extracted files
rm -f JetBrainsMono.zip JetBrainsMono*.ttf OFL.txt README.md

# Apply font changes immediately (no restart required)
termux-reload-settings
```

### One-liner (Copy & Paste)

```bash
mkdir -p ~/.termux && cd ~/.termux && curl -L -o JetBrainsMono.zip "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip" && unzip -o JetBrainsMono.zip && mv JetBrainsMonoNerdFont-Regular.ttf font.ttf && rm -f JetBrainsMono.zip JetBrainsMono*.ttf OFL.txt README.md && termux-reload-settings
```

---

## Step 4: Configure SSH Connection

### Basic SSH Connection

```bash
ssh username@your-laptop-ip
```

### SSH with Proper Terminal Settings (Recommended)

To ensure colors and terminal features work correctly:

```bash
# Force 256-color support
ssh -o "SendEnv=TERM" -t username@your-laptop-ip "export TERM=xterm-256color; exec zsh -l"
```

Or create an SSH config file for convenience:

```bash
mkdir -p ~/.ssh
nano ~/.ssh/config
```

Add:

```
Host laptop
    HostName your-laptop-ip
    User your-username
    SendEnv TERM
    RequestTTY yes
    RemoteCommand export TERM=xterm-256color && exec zsh -l
```

Then connect with:
```bash
ssh laptop
```

---

## Step 5: Verify Everything Works

After connecting via SSH, verify:

### 1. Icons Display Correctly

```bash
# Should show a gear icon and other symbols
echo "Testing: 󰍟 󰁹 󰢝 󰁼 󰂑 󰂎  "
```

### 2. Colors Work

```bash
# Should show colored output
ls --color=auto

# Check terminal colors
echo $TERM
# Should output: xterm-256color
```

### 3. Starship Prompt Renders

You should see:
- Custom directory icons
- Git branch symbols ()
- OS-specific icon ( for Ubuntu)
- Battery indicator (if applicable)

### 4. Zinit Plugins Load

```bash
zinit list
```

Should show all loaded plugins without errors.

---

## Step 6: Optimize Termux for Better Experience

### Enable Extra Keys (Recommended)

Add a row of extra keys (Ctrl, Alt, arrows, etc.) above the keyboard:

```bash
mkdir -p ~/.termux
cat > ~/.termux/termux.properties << 'EOF'
extra-keys = [['ESC','/','-','HOME','UP','END','PGUP'],['TAB','CTRL','ALT','LEFT','DOWN','RIGHT','PGDN']]
EOF

termux-reload-settings
```

### Fix Backspace Behavior

If backspace doesn't work correctly in SSH sessions:

```bash
echo 'stty erase ^?' >> ~/.bashrc
```

### Prevent Screen Timeout (Optional)

```bash
termux-wake-lock
```

---

## Step 7: SSH Key Authentication (Optional but Recommended)

Generate SSH key in Termux:

```bash
ssh-keygen -t ed25519 -C "termux@android"
```

Copy public key to your laptop:

```bash
ssh-copy-id username@your-laptop-ip
```

Now you can connect without password:
```bash
ssh username@your-laptop-ip
```

---

## Troubleshooting

### Icons Show as Boxes (□)

**Problem:** Font doesn't support Nerd Font glyphs

**Solution:** Re-run the font installation commands from Step 3.

### Colors Don't Work

**Problem:** TERM variable not set correctly

**Solution:**
```bash
# Add to laptop's ~/.zshrc or run after SSH
export TERM=xterm-256color
```

### Tmux Won't Start Automatically

**Problem:** The .zshrc only auto-starts tmux in Ghostty terminal

**Solution:** Add to ~/.zshrc on the laptop:

```bash
# Auto-start tmux in SSH sessions too
if [[ -z "$TMUX" && "$SSH_CONNECTION" != "" ]]; then
    tmux new-session -A -s main
fi
```

### Keyboard Shortcuts Not Working

**Problem:** Termux intercepts certain key combinations

**Solutions:**
- Use the extra keys row (see Step 6)
- For Ctrl+ combinations, use the Volume Down key as Ctrl
- Or configure termux.properties for custom key mappings

### Font Looks Too Small/Large

**Solution:** Pinch to zoom in/out in Termux to adjust font size.

### Copy/Paste Between Phone and Laptop

**Note:** Clipboard sync doesn't work automatically over SSH

**Workaround:**
- Copy from phone: Long-press → Copy
- Paste to laptop: Long-press → Paste (or use keyboard shortcut)
- For text from laptop: Select in terminal, it copies to phone clipboard

---

## Quick Reference Commands

```bash
# Connect to laptop
ssh username@laptop-ip

# Connect with proper terminal settings
ssh -t username@laptop-ip "export TERM=xterm-256color; exec zsh -l"

# Using SSH config (if set up)
ssh laptop

# Reload Termux settings after changes
termux-reload-settings

# Quick install Nerd Font (creates ~/.termux, downloads, extracts, applies)
mkdir -p ~/.termux && cd ~/.termux && \
pkg install -y unzip curl 2>/dev/null; \
curl -L -o JetBrainsMono.zip \
  "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip" && \
unzip -o JetBrainsMono.zip && \
mv JetBrainsMonoNerdFont-Regular.ttf font.ttf && \
rm -f JetBrainsMono.zip JetBrainsMono*.ttf OFL.txt README.md && \
termux-reload-settings
```

---

## What Works vs What Doesn't

### ✅ Works Well
- Zsh with all plugins (autosuggestions, syntax highlighting)
- Starship prompt with icons and colors
- Tmux sessions and keybindings
- FZF fuzzy finder
- Vim/Neovim with colors
- Git with colored output
- All command-line tools (fzf, zoxide, ripgrep, fd)

### ⚠️ Limitations
- No native clipboard sync between Android and remote host
- Some terminal emulators may handle colors slightly differently
- Touch-based text selection can be tricky
- No automatic font detection (must install Nerd Font manually)

### ❌ Not Applicable
- Ghostty terminal (runs on laptop only)
- Font installation on laptop (not visible via SSH)
- Laptop's GUI applications

---

## Tips for Best Experience

1. **Use landscape mode** for wider terminal view
2. **Enable auto-rotate** to switch between portrait/landscape
3. **Use a Bluetooth keyboard** for heavy typing sessions
4. **Set up SSH keys** to avoid typing password every time
5. **Use tmux** to persist sessions when switching apps/disconnecting
6. **Install Termux:Widget** for quick shortcuts to common SSH commands

---

## Related Documentation

- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - General troubleshooting
- [setup.sh](./setup.sh) - Main setup script
- Starship config: `~/.config/starship.toml` on the laptop
- Zsh config: `~/.zshrc` on the laptop
