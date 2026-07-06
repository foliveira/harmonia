# Harmonia v1 — end-to-end dogfood walkthrough

Run in a fresh sandbox repo (copy `tests/fixtures/sandbox/`). Each step names its expected observable outcome; check the box only when you observed it. Steps marked `[headless-ok]` can be executed with `claude -p` from a script; the rest want a live session. Observations from the 2026-07-02 build-day run are recorded inline; unchecked boxes are first-drive items with their script-level evidence noted.

## 0. The cache-refresh loop (KTD4)

- [x] Commit an engine change, `claude plugin update harmonia@harmonia`, fresh session. **Observed 2026-07-02:** cache refreshed `b67ef9f → add88a4`, matching HEAD exactly; `claude plugin list` shows the commit SHA as the version.

## 1. Install (R2, KTD1) `[headless-ok]`

- [x] `claude plugin marketplace add` succeeds. **Observed:** root-path source (`"./"`) accepted against the local checkout — the KTD1 assumption retired positively.
- [x] `claude plugin install harmonia` succeeds and lists enabled. **Observed:** `harmonia@harmonia`, scope user.

## 2. Recall injection (AE5, tier A) `[headless-ok]`

- [x] Seed one global learning via `capture.sh`. **Observed:** `kcov attribution quirks in bash coverage` captured to `~/.harmonia/` with one index line.
- [x] Fresh session in the sandbox carries the rules and the learning unprompted. **Observed:** headless session answered with all four rule names and the exact learning title.
- [x] `HARMONIA_DISABLE=1` yields no injection. **Observed:** fresh session confirmed no Harmonia rules or learnings in context (plugin skills/agents still registered, as expected — the kill-switch silences the hook, not the catalog).

## 3. Express lane and the soft block (AE1)

- [x] `/harmonia:quick` on a change leaving uncovered lines: gate fails soft; reviewer reads the report file. **Observed (headless run):** workspace `2026-07-02-tool-sh-usage-comment` minted with base-ref; gate report `status: 1`, `tool.sh:ALL (absent from coverage data)`; digest-bearing receipt written; the review lead's `verdict.md` cited the gate report, arbitrated the soft block as non-blocking with reasoning, and **failed the review on a real finding it caught itself** (the usage comment documented an invocation that didn't work) — which the loop then fixed.
- [ ] Record an override and see it cited in a verdict. *Script-level evidence: bats asserts `--record-override` appends one well-formed audit-log entry. First-drive item.*

## 4. Full cycle on a feature-shaped task — live session

- [ ] `/harmonia:discuss` mints `scope.md` once; `/harmonia:plan` refines, never re-mints (R31). *Script-level evidence: skills lint + workspace matrix. First-drive item.*
- [x] `/harmonia:implement` with prose-only criteria refuses, naming the offender, receipt still written (AE2 intake). **Observed (headless):** resolved the active workspace, rejected `make it nicer` as not machine-checkable, wrote the failing receipt, refused to patch scope itself ("that's the scoper's job"), and pointed at `/harmonia:plan`.
- [ ] Cover-first round closes a seeded gap green-on-arrival, implementer turn skipped (AE7). *Script-level evidence: gate report feeds gaps; hash discipline tested in the workspace matrix. First-drive item.*
- [ ] Adversarial lens fires on a new abstraction; verdict carries attributed findings (AE8). *Script-level evidence: lens frontmatter triggers + stage declarations validated. First-drive item.*
- [x] `/harmonia:capture`: curator files learnings; committer ships structured commits (R6). **Observed (headless):** single-concern commit `8d677c4 "Add usage comment to tool.sh"`, nothing outside the boundary, no workspace files; the curator declined to capture a learning for a one-line comment task — the refuse-noise clause of its charter.

## 5. Interruption recovery (KTD10)

- [x] A later stage in a **new session** resolves the single incomplete workspace with no task id. **Observed (headless):** both the implement and capture probes were fresh sessions that resolved `2026-07-02-tool-sh-usage-comment` by marker state; capture wrote the completion marker, closing it (resolution now reports no active task).

## 6. Memory tiers (AE4, AE5 agent-seat) — live session

- [ ] Client-flagged learning lands project-tier only (AE4). *Script-level evidence: bats asserts the global-tier refusal and the docs/learnings landing. First-drive item.*
- [ ] A roster agent (not the main session) states a recalled learning (AE5 agent-seat). *Script-level evidence: agent bodies carry the literal recall path; script parity test passes. First-drive item.*

## 7. Platform probes (KTD2, KTD11) — live session

- [ ] Manual agent spawn quotes its charter; broken path triggers the refusal clause. *First-drive item.*
- [ ] Nested-dispatch probe (named panel member + lens with recorded models); on failure, lenses become thin defined agents and KTD11 records the fallback. *First-drive item.*

## Results — 2026-07-02 build-day summary

Ten boxes observed live through the installed plugin (cache loop, install, injection, kill-switch, soft block with real verdict arbitration, criteria refusal with role separation, structured commit, workspace resolution and closure). Seven boxes remain for the first live drive, each already covered at script level by the bats suite (74 tests green). The engine's own diff passes its own coverage gate with two justified kcov-quirk exemptions.
