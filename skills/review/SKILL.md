---
name: review
description: Harmonia review stage - hierarchical review under the review lead with gates and receipts. Use ONLY when explicitly invoked as /harmonia:review.
---

Your working contract is the 4 rules; their digest is injected at session start - read `${CLAUDE_PLUGIN_ROOT}/core/RULES.md` in full only if that digest is not in your context.
Read the `review` stage from `${CLAUDE_PLUGIN_ROOT}/core/lifecycle.yaml` (already in context if the flow runner loaded it - do not re-read) - the panel roster and lens name list live there and are authoritative - do not hardcode them (KTD11); each lens file under `${CLAUDE_PLUGIN_ROOT}/core/lenses/` carries its own trigger rules in frontmatter, which are authoritative for dispatch.

1. Workspace: `bash ${CLAUDE_PLUGIN_ROOT}/bin/workspace.sh resolve --repo .` (later stage: never mints; surface ambiguity or no-active-task and stop).
2. Gates before judgment:
   - `bash ${CLAUDE_PLUGIN_ROOT}/bin/coverage/gate.sh --repo . --base <workspace base-ref> --workspace <ws>` (soft block: uncovered lines flag the work incomplete; overrides go through `--record-override` and the audit log).
   - `bash ${CLAUDE_PLUGIN_ROOT}/bin/check-criteria.sh --run --workspace <ws> --repo .` - executes every `- run:` criterion the scope declares, from the repo root, and prints the whole set it ran with each command verbatim. A failing criterion FAILS the review - this gate is hard, unlike coverage; exit 3 means there was no scope declaration to run. Keep the order: shipped criteria invoke the stage gates themselves, and `--verify-receipts` passes only once this round's coverage receipt exists.
   - `bash ${CLAUDE_PLUGIN_ROOT}/bin/coverage/gate.sh --verify-receipts --workspace <ws> --repo .` - missing or stale receipts FAIL the review (tier B honesty, KTD7).
3. Dispatch the reviewer (review lead) by path with every artifact this stage declares `in`, plus the rest of the lead's charter `consumes:` list - both are authoritative and neither is restated here (R9). The lead convenes the panel declared by this stage, dispatches lenses whose frontmatter triggers match the diff (security auto-fires on its fixed list), runs seats per `${CLAUDE_PLUGIN_ROOT}/core/patterns/panel.md` with model-diverse dispatch, and writes one attributed `verdict.md` to the workspace.
4. A test-immutability violation recorded in the workspace is treated like a missing receipt: the review fails.

Pass workspace paths, not prose recaps (R8). Orchestrate only (R9).
