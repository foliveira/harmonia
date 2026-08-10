#!/usr/bin/env bats
# U6 enforcement tests - session-start injection (tier A) and the criteria gate (tier B).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HARMONIA_HOME="$BATS_TEST_TMPDIR/home"
  export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"
  unset HARMONIA_DISABLE || true
  INJECT="$REPO_ROOT/bin/inject-context.sh"
  CHECK="$REPO_ROOT/bin/check-criteria.sh"

  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$PROJ"
  git -C "$PROJ" init -q
  echo 'package main' > "$PROJ/main.go"
  git -C "$PROJ" add -A && git -C "$PROJ" -c user.email=t@t -c user.name=t commit -qm x

  WS="$PROJ/.harmonia/tasks/2026-07-02-fixture"
  mkdir -p "$WS"
}

seed_learning() {
  echo "avoid global test state" | bash "$REPO_ROOT/bin/memory/capture.sh" \
    --title "Go pitfall fixture" --tier global --tags "go" --repo "$PROJ" >/dev/null
}

@test "injection carries all four rule names and a matching learning summary" {
  seed_learning
  run bash -c "cd '$PROJ' && bash '$INJECT'"
  [ "$status" -eq 0 ]
  for rule in "Think Before Coding" "Simplicity First" "Surgical Changes" "Goal-Driven Execution"; do
    [[ "$output" == *"$rule"* ]]
  done
  [[ "$output" == *"Go pitfall fixture"* ]]
}

@test "output respects the hard size cap even with an oversized store" {
  for i in $(seq 1 200); do
    echo x | bash "$REPO_ROOT/bin/memory/capture.sh" --title "Learning number $i with a fairly long descriptive title" \
      --tier global --tags go --repo "$PROJ" >/dev/null
  done
  run bash -c "cd '$PROJ' && bash '$INJECT'"
  [ "$status" -eq 0 ]
  [ "${#output}" -le 4096 ]
}

@test "the kill-switch yields empty output and exit zero" {
  seed_learning
  HARMONIA_DISABLE=1 run bash -c "cd '$PROJ' && HARMONIA_DISABLE=1 bash '$INJECT'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "empty or missing store injects rules only, exit zero" {
  run bash -c "cd '$PROJ' && bash '$INJECT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Simplicity First"* ]]
}

@test "an internal error empties stdout, warns on stderr, exits zero" {
  FAKEROOT="$BATS_TEST_TMPDIR/fakeroot"
  mkdir -p "$FAKEROOT/core" "$FAKEROOT/bin/memory"
  cp "$REPO_ROOT/bin/inject-context.sh" "$FAKEROOT/bin/"
  cp "$REPO_ROOT"/bin/memory/*.sh "$FAKEROOT/bin/memory/"
  # No RULES.md in the fake root -> the digest cannot be built.
  run bash -c "cd '$PROJ' && CLAUDE_PLUGIN_ROOT='$FAKEROOT' bash '$FAKEROOT/bin/inject-context.sh' 2>/dev/null"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run bash -c "cd '$PROJ' && CLAUDE_PLUGIN_ROOT='$FAKEROOT' bash '$FAKEROOT/bin/inject-context.sh' 2>&1 >/dev/null"
  [[ "$output" == *"warning"* ]]
}

@test "a directly-run recall yields the same summaries the injection emitted" {
  seed_learning
  inj="$(cd "$PROJ" && bash "$INJECT" | grep 'Go pitfall fixture')"
  dir="$(bash "$REPO_ROOT/bin/memory/recall.sh" --repo "$PROJ" | grep 'Go pitfall fixture')"
  [ -n "$dir" ]
  [ "$inj" = "$dir" ]
}

@test "check-criteria accepts runnable criteria and writes a digest-bearing receipt" {
  cat > "$WS/scope.md" <<'EOF'
---
title: fixture scope
---
## Success Criteria
- run: bats tests/
- run: bin/validate-core.sh
EOF
  echo "ref: $(git -C "$PROJ" rev-parse HEAD)" > "$WS/base-ref"
  run bash "$CHECK" --workspace "$WS" --repo "$PROJ"
  [ "$status" -eq 0 ]
  r="$WS/receipts/check-criteria.json"
  [ -f "$r" ]
  [ "$(jq -r .task_id "$r")" = "2026-07-02-fixture" ]
  [ -n "$(jq -r .timestamp "$r")" ]
  [ "$(jq -r .diff_digest "$r" | wc -c)" -gt 32 ]
}

@test "check-criteria rejects prose-only criteria, names the offender, still writes the receipt" {
  cat > "$WS/scope.md" <<'EOF'
## Success Criteria
- run: bats tests/
- make it nicer
EOF
  run bash "$CHECK" --workspace "$WS" --repo "$PROJ"
  [ "$status" -ne 0 ]
  [[ "$output" == *"make it nicer"* ]]
  [ -f "$WS/receipts/check-criteria.json" ]
  [ "$(jq -r .status "$WS/receipts/check-criteria.json")" = "fail" ]
}

@test "hooks.json parses, sets an explicit timeout, and points at an executable script" {
  H="$REPO_ROOT/hooks/hooks.json"
  jq -e . "$H" >/dev/null
  t="$(jq -r '.. | .timeout? // empty' "$H" | head -1)"
  [ -n "$t" ] && [ "$t" -le 60 ]
  cmd="$(jq -r '.. | .command? // empty' "$H" | head -1)"
  resolved="${cmd//\$\{CLAUDE_PLUGIN_ROOT\}/$REPO_ROOT}"
  script="$(echo "$resolved" | awk '{print $2}')"
  [ -x "$script" ]
}

@test "check-criteria parses the base-ref through the shared parser: bare and prefixed forms yield the same digest" {
  cat > "$WS/scope.md" <<'EOF'
## Success Criteria
- run: true
EOF
  base="$(git -C "$PROJ" rev-parse HEAD)"
  echo more >> "$PROJ/main.go"
  git -C "$PROJ" add -A && git -C "$PROJ" -c user.email=t@t -c user.name=t commit -qm drift
  expected="$(git -C "$PROJ" diff "$base" | sha256sum | awk '{print $1}')"

  printf '%s\n' "$base" > "$WS/base-ref"
  run bash "$CHECK" --workspace "$WS" --repo "$PROJ"
  [ "$status" -eq 0 ]
  [ "$(jq -r .diff_digest "$WS/receipts/check-criteria.json")" = "$expected" ]

  printf 'ref: %s\n' "$base" > "$WS/base-ref"
  run bash "$CHECK" --workspace "$WS" --repo "$PROJ"
  [ "$status" -eq 0 ]
  [ "$(jq -r .diff_digest "$WS/receipts/check-criteria.json")" = "$expected" ]
}

# --- the criteria gate's run mode (--run) ------------------------------------
# The three shape-mode tests above are the byte-identity guard on the
# implement-entry gate and are deliberately not edited here. Every test below
# points the run at the fixture repo ($PROJ, a throwaway git repo under
# BATS_TEST_TMPDIR), never at this repo, so no fixture criterion can modify a
# tracked file or leave an untracked file at this repo's root - the invariant the
# pinned coverage -> criteria-run -> verify-receipts order depends on. No fixture
# criterion runs `bats`: a nested run inherits BATS_*, and the criteria run
# itself executes under `bats tests/` at review. Each test names the wrong
# implementation it must reject.

@test "run mode executes every criterion and reports the whole set it ran" {
  # Rejects failure-only reporting (the PASSING criterion must be echoed too -
  # that is the adopted mitigation for a model-written criteria set reaching the
  # lead unseen), fail-open on a command that does not exist, and
  # stop-at-first-failure (a prefix of the set is not the set).
  cat > "$WS/scope.md" <<'EOF'
## Success Criteria
- run: true HKPASS
- run: grep -q HKMISS main.go
- run: hk-nope-cmd
EOF
  run bash "$CHECK" --run --workspace "$WS" --repo "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"$WS/scope.md"* ]]         # the report names the set's source
  [[ "$output" == *"HKPASS"* ]]               # the criterion that PASSED is echoed
  [[ "$output" == *"HKMISS"* ]]               # the criterion that ran and failed
  [[ "$output" == *"hk-nope-cmd"* ]]          # the run did not stop at the first failure
  [[ "$output" == *"exit 127"* ]]             # command-not-found is a failure, not a pass
  [[ "$output" == *"command not found"* ]]    # ... carrying the child's own diagnostic
  [[ "$output" == *"2 of 3"* ]]               # the tally counts the whole set

  # The report is on stdout - the channel skills/review/SKILL.md reads, and not a
  # workspace file no stage declares. The child's stderr is folded into the
  # excerpt rather than leaking to the gate's own stderr.
  run bash -c "bash '$CHECK' --run --workspace '$WS' --repo '$PROJ' 2>/dev/null"
  [ "$status" -eq 1 ]
  [[ "$output" == *"HKPASS"* ]]
  [[ "$output" == *"command not found"* ]]
}

@test "run mode bounds a long failure excerpt and labels what it elided" {
  # Rejects an unbounded dump and a head-only excerpt: the real error is the last
  # line the command printed, and the reduction must be labelled with a truthful
  # count rather than applied silently.
  cat > "$WS/scope.md" <<'EOF'
## Success Criteria
- run: bash -c 'for i in $(seq 1 50); do echo "line $i"; done; echo "the real error"; exit 2'
EOF
  run bash "$CHECK" --run --workspace "$WS" --repo "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"line 1"* ]]                 # the head survives
  [[ "$output" == *"line 10"* ]]
  [[ "$output" == *"the real error"* ]]         # so does the tail - head-only loses it
  [[ "$output" == *"(31 lines elided)"* ]]      # 51 output lines, 20 kept, 31 named
  [[ "$output" != *"line 30"* ]]                # and it really is bounded
}

@test "run mode keeps a TAP failure visible when it sits in the middle of the run" {
  # `bats tests/` is criterion one of nearly every task in this repo and its
  # failure sits wherever the failing test sits, so pin a failure at test 15 of
  # 30. Rejects a head+tail excerpt with no TAP-noise filter (the `not ok` and its
  # diagnostic land inside the elided middle - a failure at test 1 is the only
  # position where a fixed head window happens to work), a tail-only excerpt, and
  # an unbounded dump.
  cat > "$WS/scope.md" <<'EOF'
## Success Criteria
- run: bash -c 'echo 1..30; for i in $(seq 1 14); do echo "ok $i tap pass"; done; echo "not ok 15 the real failure"; echo "# (in test file tests/x.bats, line 9)"; for i in $(seq 16 30); do echo "ok $i tap pass"; done; exit 1'
EOF
  run bash "$CHECK" --run --workspace "$WS" --repo "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not ok 15 the real failure"* ]]              # the failing test is named
  [[ "$output" == *"# (in test file tests/x.bats, line 9)"* ]]   # with its diagnostic
  [[ "$output" != *"ok 7 tap pass"* ]]                           # passes dropped, not excerpted
}

@test "run mode hands a criterion to a shell verbatim, from the repo under test" {
  # Both criteria carry a trailing comment tail; the second also carries a `#`
  # inside quotes, and both name repo-relative paths. Rejects any tail stripping
  # (a `sed 's/ *#.*//'` truncates the quoted pattern and the command dies on an
  # unbalanced quote) and running the criterion from the gate's own cwd rather
  # than --repo. The echo assertion pins the command reaching the report as
  # written, comment tail included.
  printf 'the # sign\n' > "$PROJ/notes.md"
  cat > "$WS/scope.md" <<'EOF'
## Success Criteria
- run: grep -q "package main" main.go   # tail comment
- run: grep -q "the # sign" notes.md   # tail comment
EOF
  run bash "$CHECK" --run --workspace "$WS" --repo "$PROJ"
  [ "$status" -eq 0 ]
  [[ "$output" == *'grep -q "the # sign" notes.md   # tail comment'* ]]
}

