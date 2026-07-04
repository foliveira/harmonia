#!/usr/bin/env bats
# U7 coverage-gate tests - diff-cover adoption path, markers, receipts, routing.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export PATH="$PATH:$HOME/.local/bin"
  GATE="$REPO_ROOT/bin/coverage/gate.sh"

  R="$BATS_TEST_TMPDIR/target"
  mkdir -p "$R"
  git -C "$R" init -q
  git -C "$R" checkout -qb main
  printf 'line1\nline2\nline3\nline4\n' > "$R/app.ts"
  git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm base
  BASE="$(git -C "$R" rev-parse HEAD)"
  printf 'line1\nCHANGED2\nline3\nCHANGED4\nNEW5\n' > "$R/app.ts"

  WS="$R/.harmonia/tasks/2026-07-02-covfix"
  mkdir -p "$WS/receipts"
  echo "ref: $BASE" > "$WS/base-ref"
}

write_ts_cov() { # covered: 1,2(branch 50%),3 ; uncovered: 4,5
  cat > "$R/cov.xml" <<XML
<?xml version="1.0" ?>
<coverage lines-valid="5" lines-covered="3" line-rate="0.6" branch-rate="0.5" version="1.9" timestamp="1">
  <sources><source>$R/</source></sources>
  <packages><package name="app" line-rate="0.6" branch-rate="0.5">
    <classes><class name="app" filename="app.ts" line-rate="0.6" branch-rate="0.5">
      <lines>
        <line number="1" hits="1"/>
        <line number="2" hits="1" branch="true" condition-coverage="50% (1/2)"/>
        <line number="3" hits="1"/>
        <line number="4" hits="0"/>
        <line number="5" hits="0"/>
      </lines>
    </class></classes>
  </package></packages>
</coverage>
XML
}

@test "uncovered changed TS lines fail the gate and land in the workspace report" {
  write_ts_cov
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" --report "$R/cov.xml" --lang ts
  [ "$status" -eq 1 ]
  [[ "$output" == *"app.ts"* ]]
  grep -q "app.ts" "$WS/gate-report.md"
  grep -q "4" "$WS/gate-report.md"
}

@test "a changed covered line with an uncovered branch is flagged for branch-bearing formats" {
  write_ts_cov
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" --report "$R/cov.xml" --lang ts
  grep -qi "branch" "$WS/gate-report.md"
  grep -Eq "app.ts(.*)2" "$WS/gate-report.md"
}

@test "go cobertura maps covered lines correctly across multiple files, branches unmeasured" {
  printf 'a1\na2\n' > "$R/one.go"; printf 'b1\nb2\n' > "$R/two.go"
  git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm gofiles
  GB="$(git -C "$R" rev-parse HEAD)"
  printf 'a1\nA2\n' > "$R/one.go"; printf 'B1\nb2\n' > "$R/two.go"
  cat > "$R/gocov.xml" <<'XML'
<?xml version="1.0" ?>
<coverage line-rate="0.5" version="1.9" timestamp="1">
  <packages><package name="p" line-rate="0.5">
    <classes>
      <class name="one" filename="one.go" line-rate="0.5">
        <lines><line number="1" hits="1"/><line number="2" hits="1"/></lines>
      </class>
      <class name="two" filename="two.go" line-rate="0.5">
        <lines><line number="1" hits="0"/><line number="2" hits="1"/></lines>
      </class>
    </classes>
  </package></packages>
</coverage>
XML
  run bash "$GATE" --repo "$R" --base "$GB" --workspace "$WS" --report "$R/gocov.xml" --lang go
  [ "$status" -eq 1 ]
  [[ "$output" == *"two.go"* ]]
  [[ "$output" != *"one.go"* ]]
  grep -qi "branches unmeasured" "$WS/gate-report.md"
}

