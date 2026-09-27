#!/usr/bin/env bash
# Receipt audit (review's tier-B honesty gate, KTD7): every receipt in a task
# workspace must be one this machine wrote, and every code-dependent one must be
# fresh for the tree under review.
#
#   verify-receipts.sh --workspace WS [--repo R] [--base REF]
#
# Exit: 0 receipts verified | 1 a receipt is missing, stale, did not pass, lies
# outside the workspace or arrived with the repository | 4 cannot verify (the
# base-ref is not a real path inside the workspace, arrived with the repository,
# or does not resolve).
set -u

REPO="." BASE="HEAD" BASE_GIVEN=0 WS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --base) BASE="$2"; BASE_GIVEN=1; shift 2 ;;
    --workspace) WS="$2"; shift 2 ;;
    *) echo "verify-receipts: unknown argument '$1'" >&2; exit 1 ;;
  esac
done
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/base-ref-lib.sh"
[ -n "$WS" ] || { echo "verify-receipts: --workspace is required" >&2; exit 1; }
REPO="$(cd "$REPO" && pwd)"

# Absent --base, the workspace's base-ref file supplies the base, which makes
# base-ref an audit input with the same standing as the receipts checked against
# it: redirected, it names a base the caller never chose, and the audit's answer
# flips on it - a receipt holding the empty-diff digest goes from `stale` to
# `receipts verified` when base-ref is symlinked at a file naming a ref the diff
# really is empty against. base-ref is judged whenever a workspace names one, NOT
# only when this invocation is about to read it: a caller that passes
# `--base <workspace base-ref>` hands the file's value straight back in, and a
# guard placed behind `--base` being absent never runs for it. A workspace whose
# base-ref a repository carries is not a workspace anyone here minted.
if [ -f "$WS/base-ref" ]; then
  ws_contained "$WS" base-ref || { echo "verify-receipts: cannot verify - base-ref is not a real path inside the task workspace $WS (refusing to take a base from outside it)"; exit 4; }
  vbase_reason="$(ws_provenance_reason "$WS" base-ref)" || { echo "verify-receipts: cannot verify - $vbase_reason"; exit 4; }
  [ "$BASE_GIVEN" -eq 0 ] && BASE="$(cat "$WS/base-ref")"
fi
BASE="$(parse_base_ref "$BASE")"

# Never audit against a ref git cannot resolve: an unresolvable base makes every
# diff empty, and a receipt carrying the empty-diff digest would read as fresh.
if ! base_resolves "$REPO" "$BASE"; then
  echo "verify-receipts: cannot verify - base ref '$BASE' does not resolve"
  exit 4
fi

[ -d "$WS/receipts" ] || { echo "verify-receipts: receipts missing at $WS/receipts"; exit 1; }
cur="$(diff_digest "$REPO" "$BASE")"
# crit_seen answers the question the audit is actually asked: did a gate that
# executes against the tree leave a fresh receipt for it. check-criteria's shape
# receipt cannot answer that - it is validated by status alone - so a store
# holding only that one certifies a tree nothing ran against.
bad=0 crit_seen=0
for r in "$WS"/receipts/*.json; do
  [ -f "$r" ] || { echo "verify-receipts: receipts missing at $WS/receipts"; exit 1; }
  # Nothing is written here, so no escape detector sees a redirected store - what
  # is wrong is the VERDICT. Asked per receipt rather than once for receipts/,
  # because this loop GLOBS: it reaches names no writer knows to guard, and a
  # symlink at one receipt is followed inside a receipts/ that is itself
  # contained. The per-receipt question also refuses every redirect above it.
  ws_contained "$WS" "receipts/${r##*/}" || { echo "verify-receipts: FAIL - receipts/${r##*/} does not resolve inside the task workspace $WS (refusing to certify a receipt from outside it)"; exit 1; }
  # Containment is the wrong question on its own here. A repository can COMMIT
  # its own receipts: every path then resolves exactly where a receipt belongs,
  # containment accepts, and on a fresh clone with nothing run locally this audit
  # certifies a tree no gate here ever looked at. Task workspaces are
  # gitignored, so a tracked receipt is never one we wrote.
  rcp_reason="$(ws_provenance_reason "$WS" "receipts/${r##*/}")" || {
    echo "verify-receipts: FAIL - $rcp_reason"
    exit 1
  }
  g="$(jq -r '.gate // empty' "$r")"
  # check-criteria validates scope.md (code-independent) but its receipt hashes
  # the diff at implement-start on a clean tree, so its digest goes code-stale
  # the moment implement writes code. Validate it by status, not freshness.
  if [ "$g" = "check-criteria" ]; then  # The waiver keys on this gate NAME, not on the script: the same script's review-time `--run` receipt (gate "criteria-run") is code-dependent and takes the freshness path below.
    if [ "$(jq -r '.status // empty' "$r")" != "pass" ]; then echo "verify-receipts: receipt $(basename "$r") did not pass (status not pass)"; bad=1; fi
    continue
  fi
  [ "$g" = "criteria-run" ] && crit_seen=1
  # criteria-run's exit code is the gate and its receipt witnesses freshness, so
  # `fail` there means the criteria ran and lost. `running` is accepted: it is
  # what an audit invoked from inside the run it certifies finds on disk.
  if [ "$g" = "criteria-run" ] && [ "$(jq -r '.status // empty' "$r")" = "fail" ]; then
    echo "verify-receipts: receipt $(basename "$r") reports the criteria run failed"; bad=1
  fi
  stored="$(jq -r '.diff_digest // empty' "$r")"
  if [ -z "$stored" ]; then echo "verify-receipts: receipt $(basename "$r") carries no digest - stale"; bad=1
  elif [ "$stored" != "$cur" ]; then echo "verify-receipts: receipt $(basename "$r") is stale (diff digest mismatch)"; bad=1
  fi
done
[ "$bad" -eq 1 ] && exit 1
[ "$crit_seen" -eq 0 ] && { echo "verify-receipts: no code-dependent receipt to verify - refusing (no criteria-run receipt)"; exit 1; }
echo "verify-receipts: receipts verified"
exit 0