@test "a criterion cannot move the working directory for the next one" {
  # Rejects `eval` in the gate's own shell: `cd /` would move the cwd and the
  # next criterion's repo-relative path would vanish.
  cat > "$WS/scope.md" <<'EOF'
## Success Criteria
- run: cd /
- run: test -f main.go
EOF
  run bash "$CHECK" --run --workspace "$WS" --repo "$PROJ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"test -f main.go"* ]]
}

@test "a criterion cannot end the run, and the receipt still lands" {
  # Rejects `eval` in the gate's own shell: `exit 0` would terminate the gate
  # with status 0, before the second criterion ran and before the receipt was
  # written. Verdict-first reporting means a criterion appears in the output only
  # once it has returned.
  cat > "$WS/scope.md" <<'EOF'
## Success Criteria
- run: exit 0
- run: false
EOF
  run bash "$CHECK" --run --workspace "$WS" --repo "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"exit 0"* ]]     # the first criterion returned and was reported
  [[ "$output" == *"false"* ]]      # the second still ran and is named
  [ -f "$WS/receipts/criteria-run.json" ]
}

@test "a criterion that reads stdin does not swallow the rest of the criteria" {
  # Rejects a child that inherits the loop's stdin: `cat` would drain the
  # herestring feeding the criteria loop and the second criterion would never
  # run. The exit code does NOT discriminate here - the tally comes from the
  # extracted set, so a swallowed criterion still summarises as 2 and exits 0 -
  # which is why the load-bearing assertion is that the second one is reported.
  cat > "$WS/scope.md" <<'EOF'
## Success Criteria
- run: cat
- run: test -f main.go
EOF
  run bash "$CHECK" --run --workspace "$WS" --repo "$PROJ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"test -f main.go"* ]]
}

@test "run mode writes its own receipt under the criteria-run gate name" {
  # Rejects reusing the shape gate's receipt: bin/coverage/gate.sh:82 waives
  # freshness for the name `check-criteria` only, so a code-dependent run-mode
  # result travelling under that name would take the status-waived path AND
  # clobber the implement-stage receipt.
  cat > "$WS/scope.md" <<'EOF'
## Success Criteria
- run: true
EOF
  echo more >> "$PROJ/main.go"    # a real diff, so the digest is content-bearing
  expected="$(git -C "$PROJ" diff HEAD | sha256sum | awk '{print $1}')"
  run bash "$CHECK" --run --workspace "$WS" --repo "$PROJ"
  [ "$status" -eq 0 ]
  r="$WS/receipts/criteria-run.json"
  [ -f "$r" ]
  [ "$(jq -r .gate "$r")" = "criteria-run" ]
  [ "$(jq -r .task_id "$r")" = "2026-07-02-fixture" ]
  [ -n "$(jq -r .timestamp "$r")" ]
  [ "$(jq -r .timestamp "$r")" != "null" ]
  [ "$(jq -r .status "$r")" = "pass" ]
  [ "$(jq -r .diff_digest "$r")" = "$expected" ]
  [ ! -f "$WS/receipts/check-criteria.json" ]   # the shape receipt is not clobbered
}

@test "run mode receipts a failing run, recording status fail" {
  # Rejects exiting before the receipt is written. The receipt proves the gate ran
  # (KTD7); gate.sh:86-90 checks only the digest for a non-check-criteria receipt,
  # so a `status: fail` receipt still passes the audit and the executor's exit
  # code is what blocks.
  cat > "$WS/scope.md" <<'EOF'
## Success Criteria
- run: false
EOF
  run bash "$CHECK" --run --workspace "$WS" --repo "$PROJ"
  [ "$status" -eq 1 ]
  [ -f "$WS/receipts/criteria-run.json" ]
  [ "$(jq -r .status "$WS/receipts/criteria-run.json")" = "fail" ]
}

@test "run mode does not pass a scope with no Success Criteria section" {
  # Rejects a vacuous pass on an empty derived set: this gate derives its input
  # set from a model-written file, and a gate that derives its own input set
  # passes vacuously when the set comes back empty. Exit 1 (a failure), not 3
  # (cannot-check) - both modes must agree about what the criteria set IS, and
  # routing this to 3 would make a scope that lost its criteria section
  # indistinguishable from the quick lane's legitimate absence. The message
  # assertion is load-bearing: at base the exit code alone reads green, because
  # an unknown `--run` argument also exits 1.
  cat > "$WS/scope.md" <<'EOF'
# Scope

Nothing pinned here.
EOF
  run bash "$CHECK" --run --workspace "$WS" --repo "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no criteria"* ]]
}

@test "run mode reports cannot-check when there is no scope declaration" {
  # Rejects collapsing cannot-check into failure. Tri-state, per the convention
  # bin/check-criteria.sh:5-6 and bin/coverage/gate.sh:11-12 already keep. This is
  # also the quick lane's answer: that lane pins no scope.md.
  [ ! -f "$WS/scope.md" ]
  run bash "$CHECK" --run --workspace "$WS" --repo "$PROJ"
  [ "$status" -eq 3 ]
}

@test "run mode fails and names a bullet it cannot execute" {
  # Rejects silently skipping an unexecutable bullet: the report must cover every
  # bullet the extractor found, not only the executable ones, or an unexecuted
  # criterion hides behind a passing gate.
  cat > "$WS/scope.md" <<'EOF'
## Success Criteria
- run: true
- make it nicer
EOF
  run bash "$CHECK" --run --workspace "$WS" --repo "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"make it nicer"* ]]
  [[ "$output" == *"not machine-checkable"* ]]
}

@test "run mode reports and counts an empty run: bullet" {
  # Rejects the silent-empty-bullet bug: an empty `- run:` marks the run failed
  # but named no offender and left the tally reading `0 of 2`. This is also the
  # only test that reaches the empty-bullet arm at all - the one pre-existing line
  # whose bytes change when that arm gains an elif - so it is what keeps that line
  # out of the uncovered changed set.
  cat > "$WS/scope.md" <<'EOF'
## Success Criteria
- run:
- run: true
EOF
  run bash "$CHECK" --run --workspace "$WS" --repo "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"empty run: criterion"* ]]
  [[ "$output" == *"1 of 2"* ]]
}

@test "the quick lane's gates list does not name the criteria-run gate" {
  # The two `gates: [coverage, receipts]` lines in core/lifecycle.yaml are
  # byte-identical (review at :102, quick at :142), so a global replace that
  # widens the review stage silently widens the quick lane too - a named non-goal:
  # quick declares `artifacts.in: []`, has no scope.md, and so has no criteria set
  # to run. Extract the quick stage's OWN gates line and require it non-empty
  # first, so a renamed stage cannot satisfy this vacuously. Lives here rather
  # than in core.bats, which holds no gates/quick assertion for the wiring to
  # move; the review-side half of this pin is the scope's own criterion 7 and is
  # deliberately not promoted into the suite.
  q="$(awk '/^  quick:/{f=1} f&&/^    gates:/{print; exit}' "$REPO_ROOT/core/lifecycle.yaml")"
  [ -n "$q" ]
  ! grep -qi criteri <<<"$q"
}

# --- the two blockers the round-1 review verdict named -----------------------
# Both are reproduced end to end in that verdict's `## Blocking` section and both
# live in the run mode's receipt handling. Same fixture hygiene as the block
# above: every invocation passes --repo "$PROJ", and no fixture criterion invokes
# the run mode, so nothing recurses.

@test "run mode passes a --verify-receipts criterion on the round after its own previous run" {
  # B1. `- run: bash bin/coverage/gate.sh --verify-receipts ...` is the shape
  # every prior task in this repo carries, and criterion 14 of this task is one,
  # so the gate audits its own receipts directory from INSIDE the run. Rejects
  # writing criteria-run.json only after the criteria loop: the previous round's
  # receipt is then still on disk carrying the previous round's digest, and
  # bin/coverage/gate.sh:87-90 finds it stale against a tree that changed since -
  # so the criterion fails on every round after the first, whatever the work was,
  # and the gate is hard by design. Round 1 is asserted too, because it is what
  # makes the round-2 state real: the prior receipt here is written by the gate
  # itself, not hand-built. The fix shape is not pinned - writing the receipt
  # before the loop and rewriting it after, or clearing it first, both satisfy
  # this.
  #
  # RED at fc0ea9e, on the second run only: `FAIL (exit 1)` under
  # `| gate: receipt criteria-run.json is stale (diff digest mismatch)`, then
  # `check-criteria: FAIL - 1 of 1 criteria failed (receipt written)`, exit 1.
  base="$(git -C "$PROJ" rev-parse HEAD)"
  echo "ref: $base" > "$WS/base-ref"
  mkdir -p "$WS/receipts"
  cat > "$WS/scope.md" <<EOF
## Success Criteria
- run: bash $REPO_ROOT/bin/coverage/gate.sh --verify-receipts --workspace $WS --repo $PROJ
EOF

  # Round 1: a tracked change, plus the coverage receipt a review round writes
  # before the criteria run - the order skills/review/SKILL.md pins.
  echo 'round one' >> "$PROJ/main.go"
  d1="$(git -C "$PROJ" diff "$base" | sha256sum | awk '{print $1}')"
  cat > "$WS/receipts/coverage.json" <<EOF
{ "gate": "coverage", "task_id": "2026-07-02-fixture", "timestamp": "2026-07-28T00:00:00Z", "diff_digest": "$d1", "status": "pass" }
EOF
  run bash "$CHECK" --run --workspace "$WS" --repo "$PROJ"
  [ "$status" -eq 0 ]
  [ "$(jq -r .diff_digest "$WS/receipts/criteria-run.json")" = "$d1" ]   # a real prior-round receipt about the prior round's tree

  # Round 2: implement changed a tracked file since, so this round's coverage gate
  # measured a tree the round-1 receipt no longer describes.
  echo 'round two' >> "$PROJ/main.go"
  d2="$(git -C "$PROJ" diff "$base" | sha256sum | awk '{print $1}')"
  [ "$d1" != "$d2" ]        # the fixture really is a since-changed tree, so round 2 cannot pass vacuously
  cat > "$WS/receipts/coverage.json" <<EOF
{ "gate": "coverage", "task_id": "2026-07-02-fixture", "timestamp": "2026-07-29T00:00:00Z", "diff_digest": "$d2", "status": "pass" }
EOF
  run bash "$CHECK" --run --workspace "$WS" --repo "$PROJ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS  bash $REPO_ROOT/bin/coverage/gate.sh --verify-receipts"* ]]   # the audit is what passed, not some other criterion
  [ "$(jq -r .diff_digest "$WS/receipts/criteria-run.json")" = "$d2" ]   # and the round still leaves a receipt about the tree it ran on
  [ "$(jq -r .status "$WS/receipts/criteria-run.json")" = "pass" ]
}

