# Design Log #005: Host-Matching Container Paths

**Date Created:** 2026-07-16
**Status:** Proposed

## Background

Claude Code keys all project-scoped state off the process's working directory: session transcripts and auto-memory live under `~/.claude/projects/<escaped-cwd>` (e.g. `-Users-daniel-Projects-foo`), and per-project settings live in the `projects` map of `~/.claude.json`, keyed by absolute path.

The sandbox mounts the host's `~/Projects` at `/home/dev/projects` and `~/.claude` at `/home/dev/.claude`. Because the container cwd differs from the host cwd for the same project, Claude Code treats them as two unrelated projects: memory, history, and sessions created in the container are invisible on the host and vice versa.

An earlier attempt to fix this with symlinks (`/Users/daniel/Projects → /home/dev/projects`, baked into the Dockerfile) does not work: the kernel resolves symlinks when setting a process's cwd, so even after `cd /Users/daniel/Projects/foo`, Claude Code sees `/home/dev/projects/foo` and records state under that key.

## Problem

Make Claude Code's project tracking consistent between host and container, so a project has one shared identity — one memory directory, one session history, one `.claude.json` project entry — regardless of where a session runs.

## Questions and Answers

Q1: Does naming the container home `/Users/daniel` introduce security risk?
A: No. On Linux the path is cosmetic — no tool grants privileges based on it, and container escape difficulty is unaffected by in-container path names. The security surface is *what* is mounted, which this change does not alter.

Q2: Does sharing project state create a prompt-injection channel?
A: Yes, and it is the flip side of the feature. Today the mismatched paths accidentally isolate project-keyed state: container-written memory is never loaded by host sessions. Once paths match, a container agent that gets prompt-injected (hostile repo content, fetched web page) can write project memory and transcripts that host sessions later load as trusted context. However, a strictly stronger channel already exists: the container has read-write access to all of `~/.claude`, including `CLAUDE.md` (injected into every host session as instructions) and `settings.json` hooks (arbitrary commands executed by the host shell). The path change marginally widens an already-open channel; closing it is a mount-granularity problem, tracked as follow-up work below, not a reason to keep paths mismatched.

Q3: Should the host's `~/.claude.json` be shared into the container once paths match?
A: No. Claude Code rewrites `.claude.json` wholesale, so simultaneous host and container sessions would clobber each other. Keep the container-local copy; with matched paths its project keys become identical to the host's, which is enough for consistent tracking within container sessions. `~/.claude/projects/` is safe to share because session files are per-UUID.

Q4: Hardcode `/Users/daniel` or parameterize?
A: Hardcode for now. A `--build-arg HOST_HOME="$HOME"` would generalize it, but this is a single-user setup and the rest of the repo (e.g. the Dockerfile symlink block being removed) already hardcodes the username. Parameterize if the image ever needs to serve another user.

## Design

### Approach

Mount the host directories at byte-identical paths inside the container and make `/Users/daniel` the dev user's home directory. No symlinks, no translation layer — the container cwd simply *is* the host path.

### Mount Changes (`claude-sandbox.sh`)

| Mount | Current target | New target |
|---|---|---|
| `$PROJECTS_DIR` | `/home/dev/projects` | `/Users/daniel/Projects` |
| `$CLAUDE_DIR` | `/home/dev/.claude` | `/Users/daniel/.claude` |
| `claude-sandbox-ide` volume | `/home/dev/.claude/ide` | `/Users/daniel/.claude/ide` |
| `claude-sandbox-nvim-data` volume | `/home/dev/.local/share/nvim` | `/Users/daniel/.local/share/nvim` |
| repo `.claude.json` | `/home/dev/.claude.json` | `/Users/daniel/.claude.json` |
| repo `.zsh_history` | `/home/dev/.zsh_history` | `/Users/daniel/.zsh_history` |

The `-w` working-directory flag updates to the `/Users/daniel/Projects/...` form. Note the case change: the host directory is `Projects`, and capitalization is part of the recorded project key.

### Dockerfile Changes

