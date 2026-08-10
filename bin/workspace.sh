#!/usr/bin/env bash
# Task-workspace mechanics (KTD10): the deterministic owner of mint, resolve,
# clear-span, accept, complete, abandon, and the test-immutability hash checks (KTD12).
#
#   workspace.sh mint    --repo R --slug <slug> [--new]
#   workspace.sh resolve --repo R [--task <id>]
#   workspace.sh clear-span --repo R [--task <id>]
#   workspace.sh accept  --repo R [--task <id>]
#   workspace.sh reject  --repo R [--task <id>] --reason <text>
#   workspace.sh verify-acceptance --repo R [--task <id>]
#   workspace.sh complete --repo R [--task <id>]
#   workspace.sh abandon  --repo R [--task <id>]
#   workspace.sh record-test-hashes --repo R [--task <id>]
#   workspace.sh verify-test-hashes --repo R [--task <id>]
#
# Exit: 0 ok | 1 failure (incl. hash violation, stale acceptance,
# unresolvable base, and a workspace path that does not resolve inside the
# repository's task tree) | 2 ambiguity | 3 no active task | 4 mint refused
# (incomplete workspace exists; pass --new to force) | 5 no acceptance
# marker (verify-acceptance) | 6 live rejection blocks verify-acceptance.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/base-ref-lib.sh"

CMD="${1:-}"; shift || true
REPO="." SLUG="" TASK="" FORCE_NEW=0 REASON=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --slug) SLUG="$2"; shift 2 ;;
    --task) TASK="$2"; shift 2 ;;
    --new)  FORCE_NEW=1; shift ;;
    --reason) REASON="$2"; shift 2 ;;
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
    echo "workspace: no active task - start an entry stage (ideate/discuss/plan/quick) or pass --task <id>" >&2
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

