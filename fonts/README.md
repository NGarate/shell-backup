# Fonts Directory

This directory is for font files that can be distributed with shell-backup.

## Current Font: JetBrains Mono

The setup script now automatically downloads and installs **JetBrains Mono** from the official GitHub releases. No manual font installation is required.

### Download Details

- **Font:** JetBrains Mono
- **Version:** 2.304
- **Source:** https://github.com/JetBrains/JetBrainsMono/releases
- **Download URL:** `https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip`

### Installation Locations

The script installs fonts to:
- **macOS:** `~/Library/Fonts/`
- **Linux:** `~/.local/share/fonts/`

### What Gets Installed

All TTF font files are installed:
- JetBrainsMono-Regular.ttf
- JetBrainsMono-Bold.ttf
- JetBrainsMono-Italic.ttf
- JetBrainsMono-BoldItalic.ttf
- JetBrainsMono-Light.ttf
- JetBrainsMono-Medium.ttf
- JetBrainsMono-SemiBold.ttf
- JetBrainsMono-ExtraLight.ttf
- JetBrainsMono-ExtraBold.ttf
- And their italic variants

## Font Installation During Setup

When you run `./setup.sh`:
1. It checks if JetBrains Mono fonts are already installed
2. If not, downloads the official release from GitHub
3. Extracts and installs all TTF files to the system font directory
4. On Linux, runs `fc-cache` to refresh the font cache

## Troubleshooting

If fonts are not being detected during setup, see [TROUBLESHOOTING.md](../TROUBLESHOOTING.md#jetbrains-mono-not-found-during-setup-or-verification)

## Using Alternative Fonts

If you prefer a different font, you can:

1. Install it manually to your system font directory
2. Update the terminal configuration (e.g., Ghostty config in `~/.config/ghostty/config`)
3. Update Starship configuration if needed (`~/.config/starship.toml`)

Recommended alternatives:
- **Fira Code** - Popular programming font with ligatures
- **Iosevka** - Tall, narrow monospace font
- **Cascadia Code** - Microsoft's programming font
- **Source Code Pro** - Adobe's monospace font

## Notes

- Font files should be `.ttf` or `.otf` format
- For best terminal compatibility with icons, use Nerd Fonts variants
- Terminal must be configured to use the installed font
- After setup, restart your terminal to apply the font

---

See [Font Setup Troubleshooting](../TROUBLESHOOTING.md) for help with font display issues.
