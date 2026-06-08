# Shell-Backup Shortcuts & Reference

Complete reference guide for all aliases, keybindings, and shortcuts installed by shell-backup.

---

## Table of Contents

- [Shell Navigation](#shell-navigation)
- [Git Aliases](#git-aliases)
- [Ghostty Keybindings](#ghostty-keybindings)
- [Yazi](#yazi)
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

## Ghostty Keybindings

### Configured Keybindings

| Platform | Key | Action |
|----------|-----|--------|
| macOS | `Cmd+Shift+F` | Toggle fullscreen |
| Linux | `Alt+Shift+F` | Toggle fullscreen |
| All | `Shift+Enter` | Send escaped newline for OpenCode |

Ghostty tabs, splits, copy/paste, and window management use Ghostty's native defaults and application menus.

---

## Yazi

Yazi uses its native default keybindings. shell-backup configures two plugins: Git status signs in the file list and a Starship-powered header prompt.

### Commands

| Command | Description |
|---------|-------------|
| `yazi` | Open Yazi file manager |
| `ya pkg list` | List installed Yazi plugins |
| `ya pkg install` | Install plugins from `~/.config/yazi/package.toml` |
| `ya pkg upgrade` | Upgrade Yazi plugins |

### Configured Plugins

| Plugin | Effect |
|--------|--------|
| `yazi-rs/plugins:git` | Shows Git status signs beside files and directories |
| `Rolv-Apneseth/starship` | Replaces the Yazi header with a Starship prompt |

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
| `yazi` | Terminal file manager |
| `ya pkg list` | List Yazi plugins |
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

## Quick Reference Card

### Most Used Commands

```
Git:          gst  ga  gcmsg  gp  gco  gcb  glog  gdf
Ghostty:      Cmd+Shift+F (macOS)  Alt+Shift+F (Linux)  Shift+Enter
Yazi:         yazi  ya pkg list  ya pkg upgrade
Navigation:   z <dir>  Ctrl+R  Ctrl+T  Alt+C
pnpm:         p  pa  pi  pr  prd
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

Edit `~/.zshrc` for zsh keybindings, `~/.config/ghostty/config` for Ghostty keybindings, or `~/.config/yazi/yazi.toml` for Yazi settings.

### Learn More

- `zinit help` - Zinit plugin manager
- `ya help` - Yazi helper CLI
- `ya pkg list` - List Yazi plugins
- `bindkey` - List zsh keybindings
- `alias` - List all aliases

---

**Last Updated:** 2026-06-08
**For issues:** See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
