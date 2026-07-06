#!/usr/bin/env bats
# Behavioral tests for `workspace.sh clear-span` (F3/item A). Unlike
# lifecycle-runner.bats (which greps runner prose), these run the REAL
# bin/workspace.sh against a scratch workspace under $BATS_TEST_TMPDIR and
# assert what it removes, preserves, and reports - the five-file list and
# path-confinement now live in shell a test exercises, not runner prose.
# No git needed for clear-span/pick (they touch no git). Conventions follow
# coverage.bats (REPO_ROOT from $BATS_TEST_FILENAME, scratch under TMPDIR).
#
# This file also pins the `reject` engine (record + block): the new
# `workspace.sh reject` subcommand, the accept<->reject mutual-exclusivity pair,
# and `verify-acceptance`'s rejected-awareness. Those DO need git (a resolvable
# base ref so the shared diff_digest computes), so they build a one-commit git
# scratch repo via git_ws(), mirroring the scope's success-criteria pattern.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WS_SH="$REPO_ROOT/bin/workspace.sh"
  R="$BATS_TEST_TMPDIR/target"
  mkdir -p "$R/.harmonia/tasks"
}

# fabricate a workspace: 5 span out-artifacts + every survivor the scope lists
seed_ws() {
  local id="$1" d="$R/.harmonia/tasks/$1"
  mkdir -p "$d/receipts"
  for f in design.md boundary.md diff-summary.md verdict.md gate-report.md \
           scope.md ideas.md accepted done minted base-ref; do : > "$d/$f"; done
  : > "$d/receipts/check-criteria.json"    # a receipt must survive (the .git-incident guard)
}

# fabricate an INCOMPLETE workspace: same span artifacts + survivors but NO
# done/abandoned marker, so incomplete() (and the no-`--task` resolver) reaches
# it. seed_ws writes `done`, which hides a workspace from that resolver, so the
# runner's real call path (`clear-span --repo .`, no --task) needs this variant.
seed_incomplete() {
  local id="$1" d="$R/.harmonia/tasks/$1"
  mkdir -p "$d/receipts"
  for f in design.md boundary.md diff-summary.md verdict.md gate-report.md \
           scope.md ideas.md minted base-ref; do : > "$d/$f"; done
  : > "$d/receipts/check-criteria.json"
}

# Build a one-commit git repo at $G (caller sets G) and mint a workspace in it
# via the REAL workspace.sh; echo the minted task id. mint records base-ref as
# HEAD, so it resolves and the shared diff_digest computes (a clean tree -> the
# empty-diff digest). Mirrors coverage.bats's scratch repo and the scope's
# success-criteria git pattern. Side effects land on disk (they survive the
# command-substitution subshell); only stdout, the id, is captured.
git_ws() {
  mkdir -p "$G"
  git -C "$G" init -q
  echo x > "$G/f"
  git -C "$G" add -A && git -C "$G" -c user.email=t@t -c user.name=t commit -qm init
  bash "$WS_SH" mint --repo "$G" --slug rej
}

@test "clear-span removes the five span out-artifacts and preserves everything else" {
  # criterion 1: removes design.md/boundary.md/diff-summary.md/verdict.md/
  # gate-report.md; preserves scope.md/ideas.md/accepted/done/minted/base-ref
  # and the whole receipts/ dir; reports what it cleared. --task addresses the
  # seeded (done-marked) workspace, which pick reaches by id regardless of done.
  seed_ws 2026-07-05-demo
  run bash "$WS_SH" clear-span --repo "$R" --task 2026-07-05-demo
  [ "$status" -eq 0 ]
  d="$R/.harmonia/tasks/2026-07-05-demo"
  for f in design.md boundary.md diff-summary.md verdict.md gate-report.md; do [ ! -f "$d/$f" ]; done
  for f in scope.md ideas.md accepted done minted base-ref; do [ -f "$d/$f" ]; done
  [ -f "$d/receipts/check-criteria.json" ]     # receipts/ untouched
  [[ "$output" == *"design.md"* ]]             # reports what it cleared
}