@test "run mode does not report success when the receipt write fails" {
  # B2. bin/check-criteria.sh:115's heredoc is unchecked and :132 announces
  # "receipt written" unconditionally, so a write that cannot land is still
  # reported as a clean run. A directory at the receipt path is the cheap
  # reproduction; a read-only mount or a full disk fails the same way. Rejects an
  # unchecked write: the receipt IS the proof the gate ran (KTD7), and a gate
  # whose own summary line states something untrue is the class this task exists
  # to retire. What is pinned is the claim, not a wording - any report that names
  # the failed write and exits nonzero satisfies it, so phrase a negative as "no
  # receipt" or "receipt write failed" rather than "no receipt written".
  #
  # RED at fc0ea9e: `  PASS  true`, bash's own
  # `line 115: .../criteria-run.json: Is a directory`, then
  # `check-criteria: OK (1 criteria executed, receipt written)` and exit 0, with
  # no receipt anywhere.
  cat > "$WS/scope.md" <<'EOF'
## Success Criteria
- run: true
EOF
  mkdir -p "$WS/receipts/criteria-run.json"     # the receipt write cannot land here
  run bash "$CHECK" --run --workspace "$WS" --repo "$PROJ"
  [ "$status" -ne 0 ]                           # exit 0 certifies a run that left no receipt at all
  [[ "$output" != *"check-criteria: OK"* ]]     # ... and the success summary must not print
  [[ "$output" != *"receipt written"* ]]        # nor the claim itself, on either ending
  [[ "$output" != *"criteria failed"* ]]        # nor may an I/O failure be blamed on `true`, which passed
  grep -qi receipt <<<"$output"                 # the run reports what went wrong instead of swallowing it
  [ -d "$WS/receipts/criteria-run.json" ]       # and reports it rather than clearing the path to force the write
}

# --- FU-13: --repo is refused before anything happens ------------------------
# Security's S-2, reproduced end to end in the round-2 verdict and folded into
# the scope as criterion 15. `$REPO` reaches `cd` at bin/check-criteria.sh:108
# unvalidated, so the `cd` builtin reads a dash-leading value as an option: -P,
# -L and -- land in $HOME, `-` lands in OLDPWD. The forms below are the four the
# verdict measured, plus a plainly nonexistent path and a regular file - the
# forms a dash-prefix allowlist (both) and an `[ -e ]` test (the file) let
# through, and `[ -d ]` is false for all six (verified).
#
# Three tests, because the surface has three separable properties: a value that
# is not a directory is refused (run mode, then shape mode), and - the third -
# a criterion never executes from a cwd `--repo` did not name. The third is where
# a path check alone leaves the hole open: `[ -d "$REPO" ]` resolves the value as
# a PATH while an untouched `cd "$REPO"` still resolves it as an OPTION, so a
# directory named `-P` satisfies the guard and is still eaten by `cd`. The two
# refusal tests invoke from an empty scratch directory, so the four dash forms
# are guaranteed to name nothing there and a correct build cannot be failed by an
# ambient `./-P`; the third creates the directory they name and pins the
# complement.
#
# The empty string is deliberately not among them: `cd ""` succeeds without
# moving (verified), so it is the silent-fallback-to-the-gate's-own-cwd case
# already rejected below by the execution witness, and on the current tree
# running it would point the fixture criteria at THIS repo - the one thing the
# fixture rule at the head of the run-mode block forbids. Same hygiene otherwise:
# every invocation names --repo, every fixture path interpolated into a criterion
# string is quoted there (a TMPDIR with a space otherwise fails the right build),
# the criteria write only under BATS_TEST_TMPDIR, and none invokes the run mode.
#
# Wording is not asserted anywhere here. The refusal's message is the
# implementer's; what is pinned is that nothing ran and nothing was receipted.

@test "run mode refuses a --repo that is not a directory before any criterion runs" {
  # The dangerous state this kills is not a crash - it is a PASSING run over a
  # criterion that must be red, receipted `status: pass` with e3b0c442...b855,
  # the sha256 of the empty string, because `git -C -P diff` fails and
  # base-ref-lib.sh:20 discards the error. So an exit-code-only assertion is not
  # enough: two of the six forms already exit 1 today, by failing every criterion
  # on a broken `cd`. Two fixture criteria separate a refusal from that:
  #   1. an execution witness on an absolute path - it fires from ANY cwd, so its
  #      absence means not one criterion ran;
  #   2. a criterion that is red in the fixture repo (the marker is there) and
  #      passes vacuously anywhere else - the vacuity class S-2 names.
  # Each wrong implementation and the assertion that kills it:
  #   - no guard (today): -P, -L, --, - all exit 0 with `check-criteria: OK`
  #     while the witness fires -> the status and witness assertions;
  #   - `cd -- "$REPO"` instead of a guard: the verdict measured `cd -- -` still
  #     succeeding into OLDPWD -> the witness; and for the forms where `cd` then
  #     does fail, a receipt still lands about a repo the gate never entered ->
  #     the receipt assertion, which is the only one that fires there;
  #   - a silent fallback to the gate's own cwd -> the witness;
  #   - a dash-prefix allowlist -> the nonexistent path and the regular file;
  #   - an `[ -e ]` test rather than `[ -d ]` -> the regular file;
  #   - a guard that refuses and THEN receipts -> the receipt assertion, which
  #     requires the receipts directory itself to be absent, so the pre-loop
  #     write cannot land either; per S-1 a `running` receipt verifies clean at
  #     gate.sh:86-90, so leaving one behind is not harmless;
  #   - refusing every invocation -> the control, which demands exit 1 with the
  #     witness fired and the receipt written;
  #   - a guard that narrows what --repo ACCEPTS -> the second control, an
  #     ordinary directory that is no git checkout. `[ -d "$REPO/.git" ]` passes
  #     the first control and fails that one, and it would refuse the gate inside
  #     any git worktree, where `.git` is a file; so would an allowlist of the
  #     literal `.`, which is the laziest build that satisfies criterion 15.
  : > "$PROJ/hk-repo-marker"
  cat > "$WS/scope.md" <<EOF
## Success Criteria
- run: touch "$WS/ran-witness"
- run: ! test -f hk-repo-marker
EOF

  # Control: from the real repo this set exits 1 because the marker criterion is
  # red there, and the witness fired, so `touch` passed and the failure can only
  # be the marker. The same set exits 0 from anywhere else - that is the finding.
  run bash "$CHECK" --run --workspace "$WS" --repo "$PROJ"
  [ "$status" -eq 1 ]
  [ -e "$WS/ran-witness" ]
  [ -f "$WS/receipts/criteria-run.json" ]
  [ "$(jq -r .status "$WS/receipts/criteria-run.json")" = "fail" ]

  # Second control, the accept side: an ordinary directory that is neither a git
  # checkout nor a Harmonia root. A consuming project points --repo at its own
  # working tree, so the guard's job is to refuse a non-directory - not to demand
  # git-ness, a `core/lifecycle.yaml`, or the literal `.`.
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  rm -rf "$WS/receipts" "$WS/ran-witness"
  run bash "$CHECK" --run --workspace "$WS" --repo "$BATS_TEST_TMPDIR/plain"
  [ "$status" -eq 0 ]                          # accepted, and the marker criterion is green out there
  [ -e "$WS/ran-witness" ]                     # ... because the criteria really did run from it
  [ "$(jq -r .status "$WS/receipts/criteria-run.json")" = "pass" ]

  # The refusal set runs from an empty scratch directory, so the four dash forms
  # name nothing at all there: with a `./-P` present a correct build resolves it
  # and this test would fail a build that is right (the ambient-name fragility).
  # OLDPWD is passed explicitly for the same reason in the other direction - the
  # `-` form's danger must not depend on the invoking shell's history, since with
  # OLDPWD unset `cd -` fails and the form would go red for a shape reason.
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere" "$BATS_TEST_TMPDIR/empty-callsite"
  for bad in -P -L -- - "/nonexistent-hk-$$-not-a-dir" "$PROJ/main.go"; do
    echo "--repo form: $bad"
    rm -rf "$WS/receipts" "$WS/ran-witness"
    run bash -c "cd '$BATS_TEST_TMPDIR/empty-callsite' && env OLDPWD='$BATS_TEST_TMPDIR/elsewhere' bash '$CHECK' --run --workspace '$WS' --repo '$bad'"
    # Exit 1, not merely non-zero: bin/check-criteria.sh:10-11 defines 3 as
    # cannot-check and skills/review/SKILL.md:12 - the only consumer - reads it as
    # "there was no scope declaration to run". A refusal that exits 3 tells the
    # review lead there was nothing to execute, which is the vacuous review this
    # gate exists to prevent, one exit code sideways.
    [ "$status" -eq 1 ]
    [[ "$output" != *"check-criteria: OK"* ]]  # a red criterion must never report OK
    [ ! -e "$WS/ran-witness" ]                 # nothing executed - not one criterion
    [ ! -e "$WS/receipts" ]                    # and nothing was receipted, not even `running`
  done
}

@test "shape mode refuses the same --repo forms rather than receipt a digest it never took" {
  # The guard belongs in BOTH modes and this pins that decision instead of
  # leaving it to wherever the fix happens to land. In shape mode `$REPO` has
  # exactly one consumer, the receipt's diff_digest at bin/check-criteria.sh:39,
  # and a value `git -C` cannot use makes diff_digest hash nothing - so the
  # implement-entry gate exits 0 and writes `status: pass` carrying the
  # empty-string digest: a clean-tree claim about a repo it never looked at,
  # which then verifies against any genuinely clean tree (S-2 consequence 3).
  # Rejects a guard placed inside the `--run` branch: the argument loop is shared
  # and the fix the verdict names is one line after it. The digest assertion on
  # the control is what makes the fixture discriminating - without a real diff in
  # the fixture repo the honest digest IS the empty-string digest, and a refusal
  # would be indistinguishable from a vacuous pass.
  cat > "$WS/scope.md" <<'EOF'
## Success Criteria
- run: true
EOF
  echo more >> "$PROJ/main.go"
  honest="$(git -C "$PROJ" diff HEAD | sha256sum | awk '{print $1}')"
  empty="$(printf '' | sha256sum | awk '{print $1}')"
  [ "$honest" != "$empty" ]      # the fixture can tell a real digest from "no diff at all"

  run bash "$CHECK" --workspace "$WS" --repo "$PROJ"
  [ "$status" -eq 0 ]                                                          # a real repo still passes
  [ "$(jq -r .diff_digest "$WS/receipts/check-criteria.json")" = "$honest" ]   # over the diff it actually took

  # The accept side here too: an ordinary directory, no git checkout. Its digest
  # is not asserted - `git -C` cannot diff a non-repo either, and that is
  # pre-existing behaviour outside this guard's job.
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  rm -rf "$WS/receipts"
  run bash "$CHECK" --workspace "$WS" --repo "$BATS_TEST_TMPDIR/plain"
  [ "$status" -eq 0 ]
  [ -f "$WS/receipts/check-criteria.json" ]     # accepted, and the shape gate still receipts

  mkdir -p "$BATS_TEST_TMPDIR/empty-callsite"
  for bad in -P -L -- - "/nonexistent-hk-$$-not-a-dir" "$PROJ/main.go"; do
    echo "--repo form: $bad"
    rm -rf "$WS/receipts"
    run bash -c "cd '$BATS_TEST_TMPDIR/empty-callsite' && bash '$CHECK' --workspace '$WS' --repo '$bad'"
    [ "$status" -eq 1 ]                        # 1, an argument error - not 3, which reads as cannot-check
    [[ "$output" != *"check-criteria: OK"* ]]
    [ ! -e "$WS/receipts" ]                    # no receipt, so no empty-string digest under `status: pass`
  done
}

