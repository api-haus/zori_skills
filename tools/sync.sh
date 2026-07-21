#!/usr/bin/env bash
# Rebuild a plugin's payload from the canonical workflow repo, then verify it stands alone.
#
#   tools/sync.sh [plugin ...]      # default: every plugin with a .sync-manifest
#
# Source of truth is WORKFLOW_REPO; everything under plugins/<name>/{skills,agents,reference}
# is generated and safe to delete. Only git-tracked files are copied — a recursive copy would
# drag skills/research/.venv (6.5 GB of CUDA wheels) into the marketplace.

set -euo pipefail

MKT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW_REPO="${WORKFLOW_REPO:-$HOME/_dev/my-claude-workflow}"

[[ -d "$WORKFLOW_REPO/.git" ]] || { echo "not a git repo: $WORKFLOW_REPO" >&2; exit 1; }

plugins=("$@")
if [[ ${#plugins[@]} -eq 0 ]]; then
    for m in "$MKT_ROOT"/plugins/*/.sync-manifest; do
        [[ -e "$m" ]] && plugins+=("$(basename "$(dirname "$m")")")
    done
fi

fail=0

for plugin in "${plugins[@]}"; do
    dst="$MKT_ROOT/plugins/$plugin"
    manifest="$dst/.sync-manifest"
    [[ -f "$manifest" ]] || { echo "no manifest: $manifest" >&2; exit 1; }

    echo "── $plugin"

    skills=() agents=() refs=() excludes=()
    while read -r kind value _; do
        case "$kind" in
            skill)     skills+=("$value") ;;
            agent)     agents+=("$value") ;;
            reference) refs+=("$value") ;;
            exclude)   excludes+=("$value") ;;
        esac
    done < <(grep -vE '^\s*(#|$)' "$manifest")

    rm -rf "$dst/skills" "$dst/agents" "$dst/reference"
    mkdir -p "$dst/skills" "$dst/agents" "$dst/reference"

    for s in "${skills[@]}"; do
        while IFS= read -r -d '' f; do
            out="$dst/${f#skills/}"
            mkdir -p "$(dirname "$dst/skills/${f#skills/}")"
            cp -a "$WORKFLOW_REPO/$f" "$dst/skills/${f#skills/}"
        done < <(git -C "$WORKFLOW_REPO" ls-files -z "skills/$s")
    done

    for a in "${agents[@]}"; do
        cp -a "$WORKFLOW_REPO/agents/$a.md" "$dst/agents/$a.md"
    done

    for r in "${refs[@]}"; do
        cp -a "$WORKFLOW_REPO/$r" "$dst/reference/$(basename "$r")"
    done

    for e in "${excludes[@]}"; do
        rm -f "$dst/$e"
    done

    find "$dst" -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true

    # Rewrite every path that assumes the author's machine into a plugin-relative one.
    sed_args=()
    for s in "${skills[@]}"; do
        sed_args+=(-e "s|~/\.claude/skills/$s/|\${CLAUDE_PLUGIN_ROOT}/skills/$s/|g")
    done
    for r in "${refs[@]}"; do
        esc="${r//./\\.}"
        sed_args+=(-e "s|$WORKFLOW_REPO/$esc|\${CLAUDE_PLUGIN_ROOT}/reference/$(basename "$r")|g")
        sed_args+=(-e "s|~/_dev/$(basename "$WORKFLOW_REPO")/$esc|\${CLAUDE_PLUGIN_ROOT}/reference/$(basename "$r")|g")
    done
    grep -rlZ -F -e '~/.claude/skills/' -e "$WORKFLOW_REPO" -e "~/_dev/$(basename "$WORKFLOW_REPO")" \
        "$dst/skills" "$dst/agents" 2>/dev/null | xargs -0 -r sed -i "${sed_args[@]}"

    # ── Gate. A payload that points off its own root is broken on every consumer machine.
    leaked=$(grep -rn -F -e '~/.claude/skills/' -e "$WORKFLOW_REPO" -e "~/_dev/$(basename "$WORKFLOW_REPO")" \
        "$dst/skills" "$dst/agents" "$dst/reference" 2>/dev/null || true)
    if [[ -n "$leaked" ]]; then
        echo "   FAIL author-machine paths survived the rewrite:" >&2
        sed "s|$dst/|     |" <<<"$leaked" | cut -c1-140 >&2
        fail=1
    fi

    dangling=0
    while read -r p; do
        [[ -z "$p" ]] && continue
        if [[ ! -e "$dst/$p" ]]; then echo "   FAIL dangling reference: \${CLAUDE_PLUGIN_ROOT}/$p" >&2; dangling=1; fi
    done < <(grep -rhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./-]+' "$dst" 2>/dev/null \
             | sed 's|\${CLAUDE_PLUGIN_ROOT}/||' | sort -u)
    [[ $dangling -eq 1 ]] && fail=1

    for s in "${skills[@]}"; do
        [[ -f "$dst/skills/$s/SKILL.md" ]] || { echo "   FAIL missing skills/$s/SKILL.md" >&2; fail=1; }
    done
    for a in "${agents[@]}"; do
        [[ -f "$dst/agents/$a.md" ]] || { echo "   FAIL missing agents/$a.md" >&2; fail=1; }
    done

    printf '   %d skills, %d agents, %d reference docs, %s\n' \
        "${#skills[@]}" "${#agents[@]}" "${#refs[@]}" "$(du -sh "$dst" | cut -f1)"
done

if [[ $fail -ne 0 ]]; then
    echo >&2
    echo "sync FAILED — payload is not self-contained" >&2
    exit 1
fi
echo
echo "sync OK — every payload is self-contained"
