#!/usr/bin/env bats
# Behavioral tests for `workspace.sh clear-span` (F3/item A). Unlike
# lifecycle-runner.bats (which greps runner prose), these run the REAL
# bin/workspace.sh against a scratch workspace under $BATS_TEST_TMPDIR and
# assert what it removes, preserves, and reports - the five-file list and
# path-confinement now live in shell a test exercises, not runner prose.
# No git needed: clear-span and pick touch no git. Conventions follow
# coverage.bats (REPO_ROOT from $BATS_TEST_FILENAME, scratch under TMPDIR).

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
