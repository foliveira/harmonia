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