@test "run mode never executes a criterion from a cwd --repo did not name, dash-leading directory included" {
  # The complement of the guard, and the hole a path check alone leaves open:
  # `[ -d "$REPO" ]` resolves the value as a path, `cd "$REPO"` resolves it as an
  # option first. With a directory literally named `-P` at the invocation cwd,
  # `[ -d "-P" ]` is TRUE, the guard passes, and `cd "-P"` still lands in $HOME -
  # producing the whole FU-13 outcome (criteria executed outside the named tree,
  # `check-criteria: OK`, a receipt with the empty-string digest) through a build
  # that satisfies both the guard and the scope's criterion 15.
  #
  # What is pinned is the safety property, not a remedy: if a criterion ran at
  # all, it ran in the directory --repo named. Both plausible answers pass -
  # refusing every dash-leading value, or entering the directory because it
  # genuinely is one - and only the silent wrong-cwd landing fails. `cd --` is
  # deliberately NOT forced: it is an incomplete remedy (measured: `cd -- -` still
  # resolves to OLDPWD, so a build that adds only `--` still leaves the `-` form
  # holed, and this test still fails it), while normalising a dash-leading value
  # to `./-P` and keeping the existing `cd` is equally correct and passes.
  #
  # The cwd is recorded and compared rather than inferred from a vacuity pass,
  # because which way the vacuity falls is a property of the fixture, not of the
  # bug: criterion 15's criteria pass in $HOME, so the wrong landing there reports
  # OK, while this fixture's marker criterion fails there and the same wrong
  # landing reports FAIL. Same defect, opposite exit codes - the recorded cwd
  # names it either way, and no assertion depends on what $HOME happens to hold.
  #
  # Shape mode has no counterpart: $REPO never reaches `cd` there, so the
  # option-versus-path split cannot arise; its one consumer is the digest, pinned
  # by the test above.
  call="$BATS_TEST_TMPDIR/dashcall"
  mkdir -p "$call" "$BATS_TEST_TMPDIR/oldpwd-target"
  cat > "$WS/scope.md" <<EOF
## Success Criteria
- run: pwd -P > "$WS/cwd-witness"
- run: test -f hk-dash-target
EOF

  for form in -P -L -- -; do
    echo "--repo names a real directory called: $form"
    target="$call/$form"
    mkdir -p "$target"
    : > "$target/hk-dash-target"
    want="$(cd "$target" && pwd -P)"
    rm -rf "$WS/receipts" "$WS/cwd-witness"
    run bash -c "cd '$call' && env OLDPWD='$BATS_TEST_TMPDIR/oldpwd-target' bash '$CHECK' --run --workspace '$WS' --repo '$form'"
    if [ -e "$WS/cwd-witness" ]; then
      # It ran. Then it ran where --repo pointed, and nowhere else.
      [ "$(cat "$WS/cwd-witness")" = "$want" ]
      [ "$status" -eq 0 ]                      # ... and reported honestly: both criteria pass in there
    else
      # Or it refused the form outright, which is the other correct answer.
      [ "$status" -eq 1 ]
      [ ! -e "$WS/receipts" ]                  # receipting nothing on the way out
    fi
  done
}

# --- FU-10 read at both moments: the in-run audit and the standalone one ------
# A run that FAILED its criteria must still pass its OWN in-run receipt audit and
# must fail the standalone one afterwards. Both halves in one test because they
# are the same receipt read at two moments: the pre-loop write says `running`,
# which an audit invoked from inside the run it certifies has to accept, and the
# post-loop rewrite says `fail`, which review's standalone --verify-receipts step
# must refuse. Requiring `status: pass` breaks the first half - the round's own
# audit criterion then fails from round 1 onwards, whatever the work was.
# Leaving `fail` unread leaves the second half certifying a round that ran and
# lost, which is what the base gate does.
#
# The hand-written coverage.json is the receipt review's coverage gate writes
# before the criteria run (the order skills/review/SKILL.md:11-13 pins); without
# it the audit refuses for the no-coverage-receipt reason instead, and neither
# half of this test would be about FU-10.
#
# Every fixture path interpolated into the criterion is QUOTED there, the hygiene
# rule this file states at :511: the criteria run through `bash -c`, so with an
# unquoted $WS a $TMPDIR carrying a space reds a build that is right. Measured
# both ways under `TMPDIR=<a path with a space>` before it was written this way.
@test "a failed criteria run keeps its in-run audit passing and fails the standalone one" {
  base="$(git -C "$PROJ" rev-parse HEAD)"
  echo "ref: $base" > "$WS/base-ref"
  mkdir -p "$WS/receipts"
  cat > "$WS/scope.md" <<EOF
## Success Criteria
- run: bash "$REPO_ROOT/bin/coverage/gate.sh" --verify-receipts --workspace "$WS" --repo "$PROJ"
- run: false
EOF
  echo 'a change the round measured' >> "$PROJ/main.go"
  d="$(git -C "$PROJ" diff "$base" | sha256sum | awk '{print $1}')"
  cat > "$WS/receipts/coverage.json" <<EOF
{ "gate": "coverage", "task_id": "2026-07-02-fixture", "timestamp": "2026-07-31T00:00:00Z", "diff_digest": "$d", "status": "pass" }
EOF
  run bash "$CHECK" --run --workspace "$WS" --repo "$PROJ"
  [ "$status" -eq 1 ]                                    # `false` failed the round, as it must
  [[ "$output" == *"PASS  bash \"$REPO_ROOT/bin/coverage/gate.sh\" --verify-receipts"* ]]   # ...and the audit inside it passed
  [ "$(jq -r .status "$WS/receipts/criteria-run.json")" = "fail" ]
  [ "$(jq -r .diff_digest "$WS/receipts/criteria-run.json")" = "$d" ]   # fresh, so the refusal below is about the status

  run bash "$REPO_ROOT/bin/coverage/gate.sh" --verify-receipts --workspace "$WS" --repo "$PROJ"
  [ "$status" -ne 0 ]
  [[ "$output" == *"criteria-run"* ]]
  [[ "$output" != *"receipts verified"* ]]
  [[ "$output" != *"stale"* ]]
}

# --- FU-16: the task workspace path is not a trust boundary -------------------
# Everything under .harmonia/tasks is treated as the user's own and its PATH has
# not earned that. A symlink anywhere on the way to a workspace redirects the
# receipt write that goes through it: base writes the receipt out there, reports
# `check-criteria: OK` and exits 0.
#
# The forms are POSITIONS on the receipt's own path, derived component by
# component from <repo>/.harmonia/tasks/<id>/receipts/<name>.json rather than
# copied from a list - D .harmonia, C tasks, B <id>, A receipts, E <name>.json -
# so no component of that path is left unprobed. `shaped` is the C position with
# a redirect TARGET that is itself named .harmonia/tasks: a guard that asks only
# whether the resolved path LOOKS like a workspace accepts it and writes into a
# directory outside the tree it was handed, which is the same escape one name
# later. `clean` and `linkedroot` are the accept side, and linkedroot is not
# decoration: it is a checkout reached through a symlinked ancestor (the
# /var -> /private/var shape every macOS TMPDIR has), and a guard comparing the
# path it was GIVEN against a resolved one refuses every such checkout.
#
# Both modes, because both reach the same writer - shape mode at every implement
# round, --run only at review - so a rule gated on --run still clobbers a victim
# at implement time, which is the more frequent of the two.
#
# The detector is a before/after snapshot of the whole outside tree (every path,
# plus every file's sha256), not a match on artifact names: a write under a name
# this test does not know is still an escape, and so is a deletion. A redirected
# command's exit status cannot say whether the write landed; the disk can.

snap_tree() {   # <dir> -> a listing that moves if anything under it is added, removed or edited
  { find "$1" | sort; find "$1" -type f -exec sha256sum {} + 2>/dev/null | sort; }
}

cc_assert_outside_unchanged() {   # <dir> <snapshot-taken-before>
  local after; after="$(snap_tree "$1")"
  if [ "$after" != "$2" ]; then
    echo "ESCAPED - the tree outside the workspace changed:"
    diff <(printf '%s\n' "$2") <(printf '%s\n' "$after") || true
  fi
  [ "$after" = "$2" ]
}

plant_receipts() {   # <receipts-dir>: the two names check-criteria.sh writes, one per mode
  printf 'VICTIM\n' > "$1/check-criteria.json"
  printf 'VICTIM\n' > "$1/criteria-run.json"
}

stage_cc() {   # <form>: builds one self-contained cell; sets CELL, RB (--repo), WSP (--workspace)
  local form="$1" real
  CELL="$BATS_TEST_TMPDIR/cc-$form"
  mkdir -p "$CELL/out" "$CELL/real"
  real="$CELL/real/r"
  mkdir -p "$real"
  git -C "$real" init -q
  printf 'a\n' > "$real/f.sh"
  git -C "$real" add -A
  git -C "$real" -c user.email=t@t -c user.name=t commit -qm b
  RB="$real"
  WSP="$real/.harmonia/tasks/T"
  mkdir -p "$WSP/receipts"
  cat > "$WSP/scope.md" <<'EOS'
## Success Criteria
- run: true
EOS
  case "$form" in
    clean) ;;
    linkedroot)
      ln -s "$CELL/real" "$CELL/link" || { echo "fixture unusable: cannot symlink in TMPDIR" >&2; return 1; }
      [ -f "$CELL/link/r/.harmonia/tasks/T/scope.md" ] || { echo "fixture unusable: the symlinked ancestor is unusable" >&2; return 1; }
      RB="$CELL/link/r"; WSP="$CELL/link/r/.harmonia/tasks/T" ;;
    A)  rm -rf "$WSP/receipts"; mkdir -p "$CELL/out/receipts"; plant_receipts "$CELL/out/receipts"
        ln -s "$CELL/out/receipts" "$WSP/receipts" ;;
    B)  mv "$WSP" "$CELL/out/T"; ln -s "$CELL/out/T" "$WSP"; plant_receipts "$CELL/out/T/receipts" ;;
    C)  mv "$real/.harmonia/tasks" "$CELL/out/tasks"; ln -s "$CELL/out/tasks" "$real/.harmonia/tasks"
        plant_receipts "$CELL/out/tasks/T/receipts" ;;
    C-absent)
        # Same redirect as C, with receipts/ stripped from the target. Every
        # other form carries it along, so the gate's `mkdir -p` is a no-op and
        # deleting the guard in front of it reds nothing; here that mkdir is the
        # statement that creates a directory outside the repository.
        mv "$real/.harmonia/tasks" "$CELL/out/tasks"; ln -s "$CELL/out/tasks" "$real/.harmonia/tasks"
        rm -rf "$CELL/out/tasks/T/receipts" ;;
    D)  mv "$real/.harmonia" "$CELL/out/harmonia"; ln -s "$CELL/out/harmonia" "$real/.harmonia"
        plant_receipts "$CELL/out/harmonia/tasks/T/receipts" ;;
    E)  printf 'VICTIM\n' > "$CELL/out/E-shape.json"; printf 'VICTIM\n' > "$CELL/out/E-run.json"
        rm -f "$WSP/receipts/check-criteria.json" "$WSP/receipts/criteria-run.json"
        ln -s "$CELL/out/E-shape.json" "$WSP/receipts/check-criteria.json"
        ln -s "$CELL/out/E-run.json" "$WSP/receipts/criteria-run.json" ;;
    shaped)
        mkdir -p "$CELL/out/.harmonia"
        mv "$real/.harmonia/tasks" "$CELL/out/.harmonia/tasks"
        ln -s "$CELL/out/.harmonia/tasks" "$real/.harmonia/tasks"
        plant_receipts "$CELL/out/.harmonia/tasks/T/receipts" ;;
  esac
  [ -f "$WSP/scope.md" ] || { echo "fixture unusable: no scope.md is reachable at $WSP - the gate would refuse for the wrong reason" >&2; return 1; }
}

