# Harmonia

A personal SDLC that runs on top of Claude Code: thin lifecycle commands orchestrate a thirteen-agent roster bound by the 4 Karpathy rules, hooks deterministically enforce everything a machine can check, and captured knowledge compounds across sessions and projects.

## Why "Harmonia"

From the Portuguese word for harmony, and for Harmonia, the Greek goddess of harmony — the cosmos as ordered music and balance (the Music of the Spheres). The name evokes order, structure, and beauty: exactly what a good SDLC provides. It is instantly readable and pronounceable, and it feels classical and mythic.

## Install

```bash
claude plugin marketplace add foliveira/harmonia
claude plugin install harmonia
```

Every commit to this repo is an auto-update on installed machines (the plugin declares no version). Live behavior runs from the plugin cache: after changing the engine, commit, run `claude plugin update harmonia`, and open a fresh session.

### Disabling in a specific repo (client work)

Add to that repo's `.claude/settings.local.json`:

```json
{ "enabledPlugins": { "harmonia": false } }
```

Emergency brake: set `HARMONIA_DISABLE=1` in the environment — the session-start hook checks it first and stays silent.

## Using it

Every session starts with the 4 rules and relevant learnings injected automatically. The lifecycle is seven explicit commands:

| Command | What runs |
|---|---|
| `/harmonia:ideate` | ideator (+ rubber duck) widen the option space into `ideas.md` |
| `/harmonia:discuss` | scoper pins scope — goal, boundaries, non-goals, `run:` success criteria |
| `/harmonia:plan` | planner designs inside the scope boundary |
| `/harmonia:implement` | red-green loop: test engineer leads, implementer follows, coverage gate feeds gap rounds |
| `/harmonia:review` | review lead chairs the panel, dispatches triggered lenses, audits gates and receipts, writes one verdict |
| `/harmonia:capture` | knowledge curator files learnings; committer ships structured commits |
| `/harmonia:quick` | express lane: implementer + lead-solo review, gates still active |

Each task lives in `.harmonia/tasks/<task-id>/` in the target repo — a self-gitignoring workspace where stages pass artifacts by path. Entry stages mint it; later stages resolve it; interruption recovery is re-invoking a stage against the on-disk artifacts.

## The gates

- **Criteria** — implement refuses to start until the scope declaration carries machine-checkable `- run:` criteria.
- **Coverage** — 100% line (and branch, where the format measures it) on changed code, soft block. Exemptions are in-code markers with a mandatory justification (`// harmonia:exempt <why>`), surfaced to the reviewer in the gate report's exemptions-honored section. Overrides append to a versioned audit log at `.harmonia/coverage-exemptions.yaml`. Unsupported languages exit as advisory cannot-measure, never a false pass.
- **Receipts** — every gate run writes a receipt (task id, timestamp, diff digest); review fails work whose receipts are missing or stale, and a test-immutability hash violation is treated the same way.

## Memory

Two tiers of learnings: `~/.harmonia/` (global — cross-project patterns; client content is refused here) and `docs/learnings/` in each repo (project tier). Legacy `docs/solutions/` entries are read read-only for continuity. Recall filters by language tags and recency under a budget; run `/harmonia:recall` to pull more mid-session. Any roster agent or hook can run the underlying script directly:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/memory/recall.sh
```

## The roster

ideator · scoper · planner · implementer · test engineer · reviewer (review lead) · simplifier · knowledge curator · committer · debugger · documentation producer · documentation reviewer · rubber duck

Charters live in `core/charters/` (the portable truth); `agents/` are thin Claude Code wrappers. Review lenses (adversarial, security, performance) are dispatchable prompt assets in `core/lenses/` — the security lens auto-fires on auth, secrets, input parsing, and network-facing diffs.

## Developing the engine

Dev toolchain: `bats`, `jq`, `yamllint`, `check-jsonschema`, `kcov`, `diff-cover` (and `gocover-cobertura` for Go targets).

```bash
bats tests/                                  # the whole suite
bin/validate-core.sh                         # lifecycle schema + lens resolution
bin/coverage/gate.sh --self --base <ref>     # the gate, dogfooded on this repo
```

The engine is bash + YAML only, and it is held to its own coverage bar.

## Credits

Harmonia systematizes my own workflow. It vendors nothing, but draws inspiration from:
[multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills) ·
[EveryInc/compound-engineering-plugin](https://github.com/EveryInc/compound-engineering-plugin) ·
[Yeachan-Heo/oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) ·
[addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) ·
[mattpocock/skills](https://github.com/mattpocock/skills)

MIT licensed.
