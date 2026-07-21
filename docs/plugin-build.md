# How this marketplace works

This repo is the home of the skills it ships. `plugins/<name>/skills/` and `plugins/<name>/agents/`
are edited directly — there is no build step and no generated copy anywhere.

That is a deliberate reversal. The first version kept the skills in a private repo and generated
the payloads with a `sync.sh`, which meant two copies of every file, a rewrite pass between them,
and drift as the standing risk. Making this repo canonical deleted all three problems at once.

```bash
tools/validate.sh            # every plugin
tools/validate.sh delegate   # one
```

Adding a plugin is a directory under `plugins/`, a `.claude-plugin/plugin.json`, and an entry in
`.claude-plugin/marketplace.json`.

## Why payloads are self-contained rather than shared

`${CLAUDE_PLUGIN_ROOT}` resolves to the *referencing* plugin's own root. There is no variable
addressing another plugin's root, and a symlink pointing outside the plugin directory is skipped
rather than dereferenced when the source is a local path. So a plugin cannot read a file belonging
to a sibling plugin, and `dependencies` does not change that — it controls install order, not
addressability.

The consequence: `delegate` cites `shipshape/STYLE.md`, `NONDUAL.md` and `e2e-gates.md` by path, so
those files live inside the `delegate` payload. A future standalone `shipshape` plugin would carry
its own copy. Duplication is the price of payloads that stand alone; `validate.sh` reports drift on
the two `reference/` documents whose originals are global config elsewhere.

## The gate

`validate.sh` fails unless every plugin would work on a machine that has neither the author's
`~/.claude` nor any private repo:

- no path pointing at `~/.claude/skills`, `~/.claude/agents`, or the private workflow repo,
- every `${CLAUDE_PLUGIN_ROOT}/…` citation resolves to a file actually in the payload,
- `claude plugin validate` passes on each plugin and on the marketplace,
- (advisory) `reference/` copies still match their originals when the workflow repo is present.

The third arm is the official validator and it earns its place: it caught broken YAML frontmatter in
`delegate`, `cdiff` and `research-extractor` that the hand-written arms are blind to. An unquoted
YAML scalar ends at its first `: `, so a description reading `Two hard laws: (1) …` fails to parse
and the skill loads with every frontmatter field silently dropped — including the `description`
model-invocation triggers on. Prefer official checks over writing more of our own.

**Demonstrated sensitivity** — the gate was validated by breaking payloads on purpose, not by
reasoning about it:

| sabotage | result |
|---|---|
| clean tree | `OK`, exit 0 |
| append a `~/.claude/skills/…` citation to a carried skill | `FAIL`, exit 1, line named |
| cite `${CLAUDE_PLUGIN_ROOT}/reference/ghost.md` | `FAIL`, exit 1 |
| unquote a `description:` scalar | `FAIL`, exit 1, via `claude plugin validate` |
| edit `reference/NONDUAL.md` away from its original | `DRIFT` warning |
| revert each | `OK`, exit 0 |

Deleting a payload file was *not* a valid sabotage back when a build step existed — the rebuild
restored it before the check ran. Worth remembering if a generated stage ever returns.

## Plugin semantics established by probe

Measured on Claude Code, 2026-07-21; several of these are not in the published docs.

- **A local-directory marketplace loads from the source directory, not the cache.** A copy is still
  written to `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`, but it is inert: a line
  appended to the source appeared in the loaded skill while the cache copy still lacked it. So
  editing this repo takes effect in the next session with no `marketplace update`. Consumers
  installing from GitHub run from the cache copy and do need an update.
- **`${CLAUDE_PLUGIN_ROOT}` is substituted inside skill and agent markdown**, not only in hooks and
  MCP config — the text reaches the model with the absolute path already expanded. It resolved to
  the source directory for a local marketplace and to the cache path for a GitHub one; both read
  their own files correctly.
- **Everything is namespaced.** Skills invoke as `/delegate:delegate`, `/delegate:warden`; agents
  dispatch as `subagent_type: "delegate:delegate-auditor"`. There is no bare form. Personal
  `~/.claude` entries of the same name coexist as separate registrations, so during a migration both
  appear and the personal one owns the bare name.

That last point is why the skills tell the orchestrator to dispatch the string its available-agents
list shows rather than the bare name written in the prose.
