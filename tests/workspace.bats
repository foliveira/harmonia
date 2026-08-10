#!/usr/bin/env bats
# Behavioral tests for `workspace.sh clear-span` (F3/item A). Unlike
# lifecycle-runner.bats (which greps runner prose), these run the REAL
# bin/workspace.sh against a scratch workspace under $BATS_TEST_TMPDIR and
# assert what it removes, preserves, and reports - the six-file list and
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

# fabricate a workspace: 6 span out-artifacts + every survivor the scope lists.
# `violations` joins the span set once lifecycle.yaml declares it an implement
# out-artifact: review FAILS on the record's presence (skills/review/SKILL.md),
# so a stale one from a prior run would fail the next run for something that
# did not happen. It has no extension, matching the file workspace.sh writes.
seed_ws() {
  local id="$1" d="$R/.harmonia/tasks/$1"
  mkdir -p "$d/receipts"
  for f in design.md boundary.md diff-summary.md verdict.md gate-report.md violations \
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
  for f in design.md boundary.md diff-summary.md verdict.md gate-report.md violations \
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

@test "clear-span removes the six span out-artifacts and preserves everything else" {
  # criterion 1: removes design.md/boundary.md/diff-summary.md/verdict.md/
  # gate-report.md/violations; preserves scope.md/ideas.md/accepted/done/minted/
  # base-ref and the whole receipts/ dir; reports what it cleared. --task addresses
  # the seeded (done-marked) workspace, which pick reaches by id regardless of done.
  seed_ws 2026-07-05-demo
  run bash "$WS_SH" clear-span --repo "$R" --task 2026-07-05-demo
  [ "$status" -eq 0 ]
  d="$R/.harmonia/tasks/2026-07-05-demo"
  for f in design.md boundary.md diff-summary.md verdict.md gate-report.md violations; do [ ! -f "$d/$f" ]; done
  for f in scope.md ideas.md accepted done minted base-ref; do [ -f "$d/$f" ]; done
  [ -f "$d/receipts/check-criteria.json" ]     # receipts/ untouched
  [[ "$output" == *"design.md"* ]]             # reports what it cleared
  [[ "$output" == *"violations"* ]]            # ...including the newest member, so it cannot be deleted silently
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
  # single-incomplete branch must resolve it, clear the six, and keep scope.md.
  # seed_incomplete omits the done marker so incomplete() actually reaches it.
  seed_incomplete 2026-07-05-live
  run bash "$WS_SH" clear-span --repo "$R"
  [ "$status" -eq 0 ]
  d="$R/.harmonia/tasks/2026-07-05-live"
  for f in design.md boundary.md diff-summary.md verdict.md gate-report.md violations; do [ ! -f "$d/$f" ]; done
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

@test "reject and accept record the same digest for the same tree" {
  # cover-first (#4b): reject's digest: must equal accept's digest: for one
  # working tree - the invariant the staleness reader leans on. Capture reject's
  # digest BEFORE accept supersedes (removes) the rejected marker. Modify a
  # TRACKED file so the shared diff_digest is content-bearing, not the empty-diff
  # constant (diff_digest excludes untracked files).
  G="$BATS_TEST_TMPDIR/gitrepo"; id="$(git_ws)"
  echo change >> "$G/f"                                                    # tracked change; git diff HEAD sees it
  run bash "$WS_SH" reject --repo "$G" --task "$id" --reason "x"
  [ "$status" -eq 0 ]
  rej="$(sed -n 's/^digest: //p' "$G/.harmonia/tasks/$id/rejected" | head -1)"
  run bash "$WS_SH" accept --repo "$G" --task "$id"                       # supersedes reject, writes the accepted marker
  [ "$status" -eq 0 ]
  acc="$(sed -n 's/^digest: //p' "$G/.harmonia/tasks/$id/accepted" | head -1)"
  [ "$rej" = "$acc" ]                                                      # same tree -> same shared diff_digest
  [ -n "$rej" ]                                                           # and it is a real (non-empty) digest
}

# --- verify-test-hashes: empty vs. non-empty manifest -----------------------
# record-test-hashes writes an EMPTY test-hashes manifest when its test glob
# matches nothing (a task that touches no tests). GNU `sha256sum -c` treats an
# empty checksum file as an error ("no properly formatted checksum lines found",
# exit 1), so verify-test-hashes used to record a bogus KTD12 violation on such
# a task. The empty manifest must be a vacuous pass; the non-empty path (an
# edited recorded test still fails) must be untouched. Both drive the real
# subcommands against a git_ws repo. A sibling non-empty regression also lives
# in skills.bats ("moved test hashes fail verification"); the pair here pins the
# empty/non-empty contract at the fix site.

@test "verify-test-hashes vacuously passes an empty manifest with no violation (no test files recorded)" {
  # a task whose test glob matches nothing: record writes a 0-byte manifest and
  # verify must exit 0 without recording a violation. RED before the `! -s`
  # guard, where sha256sum -c's empty-file error drove the else branch to exit 1.
  G="$BATS_TEST_TMPDIR/gitrepo"; id="$(git_ws)"     # one-commit repo, no test files
  run bash "$WS_SH" record-test-hashes --repo "$G" --task "$id"
  [ "$status" -eq 0 ]
  manifest="$G/.harmonia/tasks/$id/test-hashes"
  [ -f "$manifest" ] && [ ! -s "$manifest" ]        # precondition: an empty (0-byte) manifest, as record writes here
  run bash "$WS_SH" verify-test-hashes --repo "$G" --task "$id"
  [ "$status" -eq 0 ]                               # vacuous pass, not the empty-file error
  [[ "$output" == *"no test files recorded"* ]]     # took the new empty-manifest branch, not a violation
  [ ! -f "$G/.harmonia/tasks/$id/violations" ]      # no bogus KTD12 violation recorded
}

@test "verify-test-hashes still fails a modified recorded test and records the violation (non-empty manifest untouched)" {
  # the non-empty path is unchanged: a recorded test file that is later edited
  # must fail verification (exit 1) and append the test-immutability VIOLATION.
  G="$BATS_TEST_TMPDIR/gitrepo"; id="$(git_ws)"
  echo 'assert true' > "$G/thing.bats"              # a test file matching record's glob (untracked, as a fresh test is)
  run bash "$WS_SH" record-test-hashes --repo "$G" --task "$id"
  [ "$status" -eq 0 ]
  manifest="$G/.harmonia/tasks/$id/test-hashes"
  [ -s "$manifest" ]                                # precondition: a NON-empty manifest (the test file was recorded)
  echo 'assert weakened' > "$G/thing.bats"          # the recorded test is edited (KTD12)
  run bash "$WS_SH" verify-test-hashes --repo "$G" --task "$id"
  [ "$status" -eq 1 ]                               # the violation path still bites
  V="$G/.harmonia/tasks/$id/violations"
  [ -f "$V" ]
  grep -q 'test-immutability VIOLATION' "$V"        # the recorded violation line
}

# --- FU-16 in workspace.sh: every command that mutates a workspace ------------
# The list below is the case block of bin/workspace.sh filtered to the branches
# that write or remove a file under $TASKS/$ID - resolve and verify-acceptance
# are absent because they mutate nothing, and mint has its own test because it
# CREATES the tree it would have to resolve. It is enumerated from the script
# rather than copied from a boundary list on purpose: the two sites this repo
# discovered late were both deletions (accept removes `rejected`, reject removes
# `accepted`) and clear-span, which writes nothing at all and removes six named
# files on /harmonia:flow's own entry path.
#
# Two redirect forms, because they fail differently. `tasks-tree` puts a symlink
# above the task directory, which a guard that resolves the workspace catches;
# `artifact-file` symlinks the ONE name each command writes through, which only a
# guard that also resolves that name catches - a build that resolves the
# directory and hands the wrong artifact name to its guard passes the first and
# clobbers a user's file on the second. clear-span is deliberately absent from
# the second form: it only rm -f's, and rm -f on a symlink unlinks the link
# rather than the target, so there is no escape there to assert.
#
# The detector is a before/after snapshot of the whole outside tree - every path
# plus every file's sha256 - because these commands DELETE as well as write, and
# a name-matched detector cannot see a victim that is gone. Every artifact is
# planted with content, so the clean cells cannot pass on mere existence: the
# command must really have rewritten what it claims to own.

WS_MUTATORS="clear-span accept reject complete abandon record-test-hashes verify-test-hashes"

mutator_artifact() {   # <cmd> -> the single name it writes THROUGH ('' where a symlink cannot be followed into)
  case "$1" in
    accept)             echo accepted ;;
    reject)             echo rejected ;;
    complete)           echo done ;;
    abandon)            echo abandoned ;;
    record-test-hashes) echo test-hashes ;;
    verify-test-hashes) echo violations ;;
    clear-span)         echo "" ;;
  esac
}

