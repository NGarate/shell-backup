# Shell-Backup Shortcuts & Reference

Complete reference guide for all aliases, keybindings, and shortcuts installed by shell-backup.

---

## Table of Contents

- [Shell Navigation](#shell-navigation)
- [Git Aliases](#git-aliases)
- [Tmux Keybindings](#tmux-keybindings)
- [History Navigation](#history-navigation)
- [Fuzzy Finder (fzf)](#fuzzy-finder-fzf)
- [Zoxide](#zoxide)
- [pnpm Aliases](#pnpm-aliases)
- [Useful Commands](#useful-commands)

---

## Shell Navigation

### Basic Movement

| Key | Action |
|-----|--------|
| `Ctrl+A` | Move cursor to beginning of line |
| `Ctrl+E` | Move cursor to end of line |
| `Alt+B` / `Ctrl+←` | Move backward one word |
| `Alt+F` / `Ctrl+→` | Move forward one word |
| `Ctrl+U` | Delete from cursor to beginning of line |
| `Ctrl+K` | Delete from cursor to end of line |
| `Ctrl+W` | Delete word backward |
| `Ctrl+Y` | Paste (yank) deleted text |
| `Ctrl+L` | Clear screen |
| `Ctrl+C` | Cancel current command |
| `Ctrl+D` | Exit shell (or delete character) |
| `Ctrl+R` | Search command history (fzf) |
| `Ctrl+T` | Browse files (fzf) |

### Zsh Autosuggestions

| Key | Action |
|-----|--------|
| `→` or `End` | Accept suggestion |
| `Ctrl+F` | Accept word from suggestion |
| `Ctrl+E` | Accept entire suggestion |

---

## Git Aliases

### Status & Info

| Alias | Command | Description |
|-------|---------|-------------|
| `gst` | `git status` | Show working tree status |
| `glog` | `git log --oneline --decorate --graph` | Pretty commit log |
| `glogs` | `git log --stat` | Log with file stats |
| `gloga` | `git log --oneline --decorate --graph --all` | Log all branches |
| `gdf` | `git diff` | Show changes |
| `gdfc` | `git diff --cached` | Show staged changes |
| `gsh` | `git show` | Show various objects |

### Branching

| Alias | Command | Description |
|-------|---------|-------------|
| `gco` | `git checkout` | Switch branches |
| `gcb` | `git checkout -b` | Create and switch to new branch |
| `gb` | `git branch` | List branches |
| `gba` | `git branch -a` | List all branches (local + remote) |
| `gbd` | `git branch -d` | Delete branch |
| `gbD` | `git branch -D` | Force delete branch |
| `gm` | `git merge` | Merge branches |
| `gma` | `git merge --abort` | Abort merge |

### Committing

| Alias | Command | Description |
|-------|---------|-------------|
| `ga` | `git add` | Stage files |
| `gaa` | `git add --all` | Stage all changes |
| `gc` | `git commit -v` | Commit with verbose |
| `gcmsg` | `git commit -m` | Commit with message |
| `gca` | `git commit -v -a` | Commit all changes |
| `gca!` | `git commit -v -a --amend` | Amend last commit |
| `gc!` | `git commit -v --amend` | Amend without adding |

### Remote Operations

| Alias | Command | Description |
|-------|---------|-------------|
| `gp` | `git push` | Push to remote |
| `gpf` | `git push --force-with-lease` | Force push safely |
| `gpf!` | `git push --force` | Force push (dangerous) |
| `gpu` | `git pull` | Pull from remote |
| `gpr` | `git pull --rebase` | Pull with rebase |
| `gf` | `git fetch` | Fetch from remote |
| `gfa` | `git fetch --all --prune` | Fetch all remotes |

### Stashing

| Alias | Command | Description |
|-------|---------|-------------|
| `gsta` | `git stash push` | Stash changes |
| `gstp` | `git stash pop` | Pop stash |
| `gstl` | `git stash list` | List stashes |
| `gstd` | `git stash drop` | Drop stash |
| `gstc` | `git stash clear` | Clear all stashes |
| `gsts` | `git stash show -p` | Show stash contents |

### Reset & Clean

| Alias | Command | Description |
|-------|---------|-------------|
| `grh` | `git reset` | Reset to commit |
| `grhh` | `git reset --hard` | Hard reset (destructive) |
| `grhs` | `git reset --soft` | Soft reset |
| `grm` | `git rm` | Remove files |
| `grmc` | `git rm --cached` | Unstage files |
| `gclean` | `git clean -fd` | Remove untracked files |
| `gpristine` | `git reset --hard && git clean -dfx` | Clean everything |

### Rebasing

| Alias | Command | Description |
|-------|---------|-------------|
| `grb` | `git rebase` | Rebase branch |
| `grba` | `git rebase --abort` | Abort rebase |
| `grbc` | `git rebase --continue` | Continue rebase |
| `grbi` | `git rebase -i` | Interactive rebase |
| `grbs` | `git rebase --skip` | Skip commit |

### Custom Functions

| Command | Description |
|---------|-------------|
| `gcof` | Fuzzy checkout branch - interactively select and checkout git branch |
| `gco` | `git checkout` - Use with fzf for interactive branch selection |

---

## Tmux Keybindings

### Prefix Key

**Prefix:** `Ctrl+A` (changed from default Ctrl+B)

### Session Management

| Key | Action |
|-----|--------|
| `Prefix + $` | Rename current session |
| `Prefix + S` | Switch/choose session |
| `Prefix + D` | Detach from session |
| `Prefix + s` | List all sessions |
| `Prefix + (` | Previous session |
| `Prefix + )` | Next session |
| `Prefix + L` | Switch to last session |

### Window Management

| Key | Action |
|-----|--------|
| `Prefix + c` | Create new window |
| `Prefix + ,` | Rename current window |
| `Prefix + &` | Kill current window |
| `Prefix + n` | Next window |
| `Prefix + p` | Previous window |
| `Prefix + l` | Last window |
| `Prefix + 0-9` | Switch to window number |
| `Prefix + w` | List all windows (interactive) |
| `Prefix + f` | Find window by name |
| `Prefix + .` | Move window to another index |

### Pane Management

| Key | Action |
|-----|--------|
| `Prefix + %` | Split pane vertically (left/right) |
| `Prefix + "` | Split pane horizontally (top/bottom) |
| `Prefix + x` | Kill current pane |
| `Prefix + z` | Toggle pane zoom (maximize) |
| `Prefix + q` | Show pane numbers |
| `Prefix + {` | Swap pane with previous |
| `Prefix + }` | Swap pane with next |
| `Prefix + !` | Break pane into new window |
| `Prefix + ;` | Go to last active pane |

### Pane Navigation

| Key | Action |
|-----|--------|
| `Prefix + ↑` | Select pane above |
| `Prefix + ↓` | Select pane below |
| `Prefix + ←` | Select pane left |
| `Prefix + →` | Select pane right |
| `Prefix + o` | Cycle through panes |
| `Prefix + Ctrl+o` | Rotate panes forward |
| `Prefix + Alt+o` | Rotate panes backward |

### Copy Mode

System clipboard integration is fully supported via tmux-yank. Works on:
- **macOS:** Native pbcopy/pbpaste
- **Linux (Wayland):** Uses wl-copy (wl-clipboard)
- **Linux (X11):** Uses xclip (auto-detected)
- **Linux (Ubuntu):** Automatically installs both wl-clipboard and xclip

| Key | Action |
|-----|--------|
| `Prefix + [` | Enter copy mode |
| `Prefix + ]` | Paste from buffer |
| `Prefix + =` | List paste buffers |
| `Prefix + -` | Delete most recent buffer |

**In Copy Mode (vi-style):**

| Key | Action |
|-----|--------|
| `Space` | Begin selection |
| `Enter` | Copy selection |
| `q` | Quit copy mode |
| `v` | Visual mode |
| `y` | Yank selection |
| `h/j/k/l` | Move cursor |
| `w/b` | Next/previous word |
| `0/$` | Start/end of line |
| `gg/G` | Top/bottom of buffer |
| `/` | Search forward |
| `?` | Search backward |
| `n/N` | Next/previous search result |

### Resizing Panes

| Key | Action |
|-----|--------|
| `Prefix + Alt+↑` | Resize pane up |
| `Prefix + Alt+↓` | Resize pane down |
| `Prefix + Alt+←` | Resize pane left |
| `Prefix + Alt+→` | Resize pane right |

### Layouts

| Key | Action |
|-----|--------|
| `Prefix + Space` | Cycle through layouts |
| `Prefix + Meta+1` | Even-horizontal layout |
| `Prefix + Meta+2` | Even-vertical layout |
| `Prefix + Meta+3` | Main-horizontal layout |
| `Prefix + Meta+4` | Main-vertical layout |
| `Prefix + Meta+5` | Tiled layout |

### Fullscreen

| Platform | Key | Action |
|----------|-----|--------|
| macOS | `Cmd+Shift+F` | Toggle fullscreen |
| Linux | `Alt+Shift+F` | Toggle fullscreen |

---

## History Navigation

### Arrow Keys (History Substring Search)

Type a prefix, then use arrows to search history:

| Key | Action | Example |
|-----|--------|---------|
| `↑` (Up) | Search backward in history matching prefix | `git` + `↑` shows only git commands |
| `↓` (Down) | Search forward in history matching prefix | `git` + `↓` moves to next git command |

### Standard History

| Key | Action |
|-----|--------|
| `Ctrl+R` | Search history interactively (fzf) |
| `Ctrl+P` | Previous command |
| `Ctrl+N` | Next command |
| `!!` | Run last command |
| `!n` | Run command number n from history |
| `!-n` | Run nth command from last |
| `!string` | Run last command starting with string |
| `!?string` | Run last command containing string |

---

## Fuzzy Finder (fzf)

### Default Keybindings

| Key | Action |
|-----|--------|
| `Ctrl+R` | Search command history |
| `Ctrl+T` | Browse files and directories |
| `Alt+C` | Change directory (cd) |

### In fzf Interface

| Key | Action |
|-----|--------|
| `Ctrl+J` / `↓` | Move down |
| `Ctrl+K` / `↑` | Move up |
| `Ctrl+N` | Move down |
| `Ctrl+P` | Move up |
| `Enter` | Select item |
| `Ctrl+C` / `Esc` | Cancel |
| `Tab` | Multi-select (toggle) |
| `Shift+Tab` | Multi-select (toggle backwards) |
| `Ctrl+A` | Select all |
| `Ctrl+D` | Deselect all |
| `Ctrl+G` | Deselect all |
| `Ctrl+/` | Toggle preview |
| `Ctrl+\` | Toggle preview |
| `?` | Show help |

### Search Syntax

| Pattern | Matches |
|---------|---------|
| `term` | Fuzzy match |
| `'term` | Exact match (prefix) |
| `^term` | Prefix match |
| `term$` | Suffix match |
| `!term` | Inverse match |
| `term1 term2` | AND match |
| `term1 \| term2` | OR match |

---

## Zoxide

Zoxide is a smarter cd command that remembers your frequently used directories.

### Commands

| Command | Description |
|---------|-------------|
| `z foo` | Jump to highest frequency directory matching foo |
| `z foo bar` | Jump to directory matching foo and bar |
| `z ~/foo` | Jump to absolute path |
| `z ..` | Go up one directory |
| `z -` | Go to previous directory |
| `zi` | Interactive selection with fzf |
| `zq foo` | Query and list matches without cd |
| `za /path` | Add directory to database |
| `zr /path` | Remove directory from database |

### Tips

- Just type `z` followed by any part of the directory name
- It learns from your usage patterns
- More frequently visited directories rank higher
- Works across all sessions

---

## pnpm Aliases

| Alias | Command | Description |
|-------|---------|-------------|
| `p` | `pnpm` | Run pnpm |
| `pa` | `pnpm add` | Add dependency |
| `pad` | `pnpm add --save-dev` | Add dev dependency |
| `pi` | `pnpm install` | Install dependencies |
| `pr` | `pnpm run` | Run script |
| `prd` | `pnpm run dev` | Run dev script |
| `pup` | `pnpm update` | Update packages |
| `ps` | `pnpm start` | Start project |
| `pt` | `pnpm test` | Run tests |
| `pb` | `pnpm build` | Build project |

---

## Useful Commands

### System

| Command | Description |
|---------|-------------|
| `z` | Smart cd (zoxide) |
| `rg` | Ripgrep - fast text search |
| `fd` | Fast find alternative |
| `fzf` | Fuzzy finder |
| `btm` | System monitor (if installed) |
| `exa` or `lsd` | Enhanced ls (if installed) |

### File Operations

| Command | Description |
|---------|-------------|
| `Ctrl+T` | Find file with fzf |
| `Alt+C` | Find directory with fzf |
| `cat file \| fzf` | Browse file content |
| `cd **<Tab>` | Fuzzy cd completion |
| `vim **<Tab>` | Fuzzy file open |

### Process Management

| Command | Description |
|---------|-------------|
| `ps aux \| fzf` | Find process |
| `kill **<Tab>` | Fuzzy kill |
| `killall **<Tab>` | Fuzzy killall |

### Git Workflow Examples

```bash
# Quick workflow
gst                    # Check status
gaa                    # Stage all
gcmsg "feat: add feature"  # Commit
gp                     # Push

# Branch workflow
gco -b feature-branch  # Create and switch branch
gaa && gcmsg "wip"     # Quick commit
gp -u origin feature-branch  # Push new branch

# Interactive rebase
glog                   # See commits
grbi HEAD~3            # Rebase last 3 commits
# (in editor: pick/squash/fixup/reword/drop)
```

### Tmux Workflow Examples

```bash
# Start tmux
tmux new -s project    # Create named session
tmux attach -t project # Attach to session

# Common workflow inside tmux
Prefix + c             # Create new window
tmux rename-window api # Rename window
Prefix + %             # Split vertically
Prefix + "             # Split horizontally
Prefix + Arrow         # Navigate panes
Prefix + z             # Maximize current pane
Prefix + x             # Close current pane

# Copy text
Prefix + [             # Enter copy mode
Space                  # Start selection
Enter                  # Copy selection
Prefix + ]             # Paste
```

---

## Quick Reference Card

### Most Used Commands

```
Git:          gst  ga  gcmsg  gp  gco  gcb  glog  gdf
Tmux:         Prefix+c  Prefix+%  Prefix+"  Prefix+Arrow  Prefix+z
Navigation:   z <dir>  Ctrl+R  Ctrl+T  Alt+C
pnpm:         p  pa  pi  pr  prd
```

### Tmux Prefix: Ctrl+A

```
Sessions:  $ S D s ( ) L
Windows:   c , & n p l 0-9 w f .
Panes:     % " x z q { } ! ;  ↑↓←→ o
Copy:      [ ] = -
Layout:    Space M-1 M-2 M-3 M-4 M-5
```

---

## Customization

### Add Your Own Aliases

Edit `~/.zshrc`:

```bash
# Add at the end of ~/.zshrc
alias myalias="my command"
alias gs="git status"  # Override or add
```

Then reload:
```bash
source ~/.zshrc
```

### Modify Keybindings

Edit `~/.zshrc` for zsh keybindings or `~/.tmux.conf` for tmux.

### Learn More

- `zinit help` - Zinit plugin manager
- `tmux list-keys` - List all tmux keybindings
- `bindkey` - List zsh keybindings
- `alias` - List all aliases

---

**Last Updated:** 2026-02-04  
**For issues:** See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