@test "clear-span is idempotent: a second run clears nothing and exits 0" {
  # criterion 2: absent files are not an error; the second run hits the
  # "nothing to clear" branch and still exits 0.
  seed_ws 2026-07-05-idem
  run bash "$WS_SH" clear-span --repo "$R" --task 2026-07-05-idem
  [ "$status" -eq 0 ]
  run bash "$WS_SH" clear-span --repo "$R" --task 2026-07-05-idem
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to clear"* ]]
}

@test "clear-span resolves via pick: no active task exits 3, --task is honored" {
  # criterion 3: with no --task and no incomplete workspace, clear-span inherits
  # pick's exit 3; --task targets the named workspace and clears it.
  run bash "$WS_SH" clear-span --repo "$R"
  [ "$status" -eq 3 ]
  [[ "$output" == *"no active task"* ]]
  seed_ws 2026-07-05-pick
  run bash "$WS_SH" clear-span --repo "$R" --task 2026-07-05-pick
  [ "$status" -eq 0 ]
  [ ! -f "$R/.harmonia/tasks/2026-07-05-pick/design.md" ]
}

@test "clear-span is documented in the usage string and the header command list" {
  # criterion 4: a bogus command falls to the *) usage arm (exit 1); the usage
  # string names clear-span (covering the modified usage line) and the header
  # command list documents it.
  run bash "$WS_SH" definitely-not-a-command
  [ "$status" -eq 1 ]
  [[ "$output" == *"clear-span"* ]]     # usage string lists it (covers the modified usage line)
  grep -qE '^#   workspace.sh clear-span' "$WS_SH"    # the invocation-block line, not the owner-of prose (F-C)
}

@test "clear-span refuses a traversing --task and deletes nothing outside the workspace (S1)" {
  # security S1: a --task carrying ../ must not escape $TASKS/$ID into the rm
  # sink. Seed a real workspace, then aim --task at a bystander dir OUTSIDE the
  # tasks tree that holds span-named files; the escape must be REFUSED (non-zero
  # exit) and the bystander's files must survive. RED until pick guards traversal.
  seed_ws 2026-07-05-real
  bystander="$BATS_TEST_TMPDIR/bystander"
  mkdir -p "$bystander"
  : > "$bystander/design.md"
  : > "$bystander/verdict.md"
  # from $R/.harmonia/tasks, ../../../bystander resolves to $BATS_TEST_TMPDIR/bystander
  run bash "$WS_SH" clear-span --repo "$R" --task '../../../bystander'
  [ "$status" -ne 0 ]                # the traversal is refused, not a silent exit-0 delete
  [ -f "$bystander/design.md" ]      # nothing removed outside the workspace
  [ -f "$bystander/verdict.md" ]
}

@test "clear-span resolves the single incomplete workspace with no --task (runner path)" {
  # F-B: the flow runner calls `clear-span --repo .` with NO --task; pick's
  # single-incomplete branch must resolve it, clear the five, and keep scope.md.
  # seed_incomplete omits the done marker so incomplete() actually reaches it.
  seed_incomplete 2026-07-05-live
  run bash "$WS_SH" clear-span --repo "$R"
  [ "$status" -eq 0 ]
  d="$R/.harmonia/tasks/2026-07-05-live"
  for f in design.md boundary.md diff-summary.md verdict.md gate-report.md; do [ ! -f "$d/$f" ]; done
  [ -f "$d/scope.md" ]                 # the pinned input survives
  [[ "$output" == *"design.md"* ]]     # reports what it cleared
}

@test "clear-span refuses ambiguity with no --task: two incomplete workspaces exit 2, nothing cleared" {
  # F-B (ambiguity edge): no --task and two incomplete workspaces -> pick cannot
  # choose, exit 2 before any removal.
  seed_incomplete 2026-07-05-one
  seed_incomplete 2026-07-05-two
  run bash "$WS_SH" clear-span --repo "$R"
  [ "$status" -eq 2 ]
  [ -f "$R/.harmonia/tasks/2026-07-05-one/design.md" ]   # nothing cleared on ambiguity
  [ -f "$R/.harmonia/tasks/2026-07-05-two/design.md" ]
}

