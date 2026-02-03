# Fonts Directory

This directory should contain the Iosevka Nerd Font files for distribution with shell-backup.

## Required Files

The setup script expects the following font files:
- `IosevkaTerm-ExtraLight.ttf` - Regular weight (normal text)
- `IosevkaTerm-Medium.ttf` - Bold weight (bold text)
- `IosevkaTerm-ExtraLight-Italic.ttf` - Italic weight (italic text)

## How to Add Fonts

### Option 1: Download from Nerd Fonts (Recommended)

1. Go to https://www.nerdfonts.com/font-downloads
2. Download "Iosevka Term Nerd Font" (the monospace terminal variant)
3. Extract the downloaded zip file
4. Copy the font files listed above into this directory:

```bash
# From your Downloads directory
cd ~/Downloads/IosevkaTermNerdFont
cp IosevkaTerm-ExtraLight.ttf /path/to/shell-backup/fonts/
cp IosevkaTerm-Medium.ttf /path/to/shell-backup/fonts/
cp IosevkaTerm-ExtraLight-Italic.ttf /path/to/shell-backup/fonts/
```

### Option 2: Copy from Existing Installation

If you already have Iosevka Nerd Font installed:

**macOS:**
```bash
cp ~/Library/Fonts/IosevkaTerm*.ttf /path/to/shell-backup/fonts/
```

**Linux:**
```bash
cp ~/.local/share/fonts/IosevkaTerm*.ttf /path/to/shell-backup/fonts/
```

### Option 3: Alternative Nerd Fonts

If you prefer a different monospace Nerd Font, you can substitute:
- Fira Code Nerd Font
- JetBrains Mono Nerd Font
- DejaVu Sans Mono Nerd Font
- Source Code Pro Nerd Font

Just update the font name references in:
1. `setup.sh` - Update the `deploy_fonts()` function
2. Configuration files - Update `alacritty.toml`, `starship.toml`, etc.

## Font Installation During Setup

When you run `./setup.sh`:
1. It checks if font files exist in this directory
2. Copies them to the appropriate system location:
   - **macOS:** `~/Library/Fonts/`
   - **Linux:** `~/.local/share/fonts/`
3. On Linux, runs `fc-cache` to refresh font cache

## Notes

- Font files should be `.ttf` or `.otf` format
- For best terminal compatibility, use Nerd Fonts variants
- Terminal must be configured to use the installed font
- After setup, restart your terminal to apply the font

---

See [Font Setup Troubleshooting](../TROUBLESHOOTING.md#special-symbols-showing-as-boxes-or-question-marks) for help with font display issues.
