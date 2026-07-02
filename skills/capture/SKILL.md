---
name: capture
description: Harmonia capture stage - record learnings into the right memory tier, then ship structured commits. Use ONLY when explicitly invoked as /harmonia:capture.
---

Read your working contract first: `${CLAUDE_PLUGIN_ROOT}/core/RULES.md`.
Read the `capture` stage from `${CLAUDE_PLUGIN_ROOT}/core/lifecycle.yaml` - its agent sequence ends with the committer by contract; do not hardcode.

1. Workspace: `bash ${CLAUDE_PLUGIN_ROOT}/bin/workspace.sh resolve --repo .` (later stage: never mints; surface ambiguity or no-active-task and stop).
2. Dispatch the knowledge curator with the verdict, scope, and diff-summary paths. It drafts learnings and writes each through `bash ${CLAUDE_PLUGIN_ROOT}/bin/memory/capture.sh` with an explicit `--tier` decision and `--client` flag where applicable - client content never reaches the global tier (R21).
3. Dispatch the committer with `boundary.md`, `diff-summary.md`, and the verdict: structured, single-concern commits whose messages communicate intent (R6); nothing outside the boundary, never workspace files.
4. Close the task: `bash ${CLAUDE_PLUGIN_ROOT}/bin/workspace.sh complete --repo .` (writes the completion marker so resolution skips this workspace).

Pass workspace paths, not prose recaps (R8). Orchestrate only (R9).