wsnap_tree() {   # <dir> -> a listing that moves if anything under it is added, removed or edited
  { find "$1" | sort; find "$1" -type f -exec sha256sum {} + 2>/dev/null | sort; }
}

wassert_outside_unchanged() {   # <dir> <snapshot-taken-before>
  local after; after="$(wsnap_tree "$1")"
  if [ "$after" != "$2" ]; then
    echo "ESCAPED - the tree outside the workspace changed:"
    diff <(printf '%s\n' "$2") <(printf '%s\n' "$after") || true
  fi
  [ "$after" = "$2" ]
}

stage_wsmut() {   # <form>: one repo per form, one task directory per command; sets CELL, MR
  local form="$1" real d art
  CELL="$BATS_TEST_TMPDIR/wm-$form"
  mkdir -p "$CELL/out" "$CELL/real"
  real="$CELL/real/r"; mkdir -p "$real"
  git -C "$real" init -q
  printf 'a\n' > "$real/f.sh"
  printf 'x\n' > "$real/thing.bats"        # a test file, so record-test-hashes has something to record
  git -C "$real" add -A
  git -C "$real" -c user.email=t@t -c user.name=t commit -qm b
  MR="$real"
  local ref; ref="$(git -C "$real" rev-parse HEAD)"
  for cmd in $WS_MUTATORS; do
    d="$real/.harmonia/tasks/2026-01-01-$cmd"
    mkdir -p "$d/receipts"
    for f in design.md boundary.md diff-summary.md verdict.md gate-report.md violations \
             accepted rejected done abandoned test-hashes scope.md; do printf 'PLANTED\n' > "$d/$f"; done
    printf 'ref: %s\n' "$ref" > "$d/base-ref"   # resolvable, so accept and reject reach their write instead of refusing for another reason
  done
  case "$form" in
    clean) ;;
    tasks-tree)
      mv "$real/.harmonia/tasks" "$CELL/out/tasks"
      ln -s "$CELL/out/tasks" "$real/.harmonia/tasks" ;;
    artifact-file)
      for cmd in $WS_MUTATORS; do
        art="$(mutator_artifact "$cmd")"
        [ -n "$art" ] || continue
        printf 'VICTIM\n' > "$CELL/out/$cmd-$art"
        rm -f "$real/.harmonia/tasks/2026-01-01-$cmd/$art"
        ln -s "$CELL/out/$cmd-$art" "$real/.harmonia/tasks/2026-01-01-$cmd/$art"
      done ;;
  esac
}

