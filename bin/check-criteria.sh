#!/usr/bin/env bash
# Criteria gate (tier B, KTD7): validate that the scope declaration carries
# machine-checkable success criteria, and write a digest-bearing receipt.
#   check-criteria.sh [--run] --workspace <task-workspace> [--repo <path>]
# With --run each criterion is executed from --repo, reported one line per
# criterion on stdout, and receipted under the gate name `criteria-run`; without
# it only the `- run:` shape is checked.
# Exit: 0 criteria valid (with --run: every criterion passed); 1 invalid, a
# criterion failed (per-criterion report, receipt still written), the receipt
# itself could not be written or would have landed outside the workspace, or
# --run was pointed at a scope declaration that is tracked in git; 3
# cannot-check (no scope declaration at the contract path).
set -u
. "$(dirname "${BASH_SOURCE[0]}")/base-ref-lib.sh"

WS="" REPO="." RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) WS="$2"; shift 2 ;;
    --repo)      REPO="$2"; shift 2 ;;
    --run)       RUN=1; shift ;;
    *) echo "check-criteria: unknown argument '$1'" >&2; exit 1 ;;
  esac
done
[ -n "$WS" ] || { echo "check-criteria: --workspace is required" >&2; exit 1; }
# --repo names a path and both its consumers must resolve it as one. The `cd` in
# the run loop reads a dash-leading value as an option instead - `-P`, `-L` and
# `--` land in $HOME, `-` in OLDPWD - so criteria execute outside the named tree
# and report OK over a red one, while `git -C` fails and the receipt carries the
# sha256 of the empty string under `status: pass`. Both lines are needed and
# neither of them is `cd --`: `[ -d ]` resolves the value as a path, so the
# sibling forms go too (a nonexistent path, a regular file, and "", which `cd`
# takes without moving); the `./` prefix is what stops `cd` re-reading a
# directory that genuinely is named `-P`; and `cd -- -` still lands in OLDPWD
# (measured). Here rather than in the --run branch because shape mode's
# diff_digest is the other consumer - unchecked, it receipts a clean-tree digest
# for a repo it never looked at.
[ -d "$REPO" ] || { echo "check-criteria: --repo '$REPO' is not a directory" >&2; exit 1; }
case "$REPO" in -*) REPO="./$REPO" ;; esac

SCOPE="$WS/scope.md"
if [ ! -f "$SCOPE" ]; then
  echo "check-criteria: no scope declaration at $SCOPE - run the scoper first (R31)" >&2
  exit 3
fi

# The CONTENTS of a workspace have not earned trust either: --run executes this
# file's `- run:` lines, and a repository you clone can ship one, so reading a
# stranger's repo becomes code execution. The `cd` moves into the workspace's
# PHYSICAL directory before git is asked, because git reads getcwd(): a guard
# keyed on the literal <ws>/scope.md path, or on the `git ls-files -- "$WS"`
# directory pathspec, is walked past by a clone that tracks a symlink at
# .harmonia/tasks with the payload one directory over. Outside a git work tree
# there is no index to ask, so the file is treated as the user's - a hand-made
# workspace in a non-git tree is the shipped shape, and the block at
# tests/hooks.bats is what pins it (the non-git accept cell of the fail-closed
# block; cited by name rather than line, because this task has moved that line
# twice and a stale citation was a finding in both prior rounds).
# Run mode only: shape mode executes nothing, and the same rule before the mode
# split would refuse work no one can run. Before any write, so a hostile clone
# leaves no receipt claiming a run happened.
#
# The predicate itself lives in bin/base-ref-lib.sh because the acceptance
# marker and the test-hash manifest need exactly the same question asked of
# them, and because "git said no" is not the same answer as "there is no
# repository" - ws_tracked is what separates the two and fails closed between.
# Two refusals, not one, and both worded in one place (bin/base-ref-lib.sh):
# "carried" has a remedy and "cannot be asked" does not, and telling a user their
# own file arrived with the repository when git merely failed to read an index is
# false and sends them somewhere that cannot help.
if [ "$RUN" -eq 1 ]; then
  prov_reason="$(ws_provenance_reason "$WS" scope.md)" || {
    echo "check-criteria: FAIL - refusing to execute $SCOPE: $prov_reason"
    exit 1
  }
  # base-ref gets the same question, and in run mode only for the same reason
  # scope.md does: shape mode executes nothing, and a rule placed before the mode
  # split refuses work no one can run - the over-reach probe of C4 is what
  # measures that. Here the base selects the tree this run receipts a digest for.
  base_reason="$(ws_provenance_reason "$WS" base-ref)" || {
    echo "check-criteria: FAIL - $base_reason"
    exit 1
  }
fi

# Receipt fields (KTD7): task-id, timestamp, digest of the evaluated diff.
TASK_ID="$(basename "$WS")"
BASE="HEAD"
if [ -f "$WS/base-ref" ]; then
  # The fifth and last base-ref reader to be guarded. It is not a marker and
  # nothing writes it here, but it supplies the base this gate's receipt attests
  # to, so a redirect makes the receipt claim a tree the caller never named.
  # ws_guard is defined further down, next to the receipt writer it was built
  # for, so the predicate is called directly rather than moved.
  ws_contained "$WS" base-ref || {
    echo "check-criteria: FAIL - base-ref is not a real path inside the task workspace $WS (refusing to take a base from outside it)"
    exit 1
  }
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
NTOTAL=0
[ -n "$CRITERIA" ] && NTOTAL="$(echo "$CRITERIA" | wc -l | tr -d ' ')"
NFAILED=0

