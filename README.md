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

## Environment Variables

Copy `.env.sample` to `.env` and fill in the values:

```bash
cp .env.sample .env
```

| Variable                      | Default      | Description                                                                 |
| ----------------------------- | ------------ | --------------------------------------------------------------------------- |
| `ANTHROPIC_API_KEY`           | _(none)_     | API key for Claude, passed into the container                               |
| `CLAUDE_SANDBOX_PROJECTS`     | `~/Projects` | Host directory to mount as projects                                         |
| `CLAUDE_SANDBOX_CLAUDE_DIR`   | `~/.claude`  | Host directory for Claude config                                            |
| `GITHUB_APP_PEM`              | _(none)_     | Path to the GitHub App private key `.pem` file on the host                  |
| `GITHUB_APP_CLIENT_ID`        | _(none)_     | Client ID of the GitHub App (used as `iss` in JWT for token generation)     |
| `GITHUB_APP_INSTALLATION_ID`  | _(none)_     | Installation ID of the GitHub App (found in the installation URL on GitHub) |

## GitHub App Authentication

If `GITHUB_APP_PEM`, `GITHUB_APP_CLIENT_ID`, and `GITHUB_APP_INSTALLATION_ID` are set, the container automatically configures `git` and `gh` CLI to authenticate via the GitHub App.

- **git** uses a credential helper that generates a fresh installation token on each push/pull/clone
- **gh** generates a fresh token on each invocation via a shell wrapper

Tokens are never stored — they're generated on demand, so there are no expiry issues.

## Network Isolation

With `--isolated`, the container uses iptables to block all outbound traffic except:

- Loopback
- DNS (UDP port 53)
- HTTPS to `api.anthropic.com`, `anthropic.com`, `api.github.com`, and `github.com`

## What's Included

The container image is based on Ubuntu 24.04 and includes:

- Node.js 23.x with Claude Code installed globally
- GitHub CLI (`gh`)
- Python 3 with uv
- Neovim, git, zsh (with oh-my-zsh), fzf
- ffmpeg, jq, curl