@test "every workspace.sh command that mutates a workspace refuses a redirected one" {
  for form in clean tasks-tree artifact-file; do
    stage_wsmut "$form"
    for cmd in $WS_MUTATORS; do
      if [ "$form" = artifact-file ] && [ -z "$(mutator_artifact "$cmd")" ]; then continue; fi
      id="2026-01-01-$cmd"; d="$MR/.harmonia/tasks/$id"
      before="$(wsnap_tree "$CELL/out")"
      echo "--- $cmd, redirect form: $form"
      case "$cmd" in
        reject) run bash "$WS_SH" reject --repo "$MR" --task "$id" --reason "x" ;;
        *)      run bash "$WS_SH" "$cmd" --repo "$MR" --task "$id" ;;
      esac
      echo "status=$status"
      echo "$output"
      if [ "$form" = clean ]; then
        # The accept side, one assertion per command: the artifact it owns is
        # really rewritten (not merely present - every one was planted), and the
        # ones it supersedes are really gone.
        case "$cmd" in
          clear-span)
            [ "$status" -eq 0 ]
            for f in design.md boundary.md diff-summary.md verdict.md gate-report.md violations; do [ ! -e "$d/$f" ]; done ;;
          accept)
            [ "$status" -eq 0 ]; [ "$(head -1 "$d/accepted")" != "PLANTED" ]; [ ! -e "$d/rejected" ] ;;
          reject)
            [ "$status" -eq 0 ]; grep -q '^reason: x' "$d/rejected"; [ ! -e "$d/accepted" ] ;;
          complete)
            [ "$status" -eq 0 ]; [ "$(cat "$d/done")" != "PLANTED" ] ;;
          abandon)
            [ "$status" -eq 0 ]; [ "$(cat "$d/abandoned")" != "PLANTED" ] ;;
          record-test-hashes)
            [ "$status" -eq 0 ]; grep -q 'thing.bats' "$d/test-hashes" ;;
          verify-test-hashes)
            # a planted junk manifest IS a violation; what this pins is that the
            # record of it lands inside the workspace and the command says so.
            [ "$status" -ne 0 ]; grep -q 'VIOLATION' "$d/violations" ;;
        esac
      else
        [ "$status" -ne 0 ]
      fi
      wassert_outside_unchanged "$CELL/out" "$before"
    done
  done
}

