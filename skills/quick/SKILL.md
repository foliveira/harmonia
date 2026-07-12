---
name: quick
description: Harmonia express lane - implementer plus lead-solo review for trivial fixes, gates still active. Use ONLY when explicitly invoked as /harmonia:quick.
---

Your working contract is the 4 rules; their digest is injected at session start - read `${CLAUDE_PLUGIN_ROOT}/core/RULES.md` in full only if that digest is not in your context.
Read the `quick` stage from `${CLAUDE_PLUGIN_ROOT}/core/lifecycle.yaml` - agents, artifacts, gates, and its lead-solo review declaration are authoritative; do not hardcode them.

1. Workspace: `bash ${CLAUDE_PLUGIN_ROOT}/bin/workspace.sh mint --repo . --slug <short-task-slug>` (entry stage; on refusal, surface the message and stop).
2. Dispatch the implementer for the fix (Surgical Changes: only what the task requires).
3. Gates: `bash ${CLAUDE_PLUGIN_ROOT}/bin/coverage/gate.sh --repo . --base <workspace base-ref> --workspace <ws>`, then `--verify-receipts`. The soft block applies exactly as in the full cycle.
4. Dispatch the reviewer in lead-solo mode per the stage declaration - no panel; the security lens still auto-fires when its frontmatter triggers match the diff. One `verdict.md` to the workspace.
5. Close: `bash ${CLAUDE_PLUGIN_ROOT}/bin/workspace.sh complete --repo .`.

Pass workspace paths, not prose recaps (R8). Orchestrate only (R9).
