# zori_skills

A Claude Code plugin marketplace. Each plugin is a self-contained workflow — install the ones you
want, uninstall them cleanly, and nothing is symlinked into your `~/.claude`.

## Install

```bash
claude plugin marketplace add api-haus/zori_skills
claude plugin install delegate@zori
```

That is the whole thing. Skills and agents arrive together; nothing else on your machine is touched.

To update later:

```bash
claude plugin marketplace update zori
```

To remove:

```bash
claude plugin uninstall delegate@zori
claude plugin marketplace remove zori
```

## Plugins

### `delegate` — multi-agent orchestration

An orchestrator that scopes, briefs and synthesizes, and does nothing else itself. Every other
action is dispatched to a sub-agent whose context was deliberately kept clean. Two hard laws hold
the whole thing up:

1. The orchestrator never injects hypotheses, code-path references or fix directions into a brief.
   Sub-agent context purity is the entire value proposition — an agent handed your hunch will
   confirm your hunch.
2. The orchestrator never edits repo code and never runs the gate. It dispatches; agents do. No
   matter how small the change.

Invoke it as `/delegate:delegate`, or just describe an orchestration-shaped task and Claude will
reach for it.

**What ships with it.** `delegate` references three other workflows by path, so they travel in the
same plugin rather than dangling:

| skill | role |
|---|---|
| `delegate` | the orchestration protocol itself |
| `warden` | structural pass — one fresh agent per law family, evidence by enumeration before judgment |
| `diagnose-first` | circuit-breaker for confusing bugs; forces observation before action |
| `shipshape` | publish-grade style canon, the tell blacklist, and the metrics/scorecard tooling |

Nine sub-agents come with them: `delegate-{architect,auditor,consolidated,reviewer}`, `warden`, and
`shipshape-{adversary,formatter,implementer,surveyor}`.

Two reference documents sit under `reference/` because the skills cite them directly:
`e2e-gates.md` (gate-authoring criteria — what makes a test capable of failing) and `NONDUAL.md`
(the reasoning discipline the orchestrator's judgment calls lean on).

## Notes for consumers

- Plugin skills are namespaced. `/delegate:delegate`, not `/delegate`.
- `shipshape` is calibrated for C#/Unity in places (csharpier, asmdef graphs). The style canon and
  the tell blacklist are language-agnostic; the tooling under `skills/shipshape/tools/` is not.
- `delegate` writes its working memory to `docs/orchestrate/<topic>/` in whatever repo you run it
  in. Those files are one session's journal, not canon — the code at HEAD always outranks them.

## Licence

MIT. See `LICENSE`.