# --- mint: the write that decides where every later stage writes --------------
# mint is the exception to resolve-then-work, because it CREATES the workspace:
# there is nothing to resolve when the check has to run. It writes four things -
# the task directory with receipts/, $TASKS/.gitignore one level ABOVE it,
# `minted` and `base-ref` - and it re-uses an existing directory when the date
# and slug repeat, so a symlink planted at any of those names survives to be
# followed. The cells below are those four writes plus the two tree positions
# above them; the three artifact cells are the ones a post-check that names only
# receipts/ walks straight past, with two user files overwritten at exit 0.
#
# Each cell begins with a real mint, so the accept side is asserted seven times:
# mint still mints, and the id it prints is what the cell plants under.

@test "mint refuses to create or extend a task tree that leaves the repository" {
  for cell in harmonia-link tasks-link gitignore-link id-link minted-link base-ref-link receipts-link; do
    C="$BATS_TEST_TMPDIR/mint-$cell"
    mkdir -p "$C/out" "$C/r"
    T="$C/r/.harmonia/tasks"

    echo "--- mint cell: $cell"
    run bash "$WS_SH" mint --repo "$C/r" --slug probe
    echo "first mint status=$status"
    echo "$output"
    [ "$status" -eq 0 ]
    id="$output"
    [ -s "$T/$id/minted" ]
    [ -s "$T/$id/base-ref" ]
    [ -d "$T/$id/receipts" ]
    [ "$(cat "$T/.gitignore")" = "*" ]
    [ "$id" = "$(date +%Y-%m-%d)-probe" ]   # precondition: the re-mint below lands on this same directory

    case "$cell" in
      harmonia-link)
        rm -rf "$C/r/.harmonia"; mkdir -p "$C/out/harmonia"
        ln -s "$C/out/harmonia" "$C/r/.harmonia" ;;
      tasks-link)
        rm -rf "$T"; mkdir -p "$C/out/tasks"
        ln -s "$C/out/tasks" "$T" ;;
      gitignore-link)
        printf 'VICTIM\n' > "$C/out/victim-gitignore"
        rm -f "$T/.gitignore"; ln -s "$C/out/victim-gitignore" "$T/.gitignore" ;;
      id-link)
        rm -rf "$T/$id"; mkdir -p "$C/out/id-target"
        ln -s "$C/out/id-target" "$T/$id" ;;
      minted-link)
        printf 'VICTIM\n' > "$C/out/victim-minted"
        rm -f "$T/$id/minted"; ln -s "$C/out/victim-minted" "$T/$id/minted" ;;
      base-ref-link)
        printf 'VICTIM\n' > "$C/out/victim-base-ref"
        rm -f "$T/$id/base-ref"; ln -s "$C/out/victim-base-ref" "$T/$id/base-ref" ;;
      receipts-link)
        # the target deliberately does NOT exist: mkdir -p through a dangling
        # symlink is what creates a directory outside the repository.
        rm -rf "$T/$id/receipts"; ln -s "$C/out/receipts-target" "$T/$id/receipts" ;;
    esac

    before="$(wsnap_tree "$C/out")"
    run bash "$WS_SH" mint --repo "$C/r" --slug probe --new
    echo "re-mint status=$status"
    echo "$output"
    [ "$status" -ne 0 ]
    wassert_outside_unchanged "$C/out" "$before"
  done
}