@test "the criteria gate refuses a receipt write that resolves outside the workspace, in both modes" {
  for form in clean linkedroot A B C D E shaped C-absent; do
    stage_cc "$form"
    before="$(snap_tree "$CELL/out")"
    for mode in shape run; do
      echo "--- redirect form: $form ($mode mode), workspace $WSP"
      if [ "$mode" = run ]; then
        run bash "$CHECK" --run --workspace "$WSP" --repo "$RB"
      else
        run bash "$CHECK" --workspace "$WSP" --repo "$RB"
      fi
      echo "status=$status"
      echo "$output"
      case "$form" in
        clean|linkedroot)
          # The accept side. A legitimate workspace still receipts, in the
          # directory it was pointed at, and reports so.
          [ "$status" -eq 0 ]
          [[ "$output" == *"check-criteria: OK"* ]]
          if [ "$mode" = run ]; then
            [ -s "$WSP/receipts/criteria-run.json" ]
          else
            [ -s "$WSP/receipts/check-criteria.json" ]
          fi
          ;;
        *)
          [ "$status" -ne 0 ]                        # a receipt that cannot land is a gate failure, not a verdict
          [[ "$output" != *"check-criteria: OK"* ]]  # and never an OK over a write that went elsewhere
          ;;
      esac
      # The judgement, every form: nothing outside the tree the caller named was
      # created, rewritten or removed.
      cc_assert_outside_unchanged "$CELL/out" "$before"
    done
  done
}

# --- the contents have not earned it either: clone-supplied execution ---------
# `--run` executes the `- run:` lines of $WS/scope.md verbatim, and a repository
# you clone can ship one. Reading a stranger's repo becomes code execution.
#
# Two constructions of the same class, because a guard can pass one and be walked
# past by the other. The first commits a COMPLETE-looking workspace - scope.md,
# minted and base-ref all tracked - so a guard keyed on the presence of a mint
# marker is red on it. The second tracks a SYMLINK at .harmonia/tasks with the
# payload one directory over, so the path the caller is handed and the file that
# will actually execute are tracked at different paths: that one reds a guard
# keyed on the literal <ws>/scope.md path and one keyed on the
# `git ls-files -- "$WS"` directory pathspec, which the first passes (measured -
# a literal-path key is green on the first probe and red on the second). Neither
# proves a guard resolves in general; each probe depth only rules out the keys
# shallower than it.
#
# The accept side is three-quarters of this test on purpose. Every workspace this
# repo mints is untracked-inside-a-git-repo, and a guard that refuses when git is
# present, when the file is not gitignored, or when stdin is not a terminal also
# passes both reject probes while breaking every real round. Shape mode is here
# for the same reason in the other direction: it executes nothing, so refusing
# there is over-wide, and the same rule placed before the mode split reds :136.

@test "run mode refuses to execute a scope declaration that arrived with the repository" {
  ID=2026-01-01-innocuous-refactor
  SENT="$BATS_TEST_TMPDIR/SENTINEL"

  for probe in plain tracked-symlink; do
    H="$BATS_TEST_TMPDIR/hostile-$probe"
    C="$BATS_TEST_TMPDIR/clone-$probe"
    mkdir -p "$H"
    printf 'x\n' > "$H/README.md"
    case "$probe" in
      plain)
        PAY="$H/.harmonia/tasks/$ID"; TRACKED=".harmonia/tasks/$ID/scope.md"; MODE=100644; MPATH=".harmonia/tasks/$ID"
        mkdir -p "$PAY" ;;
      tracked-symlink)
        PAY="$H/payload/.harmonia/tasks/$ID"; TRACKED="payload/.harmonia/tasks/$ID/scope.md"; MODE=120000; MPATH=".harmonia/tasks"
        mkdir -p "$PAY" "$H/.harmonia"
        ln -s "../payload/.harmonia/tasks" "$H/.harmonia/tasks" ;;
    esac
    cat > "$PAY/scope.md" <<EOF
## Success Criteria
- run: touch "$SENT" && echo owned
EOF
    date -u +%Y-%m-%dT%H:%M:%SZ > "$PAY/minted"
    printf 'ref: none\n' > "$PAY/base-ref"
    git -C "$H" init -q
    git -C "$H" add -A -f
    git -C "$H" -c user.email=t@t -c user.name=t commit -qm x
    git clone -q "$H" "$C"
    CW="$C/.harmonia/tasks/$ID"

    # The fixture asserts what it is FOR, four ways: without these a broken
    # hostile repo reads as a guard that works.
    echo "--- hostile clone: $probe"
    git -C "$C" ls-files --error-unmatch -- "$TRACKED" >/dev/null   # the payload really arrived tracked...
    [ "$(git -C "$C" ls-files -s -- "$MPATH" | awk '{print $1}' | head -1)" = "$MODE" ]   # ...at the mode this probe intends
    [ -f "$CW/scope.md" ]                                          # and is reachable at the workspace path
    [ "$(bash "$REPO_ROOT/bin/workspace.sh" resolve --repo "$C")" = "$ID" ]   # which is the one resolve selects

    rm -f "$SENT"
    run bash "$CHECK" --run --workspace "$CW" --repo "$C" </dev/null
    echo "status=$status"
    echo "$output"
    [ ! -e "$SENT" ]                                 # the clone's command did not run
    [ "$status" -ne 0 ]
    [[ "$output" != *"check-criteria: OK"* ]]

    # Shape mode executes nothing, so it must still pass on the same clone: this
    # is the over-reach probe, and it is also what keeps a containment rule from
    # standing in for provenance - the redirect here stays inside the clone.
    rm -f "$SENT"
    run bash "$CHECK" --workspace "$CW" --repo "$C" </dev/null
    echo "shape-mode status=$status"
    echo "$output"
    [ "$status" -eq 0 ]
    [ ! -e "$SENT" ]
  done

  # Accept side 1: a HAND-MADE workspace in a git repo (tests/hooks.bats:19
  # makes them with mkdir -p, so this is the shipped shape) whose scope.md the
  # developer wrote. Same repo as the reject probe above, one directory over.
  A="$BATS_TEST_TMPDIR/clone-plain/.harmonia/tasks/2026-08-01-mine"
  mkdir -p "$A"
  OK1="$BATS_TEST_TMPDIR/OK-in-git"; rm -f "$OK1"
  cat > "$A/scope.md" <<EOF
## Success Criteria
- run: touch "$OK1" && echo fine
EOF
  run bash "$CHECK" --run --workspace "$A" --repo "$BATS_TEST_TMPDIR/clone-plain" </dev/null
  echo "accept in-git status=$status"
  echo "$output"
  [ "$status" -eq 0 ]
  [ -e "$OK1" ]
  [[ "$output" == *"check-criteria: OK"* ]]

  # Accept side 2: a workspace in a tree that is no git checkout at all - there
  # is no index to ask, and :571 requires a non-git --repo to work.
  NG="$BATS_TEST_TMPDIR/nogit"
  mkdir -p "$NG/.harmonia/tasks/2026-08-01-hand"
  if git -C "$NG" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "fixture unusable: the non-git tree is inside a git work tree" >&2
    return 1
  fi
  OK2="$BATS_TEST_TMPDIR/OK-no-git"; rm -f "$OK2"
  cat > "$NG/.harmonia/tasks/2026-08-01-hand/scope.md" <<EOF
## Success Criteria
- run: touch "$OK2" && echo fine
EOF
  run bash "$CHECK" --run --workspace "$NG/.harmonia/tasks/2026-08-01-hand" --repo "$NG" </dev/null
  echo "accept non-git status=$status"
  echo "$output"
  [ "$status" -eq 0 ]
  [ -e "$OK2" ]
}

