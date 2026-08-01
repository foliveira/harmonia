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

# F1 follow-up: presence, not just freshness. Since check-criteria is validated
# by status and skipped by the freshness loop, a receipts dir carrying only a
# passing check-criteria certifies a tree where no code-dependent (coverage)
# receipt was ever verified - including the coverage-cannot-measure case that
# writes no coverage.json. verify-receipts must refuse when the loop verified no
# code-dependent receipt. setup() already drifts app.ts off BASE, so this is the
# drifted-tree case: an unmeasured, drifted tree must not be certified.
@test "verify-receipts refuses a receipts dir carrying only a passing check-criteria receipt" {
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
  [ "$status" -eq 1 ]
  [[ "$output" == *"no code-dependent receipt"* ]]
}

# --- project coverage command: the widened firing domain (onboard task) --------
# When .harmonia/project.yaml supplies a coverage command, the gate RUNS it fresh
# on the current tree and measures a changed source file whose extension the
# built-in adapters route to "unsupported" today (.py), through the command's own
# report - instead of dropping it to the advisory cannot-measure path. With no
# coverage command, the built-in adapter path is preserved byte-for-byte.

@test "the gate runs a project coverage command and measures a changed .py through its report" {
  git -C "$R" checkout -q -- app.ts                            # drop setup's app.ts edit
  printf 'p1\np2\np3\np4\n' > "$R/calc.py"                     # a .py: lang_of maps it to unsupported today
  git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm pybase
  PB="$(git -C "$R" rev-parse HEAD)"
  printf 'p1\nCHANGED2\np3\nCHANGED4\nNEW5\n' > "$R/calc.py"   # tracked-then-modified, not untracked

  mkdir -p "$R/.harmonia"
  # The command touches a sentinel (proving the gate RAN it, versus reading a
  # report lying around), writes a Cobertura report over calc.py with changed
  # lines 4 and 5 uncovered, and echoes the report path - the seam's output
  # contract. Relative paths resolve because the gate runs it from $REPO.
  cat > "$R/.harmonia/project.yaml" <<'YAML'
coverage: touch cmd-ran.sentinel && printf '<?xml version="1.0"?>\n<coverage line-rate="0.5" version="1.9" timestamp="1">\n<packages><package name="c" line-rate="0.5"><classes>\n<class name="calc" filename="calc.py" line-rate="0.5"><lines>\n<line number="2" hits="1"/>\n<line number="4" hits="0"/>\n<line number="5" hits="0"/>\n</lines></class>\n</classes></package></packages>\n</coverage>\n' > pycov.xml && echo pycov.xml
YAML

  run bash "$GATE" --repo "$R" --base "$PB" --workspace "$WS"  # NO --lang, NO --report
  [ -f "$R/cmd-ran.sentinel" ]                                 # the gate actually RAN the command
  [ "$status" -eq 1 ]                                          # measured: uncovered changed lines (not advisory exit 4)
  [[ "$output" == *"calc.py"* ]]                               # the .py surfaced through the command's report
  # F3: prove measurement flowed THROUGH the report, not the absent-means-uncovered
  # fallback. Line 4 (CHANGED4) is a changed line the report marks hits="0", so only a
  # genuinely-consumed report yields the specific token "calc.py:4"; a report never
  # matched to calc.py (wrong filename=) drops to "calc.py:ALL (absent from coverage
  # data ...)" and fails both assertions below. The two together distinguish real
  # measurement from the file-level fallback the prior assertions could not tell apart.
  [[ "$output" == *"calc.py:4"* ]]                             # a specific measured uncovered line - only the consumed report yields it
  [[ "$output" != *"absent from coverage data"* ]]             # excludes the absent-means-uncovered fallback entirely
  [[ "$output" != *"cannot measure"* ]]                        # NOT the advisory cannot-measure path
  grep -q "calc.py" "$WS/gate-report.md"
}

@test "a project coverage command that fails yields cannot-measure, not the advisory path" {
  git -C "$R" checkout -q -- app.ts
  printf 'p1\np2\n' > "$R/calc.py"
  git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm pybase
  PB="$(git -C "$R" rev-parse HEAD)"
  printf 'p1\nCHANGED2\n' > "$R/calc.py"
  mkdir -p "$R/.harmonia"

  # A present command that exits non-zero exercises the seam's `|| { ... exit 4; }`.
  printf 'coverage: exit 7\n' > "$R/.harmonia/project.yaml"
  run bash "$GATE" --repo "$R" --base "$PB" --workspace "$WS"
  [ "$status" -eq 4 ]
  [[ "$output" == *"project coverage command"* ]]             # names the command path...
  [[ "$output" != *"unsupported language"* ]]                 # ...not the advisory path

  # A present command that exits 0 but names no readable report exercises the -f guard.
  printf 'coverage: echo /nonexistent/nope.xml\n' > "$R/.harmonia/project.yaml"
  run bash "$GATE" --repo "$R" --base "$PB" --workspace "$WS"
  [ "$status" -eq 4 ]
  [[ "$output" == *"project coverage command"* ]]
  [[ "$output" != *"unsupported language"* ]]
}

