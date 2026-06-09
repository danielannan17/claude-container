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

| Option       | Description                                                          |
| ------------ | -------------------------------------------------------------------- |
| `--isolated` | Block all internet except Anthropic API and GitHub                   |

## Environment Variables

| Variable                      | Default      | Description                                                                 |
| ----------------------------- | ------------ | --------------------------------------------------------------------------- |
| `ANTHROPIC_API_KEY`           | _(none)_     | API key for Claude, passed into the container                               |
| `CLAUDE_SANDBOX_PROJECTS`     | `~/Projects` | Host directory to mount as projects                                         |
| `CLAUDE_SANDBOX_CLAUDE_DIR`   | `~/.claude`  | Host directory for Claude config                                            |
| `GITHUB_APP_PEM`              | _(none)_     | Path to the GitHub App private key `.pem` file on the host                  |
| `GITHUB_APP_CLIENT_ID`        | _(none)_     | Client ID of the GitHub App (used as `iss` in JWT for token generation)     |
| `GITHUB_APP_INSTALLATION_ID`  | _(none)_     | Installation ID of the GitHub App (found in the installation URL on GitHub) |

## What's Included

The container image is based on Ubuntu 24.04 and includes:

- Node.js 23.x with [Claude Code](https://github.com/anthropics/claude-code) installed globally
- [GitHub CLI](https://github.com/cli/cli) (`gh`)
- Python 3 with [uv](https://github.com/astral-sh/uv)
- [Neovim](https://github.com/neovim/neovim), git, zsh with [oh-my-zsh](https://github.com/ohmyzsh/ohmyzsh), [fzf](https://github.com/junegunn/fzf), [lazygit](https://github.com/jesseduffield/lazygit)
- [gh-dash](https://github.com/dlvhdr/gh-dash) (GitHub dashboard, via `gh dash`)
- jq, curl, ripgrep
