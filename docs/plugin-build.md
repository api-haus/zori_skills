# How this marketplace is built

The canonical source for every skill and agent is the private workflow repo
(`~/_dev/my-claude-workflow`, overridable via `WORKFLOW_REPO`). Nothing under
`plugins/<name>/{skills,agents,reference}` is edited by hand — it is generated:

```bash
tools/sync.sh            # every plugin
tools/sync.sh delegate   # one
```

Each plugin declares what it carries in `plugins/<name>/.sync-manifest` — `skill`, `agent`,
`reference` and `exclude` lines. Adding a plugin is a manifest plus an entry in
`.claude-plugin/marketplace.json`.

## Why payloads are self-contained rather than shared

`${CLAUDE_PLUGIN_ROOT}` resolves to the *referencing* plugin's own root. There is no variable
addressing another plugin's root, and a symlink pointing outside the plugin directory is skipped
rather than dereferenced when the source is a local path. So a plugin cannot read a file belonging
to a sibling plugin, and `dependencies` does not change that — it controls install order, not
addressability.

The consequence: `delegate` cites `shipshape/STYLE.md`, `NONDUAL.md` and `e2e-gates.md` by path, so
those files travel inside the `delegate` payload. A future standalone `shipshape` plugin will
duplicate them. Duplication is the cost of the payloads standing alone; the sync script is what
keeps the duplicates from drifting, because all of them regenerate from one source.

## The gate

`sync.sh` fails the build unless the payload stands alone:

- no path pointing at `~/.claude/skills/` or the workflow repo survived the rewrite,
- every `${CLAUDE_PLUGIN_ROOT}/…` citation resolves to a file actually in the payload,
- every manifest-declared skill has a `SKILL.md` and every declared agent a file.

**Demonstrated sensitivity** (2026-07-21) — the gate was validated by breaking the payload on
purpose, not by reasoning about it:

| sabotage | result |
|---|---|
| clean rebuild | `OK`, exit 0 |
| drop `reference docs/e2e-gates.md` from the manifest, leave the two citations in place | `FAIL`, exit 1, both offending lines named |
| add a citation to `${CLAUDE_PLUGIN_ROOT}/reference/does-not-exist.md` | `FAIL`, exit 1 |
| revert both | `OK`, exit 0 |

Deleting a payload file is *not* a valid sabotage — the rebuild restores it before the check runs.
The failure has to be introduced upstream of the copy, in the manifest or the source.

Only git-tracked files are copied. A recursive copy would pull `skills/research/.venv` — 6.5 GB of
CUDA wheels dragged in by `marker-pdf` — into the marketplace.

## Plugin semantics established by probe

Measured on Claude Code, 2026-07-21; several of these are not in the published docs.

- **A local-directory marketplace loads in place.** `${CLAUDE_PLUGIN_ROOT}` resolved to
  `/home/midori/_dev/zori_skills/plugins/delegate`, not to the cache copy — so edits to this repo
  take effect in the next session with no `marketplace update`. A copy *is* also written to
  `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` (28/28 files, a real copy, not a
  symlink); consumers installing from GitHub run from that copy.
- **`${CLAUDE_PLUGIN_ROOT}` is substituted inside skill and agent markdown**, not only in hooks and
  MCP config. The skill text reaches the model with the absolute path already expanded.
- **Everything is namespaced.** Skills invoke as `/delegate:delegate`, `/delegate:warden`; agents
  dispatch as `subagent_type: "delegate:delegate-auditor"`. There is no bare form. Personal
  `~/.claude/skills` and `~/.claude/agents` entries of the same name coexist as separate
  registrations, so during migration both appear and the personal one wins on the bare name.

That last point is why the skills tell the orchestrator to dispatch the string its available-agents
list shows rather than the bare name written in the prose.