@test "with no coverage command configured the gate falls back to the built-in adapter" {
  git -C "$R" checkout -q -- app.ts
  printf '#!/bin/sh\necho hi\n' > "$R/tool.sh"
  git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm sh
  SB="$(git -C "$R" rev-parse HEAD)"
  printf '#!/bin/sh\necho changed\n' > "$R/tool.sh"
  # project.yaml present but carries only verify keys - no coverage command - so
  # the gate must take the built-in adapter path exactly as with no file at all.
  mkdir -p "$R/.harmonia"
  cat > "$R/.harmonia/project.yaml" <<'YAML'
test: bats tests/
lint: shellcheck bin/
typecheck: true
build: true
YAML
  run env HARMONIA_KCOV=/nonexistent-kcov bash "$GATE" --repo "$R" --base "$SB" --workspace "$WS"
  [ "$status" -eq 4 ]
  [[ "$output" == *"cannot measure"* ]]
}

# --- receipt integrity: the audit must name the coverage gate -----------------
# The vacuity guard COUNTED receipts that took the digest-freshness path, and
# criteria-run.json is code-dependent and fresh by construction, so it satisfied
# that count on its own and the audit certified a tree nothing had measured. The
# state the lifecycle actually produces holds TWO receipts - the shape gate
# writes check-criteria.json at implement-start, long before review's coverage
# gate runs - so a refusal keyed on "the receipts dir holds at most one file"
# would satisfy a one-receipt probe while leaving the defect live. This is that
# pair, with no coverage receipt in it.

@test "verify-receipts refuses the wired receipt pair when no coverage receipt is present" {
  d="$(git -C "$R" diff "$BASE" | sha256sum | awk '{print $1}')"   # setup() drifted app.ts, so the digest is content-bearing
  cat > "$WS/receipts/criteria-run.json" <<JSON
{ "gate": "criteria-run", "task_id": "2026-07-02-covfix", "timestamp": "2026-07-31T00:00:00Z", "diff_digest": "$d", "status": "pass" }
JSON
  cat > "$WS/receipts/check-criteria.json" <<'JSON'
{ "gate": "check-criteria", "task_id": "2026-07-02-covfix", "timestamp": "2026-07-31T00:00:00Z", "diff_digest": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "status": "pass" }
JSON
  [ ! -f "$WS/receipts/coverage.json" ]        # the fixture IS the no-coverage-receipt state
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" --verify-receipts
  [ "$status" -ne 0 ]
  [[ "$output" == *"no code-dependent receipt"* ]]
  [[ "$output" != *"receipts verified"* ]]
  # Staleness must not be the reason: the loop returns on a stale digest BEFORE
  # the vacuity guard, so an exit-code-only assertion would be right for the
  # wrong reason the day this fixture's digest drifts.
  [[ "$output" != *"stale"* ]]
}

# The same refusal in the singleton state, which is the state the defect was
# measured in: a receipts directory holding nothing but a fresh criteria-run.json
# answered `gate: receipts verified` exit 0. The pair above does not cover it - a
# build that refuses only once it has SEEN a check-criteria receipt passes the
# pair and still certifies this (measured) - and the two together leave no room
# to key the refusal on anything but the coverage receipt's own absence.
@test "verify-receipts refuses a receipts dir holding only a fresh criteria-run receipt" {
  d="$(git -C "$R" diff "$BASE" | sha256sum | awk '{print $1}')"
  cat > "$WS/receipts/criteria-run.json" <<JSON
{ "gate": "criteria-run", "task_id": "2026-07-02-covfix", "timestamp": "2026-07-31T00:00:00Z", "diff_digest": "$d", "status": "pass" }
JSON
  [ "$(ls -1 "$WS"/receipts/*.json | wc -l)" -eq 1 ]   # the fixture really is the singleton
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" --verify-receipts
  [ "$status" -ne 0 ]
  [[ "$output" == *"no code-dependent receipt"* ]]
  [[ "$output" != *"receipts verified"* ]]
  [[ "$output" != *"stale"* ]]
}