# --- the READ side: verify-acceptance and verify-test-hashes ----------------
# Both commands write nothing, so no escape detector can see them getting the
# wrong bytes - what is wrong is the VERDICT each one prints, and both verdicts
# are gates: skills/capture/SKILL.md:11 gates on acceptance, and the review lead
# treats the manifest check as a mandatory audit input. Two ways to be handed the
# wrong file: it is redirected (containment), or it shipped with the repository
# (provenance). Neither is reachable from the write-side guards.

stage_read() {   # <form>: sets RR (repo) and RW (workspace), with a genuinely edited recorded test
  local form="$1" real
  RCELL="$BATS_TEST_TMPDIR/rd-$form"
  mkdir -p "$RCELL/out"
  real="$RCELL/r"; mkdir -p "$real"
  git -C "$real" init -q
  printf 'a\n' > "$real/f.sh"
  printf 'x\n' > "$real/t.bats"
  git -C "$real" add -A
  git -C "$real" -c user.email=t@t -c user.name=t commit -qm b
  RR="$real"
  RW="$real/.harmonia/tasks/T"
  mkdir -p "$RW/receipts"
  printf 'ref: %s\n' "$(git -C "$real" rev-parse HEAD)" > "$RW/base-ref"
  ( cd "$real" && sha256sum t.bats ) > "$RW/test-hashes"
  printf 'x\n# edited\n' > "$real/t.bats"    # a REAL violation, so the honest verdict is known
  printf 'ts\ndigest: %s\n' \
    "$(git -C "$real" diff "$(git -C "$real" rev-parse HEAD)" | sha256sum | awk '{print $1}')" \
    > "$RW/accepted"
  case "$form" in
    clean) ;;
    manifest)
        # recomputed at the redirect target, so it MATCHES the edit: unguarded,
        # the KTD12 violation simply disappears.
        ( cd "$real" && sha256sum t.bats ) > "$RCELL/out/forged-hashes"
        rm -f "$RW/test-hashes"; ln -s "$RCELL/out/forged-hashes" "$RW/test-hashes" ;;
    marker)
        cp "$RW/accepted" "$RCELL/out/forged-accepted"
        rm -f "$RW/accepted"; ln -s "$RCELL/out/forged-accepted" "$RW/accepted" ;;
  esac
}

