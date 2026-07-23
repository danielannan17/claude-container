# Design Log #004: Remote Server Deployment

**Date Created:** 2026-05-14
**Status:** Proposed

## Background

The container is currently designed for local use on macOS. Build-time copies (nvim, zsh, oh-my-zsh, gitconfig) come from the host's `$HOME`, and runtime bind-mounts (`~/Projects`, `~/.claude`, GitHub App pem, `.env`) expect macOS host paths. Considering running an image of this on a remote server.

## Problem

What changes, breaks, or becomes a risk when the image runs on a remote server instead of the local laptop. Image is not expected to leave personal control, but the risk surface still matters because the server's blast radius is larger than the laptop's.

## What Travels in the Image vs What Doesn't

### Baked in (identical on server)

- `nvim/` — `rsync`'d from `~/.config/nvim/` at build time
- `zsh/.zshrc`, `zsh/.gitconfig`, `zsh/.oh-my-zsh/` — copied from `$HOME`
- All system tools (claude code CLI, lazygit, gh, fzf, ripgrep, neovim, uv, node, pnpm)
- `dev` user with passwordless sudo
- macOS-style symlinks (`/Users/daniel/.claude`, `/Users/daniel/Projects`)
- `ENV SHELL=/usr/bin/zsh`, `HOST_UID=501`, `HOST_GID=20`

### Runtime / bind-mounted (gone on server unless re-provided)

| Thing | Source on laptop | Server impact |
|---|---|---|
| Projects | bind-mount `~/Projects` | No code unless mounted or cloned in |
| `~/.claude` (auth + history) | bind-mount `~/.claude` | Fresh Claude Code login required |
| `.claude.json` | bind-mount of repo-local file | Empty/missing |
| GitHub App `.pem` | bind-mount from `.env` path | gh/git auth broken until pem present |
| `GITHUB_APP_*` env | `.env` next to script | Need to provide on server |
| `.zsh_history` | bind-mount of repo-local file | Starts empty |

## Risk Surface

### What's inside the image (visible to anyone with the image, even after `RUN rm`, via `docker history` / `docker save`)

- `~/.gitconfig` — audited 2026-05-14, clean (name, email, GCM helper pointer, diff/push prefs). No embedded tokens. GCM helper path is a dangling reference in the container — harmless.
- `~/.zshrc` — needs re-audit per-build. Common leak: `export *_API_KEY=...`. Risk: anything `export`'d in zshrc ends up in image layers.
- `~/.oh-my-zsh/custom/` — possible stash for secrets in custom plugins/aliases.
- `~/.config/nvim/` — usually safe. Re-check if any plugin (avante, codecompanion, etc.) is configured with hardcoded API keys.

### Runtime privilege model

- `dev` has `NOPASSWD: ALL` sudo. Any shell in the container is effectively root inside the container.
- On laptop: host is yours — low concern.
- On server: anyone who lands a shell (compromised dep installed by Claude, exposed port, weak host SSH) has full container root + access to every mounted volume.

### `--dangerously-skip-permissions` (baked in via `terminal_cmd.patch`)

- Inside the container, Claude Code runs every tool call without prompting.
- On laptop: deliberate tradeoff inside a sandbox.
- On server: the container is the *only* boundary. Claude can `sudo`, exfiltrate any mounted data, hit any reachable endpoint, rewrite any file `dev` can touch. No per-tool confirmation backstop.
- **Decision needed:** keep the flag on for server builds, or maintain a separate server-targeted variant of the patch.

### Auth surfaces on the server

- **GitHub App pem** — anyone with shell in the container (or root on host) can mint installation tokens with whatever scopes the app has. Scope the App tightly (specific repos, minimal permissions). Treat the pem like an SSH private key.
- **`~/.claude`** — if copied to server, OAuth/API creds move with it. Anyone reading that dir on the server can impersonate the Claude account.
- **`.env`** — has App client/installation IDs. Less sensitive alone; full creds when combined with the pem.

### Operational gotchas

- **UID 501 collision.** Linux servers usually have first non-root user at UID 1000/1001. UID 501 may already exist (or not), and bind-mounted files will show as numeric UID regardless of "owner." Rebuild on the server with `--build-arg HOST_UID=$(id -u) HOST_GID=$(id -g)`.
- **macOS-path symlinks** (`/Users/daniel → /home/dev/...`) — harmless on Linux but means anything walking `/Users` finds the home structure.
- **`claude-sandbox.sh`** assumes local Docker daemon with host paths. Need a separate server-side wrapper (or run `docker run` directly).

## Questions and Answers

Q1: Keep `--dangerously-skip-permissions` enabled for server builds?
A: TBD. Probably no — the laptop sandbox justification doesn't carry over.

Q2: Push image to a private registry, or build directly on the server from a pushed source tree?
A: TBD. Registry is simpler; building on-server keeps the image off third-party storage but requires the source tree there.

Q3: How to provide `~/.zshrc` / `~/.gitconfig` for the image without leaking host secrets?
A: TBD. Options: (a) audit live host files before each build, (b) maintain trimmed `zsh/.zshrc.container` and `zsh/.gitconfig.container` checked into the repo, (c) generate them in the Dockerfile from a minimal template.

Q4: How tightly to scope the GitHub App used on the server?
A: TBD. Want to limit to specific repos and minimum perms for what the server actually needs.

Q5: Run server container behind reverse proxy / SSH tunnel, or expose directly?
A: TBD. Default plan: no published ports — reach via SSH only.

## Implementation Plan

Not yet planned. Phases to scope when starting:

1. Decide on per-server build vs registry, and on the `--dangerously-skip-permissions` policy.
2. Carve out a server-targeted build variant (separate Dockerfile or build arg) so the laptop UX doesn't regress.
3. Settle the auth story (Claude login, GitHub App scope, pem deployment path).
4. Write a server-side run wrapper analogous to `claude-sandbox.sh`.
5. Audit the build context (zshrc, gitconfig, nvim) before each server build.

## Related Design Logs

- [#000 - Project Overview](./000-project-overview.md)
- [#001 - Network Isolation](./001-network-isolation.md)
- [#003 - GitHub App Authentication](./003-github-app-auth.md)