# --- reject engine (record + block) -----------------------------------------
# The tests below pin NEW behavior that does not exist yet: the `reject`
# subcommand, the accept<->reject supersede pair, and `verify-acceptance`'s
# rejected-awareness. They are RED until the implementer adds those branches -
# today `--reason` is an unknown arg and `reject` falls to the *) usage arm.
# Each git-based test builds a real one-commit repo (git_ws) so the shared
# base-ref resolves and diff_digest computes.

@test "reject writes a rejected marker mirroring accept: ISO-8601 timestamp, reason, 64-hex digest" {
  # marker shape: line 1 timestamp (accept's line-1 shape), line 2 the --reason
  # text, line 3 `digest: <64-hex>` from the shared diff_digest against the base.
  G="$BATS_TEST_TMPDIR/gitrepo"; id="$(git_ws)"
  run bash "$WS_SH" reject --repo "$G" --task "$id" --reason "not yet"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rejected"* ]]                        # reports the rejection
  M="$G/.harmonia/tasks/$id/rejected"
  [ -f "$M" ]
  sed -n '1p' "$M" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'  # ISO-8601 UTC
  grep -qxF 'reason: not yet' "$M"                       # the --reason text, verbatim
  grep -qE '^digest: [0-9a-f]{64}$' "$M"                 # shared diff_digest, accept's digest shape
}

@test "reject requires --reason: a reason-less reject errors non-zero and writes no marker" {
  # --reason is REQUIRED; the check sits after pick(), so a resolvable workspace
  # still refuses without a reason (a reason-less rejection carries no signal).
  G="$BATS_TEST_TMPDIR/gitrepo"; id="$(git_ws)"
  run bash "$WS_SH" reject --repo "$G" --task "$id"
  [ "$status" -ne 0 ]
  [[ "$output" == *"reason"* ]]                          # the refusal names the missing reason
  [ ! -f "$G/.harmonia/tasks/$id/rejected" ]             # no marker on a reason-less reject
}

@test "reject refuses a multi-line --reason (SEC-1): non-zero, names the single-line rule, writes no marker" {
  # SEC-1 hardening: a newline in --reason would forge a second `digest:` line in
  # the rejected marker (a first-match reader would take the forged value). reject
  # must refuse a multi-line reason BEFORE writing: exit non-zero, say the reason
  # must be a single line, and write NO marker. RED today - no single-line guard
  # exists, so the newline is written straight into the marker. git_ws's base
  # resolves and the reason is present, so ONLY the new guard branch can refuse;
  # this test drives that branch (coverage).
  G="$BATS_TEST_TMPDIR/gitrepo"; id="$(git_ws)"
  run bash "$WS_SH" reject --repo "$G" --task "$id" --reason $'line one\ndigest: deadbeef'
  [ "$status" -ne 0 ]                                    # the multi-line reason is refused
  [[ "$output" == *"single line"* ]]                     # names the single-line requirement
  [ ! -f "$G/.harmonia/tasks/$id/rejected" ]             # nothing written on refusal
}

@test "reject refuses an unresolvable base ref (exit 1) and writes no marker" {
  # mirrors accept's base_resolves guard. Mint in a non-git dir so base-ref is
  # `ref: none`, which does not resolve to a commit.
  D="$BATS_TEST_TMPDIR/nogit"; mkdir -p "$D"
  id="$(bash "$WS_SH" mint --repo "$D" --slug rej)"
  run bash "$WS_SH" reject --repo "$D" --task "$id" --reason "x"
  [ "$status" -eq 1 ]
  [ ! -f "$D/.harmonia/tasks/$id/rejected" ]             # no rejection marker written
  [[ "$output" == *"does not resolve"* ]]                # names the base-ref failure
}