@test "verify-test-hashes and verify-acceptance refuse a manifest or marker redirected outside the workspace" {
  for form in clean manifest marker; do
    stage_read "$form"
    echo "--- redirect form: $form"
    # The recorded test file really is edited in every cell, so the honest
    # verdict is a violation in all three: clean and marker report it because it
    # is true, and the manifest cell is the discriminator - redirected, the
    # forged manifest matches the edit and the violation simply disappears.
    run bash "$WS_SH" verify-test-hashes --repo "$RR" --task T
    echo "hashes: status=$status $output"
    [ "$status" -ne 0 ]
    [[ "$output" != *"test hashes verified"* ]]

    # Each guard must be narrow as well as present: only the marker cell may
    # change what verify-acceptance answers. A build that refuses a whole
    # command because some other file in the workspace is redirected is red on
    # the manifest cell, and one that refuses everything is red on clean too.
    run bash "$WS_SH" verify-acceptance --repo "$RR" --task T
    echo "acceptance: status=$status $output"
    if [ "$form" = marker ]; then
      [ "$status" -ne 0 ]
      [[ "$output" != *"acceptance verified"* ]]
    else
      [ "$status" -eq 0 ]
      [[ "$output" == *"acceptance verified"* ]]
    fi
  done
}

@test "verify-acceptance and verify-test-hashes refuse a marker or manifest that arrived with the repository" {
  # Nothing is redirected here: the hostile repository TRACKS its own acceptance
  # marker carrying the empty-diff constant, which is what the digest of a fresh
  # clone's untouched tree really is. Containment cannot see this - every path
  # resolves exactly where it should.
  local h="$BATS_TEST_TMPDIR/prov-host" c="$BATS_TEST_TMPDIR/prov-clone"
  local w="$h/.harmonia/tasks/T"
  mkdir -p "$w/receipts"
  printf 'x\n' > "$h/README.md"
  printf 'ref: HEAD\n' > "$w/base-ref"
  printf 'ts\ndigest: %s\n' "$(printf '' | sha256sum | awk '{print $1}')" > "$w/accepted"
  : > "$w/test-hashes"                       # an empty manifest passes vacuously by design
  git -C "$h" init -q
  git -C "$h" add -A -f
  git -C "$h" -c user.email=t@t -c user.name=t commit -qm x
  git clone -q "$h" "$c"
  git -C "$c" ls-files --error-unmatch -- ".harmonia/tasks/T/accepted" >/dev/null
  [ "$(bash "$WS_SH" resolve --repo "$c")" = T ]    # the hostile workspace is the one that resolves

  run bash "$WS_SH" verify-acceptance --repo "$c" --task T
  echo "clone acceptance: status=$status $output"
  [ "$status" -ne 0 ]
  [[ "$output" != *"acceptance verified"* ]]

  run bash "$WS_SH" verify-test-hashes --repo "$c" --task T
  echo "clone hashes: status=$status $output"
  [ "$status" -ne 0 ]
  [[ "$output" != *"test hashes verified"* ]]

  # The accept side, through the real writers: a minted workspace put through
  # the real accept and record-test-hashes must still verify, or the guard has
  # simply broken the acceptance gate for everyone.
  local L="$BATS_TEST_TMPDIR/prov-ok"
  mkdir -p "$L"
  git -C "$L" init -q
  printf 'a\n' > "$L/f.sh"
  git -C "$L" add -A
  git -C "$L" -c user.email=t@t -c user.name=t commit -qm b
  local id; id="$(bash "$WS_SH" mint --repo "$L" --slug mine)"
  bash "$WS_SH" accept --repo "$L" --task "$id"
  run bash "$WS_SH" verify-acceptance --repo "$L" --task "$id"
  echo "honest acceptance: status=$status $output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"acceptance verified"* ]]
  bash "$WS_SH" record-test-hashes --repo "$L" --task "$id"
  run bash "$WS_SH" verify-test-hashes --repo "$L" --task "$id"
  echo "honest hashes: status=$status $output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"test hashes verified"* ]]
}

