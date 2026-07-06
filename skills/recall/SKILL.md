---
name: recall
description: Harmonia recall - surface relevant past learnings for the current repo mid-session. Use ONLY when explicitly invoked as /harmonia:recall.
---

Read your working contract first: `${CLAUDE_PLUGIN_ROOT}/core/RULES.md`.

Run the recall script and surface the summaries it returns:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/memory/recall.sh
```

Forward `--repo <path>` and `--budget-lines <n>` when the developer asks to widen or narrow the pull; otherwise the defaults apply. The script is the single source of truth - it filters learnings by language tags and recency under a budget. This wraps the same script the session-start hook and roster agents call directly, so it is a convenience over that mechanism, not a separate one; do not fork its logic.