@test "kcov absent yields the distinct cannot-measure exit, never a false pass" {
  printf '#!/bin/sh\necho hi\n' > "$R/tool.sh"
  git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm sh
  SB="$(git -C "$R" rev-parse HEAD)"
  printf '#!/bin/sh\necho changed\n' > "$R/tool.sh"
  run env HARMONIA_KCOV=/nonexistent-kcov bash "$GATE" --repo "$R" --base "$SB" --workspace "$WS"
  [ "$status" -eq 4 ]
  [[ "$output" == *"cannot measure"* ]]
}

@test "a new file absent from coverage data counts as uncovered" {
  write_ts_cov
  printf 'brand\nnew\n' > "$R/newfile.ts"
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" --report "$R/cov.xml" --lang ts
  [ "$status" -eq 1 ]
  [[ "$output" == *"newfile.ts"* ]]
}

@test "an unsupported-language diff exits cannot-measure and the report marks it advisory" {
  git -C "$R" checkout -q -- app.ts
  printf 'x = 1\n' > "$R/script.py"
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ "$status" -eq 4 ]
  grep -qi "advisory" "$WS/gate-report.md"
  grep -q "script.py" "$WS/gate-report.md"
}

@test "marker-exempted lines pass and surface in the exemptions-honored section" {
  printf 'line1\nCHANGED2\nline3\nCHANGED4 // harmonia:exempt unreachable on this platform\nNEW5 // harmonia:exempt boot path, no test harness\n' > "$R/app.ts"
  write_ts_cov
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" --report "$R/cov.xml" --lang ts --no-branch
  [ "$status" -eq 0 ]
  grep -qi "Exemptions honored" "$WS/gate-report.md"
  grep -q "unreachable on this platform" "$WS/gate-report.md"
}

@test "a marker without a justification fails validation" {
  printf 'line1\nCHANGED2\nline3\nCHANGED4 // harmonia:exempt\nNEW5\n' > "$R/app.ts"
  write_ts_cov
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" --report "$R/cov.xml" --lang ts --no-branch
  [ "$status" -eq 2 ]
  [[ "$output" == *"justification"* ]]
}

@test "record-override appends exactly one well-formed audit-log entry" {
  run bash "$GATE" --repo "$R" --record-override "app.ts|4-5|flaky platform API" --workspace "$WS"
  [ "$status" -eq 0 ]
  L="$R/.harmonia/coverage-exemptions.yaml"
  [ -f "$L" ]
  [ "$(grep -c "flaky platform API" "$L")" -eq 1 ]
  grep -q "path: app.ts" "$L"
  grep -q "task: 2026-07-02-covfix" "$L"
}

@test "receipt verification fails on a stale diff digest" {
  write_ts_cov
  bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" --report "$R/cov.xml" --lang ts --no-branch >/dev/null || true
  echo 'drift' >> "$R/app.ts"
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" --verify-receipts
  [ "$status" -eq 1 ]
  [[ "$output" == *"stale"* ]]
}

@test "an unknown argument exits with usage" {
  run bash "$GATE" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown argument"* ]]
}

@test "self mode parses and degrades to cannot-measure when kcov is hidden" {
  # --self resolves its repo from the script's own location, so run a copy of
  # the gate from inside the sandbox repo: the premise (an uncommitted
  # executable bash change, kcov missing) holds by construction there,
  # independent of this repo's working-tree state.
  git -C "$R" checkout -q -- app.ts
  mkdir -p "$R/bin/coverage"
  cp "$REPO_ROOT/bin/coverage/gate.sh" "$REPO_ROOT/bin/coverage/bash.sh" "$R/bin/coverage/"
  printf '#!/usr/bin/env bash\necho one\n' > "$R/tool.sh"
  chmod +x "$R/tool.sh"
  git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm selfbase
  printf '#!/usr/bin/env bash\necho two\n' > "$R/tool.sh"
  run env HARMONIA_KCOV=/nonexistent-kcov bash "$R/bin/coverage/gate.sh" --self --base HEAD
  [ "$status" -eq 4 ]
}

