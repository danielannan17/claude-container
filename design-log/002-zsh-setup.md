# Design Log #002: Zsh Setup

**Date Created:** 2026-03-07
**Status:** Implemented

## Background

The initial container used bash with no shell customization. Working inside the container felt disconnected from the host environment — no familiar aliases, no fzf, no oh-my-zsh theme.

## Problem

How to replicate the host's zsh environment inside the container so it feels seamless, while keeping container-specific customizations separate.

## Design

### Approach

Copy the host's zsh config at build time, then layer container-specific additions on top. This avoids read-only mount issues and allows appending to `.zshrc`.

### What Gets Copied from Host (at build time)
- `~/.zshrc` → `/home/dev/.zshrc`
- `~/.oh-my-zsh/` → `/home/dev/.oh-my-zsh/` (excluding `.git`)

### What Gets Mounted (at runtime)
- `.zsh_history` — persistent shell history across container sessions

### Container-Specific Configs
- `zsh/aliases.zsh` — `claude` alias with `--dangerously-skip-permissions`, `c` shortcut
- `zsh/fzf-settings.zsh` — fzf trigger (`~~`), completion, preview settings
- Custom prompt with `@hostname` to distinguish container from host shell

### Build-Time Flow

1. `build_image()` copies `~/.zshrc` and rsyncs `~/.oh-my-zsh/` into `zsh/` build context
2. Dockerfile COPYs them into the image
3. Dockerfile installs fzf from git (correct architecture for container)
4. Dockerfile appends `source` lines and prompt override to `.zshrc`
5. `build_image()` cleans up copied files from build context

### Shell Initialization Order (appended to .zshrc)
1. `source ~/.zsh_aliases`
2. `source ~/.zsh_fzf`
3. Custom prompt override (`@claude-sandbox`)

### Environment Variables
- `ANTHROPIC_API_KEY` — passed into the container so zsh-ai plugin can make API calls

### Other Changes
- Default shell changed from bash to zsh (`CMD ["/bin/zsh"]`, user shell set to `/bin/zsh`)
- Added terminal env vars (`TERM`, `COLORTERM`, `HISTORY_IGNORE`)
- Changed `DEBIAN_FRONTEND` from `ENV` to `ARG` (only needed at build time)
- Added `.claude.json` mount for Claude config
- Removed runtime mounts for `.zshrc` and `.oh-my-zsh` (replaced with build-time copy)
- Added `.gitignore` entries for `.claude.json` and `zsh/.zsh_history`
- Added `README.md`
- Build now stops container before rebuilding

## Trade-offs

### Chosen: Copy host config at build time
**Pros:**
- Writable inside container (can append to `.zshrc`)
- Container-specific additions are explicit and versioned
- No path resolution issues

**Cons:**
- Requires rebuild to pick up host zsh config changes
- oh-my-zsh copy adds to image size and build time

### Alternative: Mount .zshrc and .oh-my-zsh at runtime (original approach in commit)
**Pros:**
- Always in sync with host

**Cons:**
- Read-only mount prevents modifications
- Can't append container-specific config to `.zshrc`

**Why not chosen:** Replaced within the same commit after discovering the append limitation.

## Implementation Results

### What Was Built
- `build_image()` handles copy/rsync/cleanup of host zsh configs
- Dockerfile installs fzf, copies configs, appends shell init
- `zsh/aliases.zsh` with claude shortcuts
- `zsh/fzf-settings.zsh` with completion and preview config
- `.zsh_history` mounted for persistence

### Lessons Learned
- rsync with `--exclude '.git'` keeps oh-my-zsh copy manageable
- fzf must be installed from git inside the container for correct binary architecture
- `DEBIAN_FRONTEND` should be `ARG` not `ENV` — it's only needed during build

## Related Design Logs
- [#000 - Project Overview](./000-project-overview.md)
- [#001 - Network Isolation](./001-network-isolation.md)
