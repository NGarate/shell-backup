#!/bin/zsh
# Git Checkout Fuzzy (gcof)
# Interactive git branch checkout using fzf
# Author: ngarate
# 
# Features:
#   - Fuzzy search through branches
#   - Sort branches by date (newest first)
#   - Local branches by default
#   - Switch to remote branches with -r flag
#   - Display branch description from 'git config'
#
# Usage:
#   gcof           # Switch to a local branch
#   gcof -r        # Switch to a remote branch
#   gcof -a        # Switch to any branch (local and remote)

function gcof() {
  local branch_type="--list"
  local remote_prefix=""
  local help=false

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -r|--remote)
        branch_type="-r"
        remote_prefix="origin/"
        shift
        ;;
      -a|--all)
        branch_type="-a"
        shift
        ;;
      -h|--help)
        help=true
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  if [[ "$help" == true ]]; then
    cat <<EOF
Git Checkout Fuzzy (gcof)

USAGE:
  gcof [OPTIONS]

OPTIONS:
  -r, --remote    Check out a remote branch
  -a, --all       Show both local and remote branches
  -h, --help      Show this help message

EXAMPLES:
  gcof            # Interactive local branch selection
  gcof -r         # Interactive remote branch selection
  gcof -a         # Interactive any branch selection

FEATURES:
  - Branches sorted by commit date (newest first)
  - Fuzzy search with fzf
  - Preview of branch details
  - Current branch marked with '*'

DEPENDENCIES:
  - fzf
  - git

EOF
    return 0
  fi

  # Check if required commands exist
  if ! command -v fzf &> /dev/null; then
    echo "Error: fzf is required but not installed"
    echo "Install with: brew install fzf (macOS) or apt install fzf (Linux)"
    return 1
  fi

  if ! command -v git &> /dev/null; then
    echo "Error: git is required but not installed"
    return 1
  fi

  # Check if in a git repository
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not in a git repository"
    return 1
  fi

  # Get branches sorted by most recent commit date
  local selected_branch
  selected_branch=$(
    git branch $branch_type --sort=-committerdate --format='%(refname:short)|%(subject)|%(committerdate:relative)' |
    sed "s|^origin/||" |
    fzf \
      --ansi \
      --nth 1 \
      --delimiter='|' \
      --preview='git log --oneline --graph --color=always -10 $(echo {} | cut -d"|" -f1)' \
      --preview-window='right:50%' \
      --height='40%' \
      --header='Select branch (Ctrl+C to cancel)' \
      --pointer='▶' \
      --marker='✓' \
      --bind='ctrl-v:toggle-preview' \
      --bind='ctrl-d:preview-down' \
      --bind='ctrl-u:preview-up' \
      --color='hl:bold:underline,hl+:bold:underline:reverse' \
      --no-mouse \
      --layout=reverse \
      -q "" |
    cut -d'|' -f1 |
    xargs
  )

  # Check if a branch was selected
  if [[ -z "$selected_branch" ]]; then
    echo "No branch selected"
    return 1
  fi

  # Get current branch
  local current_branch=$(git rev-parse --abbrev-ref HEAD)

  # Check if branch is the same as current
  if [[ "$selected_branch" == "$current_branch" ]]; then
    echo "Already on '$selected_branch'"
    return 0
  fi

  # Checkout the branch
  if [[ "$branch_type" == "-r" ]]; then
    # For remote branches, create local tracking branch
    if git checkout -b "$selected_branch" "origin/$selected_branch" 2>/dev/null; then
      echo "✓ Switched to local branch '$selected_branch' tracking origin/$selected_branch"
      return 0
    else
      # Try direct checkout if tracking fails
      if git checkout "$selected_branch" 2>/dev/null; then
        echo "✓ Switched to branch '$selected_branch'"
        return 0
      else
        echo "✗ Failed to checkout '$selected_branch'"
        return 1
      fi
    fi
  else
    # For local branches
    if git checkout "$selected_branch" 2>/dev/null; then
      echo "✓ Switched to branch '$selected_branch'"
      return 0
    else
      echo "✗ Failed to checkout '$selected_branch'"
      return 1
    fi
  fi
}

# Alias for quick access
alias gcof='gcof'

# Completion function for zsh
_gcof_completion() {
  local -a options=('-r:checkout remote branch' '-a:checkout any branch' '-h:show help')
  _describe 'gcof options' options
}

# Register completion if using oh-my-zsh or similar
if [[ -n "$ZSH_VERSION" ]]; then
  compdef _gcof_completion gcof
fi