- `useradd` gains `-d /Users/daniel` so `$HOME`, `~`, and shell startup resolve there (user remains named `dev`; only the home path matters).
- Every hardcoded `/home/dev` moves to `/Users/daniel`: `ENV PATH`, all `COPY --chown=dev` destinations, the pre-created named-volume directories, the `.zshrc` echo lines (aliases/fzf/argent sourcing, GitHub App pem check, token wrapper), and `WORKDIR`.
- The symlink block (`mkdir -p /Users/daniel && ln -s ...`) is deleted — it is dead weight once the real paths exist.

### Resulting Behavior

`cd /Users/daniel/Projects/foo` in the container yields a process cwd of exactly that path, so Claude Code reads and writes `~/.claude/projects/-Users-daniel-Projects-foo` — the same directory the host uses. Memory, transcripts, and resumable sessions become shared per project.

## Implementation Plan

### Phase 1: Dockerfile
- [x] Change `useradd` to `-d /Users/daniel`
- [x] Replace all `/home/dev` references with `/Users/daniel`
- [x] Remove the symlink block
- [x] Update `WORKDIR`

### Phase 2: claude-sandbox.sh
- [x] Retarget the six mounts and `-w` flag per the table above

### Migration script

Sharing `~/.claude` read-write at the new path only unifies project keys for
*new* sessions. Existing per-machine history split across
`-home-dev-projects-<x>` and `-Users-daniel-Projects-<x>` needs a one-time
merge. `scripts/merge-project-dirs.sh` does this: for each duplicate pair it
moves transcript `.jsonl` files across (they're per-UUID, no collisions),
unions the `MEMORY.md` index lines, copies over any memory `.md` files
missing on the target side, and removes the old dir once nothing is left in
it. It is idempotent and takes an optional `projects_root` argument for
testing against a directory other than `~/.claude/projects`. It has not been
run against the real `~/.claude/projects` — that happens on the host after
rebuild, per Phase 3 below.

### Phase 3: Verify
- [ ] Rebuild image, start container
- [ ] Run Claude Code in a project inside the container; confirm state lands in the same `~/.claude/projects/-Users-daniel-Projects-...` directory the host uses
- [ ] Confirm a host-started session's history is visible/resumable in the container

## Trade-offs

### Chosen: Mount at host-identical paths, home = `/Users/daniel`
**Pros:**
- Project identity is unified with zero translation logic — the mechanism Claude Code actually uses (process cwd) matches by construction
- Same pattern devcontainers use (`workspaceFolder` matching host path); well-trodden
- Sessions become resumable across host/container

**Cons:**
- Unconventional home path on Linux (`/Users/...`); any tool assuming `/home` layout could surprise, though home is resolved via `$HOME`/passwd so this is unlikely
- Shared project state widens the container→host prompt-injection channel (see Q2)
- Hardcodes the username into image and script

### Alternative: Symlinks from host paths to container paths
**Pros:**
- No changes to mounts or home directory

**Cons:**
- Does not work: process cwd resolves symlinks, so Claude Code records the real (`/home/dev/...`) path regardless of how the directory was entered

**Why not chosen:** Already attempted; fails at the kernel level, not fixable with more symlinks.

### Alternative: Keep state separate (status quo)
**Pros:**
- Accidental isolation of container-written memory/sessions from host sessions

**Cons:**
- Defeats the purpose of sharing `~/.claude`: memory and history fragment per environment

**Why not chosen:** Consistent tracking is the goal; isolation, where wanted, should be an explicit mount decision (see follow-up) rather than a path-mismatch accident.

## Follow-up Work (out of scope)

Sharing `~/.claude` read-write means container-run agents can modify configuration the host trusts (hooks, `CLAUDE.md`, skills). Hardening candidates, independent of this change but made more relevant by it:

1. Mount `settings.json`, `CLAUDE.md`, `hooks/`, `skills/`, `plugins/` individually as `:ro`
2. A host-defined, `:ro`-mounted PreToolUse hook denying Write/Edit/Bash against `~/.claude` paths from container sessions
3. Default to `--isolated` network mode for autonomous/untrusted work
4. Post-session audit script that diffs `~/.claude` and flags unexpected config/memory changes

Detection-based approaches (e.g. classifying fetched content for injection) are advisory at best; prefer the deterministic containment above.

## Related Design Logs
- [#000 - Project Overview](./000-project-overview.md)
- [#001 - Network Isolation](./001-network-isolation.md) — the `--isolated` mode referenced in follow-up work