# Guard first, then work (FU-16): the containment question is asked as the first
# statement after a command resolves its id, before any read and before any
# write. That is what makes verify-test-hashes refuse a redirected manifest
# rather than read it, and it is one line per command instead of one per sink.
# The rm -f pairs (accept's `rejected`, reject's `accepted`, clear-span's six)
# get no call of their own: once this passes, the workspace is contained, so the
# worst those can find is a symlink inside it - and rm -f unlinks the link.
ws_guard() {   # <rel-under-the-workspace, empty for the task directory itself>
  ws_contained "$TASKS/$ID" "${1:-}" && return 0
  echo "workspace: refusing - ${1:-the task directory} is not a real path inside $TASKS/$ID (a symlink there is refused whether or not its target stays in the tree)" >&2
  exit 1
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
    # mint is the exception to guard-first: it CREATES the workspace, so there is
    # nothing to resolve when the check has to run. It checks what is already
    # there - four components, because the .gitignore below is the one mint write
    # that lands one level ABOVE the task directory - and doing the mkdir first is
    # not free: under a redirected .harmonia or .harmonia/tasks it creates the
    # whole tree outside the repository and only then refuses.
    for c in .harmonia .harmonia/tasks .harmonia/tasks/.gitignore ".harmonia/tasks/$ID"; do
      [ -L "$REPO/$c" ] && { echo "workspace: refusing to mint - $REPO/$c is a symlink; the task tree must be real directories inside the repository" >&2; exit 1; }
    done
    mkdir -p "$TASKS/$ID/receipts"
    # Then the same predicate over the result, once per artifact mint writes:
    # it re-uses an existing task directory when the date and slug repeat, so a
    # symlink planted at `minted` or `base-ref` survives to be followed.
    for r in receipts minted base-ref; do ws_guard "$r"; done
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
    ws_guard
    D="$TASKS/$ID"
    cleared=""
    for f in design.md boundary.md diff-summary.md verdict.md gate-report.md violations; do
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
    ws_guard accepted
    ws_guard base-ref   # the base decides the digest this marker records, so a redirect makes the developer's own consent record attest to a base they never chose
    base="$(parse_base_ref "$(cat "$TASKS/$ID/base-ref" 2>/dev/null)")"
    if ! base_resolves "$REPO" "$base"; then
      echo "workspace: cannot accept - base ref '$base' does not resolve; no acceptance marker written" >&2
      exit 1
    fi
    printf '%s\ndigest: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(diff_digest "$REPO" "$base")" > "$TASKS/$ID/accepted"
    rm -f "$TASKS/$ID/rejected"    # mutual exclusivity: accept supersedes reject
    echo "$ID accepted"
    ;;
  reject)
    ID="$(pick)" || exit $?
    ws_guard rejected
    [ -n "$REASON" ] || { echo "workspace: reject needs --reason <text>" >&2; exit 1; }
    case "$REASON" in *$'\n'*|*$'\r'*) echo "workspace: --reason must be a single line" >&2; exit 1 ;; esac  # SEC-1: a multi-line reason could forge a second digest: line in the marker
    ws_guard base-ref   # same reason as accept: the rejection marker carries a digest too
    base="$(parse_base_ref "$(cat "$TASKS/$ID/base-ref" 2>/dev/null)")"
    if ! base_resolves "$REPO" "$base"; then
      echo "workspace: cannot reject - base ref '$base' does not resolve; no rejection marker written" >&2
      exit 1
    fi
    printf '%s\nreason: %s\ndigest: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$REASON" "$(diff_digest "$REPO" "$base")" > "$TASKS/$ID/rejected"
    rm -f "$TASKS/$ID/accepted"    # mutual exclusivity: reject supersedes accept
    echo "$ID rejected"
    ;;
  verify-acceptance)
    ID="$(pick)" || exit $?
    # This command writes nothing, so no escape detector can notice it reading
    # the wrong bytes - what is wrong is the VERDICT, and skills/capture/SKILL.md:11
    # gates on it. Guard-first covers every file it reads, not only the ones
    # something writes. Measured on the build that guarded the writers alone:
    # `accepted` symlinked at a planted marker outside the repository answered
    # `acceptance verified` at exit 0, and the remedy that path's own message
    # names - re-accept, which supersedes - had by then been closed by the same
    # guards, leaving the forged state with no way out.
    for f in rejected accepted base-ref; do ws_guard "$f"; done
    if [ -f "$TASKS/$ID/rejected" ]; then
      reason="$(sed -n 's/^reason: //p' "$TASKS/$ID/rejected" | head -1)"
      recorded="$(sed -n 's/^digest: //p' "$TASKS/$ID/rejected" | head -1)"
      base="$(parse_base_ref "$(cat "$TASKS/$ID/base-ref" 2>/dev/null)")"
      if ! base_resolves "$REPO" "$base"; then
        staleness=" (cannot check whether this rejection is current: base ref '$base' does not resolve)"
      elif [ "$recorded" != "$(diff_digest "$REPO" "$base")" ]; then
        staleness=" - this rejection is stale: the tracked diff has moved since it was recorded"
      else
        staleness=""
      fi
      echo "workspace: cannot verify acceptance - task '$ID' has a live rejection: ${reason:-(no reason recorded)}${staleness}; clear it by re-accepting (workspace.sh accept, which supersedes) or abandon the task" >&2
      exit 6
    fi
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
    ws_guard "$marker"
    date -u +%Y-%m-%dT%H:%M:%SZ > "$TASKS/$ID/$marker"
    echo "$ID $marker"
    ;;
  record-test-hashes)
    ID="$(pick)" || exit $?
    ws_guard test-hashes
    ( cd "$REPO" && { git ls-files; git ls-files --others --exclude-standard; } \
        | grep -E '(^tests?/|\.bats$|[._]test\.|[._]spec\.)' | sort -u \
        | xargs -r sha256sum 2>/dev/null ) > "$TASKS/$ID/test-hashes"
    echo "recorded $(wc -l < "$TASKS/$ID/test-hashes" | tr -d ' ') test-file hashes"
    ;;
  verify-test-hashes)
    ID="$(pick)" || exit $?
    # Two files, two guards. `violations` is the write this command may make;
    # `test-hashes` is the manifest it exists to READ, and the comment that used
    # to sit alone on this line claimed the read was covered while naming the
    # other file. Measured against a genuinely edited recorded test: the honest
    # manifest reports the KTD12 violation, and one symlinked outside the
    # repository reports `test hashes verified` and the violation disappears.
    ws_guard violations
    ws_guard test-hashes
    H="$TASKS/$ID/test-hashes"
    [ -f "$H" ] || { echo "workspace: no recorded test hashes - run record-test-hashes after the test-engineer turn" >&2; exit 1; }
    if [ ! -s "$H" ]; then
      echo "test hashes verified (no test files recorded)"
      exit 0
    fi
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
    echo "usage: workspace.sh {mint|resolve|clear-span|accept|reject|verify-acceptance|complete|abandon|record-test-hashes|verify-test-hashes} ..." >&2
    exit 1
    ;;
esac