@test "receipt verification passes on a fresh digest" {
  write_ts_cov
  bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" --report "$R/cov.xml" --lang ts --no-branch >/dev/null || true
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" --verify-receipts
  [ "$status" -eq 0 ]
  [[ "$output" == *"receipts verified"* ]]
}

@test "a bats-only diff owes no coverage" {
  git -C "$R" checkout -q -- app.ts
  printf '#!/usr/bin/env bats\n' > "$R/new.bats"
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ "$status" -eq 0 ]
}

@test "a report rooted below the repo still matches via derived src-roots" {
  mkdir -p "$R/bin/coverage"
  printf 'l1\nl2\n' > "$R/bin/coverage/x.sh"
  git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm sub
  SUBB="$(git -C "$R" rev-parse HEAD)"
  printf 'l1\nL2\n' > "$R/bin/coverage/x.sh"
  cat > "$R/sub.xml" <<XML
<?xml version="1.0" ?>
<coverage line-rate="0.5" version="1.9" timestamp="1">
  <sources><source>$R/bin/</source></sources>
  <packages><package name="p" line-rate="0.5"><classes>
    <class name="x" filename="coverage/x.sh" line-rate="0.5">
      <lines><line number="1" hits="1"/><line number="2" hits="0"/></lines>
    </class>
  </classes></package></packages>
</coverage>
XML
  run bash "$GATE" --repo "$R" --base "$SUBB" --workspace "$WS" --report "$R/sub.xml" --lang bash
  [ "$status" -eq 1 ]
  [[ "$output" == *"bin/coverage/x.sh:2"* ]]
  [[ "$output" != *"absent from coverage data"* ]]
}

@test "an untracked file with branch data gets the branch post-pass" {
  git -C "$R" checkout -q -- app.ts
  printf 'n1\nn2\n' > "$R/fresh.ts"
  cat > "$R/br.xml" <<XML
<?xml version="1.0" ?>
<coverage line-rate="1.0" branch-rate="0.5" version="1.9" timestamp="1">
  <sources><source>$R/</source></sources>
  <packages><package name="p" line-rate="1.0" branch-rate="0.5"><classes>
    <class name="f" filename="fresh.ts" line-rate="1.0">
      <lines>
        <line number="1" hits="1"/>
        <line number="2" hits="1" branch="true" condition-coverage="50% (1/2)"/>
      </lines>
    </class>
  </classes></package></packages>
</coverage>
XML
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" --report "$R/br.xml" --lang ts
  [ "$status" -eq 1 ]
  grep -q "uncovered branch: fresh.ts:2" "$WS/gate-report.md"
}

@test "a yaml-only diff routes to validation with no coverage requirement" {
  git -C "$R" checkout -q -- app.ts
  printf 'key: value\n' > "$R/config.yaml"
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"validation"* ]]
}

@test "files under tests/ are fixtures or suites and owe no coverage" {
  git -C "$R" checkout -q -- app.ts
  mkdir -p "$R/tests/fixtures"
  printf 'package f\n' > "$R/tests/fixtures/seed.go"
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ "$status" -eq 0 ]
}

@test "an unresolvable base ref exits cannot-measure, names the ref, writes no receipt" {
  run bash "$GATE" --repo "$R" --base "no-such-ref" --workspace "$WS"
  [ "$status" -eq 4 ]
  [[ "$output" == *"cannot measure"* ]]
  [[ "$output" == *"no-such-ref"* ]]
  [ ! -f "$WS/receipts/coverage.json" ]
  # a well-formed sha absent from the object db must not slip through either
  run bash "$GATE" --repo "$R" --base "0123456789012345678901234567890123456789" --workspace "$WS"
  [ "$status" -eq 4 ]
  [ ! -f "$WS/receipts/coverage.json" ]
}

