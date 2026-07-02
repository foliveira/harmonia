# Harmonia v1 — end-to-end dogfood walkthrough

Run in a fresh sandbox repo (copy `tests/fixtures/sandbox/`). Each step names its expected observable outcome; check the box only when you observed it. Steps marked `[headless-ok]` can be executed with `claude -p` from a script; the rest want a live session.

## 0. The cache-refresh loop (KTD4)

- [ ] `git -C ~/Projects/sdlc commit` any engine change, then `claude plugin update harmonia` (or wait for the nightly), then open a **fresh session**. Expected: `claude plugin list` shows the new commit SHA as the version. Live behavior always comes from the cache, never the working checkout.

## 1. Install (R2, KTD1) `[headless-ok]`

- [ ] `claude plugin marketplace add foliveira/harmonia` (or the local checkout path) succeeds.
- [ ] `claude plugin install harmonia` succeeds; `claude plugin list` shows `harmonia@harmonia` enabled.

## 2. Recall injection (AE5, tier A) `[headless-ok]`

- [ ] Seed one global learning: `bash bin/memory/capture.sh --title "Sandbox Go pitfall" --tier global --tags go --repo <sandbox>` with a body on stdin.
- [ ] Open a fresh session in the sandbox (it contains a `.go` file). Expected: the session context carries the 4 rule names and the "Sandbox Go pitfall" summary without being asked.
- [ ] `HARMONIA_DISABLE=1 claude -p ...` in the same sandbox: expected NO Harmonia injection (kill-switch).

## 3. Express lane and the soft block (AE1) — live session

- [ ] `/harmonia:quick` on a small sandbox change that leaves one changed line uncovered. Expected: the gate fails soft; the reviewer names the uncovered file:line **from the gate report file**, not from conversation.
- [ ] Record an override: expected one new entry (date, task, path, lines, justification) appended to `.harmonia/coverage-exemptions.yaml`, and the reviewer's verdict cites it.

## 4. Full cycle on a feature-shaped task — live session

- [ ] `/harmonia:brainstorm` first: the scoper mints `scope.md` once (earliest scope-bearing stage); a later `/harmonia:plan` refines rather than re-mints (R31).
- [ ] `/harmonia:implement` with prose-only criteria ("make it nicer"): expected refusal naming the offending criterion, receipt still written (AE2 intake shape).
- [ ] Sharpen criteria to `- run:` commands; implement proceeds. Seed a coverage gap: expected a **cover-first** round — the test engineer writes a test executing the named lines, green on arrival, implementer turn skipped (AE7), gate then passes with no override entry.
- [ ] Introduce a small new abstraction in the diff: expected the review lead dispatches the adversarial lens, and `verdict.md` carries its findings (or explicit clean report) with seat attribution (AE8).
- [ ] `/harmonia:capture`: the curator writes learnings through capture.sh; the committer ships structured single-concern commits whose messages communicate intent (R6) — observed in `git log`.

## 5. Interruption recovery (KTD10) — live session

- [ ] Interrupt after implement (close the session). Open a new session, run `/harmonia:review` with no task id. Expected: it resolves the single incomplete workspace (receipts echo the task id) and completes review against the on-disk artifacts.

## 6. Memory tiers (AE4, AE5 agent-seat) — live session

- [ ] Capture one client-flagged learning: expected it lands in the sandbox's `docs/learnings/` only; `~/.harmonia/` unchanged (AE4).
- [ ] In a new session, ask a **roster agent** (not the main session) to state a relevant prior learning: expected it runs `recall.sh` via its charter path and quotes the global learning (AE5 beyond the orchestrator).

## 7. Platform probes (KTD2, KTD11) — live session

- [ ] Spawn one roster agent manually: expected it resolves and quotes its charter before acting; with a deliberately broken charter path it refuses and reports the path.
- [ ] Nested-dispatch probe: the review lead spawns one named panel member and one lens, recording which model served each. If invocation-time override or named nested dispatch fails, ship lenses as thin defined agents with model frontmatter and record the fallback in KTD11.

## Results

Record observations inline next to each box; a completed walkthrough has every box checked with its observation.