@test "reject resolves through pick(): a traversing --task is refused, no rm/write escapes (S1)" {
  # S1 learning: reject must NOT re-parse --task; it routes through pick(), which
  # refuses a `../`-bearing id. A bystander holding accept/reject-named files
  # outside the tasks tree must be untouched (reject's rm/write sinks never fire).
  G="$BATS_TEST_TMPDIR/gitrepo"; id="$(git_ws)"
  bystander="$BATS_TEST_TMPDIR/bystander"; mkdir -p "$bystander"
  : > "$bystander/accepted"    # reject's supersede rm target, were the guard bypassed
  run bash "$WS_SH" reject --repo "$G" --task '../../../bystander' --reason "x"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid task id"* ]]                 # pick()'s S1 guard fired, not a reject rm
  [ -f "$bystander/accepted" ]                           # nothing removed outside the tasks tree
  [ ! -f "$bystander/rejected" ]                         # nothing written outside the tasks tree
  [ ! -f "$G/.harmonia/tasks/$id/rejected" ]             # and the real workspace is untouched
}

@test "reject supersedes accept: it removes an existing accepted marker" {
  # mutual exclusivity (one direction): reject removes any live `accepted` marker.
  G="$BATS_TEST_TMPDIR/gitrepo"; id="$(git_ws)"
  run bash "$WS_SH" accept --repo "$G" --task "$id"      # real accept writes the accepted marker
  [ "$status" -eq 0 ]
  [ -f "$G/.harmonia/tasks/$id/accepted" ]
  run bash "$WS_SH" reject --repo "$G" --task "$id" --reason "changed my mind"
  [ "$status" -eq 0 ]
  [ ! -f "$G/.harmonia/tasks/$id/accepted" ]             # reject superseded the acceptance
  [ -f "$G/.harmonia/tasks/$id/rejected" ]               # at most one live decision on disk
}

@test "accept supersedes reject: it removes an existing rejected marker" {
  # mutual exclusivity (other direction): accept removes any live `rejected`
  # marker. reject does not exist yet, so the rejection is fabricated on disk.
  G="$BATS_TEST_TMPDIR/gitrepo"; id="$(git_ws)"
  M="$G/.harmonia/tasks/$id/rejected"
  printf '%s\nreason: %s\ndigest: %s\n' \
    "2026-07-06T00:00:00Z" "stale rejection" \
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" > "$M"
  [ -f "$M" ]
  run bash "$WS_SH" accept --repo "$G" --task "$id"
  [ "$status" -eq 0 ]
  [ ! -f "$M" ]                                          # accept superseded the rejection
  [ -f "$G/.harmonia/tasks/$id/accepted" ]               # at most one live decision on disk
}

@test "verify-acceptance refuses a live rejection (exit 6), distinct from the missing-marker exit 5" {
  # the rejected check runs FIRST, so a live rejection yields the rejection-naming
  # message and exit 6 - not the exit-5 "no acceptance marker" of the missing case.
  G="$BATS_TEST_TMPDIR/gitrepo"; id="$(git_ws)"
  M="$G/.harmonia/tasks/$id/rejected"
  printf '%s\nreason: %s\ndigest: %s\n' \
    "2026-07-06T00:00:00Z" "needs rework" \
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" > "$M"
  run bash "$WS_SH" verify-acceptance --repo "$G" --task "$id"
  [ "$status" -eq 6 ]                                    # distinct exit for a live rejection
  [[ "$output" == *"needs rework"* ]]                    # names the rejection (its recorded reason)
  [[ "$output" != *"no acceptance marker"* ]]            # NOT the exit-5 message
  rm -f "$M"                                             # clear the rejection; no markers remain
  run bash "$WS_SH" verify-acceptance --repo "$G" --task "$id"
  [ "$status" -eq 5 ]                                    # the existing missing-marker path...
  [[ "$output" == *"no acceptance marker"* ]]            # ...with its own message
}