# criteria-run's exit code is the gate; its receipt only witnesses freshness. A
# `fail` there means the criteria ran and lost, which no audit may certify. The
# coverage receipt beside it reports `fail` too - write_ts_cov leaves lines 4 and
# 5 uncovered, so the measurement soft-blocks - and that must NOT be why this
# refuses: reading coverage's status would harden the soft block into a verify
# failure and route the advisory cannot-measure case (which also receipts `fail`)
# there with it.
@test "verify-receipts refuses a criteria-run receipt reporting fail, and still reads no coverage status" {
  write_ts_cov
  bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" --report "$R/cov.xml" --lang ts --no-branch >/dev/null || true
  # The coverage receipt has to be a genuine one, so the measurement must have run:
  # with diff-cover absent the gate exits 4 before the write block and this refuses
  # rather than quietly becoming a test about a hand-written receipt.
  if [ ! -f "$WS/receipts/coverage.json" ]; then
    echo "fixture unusable: the gate wrote no coverage receipt (is diff-cover installed?)" >&2
    return 1
  fi
  [ "$(jq -r .status "$WS/receipts/coverage.json")" = "fail" ]   # the fixture really is the soft-blocked state
  d="$(git -C "$R" diff "$BASE" | sha256sum | awk '{print $1}')"
  cat > "$WS/receipts/criteria-run.json" <<JSON
{ "gate": "criteria-run", "task_id": "2026-07-02-covfix", "timestamp": "2026-07-31T00:00:00Z", "diff_digest": "$d", "status": "fail" }
JSON
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" --verify-receipts
  [ "$status" -ne 0 ]
  [[ "$output" == *"criteria-run"* ]]
  [[ "$output" != *"receipts verified"* ]]
  [[ "$output" != *"stale"* ]]                 # both receipts are fresh, so the `fail` is what refused...
  [[ "$output" != *"coverage.json"* ]]         # ...and coverage's own `fail` is not
}

# --- receipt integrity: the accept side of the criteria-run read --------------
# Every receipt probe above is a refusal. The state review actually READS on each
# round that PASSES is the one none of them reaches: a fresh coverage receipt
# beside a criteria-run receipt reporting `pass`, written over the pre-loop
# `running` by bin/check-criteria.sh:159 the moment the loop ends. So `pass` is
# the wired steady state and not an edge case - it is the state this task's own
# receipts directory is in - and the two criteria-run refusals above cannot stand
# in for it: each is a state the audit must refuse for another reason, so neither
# ever reaches `receipts verified`. Measured before this test existed: head plus
# one branch refusing criteria-run `pass` once a coverage receipt has been seen is
# 67/67 green while refusing this repo's own receipt set, so a build in that shape
# would fail every review from the round it landed and the suite would say
# nothing. What this must NOT pin is `pass` as a REQUIREMENT - the same receipt
# reads `running` while the run that writes it is still going, and an audit
# invoked from inside that run has to accept it (tests/hooks.bats' in-run half).
# It therefore asserts what the audit does WITH `pass`, never that `pass` is the
# only value it may accept.
#
# All three receipts of a real round, in the order skills/review/SKILL.md:11-13
# pins: check-criteria from implement-start (code-stale by construction, waived
# by name), the coverage gate's, then the criteria run's. Only the first is
# hand-written - the two that owe freshness come from the gates that own them, so
# a producer that renames a field or digests the wrong tree reds this instead of
# shipping a receipt no reader would accept.

@test "verify-receipts verifies a criteria-run receipt reporting pass beside a fresh coverage receipt" {
  # A bats-only diff, so the measurement passes on its own (status 0 -> receipt
  # `pass`) with no measurement tool the fixture could be missing; STAGED, so
  # `git diff` reports it and the digest under audit is content-bearing - against
  # the sha256 of an empty diff a freshness check matches whatever it is handed.
  git -C "$R" checkout -q -- app.ts
  printf '#!/usr/bin/env bats\n' > "$R/new.bats"
  git -C "$R" add new.bats
  d="$(git -C "$R" diff "$BASE" | sha256sum | awk '{print $1}')"
  [ -n "$(git -C "$R" diff "$BASE")" ]
  cat > "$WS/receipts/check-criteria.json" <<'JSON'
{ "gate": "check-criteria", "task_id": "2026-07-02-covfix", "timestamp": "2026-07-31T00:00:00Z", "diff_digest": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "status": "pass" }
JSON
  if ! bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" >/dev/null; then
    echo "fixture unusable: the round's own coverage gate did not pass on a bats-only diff" >&2
    return 1
  fi
  cat > "$WS/scope.md" <<'EOF'
## Success Criteria
- run: true
EOF
  if ! bash "$REPO_ROOT/bin/check-criteria.sh" --run --workspace "$WS" --repo "$R" >/dev/null; then
    echo "fixture unusable: the criteria run did not pass, so its receipt is not the pass state" >&2
    return 1
  fi
  # REFUSE rather than degenerate into a weaker probe: with a receipt missing or
  # not at `pass` this is some other state, and reaching `receipts verified` out
  # of it would prove nothing about the state the round leaves.
  for g in check-criteria coverage criteria-run; do
    if [ "$(jq -r '.status // empty' "$WS/receipts/$g.json" 2>/dev/null)" != "pass" ]; then
      echo "fixture unusable: $WS/receipts/$g.json is not a receipt reporting pass" >&2
      return 1
    fi
  done
  [ "$(jq -r .diff_digest "$WS/receipts/coverage.json")" = "$d" ]         # fresh for this tree...
  [ "$(jq -r .diff_digest "$WS/receipts/criteria-run.json")" = "$d" ]     # ...both of the two that owe it
  [ "$(jq -r .diff_digest "$WS/receipts/check-criteria.json")" != "$d" ]  # ...and the third is the code-stale one it is waived for
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" --verify-receipts
  [ "$status" -eq 0 ]
  [[ "$output" == *"receipts verified"* ]]
}