@test "the provenance guard fails closed when git cannot be trusted to answer" {
  # The guard above asks git whether scope.md is tracked and reads a non-zero
  # exit as "no repository here, so this file is the user's". That inference is
  # only sound when git failed because there really is no repository. Seven ways
  # to make git answer wrongly over a clone whose payload really is tracked -
  # four from the environment, three from the repository itself - and every one
  # of them executed the payload on the build that shipped the guard.
  local h="$BATS_TEST_TMPDIR/fc-host" c="$BATS_TEST_TMPDIR/fc-clone"
  local id=2026-01-01-innocuous w="$h/.harmonia/tasks/2026-01-01-innocuous"
  local sent="$BATS_TEST_TMPDIR/FC-SENTINEL"
  mkdir -p "$w/receipts"
  printf 'x\n' > "$h/README.md"
  cat > "$w/scope.md" <<EOF
## Success Criteria
- run: touch "$sent" && echo owned
EOF
  git -C "$h" init -q
  git -C "$h" add -A -f
  git -C "$h" -c user.email=t@t -c user.name=t commit -qm x
  git clone -q "$h" "$c"
  local cw="$c/.harmonia/tasks/$id"
  # The fixture is only meaningful if the payload really arrived tracked.
  git -C "$c" ls-files --error-unmatch -- ".harmonia/tasks/$id/scope.md" >/dev/null

  probe_refuses() {   # <label> [env assignments...]
    local label="$1"; shift
    rm -f "$sent"
    run env "$@" bash "$CHECK" --run --workspace "$cw" --repo "$c" </dev/null
    echo "--- $label: status=$status"
    echo "$output"
    [ ! -e "$sent" ]
    [ "$status" -ne 0 ]
    [[ "$output" != *"check-criteria: OK"* ]]
  }

  # RETIRED by scope.md's round-9 narrowing, and ASSERTED rather than unpinned: in
  # each of these git opens no repository at all, so there is nothing for the
  # payload to have been carried BY. That is the same exposure as a delivery that
  # carries no `.git`, which this task declares out of scope. A build that still
  # refuses them is red here, so the retirement cannot be reversed by accident.
  probe_accepts() {   # <label> [env assignments...]
    local label="$1"; shift
    rm -f "$sent"
    run env "$@" bash "$CHECK" --run --workspace "$cw" --repo "$c" </dev/null
    echo "--- $label (retired, must accept): status=$status"
    echo "$output"
    [ "$status" -eq 0 ]
    [ -e "$sent" ]
  }

  # The control: untampered, this clone is already refused. Without it a build
  # that refuses everything would look like a pass on all seven cells below.
  probe_refuses untampered

  # Supplied by the caller's environment. GIT_WORK_TREE and GIT_INDEX_FILE are
  # not the same failure as the other two and are listed separately for it:
  # rev-parse --is-inside-work-tree answers `true` at exit 0 under both, so they
  # defeat `git ls-files` rather than repository discovery, and a fix that only
  # makes rev-parse failures fail closed leaves these two executing.
  # /nonexistent only proves the discovery-fails path. A REAL, healthy decoy is
  # the form that matters: git succeeds and lies - the cwd is the decoy's work
  # tree so the toplevel check passes, ls-files misses against the decoy index,
  # and its history is walkable and does not contain the payload. Measured: with
  # the GIT_* names dropped from the unset, /nonexistent still refuses and this
  # one executes.
  probe_refuses GIT_DIR GIT_DIR=/nonexistent
  local decoy="$BATS_TEST_TMPDIR/fc-decoy"
  mkdir -p "$decoy"
  git -C "$decoy" init -q
  printf 'z\n' > "$decoy/z"
  git -C "$decoy" add -A
  git -C "$decoy" -c user.email=t@t -c user.name=t commit -qm z
  probe_refuses GIT_DIR-real "GIT_DIR=$decoy/.git"
  probe_refuses GIT_WORK_TREE "GIT_WORK_TREE=$BATS_TEST_TMPDIR"
  probe_refuses GIT_INDEX_FILE GIT_INDEX_FILE=/dev/null
  probe_refuses GIT_CEILING_DIRECTORIES "GIT_CEILING_DIRECTORIES=$c"

  # Supplied by the repository being examined, which is the side the threat
  # model is actually about: a clone carries its own .git.
  sed -i 's/repositoryformatversion = 0/repositoryformatversion = 99/' "$c/.git/config"
  probe_accepts core.repositoryformatversion
  sed -i 's/repositoryformatversion = 99/repositoryformatversion = 0/' "$c/.git/config"

  mv "$c/.git" "$c/.gitreal"
  printf 'gitdir: /nonexistent\n' > "$c/.git"
  probe_accepts dangling-gitfile
  rm -f "$c/.git"; mv "$c/.gitreal" "$c/.git"

  # uid 0 ignores the mode, so this cell cannot be constructed as root.
  if [ "$(id -u)" -ne 0 ]; then
    chmod 000 "$c/.git"
    probe_accepts unreadable-git-dir
    chmod -R 755 "$c/.git"
  fi

  # The accept side, and the reason the fix walks for .git in shell instead of
  # asking git: a tree with no repository above it is the one case where a git
  # failure really does mean "this file is the user's". A build that fails
  # closed by treating every git error as tracked is red here.
  local ng="$BATS_TEST_TMPDIR/fc-nogit/.harmonia/tasks/2026-08-01-hand"
  mkdir -p "$ng"
  local ok="$BATS_TEST_TMPDIR/FC-OK"; rm -f "$ok"
  cat > "$ng/scope.md" <<EOF
## Success Criteria
- run: touch "$ok" && echo fine
EOF
  run bash "$CHECK" --run --workspace "$ng" --repo "$BATS_TEST_TMPDIR/fc-nogit" </dev/null
  echo "--- accept non-git: status=$status"
  echo "$output"
  [ "$status" -eq 0 ]
  [ -e "$ok" ]
  [[ "$output" == *"check-criteria: OK"* ]]
}

@test "a base-ref VALUE supplied by a repository never reaches git diff as an option" {
  # B1. Every guard on base-ref so far tests its PATH - whether the file is
  # redirected. This is its CONTENT. `diff_digest` is `git -C R diff "$BASE"`,
  # so a base-ref of `ref: --output=<path>` makes git write that path: outside
  # the repository, with no symlink, no local write access and no .git
  # tampering. Shape mode is the vector - deliberately not provenance-guarded,
  # and it runs at every implement round.
  local h="$BATS_TEST_TMPDIR/bv-host" c="$BATS_TEST_TMPDIR/bv-clone"
  local w="$h/.harmonia/tasks/T"
  local victim="$BATS_TEST_TMPDIR/bv-victim.txt"
  printf 'PRECIOUS USER DATA\n' > "$victim"
  local before; before="$(cat "$victim")"

  mkdir -p "$w/receipts"
  printf 'x\n' > "$h/README.md"
  cat > "$w/scope.md" <<'EOS'
## Success Criteria
- run: true
EOS
  printf 'ref: --output=%s\n' "$victim" > "$w/base-ref"
  git -C "$h" init -q
  git -C "$h" add -A -f
  git -C "$h" -c user.email=t@t -c user.name=t commit -qm x
  git clone -q "$h" "$c"
  local cw="$c/.harmonia/tasks/T"
  git -C "$c" ls-files --error-unmatch -- ".harmonia/tasks/T/base-ref" >/dev/null   # the value really arrived tracked
  [ "$(bash "$REPO_ROOT/bin/workspace.sh" resolve --repo "$c")" = T ]               # and this workspace is the one that resolves

  # Shape mode: executes nothing, so nothing here should touch the filesystem
  # outside the workspace at all.
  run bash "$CHECK" --workspace "$cw" --repo "$c" </dev/null
  echo "shape: status=$status"
  echo "$output"
  [ "$(cat "$victim")" = "$before" ]

  # Run mode, and the relative call shape the skills actually use.
  run bash "$CHECK" --run --workspace "$cw" --repo "$c" </dev/null
  echo "run: status=$status"
  echo "$output"
  [ "$(cat "$victim")" = "$before" ]

  ( cd "$c" && run bash "$CHECK" --workspace ".harmonia/tasks/T" --repo "." </dev/null )
  [ "$(cat "$victim")" = "$before" ]
}

@test "an unresolvable base-ref still digests as the empty diff rather than failing the gate" {
  # The accept side of the guard above, and the reason it may not simply refuse:
  # `mint` writes `ref: none` when `git rev-parse HEAD` fails, so a hand-made or
  # minted workspace in a NON-git tree carries an unresolvable base by design.
  # Today that yields the empty-diff digest because `git diff none` fails and
  # produces no output; the fix must keep that byte-identical, not turn a
  # shipped shape into a gate failure.
  local ng="$BATS_TEST_TMPDIR/bv-nogit" ws
  ws="$ng/.harmonia/tasks/2026-08-01-hand"
  mkdir -p "$ws/receipts"
  printf 'ref: none\n' > "$ws/base-ref"
  local ok="$BATS_TEST_TMPDIR/BV-OK"; rm -f "$ok"
  cat > "$ws/scope.md" <<EOF
## Success Criteria
- run: touch "$ok" && echo fine
EOF
  run bash "$CHECK" --run --workspace "$ws" --repo "$ng" </dev/null
  echo "status=$status"
  echo "$output"
  [ "$status" -eq 0 ]
  [ -e "$ok" ]
  [[ "$output" == *"check-criteria: OK"* ]]
  # e3b0c442... is sha256 of the empty input: the digest this shape has always
  # recorded. Pinned as a literal so a fix that quietly substitutes some other
  # constant is red here.
  local empty; empty="$(printf '' | sha256sum | awk '{print $1}')"
  [ "$(jq -r .diff_digest "$ws/receipts/criteria-run.json")" = "$empty" ]
}

@test "the provenance guard fails closed when git answers wrongly rather than not at all" {
  # B2, round 3. Round 2 closed the seven triggers where git FAILS. These are the
  # ones where git SUCCEEDS and answers wrongly, plus the two filesystem shapes
  # the walk steps over. Delivery is by copy rather than clone throughout, and
  # that is honest rather than incidental: a .git path cannot be tracked and
  # clone writes its own config and index, so none of these arrive by `git clone`
  # - they arrive by archive, tarball, rsync or mount, which is the delivery
  # SECURITY.md already names as carrying .git. Three of them need no adversary
  # at all: an interrupted operation produces them.
  local src="$BATS_TEST_TMPDIR/fw-src"
  local id=2026-01-01-innocuous
  local sent="$BATS_TEST_TMPDIR/FW-SENTINEL"
  mkdir -p "$src/.harmonia/tasks/$id/receipts"
  printf 'x\n' > "$src/README.md"
  cat > "$src/.harmonia/tasks/$id/scope.md" <<EOF
## Success Criteria
- run: touch "$sent" && echo owned
EOF
  git -C "$src" init -q
  git -C "$src" add -A -f
  git -C "$src" -c user.email=t@t -c user.name=t commit -qm x

  # <label> <tamper-fn>: fresh copy per cell, so cells cannot contaminate.
  fw_probe() {
    local label="$1" tamper="$2" t="$BATS_TEST_TMPDIR/fw-$1"
    rm -rf "$t"; cp -a "$src" "$t"
    "$tamper" "$t"
    rm -f "$sent"
    run bash "$CHECK" --run --workspace "$t/.harmonia/tasks/$id" --repo "$t" </dev/null
    echo "--- $label: status=$status"
    echo "$output"
    [ ! -e "$sent" ]
    [ "$status" -ne 0 ]
    [[ "$output" != *"check-criteria: OK"* ]]
  }

  t_none()      { :; }
  t_bare()      { git -C "$1" config core.bare true; }
  t_worktree()  { git -C "$1" config core.worktree /tmp; }
  t_noindex()   { rm -f "$1/.git/index"; }
  t_badindex()  { printf 'GARBAGE' > "$1/.git/index"; }
  t_dangling()  { rm -rf "$1/.git"; ln -s /nonexistent-git-target "$1/.git"; }
  t_looping()   { rm -rf "$1/.git"; ln -s .git "$1/.git"; }

  fw_probe control  t_none        # the copy itself is already refused
  fw_probe bare     t_bare
  fw_probe worktree t_worktree
  fw_probe noindex  t_noindex
  fw_probe badindex t_badindex
  # A dangling or looping .git moves to the ACCEPT side under scope.md's round-9
  # narrowing: git opens no repository, so nothing carries the payload. Asserted,
  # not merely unpinned.
  fw_accepts() {   # <label> <tamper-fn>
    local t="$BATS_TEST_TMPDIR/fwa-$1"
    rm -rf "$t"; cp -a "$src" "$t"
    "$2" "$t"
    rm -f "$sent"
    run bash "$CHECK" --run --workspace "$t/.harmonia/tasks/$id" --repo "$t" </dev/null
    echo "--- $1 (retired, must accept): status=$status"
    echo "$output"
    [ "$status" -eq 0 ]
    [ -e "$sent" ]
  }
  fw_accepts dangling t_dangling
  fw_accepts looping  t_looping
  if [ "$(id -u)" -ne 0 ]; then
    t_unreadable() { chmod 000 "$1/.git/index"; }
    fw_probe unreadable t_unreadable
  fi
}

