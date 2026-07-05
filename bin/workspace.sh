#!/usr/bin/env bash
# Task-workspace mechanics (KTD10): the deterministic owner of mint, resolve,
# clear-span, accept, complete, abandon, and the test-immutability hash checks (KTD12).
#
#   workspace.sh mint    --repo R --slug <slug> [--new]
#   workspace.sh resolve --repo R [--task <id>]
#   workspace.sh clear-span --repo R [--task <id>]
#   workspace.sh accept  --repo R [--task <id>]
#   workspace.sh verify-acceptance --repo R [--task <id>]
#   workspace.sh complete --repo R [--task <id>]
#   workspace.sh abandon  --repo R [--task <id>]
#   workspace.sh record-test-hashes --repo R [--task <id>]
#   workspace.sh verify-test-hashes --repo R [--task <id>]
#
# Exit: 0 ok | 1 failure (incl. hash violation, stale acceptance,
# unresolvable base) | 2 ambiguity | 3 no active task | 4 mint refused
# (incomplete workspace exists; pass --new to force) | 5 no acceptance
# marker (verify-acceptance).
set -u
. "$(dirname "${BASH_SOURCE[0]}")/base-ref-lib.sh"

CMD="${1:-}"; shift || true
REPO="." SLUG="" TASK="" FORCE_NEW=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --slug) SLUG="$2"; shift 2 ;;
    --task) TASK="$2"; shift 2 ;;
    --new)  FORCE_NEW=1; shift ;;
    *) echo "workspace: unknown argument '$1'" >&2; exit 1 ;;
  esac
done
TASKS="$REPO/.harmonia/tasks"

incomplete() { # list task-ids with neither done nor abandoned marker
  [ -d "$TASKS" ] || return 0
  for d in "$TASKS"/*/; do
    [ -d "$d" ] || continue
    [ -f "${d}done" ] && continue
    [ -f "${d}abandoned" ] && continue
    basename "$d"
  done
}

pick() { # resolve --task override or the single incomplete workspace
  if [ -n "$TASK" ]; then
    case "$TASK" in */*|*..*) echo "workspace: invalid task id '$TASK'" >&2; exit 1 ;; esac
    [ -d "$TASKS/$TASK" ] || { echo "workspace: no such task '$TASK'" >&2; exit 1; }
    echo "$TASK"; return 0
  fi
  local list count
  list="$(incomplete)"
  count="$(echo "$list" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "$count" -eq 0 ]; then
    echo "workspace: no active task - start an entry stage (ideate/brainstorm/plan/quick) or pass --task <id>" >&2
    exit 3
  fi
  if [ "$count" -gt 1 ]; then
    echo "workspace: ambiguous - multiple incomplete workspaces; pass --task <id>:" >&2
    for t in $list; do
      minted="(unknown mint date)"
      [ -f "$TASKS/$t/minted" ] && minted="$(cat "$TASKS/$t/minted")"
      echo "  $t  minted: $minted" >&2
    done
    exit 2
  fi
  echo "$list" | sed '/^$/d'
}

