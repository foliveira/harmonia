---
name: implement
description: Harmonia implement stage - red-green build against the coverage gate under the criteria gate. Use ONLY when explicitly invoked as /harmonia:implement.
---

Read your working contract first: `${CLAUDE_PLUGIN_ROOT}/core/RULES.md`.
Read the `implement` stage from `${CLAUDE_PLUGIN_ROOT}/core/lifecycle.yaml` - agents, artifacts, gates, and the red-green `loop` definition (including `max_rounds`) are authoritative; do not hardcode them.

1. Workspace: `bash ${CLAUDE_PLUGIN_ROOT}/bin/workspace.sh resolve --repo .` (later stage: never mints; on ambiguity or no-active-task, surface the script's message and stop).
2. Criteria gate (tier B): `bash ${CLAUDE_PLUGIN_ROOT}/bin/check-criteria.sh --workspace <ws> --repo .` - refuse to start while it fails (Goal-Driven Execution). It writes its receipt.
3. Red-green loop, at most `max_rounds` rounds:
   - Dispatch the test-engineer: red-first for behavior; cover-first at gaps named by the last gate report (a green-on-arrival test at a gap completes the round - skip the implementer turn).
   - `bash ${CLAUDE_PLUGIN_ROOT}/bin/workspace.sh record-test-hashes --repo .` after every test-engineer turn.
   - Dispatch the implementer to go green; it may not edit tests.
   - `bash ${CLAUDE_PLUGIN_ROOT}/bin/workspace.sh verify-test-hashes --repo .` before accepting the round - a violation fails the round and is recorded for the review lead.
   - `bash ${CLAUDE_PLUGIN_ROOT}/bin/coverage/gate.sh --repo . --base <workspace base-ref> --workspace <ws>` - its report feeds the next round.
   - Exit when the gate passes; on the cap, exit incomplete and record the disagreement in the workspace - never escape via an exemption marker.
4. Producer duties on completion (KTD10): write `boundary.md` and `diff-summary.md` to the workspace.

Pass workspace paths, not prose recaps (R8). Orchestrate only (R9).
