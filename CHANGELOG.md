# Changelog

Versions are CalVer. Each release names the commit it was cut from, and installs are pinned to it rather than following `master`.

## 2026.08.16

First release.

### The contract

Four rules bind every agent, injected into each session rather than left to memory: **Think Before Coding** (no implementation without machine-checkable success criteria), **Simplicity First** (an abstraction needs a current consumer), **Surgical Changes** (a recorded task boundary the reviewer audits the diff against), and **Goal-Driven Execution** (gates decide done-ness, and receipts prove the gates ran).

### Lifecycle

Seven commands, each a thin orchestrator over a stage declared in `core/lifecycle.yaml`:

- `/harmonia:ideate` — widen the option space before committing to one
- `/harmonia:discuss` — pin scope: goal, boundaries, non-goals, and `- run:` success criteria
- `/harmonia:plan` — design inside the pinned boundary
- `/harmonia:implement` — red-green loop, capped at six rounds, tests leading
- `/harmonia:review` — panel plus triggered lenses under a review lead, one verdict
- `/harmonia:capture` — file learnings, then ship structured commits
- `/harmonia:quick` — express lane for trivial fixes; gates stay active

`/harmonia:flow` chains plan → implement → review in one unattended pass. It deliberately chains neither end: discuss is dialogic and acceptance is a human-only act.

Each task lives in `.harmonia/tasks/<task-id>/`, a self-gitignoring workspace where stages pass artifacts by path. Interruption recovery is re-invoking a stage against what is on disk.

### Roster

Twelve agents with explicit charters: scoper, ideator, rubber-duck, planner, test-engineer, implementer, reviewer, simplifier, doc-producer, doc-reviewer, knowledge-curator, committer. Five review lenses fire on triggers declared in their own frontmatter: adversarial, blindspot, performance, regression, security.

### Gates

- **Criteria** — implement refuses to start until the scope carries machine-checkable `- run:` criteria; at review every one is executed from the repo root and any failure fails the review.
- **Coverage** — 100% line coverage on changed code, soft block, over a diff-cover core with adapters for bash (kcov), TypeScript and Go. Exemptions are in-code markers with a mandatory justification, surfaced in the gate report; overrides append to a versioned audit log.
- **Receipts** — every gate run writes a receipt carrying task id, timestamp and diff digest. Review fails work whose receipts are missing or stale.
- **Test immutability** — test files are hashed before the implementer runs; a violation is treated like a missing receipt.

### Human touchpoints

Six commands act on a task without advancing a stage: `/harmonia:accept`, `/harmonia:reject`, `/harmonia:abandon`, `/harmonia:remember`, `/harmonia:recall`, `/harmonia:status`. Acceptance is a human act — no skill or agent records it on the developer's behalf, and capture refuses to run without it.

### Memory

Two tiers: `~/.harmonia/` for cross-project patterns and `docs/learnings/` per repo. Client content is refused from the global tier. Recall filters by language tags and recency under a budget, and runs automatically at session start.

### Setup

- `/harmonia:onboard` captures an existing repo's verify and coverage commands into `.harmonia/project.yaml`.
- `/harmonia:trust` records your consent, on this machine, to run a repository's coverage command.

### Trust model

The task workspace is not a trust boundary, and `SECURITY.md` states the posture rather than implying it.

- Workspace reads and writes that resolve outside the task directory are refused, including through a symlinked ancestor.
- A workspace artifact is refused when a repository carries it — in its index, or in the tree of the commit it has checked out.
- A repository's `coverage:` command runs only against a consent record kept outside every repository, written by a human act, binding a repo identity the repository cannot choose to a digest of that exact command. The command is confined to a small printable grammar so what runs is what the words say; consent covers the string and no file, and the note says so.

### Installation

Claude Code via the plugin marketplace, and OpenCode via `bin/install-opencode.sh`, which writes one command file per skill and a copy of the engine into the OpenCode config directory. Generated files carry an ownership marker and the installer never touches unmarked files.

A `HARMONIA_DISABLE=1` environment variable is an emergency brake the session-start hook checks first; per-repo disabling is a `.claude/settings.local.json` entry.

### Verification

312 tests across 14 bats files, plus `bin/validate-core.sh` for lifecycle YAML, schema conformance and lens resolution.
