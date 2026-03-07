# claude-container

A Docker-based sandbox for running Claude Code in an isolated container. Mounts your projects and Claude config from the host, with an optional network isolation mode that restricts all traffic to only the Anthropic API.

## Prerequisites

- Docker
- rsync

## Quick Start

```bash
# Build and start the container
./claude-sandbox.sh

# Or just build the image
./claude-sandbox.sh build
```

## Usage

```
claude-sandbox [--isolated] [start|stop|status|build]
```

### Commands

| Command  | Description                                  |
| -------- | -------------------------------------------- |
| _(none)_ | Start or attach to the sandbox container     |
| `stop`   | Stop and remove the container                |
| `status` | Show container status                        |
| `build`  | Rebuild the Docker image                     |

### Options

| Option       | Description                                    |
| ------------ | ---------------------------------------------- |
| `--isolated` | Block all internet except the Anthropic API    |

## What's Mounted

The container mounts the following from the host:

- `~/Projects` (or `$CLAUDE_SANDBOX_PROJECTS`) → `/home/dev/projects`
- `~/.claude` (or `$CLAUDE_SANDBOX_CLAUDE_DIR`) → `/home/dev/.claude`
- `~/.config/nvim` → `/home/dev/.config/nvim`
- `~/.gitconfig` → `/home/dev/.gitconfig` (read-only)

## Environment Variables

| Variable                   | Default        | Description                  |
| -------------------------- | -------------- | ---------------------------- |
| `CLAUDE_SANDBOX_PROJECTS`  | `~/Projects`   | Host projects directory      |
| `CLAUDE_SANDBOX_CLAUDE_DIR`| `~/.claude`    | Host Claude config directory |
| `ANTHROPIC_API_KEY`        | _(none)_       | Passed into the container    |

## Network Isolation

With `--isolated`, the container uses iptables to block all outbound traffic except:

- Loopback
- DNS (UDP port 53)
- HTTPS to `api.anthropic.com` and `anthropic.com`

## What's Included

The container image is based on Ubuntu 24.04 and includes:

- Node.js 23.x with Claude Code installed globally
- Python 3 with uv
- Neovim, git, zsh (with oh-my-zsh), fzf
- ffmpeg, jq, curl