case "$CMD" in
  mint)
    [ -n "$SLUG" ] || { echo "workspace: mint needs --slug" >&2; exit 1; }
    if [ "$FORCE_NEW" -eq 0 ]; then
      existing="$(incomplete | head -1)"
      if [ -n "$existing" ]; then
        echo "workspace: refusing to mint - incomplete workspace '$existing' exists; pass --task $existing to continue it, or --new to force a fresh mint" >&2
        exit 4
      fi
    fi
    ID="$(date +%Y-%m-%d)-$(echo "$SLUG" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//')"
    mkdir -p "$TASKS/$ID/receipts"
    printf '*\n' > "$TASKS/.gitignore"   # self-ignoring in every target repo (KTD10)
    date -u +%Y-%m-%dT%H:%M:%SZ > "$TASKS/$ID/minted"
    ref="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo none)"
    echo "ref: $ref" > "$TASKS/$ID/base-ref"
    echo "$ID"
    ;;
  resolve)
    pick
    ;;
  clear-span)
    ID="$(pick)" || exit $?
    D="$TASKS/$ID"
    cleared=""
    for f in design.md boundary.md diff-summary.md verdict.md gate-report.md; do
      if [ -f "$D/$f" ]; then
        rm -f "$D/$f"
        cleared="$cleared $f"
      fi
    done
    if [ -n "$cleared" ]; then
      echo "cleared span out-artifacts:$cleared"
    else
      echo "clear-span: nothing to clear"
    fi
    ;;
  accept)
    ID="$(pick)" || exit $?
    base="$(parse_base_ref "$(cat "$TASKS/$ID/base-ref" 2>/dev/null)")"
    if ! base_resolves "$REPO" "$base"; then
      echo "workspace: cannot accept - base ref '$base' does not resolve; no acceptance marker written" >&2
      exit 1
    fi
    printf '%s\ndigest: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(diff_digest "$REPO" "$base")" > "$TASKS/$ID/accepted"
    echo "$ID accepted"
    ;;
  verify-acceptance)
    ID="$(pick)" || exit $?
    M="$TASKS/$ID/accepted"
    if [ ! -f "$M" ]; then
      echo "workspace: no acceptance marker - the developer records acceptance via workspace.sh accept" >&2
      exit 5
    fi
    base="$(parse_base_ref "$(cat "$TASKS/$ID/base-ref" 2>/dev/null)")"
    if ! base_resolves "$REPO" "$base"; then
      echo "workspace: cannot verify acceptance - base ref '$base' does not resolve" >&2
      exit 1
    fi
    recorded="$(sed -n 's/^digest: //p' "$M" | head -1)"
    if [ "$recorded" != "$(diff_digest "$REPO" "$base")" ]; then
      echo "workspace: acceptance is stale - the accepted digest does not match the live diff; the developer must re-accept (workspace.sh accept)" >&2
      exit 1
    fi
    echo "acceptance verified"
    ;;
  complete|abandon)
    ID="$(pick)" || exit $?
    marker=done
    [ "$CMD" = abandon ] && marker=abandoned
    date -u +%Y-%m-%dT%H:%M:%SZ > "$TASKS/$ID/$marker"
    echo "$ID $marker"
    ;;
  record-test-hashes)
    ID="$(pick)" || exit $?
    ( cd "$REPO" && { git ls-files; git ls-files --others --exclude-standard; } \
        | grep -E '(^tests?/|\.bats$|[._]test\.|[._]spec\.)' | sort -u \
        | xargs -r sha256sum 2>/dev/null ) > "$TASKS/$ID/test-hashes"
    echo "recorded $(wc -l < "$TASKS/$ID/test-hashes" | tr -d ' ') test-file hashes"
    ;;
  verify-test-hashes)
    ID="$(pick)" || exit $?
    H="$TASKS/$ID/test-hashes"
    [ -f "$H" ] || { echo "workspace: no recorded test hashes - run record-test-hashes after the test-engineer turn" >&2; exit 1; }
    if out="$(cd "$REPO" && sha256sum -c "$H" --quiet 2>&1)"; then
      echo "test hashes verified"
    else
      {
        echo "test-immutability VIOLATION at $(date -u +%Y-%m-%dT%H:%M:%SZ):"
        echo "$out"
      } >> "$TASKS/$ID/violations"  # harmonia:exempt kcov cannot attribute brace-group redirect closers; the violation record is asserted by tests
      echo "workspace: test-immutability violation - the implementer may not edit tests (KTD12); recorded in the workspace for the review lead" >&2
      exit 1
    fi
    ;;
  *)
    echo "usage: workspace.sh {mint|resolve|clear-span|accept|verify-acceptance|complete|abandon|record-test-hashes|verify-test-hashes} ..." >&2
    exit 1
    ;;
esac
