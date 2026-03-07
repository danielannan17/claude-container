# Design Log #000: Project Overview

**Date Created:** 2026-03-07
**Status:** In Progress

## Purpose

Docker-based sandbox for running Claude Code in an isolated container. Provides a secure, reproducible environment with host project access, shell customization, and GitHub App authentication.

## Architecture

```
Host Machine
├── ~/Projects/          → mounted at /home/dev/projects
├── ~/.claude/           → mounted at /home/dev/.claude
├── ~/.config/nvim/      → mounted at /home/dev/.config/nvim
└── <PEM file>           → mounted at /home/dev/.github-app-key.pem (read-only)

Container (Ubuntu 24.04)
├── Claude Code (npm global)
├── gh CLI (GitHub App auth via JWT)
├── git (credential helper for GitHub App)
├── Node.js 23.x, Python 3 + uv
├── Neovim, zsh + oh-my-zsh, fzf
└── Optional network isolation (iptables)
```

## Key Files

- `Dockerfile` - Container image definition
- `claude-sandbox.sh` - Build/start/stop/status CLI
- `github-app-auth.sh` - Configures git + gh to use GitHub App token helper
- `github-app-token.sh` - Generates fresh GitHub App installation tokens on demand
- `.env` / `.env.sample` - Configuration (API keys, GitHub App credentials)

## Design Logs

- [#001 - Network Isolation](./001-network-isolation.md)
- [#002 - Zsh Setup](./002-zsh-setup.md)
- [#003 - GitHub App Authentication](./003-github-app-auth.md)