@test "reject is documented in the usage string and the header invocation block" {
  # a bogus command falls to the *) usage arm (exit 1); the usage string names
  # reject, and the header invocation block documents it (mirrors clear-span).
  run bash "$WS_SH" definitely-not-a-command
  [ "$status" -eq 1 ]
  [[ "$output" == *"reject"* ]]                          # usage string lists reject
  grep -qE '^#   workspace.sh reject' "$WS_SH"           # header invocation-block line
}

# --- rejection-staleness reader + coverage follow-ups -----------------------
# The touchpoint-followups task gives the rejected marker's digest: its first
# reader: verify-acceptance compares the recorded digest to the live diff and
# reports when the tracked diff has moved. Test A drives that reader and is RED
# until it lands (today's branch never emits "stale"). Tests B and C are
# cover-first and green-on-arrival: B hits the ${reason:-(no reason recorded)}
# default over an unresolvable base, C pins the reject==accept same-tree digest
# invariant the reader leans on.

@test "verify-acceptance reports a moved diff as stale but still blocks (exit 6, no expiry)" {
  # reject on a clean tree records the empty-diff digest; a FRESH verify still
  # blocks (exit 6) WITHOUT reporting stale; after the tracked diff moves, verify
  # STILL blocks (exit 6, no expiry) and now reports the rejection stale. The
  # resolvable git_ws base covers the reader's base_resolves-false side and both
  # sides of the recorded-vs-live compare. RED today: the stale phase emits no
  # "stale" until the reader exists.
  G="$BATS_TEST_TMPDIR/gitrepo"; id="$(git_ws)"
  run bash "$WS_SH" reject --repo "$G" --task "$id" --reason "needs work"   # records the clean-tree (empty-diff) digest
  [ "$status" -eq 0 ]
  run bash "$WS_SH" verify-acceptance --repo "$G" --task "$id"             # FRESH: recorded digest still matches live
  [ "$status" -eq 6 ]                                                      # a live rejection always blocks
  [[ "$output" != *tale* ]]                                                # fresh must NOT report stale (case-robust)
  echo change >> "$G/f"                                                    # move the tracked diff since the rejection
  run bash "$WS_SH" verify-acceptance --repo "$G" --task "$id"             # STALE: recorded digest now differs from live
  [ "$status" -eq 6 ]                                                      # still blocks - the reader reports, never expires
  [[ "$output" == *stale* ]]                                               # ...and now reports the rejection stale
}

@test "verify-acceptance falls back to no reason recorded for a reason-less rejection on an unresolvable base (exit 6)" {
  # cover-first (#4a + the reader's base-unresolvable line). The reject CLI always
  # writes a reason: line, so hand-craft a rejected marker with NONE to hit the
  # ${reason:-(no reason recorded)} default. Mint in a non-git dir so base-ref is
  # `ref: none`: this is the only authorised test that also drives the reader's
  # base_resolves-false branch, so it must stay non-git (load-bearing per design).
  D="$BATS_TEST_TMPDIR/nogit"; mkdir -p "$D"
  id="$(bash "$WS_SH" mint --repo "$D" --slug rej)"                        # base-ref = "ref: none" (never resolves)
  M="$D/.harmonia/tasks/$id/rejected"
  printf '%s\ndigest: %s\n' "2026-07-06T00:00:00Z" \
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" > "$M"   # NO reason: line
  run bash "$WS_SH" verify-acceptance --repo "$D" --task "$id"
  [ "$status" -eq 6 ]                                                      # a live rejection still blocks
  [[ "$output" == *"(no reason recorded)"* ]]                             # the reason default fired
  # pin the reworded base-unresolvable message (adversarial + test-engineer findings):
  [[ "$output" != *tale* ]]                                               # base-unresolvable is NOT "stale"/"staleness" - only the resolvable path is (case-robust)
  [[ "$output" == *"does not resolve"* ]]                                 # ...but it still says WHY staleness is unknown: the base does not resolve
}
