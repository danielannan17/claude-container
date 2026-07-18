# Design Log #006: Config-Tampering Hardening

**Date Created:** 2026-07-16
**Status:** Proposed (deferred — revisit before running autonomous agents on untrusted content)
**Builds on:** [#005 — Host-Matching Container Paths](./005-host-matching-paths.md)

## Background

With host-matching paths (#005), state written by container sessions — project memory, transcripts, and anything under the shared `~/.claude` mount — is loaded by host sessions as trusted context. The `~/.claude` mount is deliberately read-write: skills, CLAUDE.md, and other config are edited from inside the container as part of normal work, so blanket read-only mounting is off the table.

The threat: a prompt-injected container agent (hostile repo content, a fetched web page) tampering with configuration that the host later executes or trusts. This extends #005's follow-up-work list into a concrete threat model and a recommended design, deferred until autonomous agents run against untrusted content.

## Threat Surface: Four Tiers

Protection should be tiered, not uniform — the surfaces differ enormously in stakes and in what enforcement is even possible.

| Tier | Surface | Stakes | Constraint |
|---|---|---|---|
| 1. Code execution | `~/.claude/settings.json`, `~/.claude/hooks/` | A planted hook runs arbitrary commands in the host shell | Rarely edited from the container — can be locked |
| 2. Instruction injection | `~/.claude/CLAUDE.md`, `skills/`, `plugins/` | Misleads the model; nothing executes directly | Must stay writable (edited from inside the container) |
| 3. Context pollution | `~/.claude/projects/` memory + transcripts | Trusted-on-load context in future sessions | Partially covered by the session-learning system's digest alerts (personal-agent design-log 015) |
| 4. Project-scoped config | any project's `.claude/settings.json` / `.claude/settings.local.json` | Hooks defined here execute when the project is opened on the host | Projects are mounted read-write by necessity — kernel enforcement unavailable |

Tier 4 deserves emphasis: hardening `~/.claude` does not close it. Any writable project can carry hooks, and `settings.local.json` is conventionally gitignored, so tampering there is invisible to git — the sneakiest variant.

## Detection Timing Beats Detection Cadence

The dangerous moment is when a host session *loads* tampered config, not when the container writes it. A post-session audit is a postmortem; the same check placed at host session start — a shell wrapper around `claude`, or a SessionStart hook — becomes a gate.

Cheapest solid baseline: git-track `~/.claude` (config only — not `projects/` or transcripts). Then:

- audit = `git diff`
- approval = commit
- recovery = revert

The load-time gate reduces to "are there uncommitted changes to sensitive paths?" and extends naturally to the project being opened: uncommitted `.claude/**` changes, plus the existence and content of an untracked `settings.local.json`.

## Enforcement Levels

### Harness gates — survive `--dangerously-skip-permissions`, but not watertight

- **PreToolUse hooks always fire**, regardless of permission mode. A hook matching Edit/Write/Bash against protected paths can return `permissionDecision: "ask"` (interactive prompt even in bypass mode; effectively a deny in headless `-p` runs, where there is no one to ask) or `"deny"`.
- **Managed policy settings** (`/Library/Application Support/ClaudeCode/managed-settings.json`, root-owned) override user, project, and CLI-flag settings, and can disable bypass mode entirely.

Two structural weaknesses:

1. **Bash write-path detection is heuristic.** `sed -i`, `cp`, `mv`, `tee`, redirects, `python -c 'open(...).write(...)'`, base64 round-trips, variable expansion — command-string matching cannot be made watertight against a determined agent.
2. **A gate defined in a writable settings file gets deleted as step one of an attack.** The gate definition must itself live in the read-only or root-owned region.

### OS enforcement — the only genuinely terminal-command-proof layer

- **In the container: `:ro` bind mounts.** No process can write through a read-only mount — no tool, no sudo.
- **On the host: root ownership.** `sudo chown root <file> && sudo chmod 644 <file>` — the agent runs as the user, so every write route fails at the kernel. Editing requires `sudo`, which *is* the permission prompt, OS-enforced.

## Recommended Design: the Ask-Gate

Combine the layers so the unbypassable one does the enforcing and the harness one does the ergonomics:

1. **Protected originals** (tier 1: `settings.json`, `hooks/`): mounted `:ro` in the container, root-owned on the host.
2. **A PreToolUse ask-hook, defined inside the protected region**, matching writes to those paths — the courtesy layer that tells the agent to propose a change rather than hitting a bare permission error.
3. **A writable proposals path** (e.g. `~/.claude/proposed/*.diff`): the agent stages its intended change there; review and apply happen with `sudo` from the host.

This is the same staging-and-gate pattern the session-learning system uses for global rules (personal-agent design-log 015): tentative writes land in a reviewable staging area, and nothing reaches a trusted surface without the gate. One mental model for both systems.

Tier 2 stays writable and is covered by the git-diff load-time gate. Tier 3 is covered by the learning system's alerts plus the same gate. Tier 4 gets the load-time project check, the protected deny-hook for the tool route, and whatever built-in review Claude Code performs (see open question).

## Open Question (load-bearing — verify before designing further)

Claude Code snapshots hooks at session startup and requires review in the `/hooks` menu when settings files are modified externally *mid-session*. The behavior for a hook added **between** sessions — does the next session start prompt for review, or load it silently? — is unverified. The answer determines how much weight the built-in protections carry, especially for tier 4, where a planted project hook waits for the project to be opened on the host.

## Immediate Cheap Win (independent of the deferral)

`git init ~/.claude` now (config files only; ignore `projects/`, transcripts, caches). Pure upside: human-readable diffs of every config change from any source, one-command recovery, and it makes every later gate in this document cheaper to build.

## Follow-up Work (deferred)

### Migrate `~/Projects/ai_docs` into the versioned `~/.claude` setup

Once `~/.claude` is git-tracked, the ai_docs — which exist solely to instruct Claude and are referenced from the global CLAUDE.md — belong inside it, covered by the same diff-based gate. The migration is a triage, not a folder move: each doc goes to the mechanism matching its shape.

- **Discrete procedures with a trigger moment** (e.g. ISSUE_WORKFLOW.md) → skills in `~/.claude/skills/`, with trigger-shaped descriptions ("Use when creating a GitHub issue…" — concrete nouns that appear in real tasks, not topic labels; topic-shaped descriptions like "React Native best practices" fail to fire because nothing in a request like "change the tab bar color" matches them).
- **Standing guidance scoped to a stack or project type** (RN best practices, ANALYTICS.md, LOGGING.md patterns) → project-level CLAUDE.md (or `@`-refs from it) in the projects it applies to. Skills are the wrong container for always-applies-while-coding guidance: skills fire at task-start moments, not ambiently across every edit. A deterministic backstop for must-load cases: a UserPromptSubmit hook that detects the stack (e.g. `react-native` in package.json) and injects a one-line pointer.
- **Truly universal behavioral rules** → global CLAUDE.md, sparingly.

Side effects worth recording: the global CLAUDE.md's "Technology Documentation" section becomes unnecessary (skill descriptions replace it), shrinking standing context; and the migration should land before personal-agent design-log 015's Phase 3, so its rule-applier targets the final file structure rather than `~/Projects/ai_docs/*.md`.

Diagnostic lesson: a skill that never fires may simply not be listed at all — wrong directory, missing or malformed SKILL.md frontmatter — which fails silently; checking the listing is the first debugging step.

## Related Design Logs

- [#005 — Host-Matching Container Paths](./005-host-matching-paths.md) — this extends its follow-up-work list
- personal-agent `design-log/015-session-learning.md` — the learning-system intersection: its distiller reads user messages only (never tool output, fetched pages, or assistant text), a deliberate containment property that keeps the primary injection surface out of the memory-write path
