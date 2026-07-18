#!/usr/bin/env bash
# One-time migration for the host-matching-paths change (design-log/005).
#
# Before the change, the same project was tracked under two different keys
# in ~/.claude/projects/: one written by host sessions
# (-Users-daniel-Projects-<x>) and one written by container sessions
# (-home-dev-projects-<x>). This script merges each such pair into the
# host-side (-Users-daniel-Projects-<x>) directory, which is the key both
# host and container will use going forward.
#
# For each pair:
#   - transcript .jsonl files are moved from the old dir into the new one
#     (they are named per-session-UUID, so no collisions are expected)
#   - if both sides have a memory/ dir, MEMORY.md index lines are unioned
#     and any memory/*.md files missing on the new side are copied over
#   - if only the old side has memory/, it is moved over wholesale
#   - the old dir is removed once nothing is left in it; otherwise it is
#     left in place and what remains is printed
#
# Safe to run more than once: already-merged files/lines are detected and
# skipped, and a dir that no longer needs merging is left alone. If a
# same-named memory/*.md file exists on both sides but with different
# content, it is never deleted from the old side — the old copy is left in
# place with a warning so it can be reconciled manually.
#
# Usage: scripts/merge-project-dirs.sh [projects_root]
#   projects_root defaults to ~/.claude/projects

set -euo pipefail

PROJECTS_ROOT="${1:-$HOME/.claude/projects}"
OLD_PREFIX="-home-dev-projects"
NEW_PREFIX="-Users-daniel-Projects"

if [[ ! -d "$PROJECTS_ROOT" ]]; then
    echo "No such directory: $PROJECTS_ROOT" >&2
    exit 1
fi

echo "Merging duplicate project dirs under $PROJECTS_ROOT"
echo "  $OLD_PREFIX* -> $NEW_PREFIX*"
echo

shopt -s nullglob

merged_count=0
skipped_count=0

for old_dir in "$PROJECTS_ROOT"/"$OLD_PREFIX"*; do
    [[ -d "$old_dir" ]] || continue

    old_name="$(basename "$old_dir")"
    suffix="${old_name#"$OLD_PREFIX"}"
    new_name="${NEW_PREFIX}${suffix}"
    new_dir="$PROJECTS_ROOT/$new_name"

    if [[ ! -d "$new_dir" ]]; then
        echo "SKIP $old_name — no matching $new_name, not a duplicate pair"
        skipped_count=$((skipped_count + 1))
        continue
    fi

    echo "Merging $old_name -> $new_name"

    # 1. Move transcript .jsonl files (per-UUID, no collisions expected).
    for jsonl in "$old_dir"/*.jsonl; do
        [[ -e "$jsonl" ]] || continue
        base="$(basename "$jsonl")"
        dest="$new_dir/$base"
        if [[ -e "$dest" ]]; then
            echo "  ! $base already exists on both sides — leaving old copy in place, check manually"
            continue
        fi
        echo "  moving transcript $base"
        mv "$jsonl" "$dest"
    done

    # 2. Reconcile memory/ dirs.
    old_memory="$old_dir/memory"
    new_memory="$new_dir/memory"

    if [[ -d "$old_memory" && -d "$new_memory" ]]; then
        old_index="$old_memory/MEMORY.md"
        new_index="$new_memory/MEMORY.md"

        if [[ -f "$old_index" ]]; then
            if [[ -f "$new_index" ]]; then
                added=0
                while IFS= read -r line; do
                    [[ -z "$line" ]] && continue
                    if ! grep -qxF -- "$line" "$new_index"; then
                        echo "$line" >> "$new_index"
                        added=$((added + 1))
                    fi
                done < "$old_index"
                echo "  unioned MEMORY.md: $added new index line(s)"
            else
                echo "  copying MEMORY.md (target had none)"
                cp "$old_index" "$new_index"
            fi
        fi

        for mem_file in "$old_memory"/*.md; do
            [[ -e "$mem_file" ]] || continue
            mem_base="$(basename "$mem_file")"
            [[ "$mem_base" == "MEMORY.md" ]] && continue
            dest="$new_memory/$mem_base"
            if [[ -e "$dest" ]]; then
                echo "  skipping memory/$mem_base — already exists on target side"
                continue
            fi
            echo "  copying memory/$mem_base"
            cp "$mem_file" "$dest"
        done

        # Remove old memory/ only once every .md file has a home on the target side.
        remaining=("$old_memory"/*)
        if [[ ${#remaining[@]} -eq 0 ]]; then
            rmdir "$old_memory"
        else
            all_copied=true
            for f in "${remaining[@]}"; do
                if [[ ! -f "$f" ]]; then
                    all_copied=false
                    continue
                fi
                f_base="$(basename "$f")"
                dest="$new_memory/$f_base"
                if [[ ! -e "$dest" ]]; then
                    all_copied=false
                    continue
                fi
                # MEMORY.md is unioned (not copied verbatim), so the old and
                # new index legitimately differ in content — existence on
                # the new side is enough for it. Other memory/*.md files are
                # copied verbatim, so they must match byte-for-byte.
                if [[ "$f_base" != "MEMORY.md" ]] && ! cmp -s "$f" "$dest"; then
                    echo "  ! memory/$f_base differs between old and new side — leaving old copy in place, reconcile manually"
                    all_copied=false
                fi
            done
            if [[ "$all_copied" == true ]]; then
                rm -f "$old_memory"/*.md
                rmdir "$old_memory" 2>/dev/null || true
            else
                echo "  ! old memory/ still has unmerged files, leaving it in place"
            fi
        fi
    elif [[ -d "$old_memory" && ! -d "$new_memory" ]]; then
        echo "  moving memory/ (target had none)"
        mv "$old_memory" "$new_memory"
    fi

    # 3. Remove the old dir if fully merged, otherwise report what's left.
    leftovers=("$old_dir"/*)
    if [[ ${#leftovers[@]} -eq 0 ]]; then
        rmdir "$old_dir"
        echo "  done — removed empty $old_name"
        merged_count=$((merged_count + 1))
    else
        echo "  left in place, still contains: ${leftovers[*]/#"$old_dir"\//}"
    fi
    echo
done

echo "Merged and removed: $merged_count"
echo "Skipped (no pair):  $skipped_count"
