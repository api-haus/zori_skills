#!/usr/bin/env bash
# Check that every plugin here is well-formed and stands alone on a machine that has
# neither the author's ~/.claude nor any private repo.
#
#   tools/validate.sh [plugin ...]      # default: all

set -euo pipefail

MKT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW_REPO="${WORKFLOW_REPO:-$HOME/_dev/my-claude-workflow}"

plugins=("$@")
if [[ ${#plugins[@]} -eq 0 ]]; then
    for d in "$MKT_ROOT"/plugins/*/; do plugins+=("$(basename "$d")"); done
fi

fail=0

for plugin in "${plugins[@]}"; do
    dst="$MKT_ROOT/plugins/$plugin"
    [[ -d "$dst" ]] || { echo "no such plugin: $plugin" >&2; exit 1; }
    echo "── $plugin"

    leaked=$(grep -rn -F -e '~/.claude/skills/' -e '~/.claude/agents/' -e "$WORKFLOW_REPO" \
        -e "~/_dev/$(basename "$WORKFLOW_REPO")" "$dst" 2>/dev/null || true)
    if [[ -n "$leaked" ]]; then
        echo "   FAIL path only valid on the author's machine:" >&2
        sed "s|$dst/|     |" <<<"$leaked" | cut -c1-140 >&2
        fail=1
    fi

    while read -r p; do
        [[ -z "$p" ]] && continue
        [[ -e "$dst/$p" ]] || { echo "   FAIL dangling: \${CLAUDE_PLUGIN_ROOT}/$p" >&2; fail=1; }
    done < <(grep -rhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./-]+' "$dst" 2>/dev/null \
             | sed 's|\${CLAUDE_PLUGIN_ROOT}/||' | sort -u)

    if ! out=$(claude plugin validate "$dst" 2>&1); then
        echo "   FAIL claude plugin validate:" >&2
        grep -E '❯|✘' <<<"$out" | sed 's/^/     /' >&2
        fail=1
    fi

    # reference/ holds copies of documents whose original lives in the private workflow repo,
    # because a plugin cannot read a file outside its own root. Catch the drift that invites.
    if [[ -d "$WORKFLOW_REPO" && -d "$dst/reference" ]]; then
        for f in "$dst"/reference/*; do
            b=$(basename "$f")
            for orig in "$WORKFLOW_REPO/$b" "$WORKFLOW_REPO/docs/$b"; do
                if [[ -f "$orig" ]] && ! diff -q "$f" "$orig" >/dev/null; then
                    echo "   DRIFT reference/$b differs from ${orig/#$HOME/\~}" >&2
                fi
            done
        done
    fi

    printf '   %d skills, %d agents, %s\n' \
        "$(find "$dst/skills" -name SKILL.md 2>/dev/null | wc -l)" \
        "$(find "$dst/agents" -name '*.md' 2>/dev/null | wc -l)" \
        "$(du -sh "$dst" | cut -f1)"
done

if ! out=$(claude plugin validate "$MKT_ROOT" 2>&1); then
    echo "── marketplace" >&2
    echo "   FAIL claude plugin validate:" >&2
    grep -E '❯|✘' <<<"$out" | sed 's/^/     /' >&2
    fail=1
fi

[[ $fail -ne 0 ]] && { echo >&2; echo "FAILED" >&2; exit 1; }
echo
echo "OK — every plugin is well-formed and self-contained"