# One writer, two gate names: the run mode's result is code-dependent and must
# not travel under the freshness-waived `check-criteria` name (the gate-name waiver in bin/coverage/gate.sh)
# or clobber the implement-stage shape receipt.
RECEIPT="check-criteria"
[ "$RUN" -eq 1 ] && RECEIPT="criteria-run"
# The workspace PATH has not earned trust either (FU-16): a symlink anywhere on
# the way to it redirects this write, and the writer's own exit status cannot see
# where the bytes went. Both call sites and both modes route through here - shape
# mode reaches the same writer at every implement round, which is the more
# frequent of the two. Exit 1 like the I/O-failure refusal below, not 3:
# skills/review/SKILL.md:12 reads 3 as "there was no scope declaration to run".
ws_guard() {   # <rel-under-the-workspace>
  ws_contained "$WS" "$1" && return 0
  echo "check-criteria: FAIL - $1 is not a real path inside the task workspace $WS (refusing to write through it)"
  exit 1
}
# The receipt is the only proof this gate ran (KTD7), so a write that cannot land
# is an I/O failure of the gate itself: fatal at either call site, and never a
# summary line announcing a receipt that is not there. What is in the way stays
# there - clearing the path would destroy the diagnostic to force the write.
write_receipt() {   # $1 = status
  ws_guard receipts   # the mkdir below creates a directory outside through a redirected receipts/
  mkdir -p "$WS/receipts"
  ws_guard "receipts/$RECEIPT.json"
  cat > "$WS/receipts/$RECEIPT.json" <<EOF
{
  "gate": "$RECEIPT",
  "task_id": "$TASK_ID",
  "timestamp": "$TS",
  "diff_digest": "$DIGEST",
  "status": "$1"
}
EOF
  [ $? -eq 0 ] && return 0
  echo "check-criteria: FAIL - cannot write receipt $WS/receipts/$RECEIPT.json (I/O failure, not a criterion result)"
  exit 1
}

if [ "$RUN" -eq 1 ] && [ -n "$CRITERIA" ]; then
  echo "check-criteria: executing $NTOTAL criteria from $SCOPE (cwd $REPO)"
  # The receipt goes down BEFORE the loop, carrying the pre-run digest every gate
  # of this round hashes and a status no reader can take for a pass. A shipped
  # criterion audits this very directory from inside the run
  # (`gate.sh --verify-receipts`, the shape every task here carries): without this
  # write, what it finds is the PREVIOUS round's receipt, stale against a tree that
  # changed since, so that criterion could not pass on any round after the first
  # however good the work was. Rewritten with the verdict once the loop ends; a run
  # killed mid-loop leaves `running`, which is true, and is neither `pass` nor the
  # `fail` that means criteria ran and lost.
  write_receipt running
fi
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
empty run: criterion"; FAIL=1
          if [ "$RUN" -eq 1 ]; then echo "  FAIL (empty run: criterion)"; NFAILED=$((NFAILED + 1)); fi
        elif [ "$RUN" -eq 1 ]; then
          # A fresh child per criterion, from the repo root, stdin closed: the
          # criterion cannot move this loop's cwd, end the run, clobber a
          # variable it uses, or drain the herestring feeding it. The comment
          # tail every shipped criterion carries is removed by the child's own
          # parser - the only handler that also gets a quoted `#` right.
          out="$(cd "$REPO" && bash -c "$c" </dev/null 2>&1)"; rc=$?
          if [ "$rc" -eq 0 ]; then
            echo "  PASS  $c"
          else
            echo "  FAIL (exit $rc)  $c"
            FAIL=1; NFAILED=$((NFAILED + 1))
            if [ -n "$out" ]; then
              # Drop TAP pass lines before excerpting: `bats tests/` is a
              # criterion of nearly every task and its failure sits wherever the
              # failing test sits, so a fixed head+tail window elides it.
              sig="$(printf '%s\n' "$out" | grep -vE '^ok [0-9]+ ')"
              [ -z "$sig" ] && sig="$out"
              n="$(printf '%s\n' "$sig" | wc -l)"
              if [ "$n" -le 20 ]; then
                printf '%s\n' "$sig" | sed 's/^/      | /'
              else
                printf '%s\n' "$sig" | head -10 | sed 's/^/      | /'
                echo "      | ... ($((n - 20)) lines elided) ..."
                printf '%s\n' "$sig" | tail -10 | sed 's/^/      | /'
              fi
            fi
          fi
        fi
        ;;
      *)
        REPORT="$REPORT
not machine-checkable (needs 'run: <command>'): $cmd"
        FAIL=1
        if [ "$RUN" -eq 1 ]; then
          echo "  FAIL (not machine-checkable)  $cmd"
          NFAILED=$((NFAILED + 1))
        fi
        ;;
    esac
  done <<< "$CRITERIA"
fi
[ "$FAIL" -eq 1 ] && STATUS_TXT="fail"
write_receipt "$STATUS_TXT"

# The run mode's own ending. An empty criteria set falls through to the shared
# verdict below on purpose: one message, both modes.
if [ "$RUN" -eq 1 ] && [ -n "$CRITERIA" ]; then
  if [ "$FAIL" -eq 1 ]; then
    echo "check-criteria: FAIL - $NFAILED of $NTOTAL criteria failed (receipt written)"
    exit 1
  fi
  echo "check-criteria: OK ($NTOTAL criteria executed, receipt written)"
  exit 0
fi

if [ "$FAIL" -eq 1 ]; then
  echo "check-criteria: FAIL - criteria must be machine-checkable (Goal-Driven Execution):" >&2
  echo "$REPORT" | sed '/^$/d' | sed 's/^/  - /' >&2
  # Also on stdout so calling skills can surface the offenders directly.
  echo "check-criteria: FAIL$REPORT"
  exit 1
fi
echo "check-criteria: OK ($(echo "$CRITERIA" | wc -l | tr -d ' ') criteria, receipt written)"
exit 0
