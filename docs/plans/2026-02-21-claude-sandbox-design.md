# Claude Sandbox Container Design

## Purpose

A Docker container to run Claude Code with `--dangerously-skip-permissions` safely, isolating risky operations from the host machine while maintaining access to project files and Claude Code configuration.

## Architecture

### Dockerfile (Ubuntu-based)

- **Base**: Ubuntu LTS
- **Runtimes**: Node.js (via nvm), Python 3
- **Tools**: git, curl, jq, common dev utilities
- **Claude Code**: Installed globally via `npm install -g @anthropic-ai/claude-code`
- **User**: Non-root `dev` user for correct file permission mapping
- **Working directory**: `/projects`

### Volume Mounts

| Host Path | Container Path | Mode | Purpose |
|---|---|---|---|
| `~/Projects` | `/projects` | read-write | Project files |
| `~/.claude` | `/home/dev/.claude` | read-write | Claude Code config, plugins, auth tokens |

### Run Script (`claude-sandbox`)

A bash script with smart container management:

1. **First run**: Starts a new container named `claude-sandbox` with volume mounts and env vars, attaches interactive bash shell
2. **Subsequent runs**: Detects running container, does `docker exec` to attach a new bash session to the existing container
3. **Stop command**: `claude-sandbox stop` to shut down the container

The script does NOT auto-start Claude Code. Users type `claude` manually inside the container, allowing multiple independent Claude Code instances.

### Authentication

Flexible auth handling:
- If `ANTHROPIC_API_KEY` is set in the host environment, it's passed to the container
- Otherwise, relies on OAuth tokens from the mounted `~/.claude` directory (for Claude Max subscribers)
- Re-authentication (if tokens expire) is done on the host machine; tokens flow in via the mount

## What's NOT Included

- No GUI/browser support
- No Docker-in-Docker
- No network restrictions (Claude Code needs internet access)
- No GPU passthrough
