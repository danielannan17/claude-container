# Design Log #000: Project Overview

**Date Created:** 2026-03-07
**Status:** In Progress

## Purpose

Docker-based sandbox for running Claude Code in an isolated container. Provides a secure, reproducible environment with host project access, shell customization, and optional network isolation.

## Architecture

```
Host Machine
├── ~/Projects/          → mounted at /home/dev/projects
├── ~/.claude/           → mounted at /home/dev/.claude
├── ~/.config/nvim/      → mounted at /home/dev/.config/nvim
├── ~/.gitconfig         → mounted at /home/dev/.gitconfig (read-only)
├── ~/.zshrc             → mounted at /home/dev/.zshrc (read-only)
└── ~/.oh-my-zsh/        → mounted at /home/dev/.oh-my-zsh (read-only)

Container (Ubuntu 24.04)
├── Claude Code (npm global)
├── Node.js 23.x, Python 3 + uv
├── Neovim, git, zsh + oh-my-zsh, fzf
├── macOS path symlinks (/Users/daniel → /home/dev)
└── Optional network isolation (iptables)
```

## Key Files

- `Dockerfile` - Container image definition
- `claude-sandbox.sh` - Build/start/stop/status CLI

## Design Logs

- [#001 - Network Isolation](./001-network-isolation.md)