@test "a legitimate workspace is not called tracked when git merely cannot answer" {
  # The other direction of the same predicate, and the reason fail-closed needs a
  # separate message rather than reusing the provenance one. This workspace is
  # minted, gitignored and has never been tracked; a corrupt index must not let
  # it verify, and must not tell the developer their own marker "arrived with the
  # repository", which is false and sends them to a remedy that cannot work.
  local L="$BATS_TEST_TMPDIR/fw-legit"
  mkdir -p "$L"
  git -C "$L" init -q
  printf 'a\n' > "$L/f.sh"
  git -C "$L" add -A
  git -C "$L" -c user.email=t@t -c user.name=t commit -qm b
  local ws; ws="$(bash "$REPO_ROOT/bin/workspace.sh" mint --repo "$L" --slug mine)"
  bash "$REPO_ROOT/bin/workspace.sh" accept --repo "$L" --task "$ws"

  run bash "$REPO_ROOT/bin/workspace.sh" verify-acceptance --repo "$L" --task "$ws"
  [ "$status" -eq 0 ]                      # honest baseline: it verifies

  bash "$REPO_ROOT/bin/workspace.sh" record-test-hashes --repo "$L" --task "$ws"
  run bash "$REPO_ROOT/bin/workspace.sh" verify-test-hashes --repo "$L" --task "$ws"
  [ "$status" -eq 0 ]                      # honest baseline for the manifest too

  printf 'GARBAGE' > "$L/.git/index"
  run bash "$REPO_ROOT/bin/workspace.sh" verify-acceptance --repo "$L" --task "$ws"
  echo "corrupt-index acceptance: status=$status"
  echo "$output"
  [ "$status" -ne 0 ]                      # fails closed
  [[ "$output" != *"acceptance verified"* ]]
  [[ "$output" != *"arrived with the repository"* ]]   # and does not lie about why

  # The manifest carries the identical pair of refusals and is reached by a
  # separate branch, so it needs its own cell rather than inheriting this one.
  run bash "$REPO_ROOT/bin/workspace.sh" verify-test-hashes --repo "$L" --task "$ws"
  echo "corrupt-index hashes: status=$status"
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" != *"test hashes verified"* ]]
  [[ "$output" != *"arrived with the repository"* ]]
}

@test "the criteria gate refuses a base-ref that resolves outside the workspace" {
  # M1's third reader site. accept and reject are covered in workspace.bats; this
  # is the one that receipts a digest rather than writing a marker, so a redirect
  # makes the receipt attest to a base the caller never named.
  local cell="$BATS_TEST_TMPDIR/cbref" real
  mkdir -p "$cell/out"; real="$cell/r"; mkdir -p "$real"
  git -C "$real" init -q
  printf 'a\n' > "$real/f.sh"
  git -C "$real" add -A
  git -C "$real" -c user.email=t@t -c user.name=t commit -qm b
  local ws="$real/.harmonia/tasks/T"; mkdir -p "$ws/receipts"
  cat > "$ws/scope.md" <<'EOS'
## Success Criteria
- run: true
EOS
  printf 'ref: %s\n' "$(git -C "$real" rev-parse HEAD)" > "$cell/out/base-ref"
  ln -s "$cell/out/base-ref" "$ws/base-ref"
  run bash "$CHECK" --workspace "$ws" --repo "$real" </dev/null
  echo "status=$status"
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" != *"check-criteria: OK"* ]]
  [ ! -f "$ws/receipts/check-criteria.json" ]   # and no receipt claiming the run happened
}

@test "the receipt audit refuses when git cannot be asked where the receipts came from" {
  # The undecidable branch of the audit's provenance check. A corrupt index is
  # not evidence that a receipt was carried, and it is not evidence that it was
  # not - so the audit refuses and says which of the two it is.
  local L="$BATS_TEST_TMPDIR/au"
  mkdir -p "$L"
  git -C "$L" init -q
  printf 'a\n' > "$L/f.sh"
  git -C "$L" add -A
  git -C "$L" -c user.email=t@t -c user.name=t commit -qm b
  local id; id="$(bash "$REPO_ROOT/bin/workspace.sh" mint --repo "$L" --slug au)"
  local ws="$L/.harmonia/tasks/$id"
  printf 'notes\n' > "$L/notes.md"
  bash "$REPO_ROOT/bin/coverage/gate.sh" --repo "$L" --workspace "$ws" >/dev/null 2>&1
  [ -s "$ws/receipts/coverage.json" ]
  run bash "$REPO_ROOT/bin/coverage/gate.sh" --verify-receipts --repo "$L" --workspace "$ws"
  [ "$status" -eq 0 ]                       # honest baseline

  printf 'GARBAGE' > "$L/.git/index"
  run bash "$REPO_ROOT/bin/coverage/gate.sh" --verify-receipts --repo "$L" --workspace "$ws"
  echo "corrupt index: status=$status"
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" != *"receipts verified"* ]]
  [[ "$output" != *"tracked in git"* ]]     # not a claim it was carried
}

@test "a nested repository does not shadow an outer one that carries the file" {
  # Round 4 B1. The provenance walk used to stop at the FIRST .git at or above
  # the workspace. One `git init` inside a delivered tree is then the whole
  # attack: the nested repo answers "not tracked" perfectly truthfully, because
  # the payload is tracked in the OUTER one, and the walk never asks the outer.
  # Not caught by requiring the resolved toplevel to equal the directory the walk
  # found - the nested repo's toplevel legitimately IS that directory.
  local src="$BATS_TEST_TMPDIR/nst-src"
  local id=2026-01-01-innocuous
  local sent="$BATS_TEST_TMPDIR/NST-SENTINEL"
  mkdir -p "$src/.harmonia/tasks/$id/receipts"
  printf 'x\n' > "$src/README.md"
  cat > "$src/.harmonia/tasks/$id/scope.md" <<EOF
## Success Criteria
- run: touch "$sent" && echo owned
EOF
  git -C "$src" init -q
  git -C "$src" add -A -f
  git -C "$src" -c user.email=t@t -c user.name=t commit -qm x

  # Every level between the payload and the real repository root is a position.
  for pos in ".harmonia" ".harmonia/tasks" ".harmonia/tasks/$id"; do
    local t="$BATS_TEST_TMPDIR/nst-$(echo "$pos" | tr / _)"
    rm -rf "$t"; cp -a "$src" "$t"
    git -C "$t/$pos" init -q
    rm -f "$sent"
    run bash "$CHECK" --run --workspace "$t/.harmonia/tasks/$id" --repo "$t" </dev/null
    echo "--- nested .git at $pos: status=$status"
    echo "$output"
    [ ! -e "$sent" ]
    [ "$status" -ne 0 ]
    [[ "$output" != *"check-criteria: OK"* ]]
  done

  # The control: without the nested repo this delivery is already refused, so a
  # build that refuses everything cannot pass the cells above by accident.
  local c="$BATS_TEST_TMPDIR/nst-control"
  rm -rf "$c"; cp -a "$src" "$c"
  rm -f "$sent"
  run bash "$CHECK" --run --workspace "$c/.harmonia/tasks/$id" --repo "$c" </dev/null
  [ ! -e "$sent" ]
  [ "$status" -ne 0 ]

  # And the accept side of the same walk: a workspace inside a repository that
  # does NOT carry it must still run, even though an outer repository exists.
  local ok="$BATS_TEST_TMPDIR/NST-OK"; rm -f "$ok"
  local L="$BATS_TEST_TMPDIR/nst-legit"
  mkdir -p "$L"
  git -C "$L" init -q
  printf 'a\n' > "$L/f.sh"
  git -C "$L" add -A
  git -C "$L" -c user.email=t@t -c user.name=t commit -qm b
  local lw; lw="$L/.harmonia/tasks/2026-08-01-hand"
  mkdir -p "$lw"
  cat > "$lw/scope.md" <<EOF
## Success Criteria
- run: touch "$ok" && echo fine
EOF
  run bash "$CHECK" --run --workspace "$lw" --repo "$L" </dev/null
  echo "accept: status=$status"
  echo "$output"
  [ "$status" -eq 0 ]
  [ -e "$ok" ]
}

@test "a repository whose HEAD cannot be read is not consulted" {
  # Round 4 B2. The HEAD consultation added last round never tested git's exit
  # status, so a failure with empty stdout read as "the file is yours" - the same
  # "a failure wearing the shape of an answer" defect the index branch one line
  # above had already fixed. Neither cell needs an adversary: an interrupted copy
  # produces both.
  local src="$BATS_TEST_TMPDIR/hd-src"
  local id=2026-01-01-innocuous
  local sent="$BATS_TEST_TMPDIR/HD-SENTINEL"
  mkdir -p "$src/.harmonia/tasks/$id/receipts"
  printf 'x\n' > "$src/README.md"
  cat > "$src/.harmonia/tasks/$id/scope.md" <<EOF
## Success Criteria
- run: touch "$sent" && echo owned
EOF
  git -C "$src" init -q
  git -C "$src" add -A -f
  git -C "$src" -c user.email=t@t -c user.name=t commit -qm x

  # RETIRED by scope.md's round-9 narrowing. The property is now the index or the
  # tree of the commit CHECKED OUT, and both cells below are repositories with no
  # readable checked-out commit - so the property has nothing to say about them and
  # they are accepted. Reaching a verdict here needed a pristine-versus-damaged
  # discriminator, and every version of that discriminator was wrong in one
  # direction or the other: an empty object database was fooled by a removed pack
  # index, and counting commits refused an ordinary repository between `git add`
  # and its first commit. Asserted on the accept side so the retirement is visible.
  hd_probe() {   # <label> <tamper>
    local t="$BATS_TEST_TMPDIR/hd-$1"
    rm -rf "$t"; cp -a "$src" "$t"
    rm -f "$t/.git/index"          # force the HEAD path: the index has no answer
    "$2" "$t"
    rm -f "$sent"
    run bash "$CHECK" --run --workspace "$t/.harmonia/tasks/$id" --repo "$t" </dev/null
    echo "--- $1 (retired, must accept): status=$status"
    echo "$output"
    [ -e "$sent" ]
    [ "$status" -eq 0 ]
  }

  t_notree() {   # the commit is reachable but its tree object is gone: ls-tree exits 128, stdout empty
    local tree; tree="$(git -C "$1" rev-parse HEAD^{tree})"
    rm -f "$1/.git/objects/${tree:0:2}/${tree:2}"
  }
  t_norefs() { rm -rf "$1/.git/refs/heads" "$1/.git/packed-refs"; }   # rev-parse HEAD exits 1, exactly as a repo with no commits does

  hd_probe notree t_notree
  hd_probe norefs t_norefs

  # The accept side that makes those two hard: a repository with no commits also
  # fails to resolve HEAD, and it is legitimate. What separates them is that a
  # pristine repository has NO OBJECTS, so it cannot have carried anything.
  local ok="$BATS_TEST_TMPDIR/HD-OK"; rm -f "$ok"
  local F="$BATS_TEST_TMPDIR/hd-fresh"
  mkdir -p "$F/.harmonia/tasks/2026-08-01-hand"
  git -C "$F" init -q
  cat > "$F/.harmonia/tasks/2026-08-01-hand/scope.md" <<EOF
## Success Criteria
- run: touch "$ok" && echo fine
EOF
  run bash "$CHECK" --run --workspace "$F/.harmonia/tasks/2026-08-01-hand" --repo "$F" </dev/null
  echo "fresh repo: status=$status"
  echo "$output"
  [ "$status" -eq 0 ]
  [ -e "$ok" ]
}