@test "accept and reject refuse a base-ref that resolves outside the workspace" {
  # M1. base-ref decides the digest these two commands WRITE into a marker, so a
  # redirect makes the developer's own consent record attest to a base they never
  # chose. Two commits, so no-difference cannot read as a pass: the honest base
  # names the FIRST commit and digests a real change, the redirected one names
  # HEAD and digests to the empty-diff constant.
  local cell="$BATS_TEST_TMPDIR/m1" real
  mkdir -p "$cell/out"; real="$cell/r"; mkdir -p "$real"
  git -C "$real" init -q
  printf 'a\n' > "$real/f.sh"
  git -C "$real" add -A
  git -C "$real" -c user.email=t@t -c user.name=t commit -qm b
  local first; first="$(git -C "$real" rev-parse HEAD)"
  printf 'a\nb\n' > "$real/f.sh"
  git -C "$real" add -A
  git -C "$real" -c user.email=t@t -c user.name=t commit -qm c
  local head; head="$(git -C "$real" rev-parse HEAD)"
  local ws="$real/.harmonia/tasks/T"; mkdir -p "$ws/receipts"
  local empty; empty="$(printf '' | sha256sum | awk '{print $1}')"

  # Honest control: the real base digests a real change, not the empty constant.
  printf 'ref: %s\n' "$first" > "$ws/base-ref"
  run bash "$WS_SH" accept --repo "$real" --task T
  [ "$status" -eq 0 ]
  local honest; honest="$(sed -n 's/^digest: //p' "$ws/accepted")"
  [ "$honest" != "$empty" ]
  rm -f "$ws/accepted"

  printf 'ref: %s\n' "$head" > "$cell/out/base-ref"
  rm -f "$ws/base-ref"; ln -s "$cell/out/base-ref" "$ws/base-ref"
  run bash "$WS_SH" accept --repo "$real" --task T
  echo "accept: status=$status $output"
  [ "$status" -ne 0 ]
  [ ! -f "$ws/accepted" ]                 # and no marker was written at all
  run bash "$WS_SH" reject --repo "$real" --task T --reason nope
  echo "reject: status=$status $output"
  [ "$status" -ne 0 ]
  [ ! -f "$ws/rejected" ]
}

@test "verify-acceptance guards every file it reads, not only the marker" {
  # M6. The shipped loop guards rejected, accepted and base-ref; narrowing it to
  # `accepted` alone reds no test and greens every criterion, while forging
  # `acceptance verified` over a genuinely stale marker through a base the caller
  # never chose. This is the cell that pins the other two names.
  local cell="$BATS_TEST_TMPDIR/m6" real
  mkdir -p "$cell/out"; real="$cell/r"; mkdir -p "$real"
  git -C "$real" init -q
  printf 'a\n' > "$real/f.sh"
  git -C "$real" add -A
  git -C "$real" -c user.email=t@t -c user.name=t commit -qm b
  local ws; ws="$(bash "$WS_SH" mint --repo "$real" --slug t)"
  local wsd="$real/.harmonia/tasks/$ws"
  bash "$WS_SH" accept --repo "$real" --task "$ws"

  # Move the tree on: the recorded digest is now genuinely stale.
  printf 'a\nb\n' > "$real/f.sh"
  run bash "$WS_SH" verify-acceptance --repo "$real" --task "$ws"
  echo "stale: status=$status $output"
  [ "$status" -ne 0 ]
  [[ "$output" != *"acceptance verified"* ]]

  # A base-ref redirected at a file naming the CURRENT head makes the stale
  # marker look fresh. Guarded, this refuses; unguarded it certifies.
  printf 'ref: %s\n' "$(git -C "$real" rev-parse HEAD)" > "$cell/out/base-ref"
  rm -f "$wsd/base-ref"; ln -s "$cell/out/base-ref" "$wsd/base-ref"
  run bash "$WS_SH" verify-acceptance --repo "$real" --task "$ws"
  echo "redirected base-ref: status=$status $output"
  [ "$status" -ne 0 ]
  [[ "$output" != *"acceptance verified"* ]]

  # And the rejected name: a live rejection redirected outside must not be
  # readable past either. Restore an honest base first so this cell tests one
  # thing.
  rm -f "$wsd/base-ref"; printf 'ref: %s\n' "$(git -C "$real" rev-parse HEAD)" > "$wsd/base-ref"
  printf 'ts\nreason: planted\ndigest: x\n' > "$cell/out/rejected"
  ln -s "$cell/out/rejected" "$wsd/rejected"
  run bash "$WS_SH" verify-acceptance --repo "$real" --task "$ws"
  echo "redirected rejected: status=$status $output"
  [ "$status" -ne 0 ]
  [[ "$output" != *"acceptance verified"* ]]
  [[ "$output" == *"refusing"* ]]
}