@test "a --base in the base-ref file format (ref: <sha>) gates identically to the bare sha" {
  write_ts_cov
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" --report "$R/cov.xml" --lang ts
  bare_status="$status"; bare_output="$output"
  [ "$bare_status" -eq 1 ]
  run bash "$GATE" --repo "$R" --base "ref: $BASE" --workspace "$WS" --report "$R/cov.xml" --lang ts
  [ "$status" -eq "$bare_status" ]
  [ "$output" = "$bare_output" ]
}

@test "with --workspace and no --base the gate reads the workspace base-ref file" {
  write_ts_cov
  git -C "$R" add app.ts && git -C "$R" -c user.email=t@t -c user.name=t commit -qm drift
  run bash "$GATE" --repo "$R" --workspace "$WS" --report "$R/cov.xml" --lang ts
  [ "$status" -eq 1 ]
  [[ "$output" == *"app.ts"* ]]
  grep -q "base: $BASE" "$WS/gate-report.md"
}

# --- verify-receipts staleness fix (second concern) ------------------------
# check-criteria validates scope.md (code-independent) but its receipt hashes
# the diff at implement-start on a clean tree, so its digest goes code-stale the
# moment implement writes code. verify-receipts must validate check-criteria by
# presence + status: pass, while coverage stays required digest-fresh.

@test "verify-receipts passes a code-stale check-criteria receipt beside a fresh coverage receipt" {
  write_ts_cov
  # fresh coverage receipt: written against the current diff, no drift after
  bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" --report "$R/cov.xml" --lang ts --no-branch >/dev/null || true
  # check-criteria receipt: status pass but a code-stale (empty-tree) digest -
  # exactly the implement-start-on-a-clean-tree situation
  cat > "$WS/receipts/check-criteria.json" <<'JSON'
{
  "gate": "check-criteria",
  "task_id": "2026-07-02-covfix",
  "timestamp": "2026-07-04T00:00:00Z",
  "diff_digest": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "status": "pass"
}
JSON
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" --verify-receipts
  [ "$status" -eq 0 ]
  [[ "$output" == *"receipts verified"* ]]
}

@test "verify-receipts fails a check-criteria receipt whose status is fail" {
  write_ts_cov
  bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" --report "$R/cov.xml" --lang ts --no-branch >/dev/null || true
  cat > "$WS/receipts/check-criteria.json" <<'JSON'
{
  "gate": "check-criteria",
  "task_id": "2026-07-02-covfix",
  "timestamp": "2026-07-04T00:00:00Z",
  "diff_digest": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "status": "fail"
}
JSON
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" --verify-receipts
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not pass"* ]]
}

# Optional hardening beyond criterion 4, owned by the test-engineer. The scope
# requires coverage's integrity guarantee not to weaken; the two tests above do
# not pin that, because check-criteria sorts first and both would still pass a
# `break`-instead-of-`continue` masking bug. This pins the both-present case:
# a passing (code-stale) check-criteria receipt must be silently accepted while
# a stale coverage receipt beside it still fails. It is red-first - today the
# gate flags check-criteria stale (the `!= check-criteria` line fails) - and it
# also catches a fix that masks coverage staleness (the exit-1 line fails).
@test "verify-receipts still fails a stale coverage receipt when a passing check-criteria receipt is present" {
  write_ts_cov
  bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" --report "$R/cov.xml" --lang ts --no-branch >/dev/null || true
  cat > "$WS/receipts/check-criteria.json" <<'JSON'
{
  "gate": "check-criteria",
  "task_id": "2026-07-02-covfix",
  "timestamp": "2026-07-04T00:00:00Z",
  "diff_digest": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "status": "pass"
}
JSON
  echo 'drift' >> "$R/app.ts"   # the coverage receipt is now code-stale
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" --verify-receipts
  [ "$status" -eq 1 ]                        # coverage staleness still fails the run
  [[ "$output" == *"stale"* ]]
  [[ "$output" == *"coverage"* ]]            # it is coverage.json named stale...
  [[ "$output" != *"check-criteria"* ]]      # ...and check-criteria is not (its freshness is skipped)
}
