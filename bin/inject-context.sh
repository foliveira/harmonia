#!/usr/bin/env bash
# SessionStart hook (tier A, KTD7): emit a rules digest plus relevant recall
# summaries to stdout for context injection. Contract: kill-switch first; on
# any internal error emit NOTHING to stdout (warn on stderr) and exit zero -
# garbage stdout would become injected context, and a failed hook must never
# degrade the session (SWI failure containment).
set -u

# Emergency brake - works even when everything below is broken.
if [ "${HARMONIA_DISABLE:-0}" = "1" ]; then exit 0; fi

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
SIZE_CAP=4000   # bytes; the payload re-enters context after every compaction
RECALL_BUDGET=12

build_payload() {
  local rules="$ROOT/core/RULES.md"
  [ -r "$rules" ] || return 1

  echo "## Harmonia is active"
  echo
  echo "The 4 rules bind all work in this session:"
  # Digest: each rule heading plus its first line, not the whole file.
  awk '/^## [0-9]\./ { sub(/^## [0-9]+\. */, ""); name=$0; getline; getline; printf "- %s - %s\n", name, $0 }' "$rules" || return 1
  echo
  local recall
  recall="$(bash "$ROOT/bin/memory/recall.sh" --repo "$PROJECT" --budget-lines "$RECALL_BUDGET" 2>/dev/null)" || return 1
  if [ -n "$recall" ]; then
    echo "Relevant learnings (run /harmonia:recall for more):"
    echo "$recall"
  fi
}

if payload="$(build_payload)"; then
  printf '%s' "$payload" | head -c "$SIZE_CAP"
else
  echo "harmonia inject-context: warning - payload build failed, injecting nothing" >&2
fi
exit 0