@test "a colon-leading directory name does not turn the provenance guard off" {
  # Round 6 B1. The walk translates the path as it climbs, and the result goes to
  # git in PATHSPEC position. A leading `:` is pathspec magic, so git answers
  # about something else entirely: ls-files rc=1 and ls-tree rc=0-empty, which is
  # exactly the pair that reads as "not carried". One directory name, on a plain
  # clone, and every provenance guard in the system is off.
  local h="$BATS_TEST_TMPDIR/cl-h" c="$BATS_TEST_TMPDIR/cl-c"
  local sent="$BATS_TEST_TMPDIR/CL-SENTINEL"
  mkdir -p "$h/:x/.harmonia/tasks/T/receipts"
  printf 'x\n' > "$h/README.md"
  cat > "$h/:x/.harmonia/tasks/T/scope.md" <<EOF
## Success Criteria
- run: touch "$sent" && echo owned
EOF
  git -C "$h" init -q
  git -C "$h" add -A -f
  git -C "$h" -c user.email=t@t -c user.name=t commit -qm x
  git clone -q "$h" "$c"
  git -C "$c" ls-files --error-unmatch -- ':(literal):x/.harmonia/tasks/T/scope.md' >/dev/null

  rm -f "$sent"
  ( cd "$c" && run bash "$CHECK" --run --workspace ":x/.harmonia/tasks/T" --repo "." </dev/null
    echo "status=$status"
    echo "$output" )
  [ ! -e "$sent" ]

  # The control: the identical fixture with an ordinary directory name is already
  # refused, so a refuse-everything build cannot pass the cell above by accident.
  local h2="$BATS_TEST_TMPDIR/cl-h2" c2="$BATS_TEST_TMPDIR/cl-c2"
  local sent2="$BATS_TEST_TMPDIR/CL-SENTINEL2"
  mkdir -p "$h2/x/.harmonia/tasks/T/receipts"
  printf 'x\n' > "$h2/README.md"
  cat > "$h2/x/.harmonia/tasks/T/scope.md" <<EOF
## Success Criteria
- run: touch "$sent2" && echo owned
EOF
  git -C "$h2" init -q
  git -C "$h2" add -A -f
  git -C "$h2" -c user.email=t@t -c user.name=t commit -qm x
  git clone -q "$h2" "$c2"
  rm -f "$sent2"
  ( cd "$c2" && run bash "$CHECK" --run --workspace "x/.harmonia/tasks/T" --repo "." </dev/null )
  [ ! -e "$sent2" ]
}

@test "a repository between git add and its first commit is not called undecidable" {
  # Round 6 B2, the false-refusal half and the one with no adversary. `git add`
  # writes blobs, so an ordinary repository after `add` and before its first
  # commit has objects and no resolvable HEAD - which the object-count
  # discriminator read as "damaged". Three of the four consumers refused, each
  # telling the user to make `git status` work when `git status` already exits 0.
  local L="$BATS_TEST_TMPDIR/pre-commit"
  mkdir -p "$L/.harmonia/tasks/2026-08-01-hand"
  git -C "$L" init -q
  printf 'a\n' > "$L/f.sh"
  git -C "$L" add -A                       # blobs on disk, still no commit
  ( cd "$L" && git status >/dev/null )     # the state the refusal told users to repair
  local ok="$BATS_TEST_TMPDIR/PRE-OK"; rm -f "$ok"
  cat > "$L/.harmonia/tasks/2026-08-01-hand/scope.md" <<EOF
## Success Criteria
- run: touch "$ok" && echo fine
EOF
  run bash "$CHECK" --run --workspace "$L/.harmonia/tasks/2026-08-01-hand" --repo "$L" </dev/null
  echo "status=$status"
  echo "$output"
  [ "$status" -eq 0 ]
  [ -e "$ok" ]

  # An orphan branch is the same shape with history present.
  local O="$BATS_TEST_TMPDIR/orphan"
  mkdir -p "$O/.harmonia/tasks/2026-08-01-hand"
  git -C "$O" init -q
  printf 'a\n' > "$O/f.sh"
  git -C "$O" add -A
  git -C "$O" -c user.email=t@t -c user.name=t commit -qm b
  git -C "$O" checkout -q --orphan fresh
  local ok2="$BATS_TEST_TMPDIR/ORPHAN-OK"; rm -f "$ok2"
  cat > "$O/.harmonia/tasks/2026-08-01-hand/scope.md" <<EOF
## Success Criteria
- run: touch "$ok2" && echo fine
EOF
  run bash "$CHECK" --run --workspace "$O/.harmonia/tasks/2026-08-01-hand" --repo "$O" </dev/null
  echo "orphan: status=$status"
  echo "$output"
  [ "$status" -eq 0 ]
  [ -e "$ok2" ]
}

@test "a broken repository in an unrelated ancestor does not refuse legitimate work" {
  # Round 6 M7. The walk climbs to / so that a nested repository cannot shadow the
  # one that carries the file. The cost, unbounded until now: any ancestor with an
  # unusable .git - not the delivery, just something above your checkout - made
  # every run refuse, with the same message telling you to repair a repository
  # that is not yours.
  local parent="$BATS_TEST_TMPDIR/anc"
  local L="$parent/project"
  mkdir -p "$L/.harmonia/tasks/2026-08-01-hand"
  git -C "$L" init -q
  printf 'a\n' > "$L/f.sh"
  git -C "$L" add -A
  git -C "$L" -c user.email=t@t -c user.name=t commit -qm b
  local ok="$BATS_TEST_TMPDIR/ANC-OK"; rm -f "$ok"
  cat > "$L/.harmonia/tasks/2026-08-01-hand/scope.md" <<EOF
## Success Criteria
- run: touch "$ok" && echo fine
EOF
  mkdir -p "$parent/.git"                  # an ancestor .git that git cannot use
  run bash "$CHECK" --run --workspace "$L/.harmonia/tasks/2026-08-01-hand" --repo "$L" </dev/null
  echo "status=$status"
  echo "$output"
  [ "$status" -eq 0 ]
  [ -e "$ok" ]

  # And the nested-repository attack the walk exists for stays closed: here the
  # unusable repository is the NEAREST one, which is the delivery itself.
  local sent="$BATS_TEST_TMPDIR/ANC-SENT"
  local h="$BATS_TEST_TMPDIR/anc-h"
  mkdir -p "$h/.harmonia/tasks/T/receipts"
  printf 'x\n' > "$h/README.md"
  cat > "$h/.harmonia/tasks/T/scope.md" <<EOF
## Success Criteria
- run: touch "$sent" && echo owned
EOF
  git -C "$h" init -q
  git -C "$h" add -A -f
  git -C "$h" -c user.email=t@t -c user.name=t commit -qm x
  printf 'GARBAGE' > "$h/.git/index"       # the delivery's own repository cannot answer
  rm -f "$sent"
  run bash "$CHECK" --run --workspace "$h/.harmonia/tasks/T" --repo "$h" </dev/null
  echo "nearest-unusable: status=$status"
  echo "$output"
  [ ! -e "$sent" ]
  [ "$status" -ne 0 ]
}

@test "clearing CDPATH before the first cd is what stops a decoy hijacking the guard" {
  # Round 6 M4. `cd` searches CDPATH before the literal path and lands in the
  # first match, so a decoy holding the same relative workspace path takes the
  # guard somewhere else entirely - it inspects the decoy, finds no repository,
  # and answers "yours". This reds if the unset ever moves back below the cd,
  # which is the exact defect it was written to fix and which nothing pinned.
  local h="$BATS_TEST_TMPDIR/cd-h" c="$BATS_TEST_TMPDIR/cd-c"
  local id=2026-01-01-innocuous
  local sent="$BATS_TEST_TMPDIR/CD-SENTINEL"
  mkdir -p "$h/.harmonia/tasks/$id/receipts"
  printf 'x\n' > "$h/README.md"
  cat > "$h/.harmonia/tasks/$id/scope.md" <<EOF
## Success Criteria
- run: touch "$sent" && echo owned
EOF
  git -C "$h" init -q
  git -C "$h" add -A -f
  git -C "$h" -c user.email=t@t -c user.name=t commit -qm x
  git clone -q "$h" "$c"

  # The decoy: same relative path, not a repository, first on CDPATH.
  local decoy="$BATS_TEST_TMPDIR/cd-decoy"
  mkdir -p "$decoy/.harmonia/tasks/$id"
  printf '## Success Criteria\n- run: true\n' > "$decoy/.harmonia/tasks/$id/scope.md"

  for form in prefix export; do
    rm -f "$sent"
    if [ "$form" = prefix ]; then
      ( cd "$c" && CDPATH="$decoy" bash "$CHECK" --run --workspace ".harmonia/tasks/$id" --repo "." </dev/null >/dev/null 2>&1 ) || true
    else
      ( cd "$c" && export CDPATH="$decoy" && bash "$CHECK" --run --workspace ".harmonia/tasks/$id" --repo "." </dev/null >/dev/null 2>&1 ) || true
    fi
    echo "--- CDPATH $form"
    [ ! -e "$sent" ]
  done
}

@test "run mode refuses a base-ref that arrived with the repository" {
  # The criteria gate's half of the same finding: its receipt attests to a digest
  # taken against this base, so a repository supplying it decides what the receipt
  # claims. Run mode only - shape mode executes nothing, and a rule before the
  # mode split refuses work no one can run, which C4's over-reach probe measures.
  local h="$BATS_TEST_TMPDIR/cbr-h" c="$BATS_TEST_TMPDIR/cbr-c"
  mkdir -p "$h/.harmonia/tasks/T/receipts"
  printf 'a\n' > "$h/f.sh"
  git -C "$h" init -q
  git -C "$h" add -A -f
  git -C "$h" -c user.email=t@t -c user.name=t commit -qm b
  printf 'ref: %s\n' "$(git -C "$h" rev-parse HEAD)" > "$h/.harmonia/tasks/T/base-ref"
  git -C "$h" add -A -f
  git -C "$h" -c user.email=t@t -c user.name=t commit -qm p
  git clone -q "$h" "$c"
  # scope.md is written AFTER the clone, so it is the developer's: this cell has
  # to reach the base-ref question, and a carried scope.md refuses one step
  # earlier and would leave the branch under test unexercised.
  printf '## Success Criteria\n- run: true\n' > "$c/.harmonia/tasks/T/scope.md"

  run bash "$CHECK" --run --workspace "$c/.harmonia/tasks/T" --repo "$c" </dev/null
  echo "run: status=$status"
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" != *"check-criteria: OK"* ]]

  # Shape mode must still exit 0: it executes nothing, and refusing there is the
  # over-reach C4 pins.
  run bash "$CHECK" --workspace "$c/.harmonia/tasks/T" --repo "$c" </dev/null
  echo "shape: status=$status"
  echo "$output"
  [ "$status" -eq 0 ]
}