@test "a provenance refusal names a remedy that actually clears it, for every consumer" {
  # The claim under audit is that all four consumers name a remedy that works.
  # It is pinned by FOLLOWING the remedy on all four, not by grepping any of them
  # for a phrase - the remedy has been wrong twice (`accept`, then
  # `git rm --cached`) and a wording assertion pins the wrong thing: it goes green
  # the moment someone deletes the sentence.
  local real="$BATS_TEST_TMPDIR/rem/r"
  mkdir -p "$real/.harmonia/tasks/T/receipts"
  printf 'x\n' > "$real/README.md"
  printf 'a\n' > "$real/f.sh"
  local empty; empty="$(printf '' | sha256sum | awk '{print $1}')"
  printf 'ts\ndigest: %s\n' "$empty" > "$real/.harmonia/tasks/T/accepted"
  : > "$real/.harmonia/tasks/T/test-hashes"
  printf 'ref: HEAD\n' > "$real/.harmonia/tasks/T/base-ref"
  printf '## Success Criteria\n- run: true\n' > "$real/.harmonia/tasks/T/scope.md"
  cat > "$real/.harmonia/tasks/T/receipts/coverage.json" <<JSON
{ "gate": "coverage", "task_id": "T", "timestamp": "2026-01-01T00:00:00Z", "diff_digest": "$empty", "status": "pass" }
JSON
  git -C "$real" init -q
  git -C "$real" add -A -f
  git -C "$real" -c user.email=t@t -c user.name=t commit -qm x

  # All four refuse to begin with.
  run bash "$WS_SH" verify-acceptance --repo "$real" --task T
  [ "$status" -ne 0 ]
  run bash "$WS_SH" verify-test-hashes --repo "$real" --task T
  [ "$status" -ne 0 ]
  run bash "$REPO_ROOT/bin/check-criteria.sh" --run --workspace "$real/.harmonia/tasks/T" --repo "$real" </dev/null
  [ "$status" -ne 0 ]
  run bash "$REPO_ROOT/bin/coverage/gate.sh" --verify-receipts --repo "$real" --workspace "$real/.harmonia/tasks/T"
  [ "$status" -ne 0 ]

  # The remedy every one of them names: a freshly minted workspace.
  local id; id="$(bash "$WS_SH" mint --repo "$real" --slug fresh --new)"
  local w="$real/.harmonia/tasks/$id"
  printf '## Success Criteria\n- run: true\n' > "$w/scope.md"

  bash "$WS_SH" accept --repo "$real" --task "$id"
  run bash "$WS_SH" verify-acceptance --repo "$real" --task "$id"
  echo "acceptance: $status $output"
  [ "$status" -eq 0 ]
  bash "$WS_SH" record-test-hashes --repo "$real" --task "$id"
  run bash "$WS_SH" verify-test-hashes --repo "$real" --task "$id"
  echo "hashes: $status $output"
  [ "$status" -eq 0 ]
  run bash "$REPO_ROOT/bin/check-criteria.sh" --run --workspace "$w" --repo "$real" </dev/null
  echo "criteria: $status $output"
  [ "$status" -eq 0 ]
  bash "$REPO_ROOT/bin/coverage/gate.sh" --repo "$real" --workspace "$w" >/dev/null 2>&1
  run bash "$REPO_ROOT/bin/coverage/gate.sh" --verify-receipts --repo "$real" --workspace "$w"
  echo "receipts: $status $output"
  [ "$status" -eq 0 ]
}
