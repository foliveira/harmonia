#!/usr/bin/env bash
# Criteria gate (tier B, KTD7): validate that the scope declaration carries
# machine-checkable success criteria, and write a digest-bearing receipt.
#   check-criteria.sh --workspace <task-workspace> [--repo <path>]
# Exit: 0 criteria valid; 1 invalid (per-criterion report, receipt still
# written); 3 cannot-check (no scope declaration at the contract path).
set -u
. "$(dirname "${BASH_SOURCE[0]}")/base-ref-lib.sh"

WS="" REPO="."
while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) WS="$2"; shift 2 ;;
    --repo)      REPO="$2"; shift 2 ;;
    *) echo "check-criteria: unknown argument '$1'" >&2; exit 1 ;;
  esac
done
[ -n "$WS" ] || { echo "check-criteria: --workspace is required" >&2; exit 1; }

SCOPE="$WS/scope.md"
if [ ! -f "$SCOPE" ]; then
  echo "check-criteria: no scope declaration at $SCOPE - run the scoper first (R31)" >&2
  exit 3
fi

# Receipt fields (KTD7): task-id, timestamp, digest of the evaluated diff.
TASK_ID="$(basename "$WS")"
BASE="HEAD"
if [ -f "$WS/base-ref" ]; then
  BASE="$(parse_base_ref "$(cat "$WS/base-ref")")"
  [ -n "$BASE" ] || BASE="HEAD"
fi
DIGEST="$(diff_digest "$REPO" "$BASE")"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Extract the Success Criteria section's bullets.
CRITERIA="$(awk '/^## Success Criteria/{inb=1; next} /^## /{inb=0} inb && /^- /' "$SCOPE")"

STATUS_TXT="pass"
FAIL=0
REPORT=""
if [ -z "$CRITERIA" ]; then
  REPORT="no criteria found under '## Success Criteria'"
  FAIL=1
else
  while IFS= read -r line; do
    cmd="${line#- }"
    case "$cmd" in
      run:*)
        c="$(echo "${cmd#run:}" | sed 's/^ *//')"
        if [ -z "$c" ]; then REPORT="$REPORT
empty run: criterion"; FAIL=1; fi
        ;;
      *)
        REPORT="$REPORT
not machine-checkable (needs 'run: <command>'): $cmd"
        FAIL=1
        ;;
    esac
  done <<< "$CRITERIA"
fi
[ "$FAIL" -eq 1 ] && STATUS_TXT="fail"

mkdir -p "$WS/receipts"
cat > "$WS/receipts/check-criteria.json" <<EOF
{
  "gate": "check-criteria",
  "task_id": "$TASK_ID",
  "timestamp": "$TS",
  "diff_digest": "$DIGEST",
  "status": "$STATUS_TXT"
}
EOF

if [ "$FAIL" -eq 1 ]; then
  echo "check-criteria: FAIL - criteria must be machine-checkable (Goal-Driven Execution):" >&2
  echo "$REPORT" | sed '/^$/d' | sed 's/^/  - /' >&2
  # Also on stdout so calling skills can surface the offenders directly.
  echo "check-criteria: FAIL$REPORT"
  exit 1
fi
echo "check-criteria: OK ($(echo "$CRITERIA" | wc -l | tr -d ' ') criteria, receipt written)"
exit 0
