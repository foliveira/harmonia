# Changelog

Versions are CalVer. Each release names the commit it was cut from, and installs are pinned to it rather than following `master`.

## 2026.09.28

### The contract

Rob Pike's rules join the contract as rules 5 to 9: Prove the Bottleneck, Measure, Don't Get Fancy, Use Simple Algorithms and Data Dominates. Each carries a "Binding in Harmonia" clause, as the first four do. A change made for speed records the measurement that found its bottleneck. The scoper turns a speed goal into a `- run:` criterion, so review repeats the measurement. A design that reaches for a fancy algorithm names the n it expects, and the simplifier challenges it. The planner names data structures before the algorithms that use them. No new gate comes with these rules; the review lead judges them. The session-start digest lists all nine.

### Gates

Coverage is no longer a gate. `bin/coverage/` is gone with its bash, TypeScript and Go adapters, along with the gate report, the `harmonia:exempt` markers and the override audit log. The test engineer aims to exercise every changed line and branch, and judges that by reading the diff against the tests. Its charter refuses to add, configure or repair coverage tooling.

- The implement loop ends when the test engineer reports no behavior left to pin and no changed code left unexercised. It is still capped at six rounds.
- Review runs `criteria-run`, then `receipts`. The receipt audit moved to `bin/verify-receipts.sh`, and it now needs a fresh `criteria-run` receipt where it needed a coverage receipt.
- `/harmonia:quick` runs no gates. Coverage and receipts were its only two.
- A committed `.harmonia/coverage-exemptions.yaml` is no longer read and can be deleted.

### Roster

Every charter and lens ends with the same house-style block. It governs finished text a person reads: workspace artifacts, docs, learnings and commit messages. Reports to other agents are exempt. It caps a sentence at 25 words and prefers the active voice. Where it disagrees with a repo's commit conventions, the committer follows the house style.

Prompts and user-facing messages no longer cite labels such as R9 or KTD11, which only this repo's plans define.

### Memory

Recall counts `.mjs` and `.cjs` files as JavaScript, so global entries tagged `javascript` now reach repos written as ES or CommonJS modules.

### Setup

`/harmonia:trust` and `bin/trust.sh` are removed. Consent existed only so the coverage gate could run a repository's `coverage:` command. `/harmonia:onboard` drops its coverage certification and captures the four verify commands: test, lint, typecheck and build. If `project.yaml` still holds a `coverage:` key, onboard tells you nothing reads it. Consent records under `~/.harmonia/trust/` (or `$HARMONIA_HOME/trust/`) are unused and can be deleted.

### Trust model

`SECURITY.md` loses its consent section. Two execution routes went with it: the coverage adapters running a clone's own suite, and a committed filename reaching the gate's language classifier. The routes left are the `project.yaml` verify values, the `- run:` criteria in `scope.md`, and the config a delivered `.git` carries. The guarded properties are now two, containment and provenance.

Private vulnerability reporting on the Security tab is the only way to report a vulnerability. The email fallback is gone.

### Verification

214 tests across 12 bats files, plus `bin/validate-core.sh`. CI failed on `ubuntu-latest` at 2026.08.16 and passes now: bats comes from apt, and kcov and diff-cover are no longer installed.

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

Two tiers: `~/.harmonia/` for cross-project patterns and `docs/learnings/` per repo, plus legacy `docs/solutions/` entries read-only. Client content is refused from the global tier, as is an entry carrying no recognized language tag. Recall filters the global tier by language-tag overlap with the repo, leaves project and legacy entries unfiltered, and returns what is left newest-first under a line budget — automatically at session start, and on demand.

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
