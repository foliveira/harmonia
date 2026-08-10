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
  # Mirror what mint writes (bin/workspace.sh:111): the tasks tree ignores itself,
  # so a workspace is never committable. Several tests below commit the whole tree
  # mid-test, and without this they would track base-ref - a state no minted
  # workspace can reach, and one the provenance guard correctly refuses.
  printf '*\n' > "$R/.harmonia/tasks/.gitignore"
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

# --- receipt integrity: neither workspace write may be reported as a coverage
# --- result ------------------------------------------------------------------
# Both writes were unchecked. The receipt is the audit's certificate that the
# coverage gate ran against this tree, and the report is a declared review-lead
# input, so a write that cannot land is an I/O failure of the gate, never a
# measurement verdict. What these pin is the claim, not a wording: a non-zero
# exit, no success verdict, a verdict of the gate's OWN (a `gate: `-prefixed
# line, the file's convention for everything it tells a reader - a build that
# dies on an unbound variable exits non-zero while saying nothing), and the
# artifact state that decides whether an audit can certify the run. The exit
# NUMBER is deliberately unasserted: it is a documented enum in the gate's
# header, and pinning it here would make changing it an edit to a hash-recorded
# test. Every fixture below uses a bats-only diff, so the measurement itself is
# status 0 and no probe can pass because coverage failed.

@test "a blocked report path is not reported as a measurement, and leaves no coverage receipt" {
  git -C "$R" checkout -q -- app.ts
  printf '#!/usr/bin/env bats\n' > "$R/new.bats"
  # Control first, on the same fixture: the gate measures cleanly here and leaves
  # both artifacts. So a build that reds the blocked run for some unrelated
  # reason reds this control too, and the pair discriminates without asserting a
  # message the scope leaves to the implementer.
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gate: OK"* ]]
  [ -s "$WS/gate-report.md" ]
  [ -s "$WS/receipts/coverage.json" ]
  rm -f "$WS/gate-report.md" "$WS/receipts/coverage.json"
  mkdir -p "$WS/gate-report.md"                # nothing can be written at the report path
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ "$status" -ne 0 ]
  [[ "$output" != *"gate: OK"* ]]
  grep -q '^gate: ' <<<"$output"               # the gate stated a verdict of its own
  [ ! -f "$WS/receipts/coverage.json" ]        # so no audit can certify this run
  [ -d "$WS/gate-report.md" ]                  # and what was in the way stays there (bin/check-criteria.sh:71-74's policy)
}

@test "a blocked receipt path is not reported as a measurement" {
  git -C "$R" checkout -q -- app.ts
  printf '#!/usr/bin/env bats\n' > "$R/new.bats"
  mkdir -p "$WS/receipts/coverage.json"        # nothing can be written at the receipt path
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ "$status" -ne 0 ]
  [[ "$output" != *"gate: OK"* ]]
  grep -q '^gate: ' <<<"$output"
  [ ! -f "$WS/receipts/coverage.json" ]        # still the planted directory, not a receipt
  [ -d "$WS/receipts/coverage.json" ]
}

# The three states where the write does NOT fail at open, which is the realistic
# trigger and the one a check on the writing command's status cannot see. They
# belong in the suite rather than only in this task's criteria because
# `.harmonia/tasks/` is gitignored: the criteria stop being runnable the day the
# task closes, and these two suites are then the only durable guard.
#
# Each REFUSES rather than skipping when its fixture cannot express the failure -
# a runner who can write the unwritable file (root), a /dev/full that is absent
# or accepts writes, a $TMPDIR that will not hold a symlink. A fixture that
# silently degenerates into a weaker probe passes every build it exists to kill,
# which is measured history on this seam, not a hypothetical.
#
# The report tests assert a DISJUNCTION - either the gate refused and this run
# left no receipt, or it printed `gate: OK` and a regular non-empty report is at
# the declared path with its receipt. That is what keeps them property-shaped and
# admits a write-to-a-part-file-then-rename shape, which lands a complete report
# through a blocked path and which a refusal-only assertion would wrongly red.

@test "a report write that lands no bytes is not reported as a measurement" {
  git -C "$R" checkout -q -- app.ts
  printf '#!/usr/bin/env bats\n' > "$R/new.bats"
  : > "$WS/gate-report.md"                     # the end state of a create that succeeded and a first write that failed
  chmod a-w "$WS/gate-report.md"
  if printf x 2>/dev/null > "$WS/gate-report.md"; then
    chmod u+w "$WS/gate-report.md"
    echo "fixture unusable: the read-only report path accepted a write" >&2
    return 1
  fi
  [ ! -s "$WS/gate-report.md" ]                # and it is still the 0-byte file the gate must refuse
  rm -f "$WS/receipts/coverage.json"
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  chmod u+w "$WS/gate-report.md"
  if [[ "$output" == *"gate: OK"* ]]; then
    [ "$status" -eq 0 ]
    [ -f "$WS/gate-report.md" ]
    [ -s "$WS/gate-report.md" ]
    [ -s "$WS/receipts/coverage.json" ]
  else
    [ "$status" -ne 0 ]
    grep -q '^gate: ' <<<"$output"
    [ ! -f "$WS/receipts/coverage.json" ]
  fi
}

@test "a report write that lands nowhere is not reported as a measurement" {
  git -C "$R" checkout -q -- app.ts
  printf '#!/usr/bin/env bats\n' > "$R/new.bats"
  # /dev/full accepts the OPEN and fails every write, so `{ ...; } > it` exits 0
  # while nothing was written - the state that makes the writing command's own
  # status useless and a check on the result on disk the only honest one.
  [ -c /dev/full ] || { echo "fixture unusable: /dev/full is not a character device" >&2; return 1; }
  : > /dev/full 2>/dev/null || { echo "fixture unusable: /dev/full cannot be opened for writing" >&2; return 1; }
  if printf x 2>/dev/null > /dev/full; then
    echo "fixture unusable: /dev/full accepted a write" >&2
    return 1
  fi
  rm -f "$WS/gate-report.md" "$WS/receipts/coverage.json"
  ln -s /dev/full "$WS/gate-report.md" || { echo "fixture unusable: cannot symlink the report path" >&2; return 1; }
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  if [[ "$output" == *"gate: OK"* ]]; then
    [ "$status" -eq 0 ]
    [ -f "$WS/gate-report.md" ]
    [ -s "$WS/gate-report.md" ]
    [ -s "$WS/receipts/coverage.json" ]
  else
    [ "$status" -ne 0 ]
    grep -q '^gate: ' <<<"$output"
    [ ! -f "$WS/receipts/coverage.json" ]
  fi
}

# The receipt's two halves, one test each, because they fail for different
# reasons and a build can close one and leave the other open.

@test "a receipt write that fails over an existing receipt is not reported as a measurement" {
  git -C "$R" checkout -q -- app.ts
  printf '#!/usr/bin/env bats\n' > "$R/new.bats"
  # A previous round's receipt, unwritable: the open fails and leaves a non-empty
  # regular file, so no file test can tell it from a receipt this run wrote. Only
  # the writer's own status sees it.
  cat > "$WS/receipts/coverage.json" <<'JSON'
{ "gate": "coverage", "task_id": "PLANTED", "timestamp": "2026-07-30T00:00:00Z", "diff_digest": "planted", "status": "pass" }
JSON
  chmod a-w "$WS/receipts/coverage.json"
  if printf x 2>/dev/null > "$WS/receipts/coverage.json"; then
    chmod u+w "$WS/receipts/coverage.json"
    echo "fixture unusable: the read-only receipt path accepted a write" >&2
    return 1
  fi
  [ "$(jq -r .task_id "$WS/receipts/coverage.json")" = "PLANTED" ]   # the fixture really is a foreign receipt
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  chmod u+w "$WS/receipts/coverage.json"
  if [[ "$output" == *"gate: OK"* ]]; then
    [ "$(jq -r .task_id "$WS/receipts/coverage.json")" != "PLANTED" ]   # then it really is this run's receipt
  else
    [ "$status" -ne 0 ]
    grep -q '^gate: ' <<<"$output"
  fi
}

@test "a receipt write that lands nothing at the path is not reported as a measurement" {
  git -C "$R" checkout -q -- app.ts
  printf '#!/usr/bin/env bats\n' > "$R/new.bats"
  # The other half of the same claim: a write that SUCCEEDS into a discard device
  # leaves nothing at the path, which the writer's status cannot see and a file
  # test can.
  rm -f "$WS/receipts/coverage.json"
  ln -s /dev/null "$WS/receipts/coverage.json" || { echo "fixture unusable: cannot symlink the receipt path" >&2; return 1; }
  printf x > "$WS/receipts/coverage.json" || { echo "fixture unusable: the discard path refused a write" >&2; return 1; }
  [ ! -f "$WS/receipts/coverage.json" ] || { echo "fixture unusable: a regular file landed at the discard path" >&2; return 1; }
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ "$status" -ne 0 ]
  [[ "$output" != *"gate: OK"* ]]
  grep -q '^gate: ' <<<"$output"
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

# --- FU-16 in the coverage gate: the write side and the read side -------------
# Two tests, not one, for the reason this file already states at :651 about the
# receipt's two halves: they fail for different reasons and a build can close one
# and leave the other open. That is not hypothetical here - the scope's own
# reference build closed every write and still answered `gate: receipts verified`
# through a symlinked receipts/ until the audit was guarded too.
#
# The cells are the gate's three workspace SINKS (receipts/, gate-report.md,
# receipts/coverage.json - the whole list, read off the write block itself) and
# the tree above them, rather than one symlink form applied once: a guard on
# receipts/ alone leaves gate-report.md open, which is the sharpest cell in the
# task - symlink the report at a file the user owns and base overwrites it,
# prints `gate: OK` and exits 0. `shaped` gives the redirect a target that is
# itself named .harmonia/tasks, which a guard that only pattern-matches the
# resolved path accepts.
#
# Every cell's fixture makes the gate PASS at base (an untracked markdown file is
# the whole diff, so nothing is measured and no coverage tool is in play), so
# `gate: OK` at exit 0 over a clobbered victim is what red looks like here, and
# the exit code discriminates as well as the disk does.

gsnap_tree() {   # <dir> -> a listing that moves if anything under it is added, removed or edited
  { find "$1" | sort; find "$1" -type f -exec sha256sum {} + 2>/dev/null | sort; }
}

gassert_outside_unchanged() {   # <dir> <snapshot-taken-before>
  local after; after="$(gsnap_tree "$1")"
  if [ "$after" != "$2" ]; then
    echo "ESCAPED - the tree outside the workspace changed:"
    diff <(printf '%s\n' "$2") <(printf '%s\n' "$after") || true
  fi
  [ "$after" = "$2" ]
}

stage_gate() {   # <form> <kind: write|audit>: one self-contained cell; sets CELL, GR, GWS, GBASE
  local form="$1" kind="$2" real
  CELL="$BATS_TEST_TMPDIR/gt-$kind-$form"
  mkdir -p "$CELL/out" "$CELL/real"
  real="$CELL/real/r"; mkdir -p "$real"
  git -C "$real" init -q
  printf 'a\n' > "$real/f.sh"
  git -C "$real" add -A
  git -C "$real" -c user.email=t@t -c user.name=t commit -qm b
  GR="$real"; GBASE="$(git -C "$real" rev-parse HEAD)"
  GWS="$real/.harmonia/tasks/T"
  mkdir -p "$GWS/receipts"
  if [ "$kind" = audit ]; then
    printf 'a\nb\n' > "$real/f.sh"        # a TRACKED change: the audited digest is content-bearing, not the empty-diff constant
  else
    printf 'notes\n' > "$real/notes.md"   # untracked markdown: a real diff the gate routes to `skip`, so it measures nothing and passes
  fi
  case "$form" in
    clean) ;;
    receipts-dir)
        rm -rf "$GWS/receipts"; mkdir -p "$CELL/out/receipts"
        printf 'VICTIM\n' > "$CELL/out/receipts/coverage.json"
        ln -s "$CELL/out/receipts" "$GWS/receipts" ;;
    tasks-tree)
        mv "$real/.harmonia/tasks" "$CELL/out/tasks"; ln -s "$CELL/out/tasks" "$real/.harmonia/tasks"
        printf 'VICTIM\n' > "$CELL/out/tasks/T/gate-report.md"
        printf 'VICTIM\n' > "$CELL/out/tasks/T/receipts/coverage.json" ;;
    report-file)
        printf 'VICTIM\n' > "$CELL/out/victim-report.md"
        rm -f "$GWS/gate-report.md"; ln -s "$CELL/out/victim-report.md" "$GWS/gate-report.md" ;;
    receipt-file)
        printf 'VICTIM\n' > "$CELL/out/victim-receipt.json"
        rm -f "$GWS/receipts/coverage.json"; ln -s "$CELL/out/victim-receipt.json" "$GWS/receipts/coverage.json" ;;
    receipt-unguarded-name)
        # The write side knows three receipt names; the audit GLOBS. A receipt at
        # a name no writer will ever guard is reachable only from the read side.
        printf 'VICTIM\n' > "$CELL/out/victim-zz.json"
        ln -s "$CELL/out/victim-zz.json" "$GWS/receipts/zz.json" ;;
    receipts-absent)
        # tasks-tree and shaped both carry receipts/ along to the redirect
        # target, so the gate's `mkdir -p` is a no-op there and deleting the
        # guard in front of it reds nothing. Same redirect, target stripped: the
        # mkdir is now the statement that CREATES a directory outside the
        # repository, and it runs before any later guard can refuse.
        # A dangling symlink at receipts/ does not construct this - mkdir -p
        # fails "File exists" on one and nothing escapes.
        mv "$real/.harmonia/tasks" "$CELL/out/tasks"; ln -s "$CELL/out/tasks" "$real/.harmonia/tasks"
        rm -rf "$CELL/out/tasks/T/receipts" ;;
    in-repo-shape)
        # Contained but not a workspace: the redirect target is a real directory
        # INSIDE the repository, so the anchor prefix test accepts it and only
        # the shape and single-component tests refuse. Every other form redirects
        # outside, where the prefix test alone is enough.
        mkdir -p "$real/src/receipts"; printf 'VICTIM\n' > "$real/src/gate-report.md"
        rm -rf "$GWS"; ln -s "$real/src" "$GWS" ;;
    nested-task-path)
        # Contained AND correctly shaped, but one component too deep. Only the
        # single-component test refuses this, so it is the cell that pins that
        # line by itself; in-repo-shape above is refused by either half, so it
        # pins the pair rather than the line.
        mkdir -p "$GWS/sub/receipts"; printf 'VICTIM\n' > "$GWS/sub/gate-report.md"
        GWS="$GWS/sub" ;;
    shaped)
        mkdir -p "$CELL/out/.harmonia"
        mv "$real/.harmonia/tasks" "$CELL/out/.harmonia/tasks"
        ln -s "$CELL/out/.harmonia/tasks" "$real/.harmonia/tasks"
        printf 'VICTIM\n' > "$CELL/out/.harmonia/tasks/T/gate-report.md"
        printf 'VICTIM\n' > "$CELL/out/.harmonia/tasks/T/receipts/coverage.json" ;;
  esac
}

@test "the coverage gate refuses a report or receipt write that resolves outside the workspace" {
  for form in clean receipts-dir tasks-tree report-file receipt-file shaped receipts-absent in-repo-shape nested-task-path; do
    stage_gate "$form" write
    before="$(gsnap_tree "$CELL/out")"
    echo "--- redirect form: $form, workspace $GWS"
    run bash "$GATE" --repo "$GR" --base "$GBASE" --workspace "$GWS"
    echo "status=$status"
    echo "$output"
    if [ "$form" = clean ]; then
      # The accept side: a legitimate run still measures, reports and receipts.
      [ "$status" -eq 0 ]
      [[ "$output" == *"gate: OK"* ]]
      [ -s "$GWS/gate-report.md" ]
      [ -s "$GWS/receipts/coverage.json" ]
    else
      [ "$status" -ne 0 ]
      [[ "$output" != *"gate: OK"* ]]
      grep -q '^gate: ' <<<"$output"    # refusals speak in this gate's own prefix (:637, :687)
    fi
    gassert_outside_unchanged "$CELL/out" "$before"
    # in-repo-shape's victim is inside the repository, where the outside-tree
    # snapshot cannot see it: assert it directly or the cell proves nothing.
    case "$form" in
      in-repo-shape)    [ "$(cat "$GR/src/gate-report.md")" = VICTIM ] ;;
      nested-task-path) [ "$(cat "$GWS/gate-report.md")" = VICTIM ] ;;
    esac
  done
}

@test "the receipt audit refuses to certify a receipt store that lives outside the workspace" {
  # The read side, and the half a build closes last: nothing is written here, so
  # no escape detector can see it - what is wrong is the VERDICT. Base answers
  # `gate: receipts verified` at exit 0 over a store the gate never wrote into,
  # which is a certificate that a tree was measured when nothing measured it.
  # receipt-file and receipt-unguarded-name are the file-level forms: this loop
  # globs receipts/*.json, so a directory-level guard leaves an individual
  # receipt - and any name no writer knows about - followed as written.
  for form in clean receipts-dir tasks-tree shaped receipt-file receipt-unguarded-name in-repo-shape; do
    stage_gate "$form" audit
    cur="$(git -C "$GR" diff "$GBASE" | sha256sum | awk '{print $1}')"
    [ -n "$(git -C "$GR" diff "$GBASE")" ]   # a real diff, so freshness is a real check and not the empty-diff constant
    cat > "$GWS/receipts/coverage.json" <<JSON
{ "gate": "coverage", "task_id": "T", "timestamp": "2026-01-01T00:00:00Z", "diff_digest": "$cur", "status": "pass" }
JSON
    # The unguarded-name cell only discriminates if the outside receipt is a
    # VALID, FRESH one: left as junk it is refused for being unparseable and the
    # cell would pass against the very build it exists to red.
    if [ "$form" = receipt-unguarded-name ]; then
      cat > "$GWS/receipts/zz.json" <<JSON
{ "gate": "coverage", "task_id": "T", "timestamp": "2026-01-01T00:00:00Z", "diff_digest": "$cur", "status": "pass" }
JSON
    fi
    echo "--- redirect form: $form, workspace $GWS"
    run bash "$GATE" --verify-receipts --repo "$GR" --base "$GBASE" --workspace "$GWS"
    echo "status=$status"
    echo "$output"
    if [ "$form" = clean ]; then
      # The accept side: a receipt that really is in the workspace and really is
      # fresh still verifies, so a refuse-every-audit build is red here.
      [ "$status" -eq 0 ]
      [[ "$output" == *"receipts verified"* ]]
    else
      [ "$status" -ne 0 ]
      [[ "$output" != *"receipts verified"* ]]
      grep -q '^gate: ' <<<"$output"
    fi
  done
}

@test "the gate refuses a base-ref that resolves outside the workspace, in both modes" {
  # Absent --base the workspace supplies the base, so base-ref is an audit input
  # with the same standing as the receipts it is used to check. Redirected, it
  # names a base the caller never chose, and the audit's own answer flips on it:
  # the receipt below carries the EMPTY-diff digest while the tree really has a
  # change, so an honest base-ref makes the audit report staleness and the
  # redirected one - pointing at a ref against which the diff really is empty -
  # turns that into `receipts verified`. Nothing here is written, so the flip is
  # invisible to every escape detector; what is wrong is the verdict.
  local cell="$BATS_TEST_TMPDIR/bref" real
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
  cat > "$ws/receipts/coverage.json" <<JSON
{ "gate": "coverage", "task_id": "T", "timestamp": "2026-01-01T00:00:00Z", "diff_digest": "$empty", "status": "pass" }
JSON

  # Honest base-ref naming the FIRST commit: the live diff is non-empty, so the
  # empty-diff receipt is stale and the audit must say so. This is the control -
  # without it the redirect cell cannot be read as a flip.
  printf 'ref: %s\n' "$first" > "$ws/base-ref"
  run bash "$GATE" --verify-receipts --repo "$real" --workspace "$ws"
  echo "honest: status=$status $output"
  [ "$status" -ne 0 ]
  [[ "$output" != *"receipts verified"* ]]

  # Same receipt, base-ref symlinked outside the workspace at a file naming HEAD,
  # against which the diff IS empty. Unguarded, the audit certifies.
  printf 'ref: %s\n' "$head" > "$cell/out/base-ref"
  rm -f "$ws/base-ref"; ln -s "$cell/out/base-ref" "$ws/base-ref"
  run bash "$GATE" --verify-receipts --repo "$real" --workspace "$ws"
  echo "redirected: status=$status $output"
  [ "$status" -ne 0 ]
  [[ "$output" != *"receipts verified"* ]]
  grep -q '^gate: ' <<<"$output"

  # The write mode takes its base from the same line, so the same redirect makes
  # every measurement and the receipt it writes attest to a base nobody chose.
  run bash "$GATE" --repo "$real" --workspace "$ws" --lang bash
  echo "write: status=$status $output"
  [ "$status" -ne 0 ]
  [[ "$output" != *"gate: OK"* ]]
  grep -q '^gate: ' <<<"$output"
}

@test "the receipt audit refuses receipts that arrived with the repository" {
  # M2. Nothing is redirected here and containment correctly accepts every path:
  # the receipts are exactly where receipts belong. What is wrong is that the
  # repository WROTE them. On a fresh clone with nothing measured locally, the
  # tier-B honesty gate certifies a tree no gate here ever looked at.
  local h="$BATS_TEST_TMPDIR/rp-host" c="$BATS_TEST_TMPDIR/rp-clone"
  local w="$h/.harmonia/tasks/T"
  local empty; empty="$(printf '' | sha256sum | awk '{print $1}')"
  mkdir -p "$w/receipts"
  printf 'x\n' > "$h/README.md"
  cat > "$w/receipts/coverage.json" <<JSON
{ "gate": "coverage", "task_id": "T", "timestamp": "2026-01-01T00:00:00Z", "diff_digest": "$empty", "status": "pass" }
JSON
  cat > "$w/receipts/criteria-run.json" <<JSON
{ "gate": "criteria-run", "task_id": "T", "timestamp": "2026-01-01T00:00:00Z", "diff_digest": "$empty", "status": "pass" }
JSON
  git -C "$h" init -q
  git -C "$h" add -A -f
  git -C "$h" -c user.email=t@t -c user.name=t commit -qm x
  git clone -q "$h" "$c"
  local cw="$c/.harmonia/tasks/T"
  git -C "$c" ls-files --error-unmatch -- ".harmonia/tasks/T/receipts/coverage.json" >/dev/null
  # base-ref written after the clone, so the receipts are what this cell tests:
  # a carried base-ref refuses one step earlier and the receipt branch would
  # never run.
  printf 'ref: HEAD\n' > "$cw/base-ref"

  run bash "$GATE" --verify-receipts --repo "$c" --workspace "$cw"
  echo "clone absolute: status=$status $output"
  [ "$status" -ne 0 ]
  [[ "$output" != *"receipts verified"* ]]

  ( cd "$c" && run bash "$GATE" --verify-receipts --repo "." --workspace ".harmonia/tasks/T"
    [ "$status" -ne 0 ]
    [[ "$output" != *"receipts verified"* ]] )

  # The accept side, through the real gate: a workspace whose receipts this
  # machine actually wrote must still verify, or the audit is simply broken.
  local L="$BATS_TEST_TMPDIR/rp-ok"
  mkdir -p "$L"
  git -C "$L" init -q
  printf 'a\n' > "$L/f.sh"
  git -C "$L" add -A
  git -C "$L" -c user.email=t@t -c user.name=t commit -qm b
  local id; id="$(bash "$REPO_ROOT/bin/workspace.sh" mint --repo "$L" --slug mine)"
  local lw="$L/.harmonia/tasks/$id"
  printf 'notes\n' > "$L/notes.md"
  bash "$GATE" --repo "$L" --workspace "$lw" >/dev/null 2>&1
  [ -s "$lw/receipts/coverage.json" ]
  run bash "$GATE" --verify-receipts --repo "$L" --workspace "$lw"
  echo "honest: status=$status $output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"receipts verified"* ]]
}

@test "an exported CDPATH does not poison the containment predicate" {
  # A minor with a real cost: `cd` ECHOES the directory it lands in when CDPATH
  # is set and the target matches an entry, so the command substitution around it
  # captures that echo instead of the path. ws_tracked already unsets seven GIT_*
  # variables on the principle that the environment is not an input these guards
  # may trust; CDPATH is in exactly that class. Fail-closed only - it refuses the
  # shipped relative call shape rather than accepting a redirect - but a guard
  # that refuses correct work is still a guard that is wrong.
  local real="$BATS_TEST_TMPDIR/cdp/r"
  mkdir -p "$real"
  git -C "$real" init -q
  printf 'a\n' > "$real/f.sh"
  git -C "$real" add -A
  git -C "$real" -c user.email=t@t -c user.name=t commit -qm b
  local id; id="$(bash "$REPO_ROOT/bin/workspace.sh" mint --repo "$real" --slug cdp)"
  printf 'notes\n' > "$real/notes.md"

  # The relative call shape the skills actually use, from inside the repo.
  ( cd "$real" && CDPATH=. run bash "$GATE" --repo "." --workspace ".harmonia/tasks/$id"
    echo "status=$status"
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"gate: OK"* ]] )
}

@test "the gate refuses a base-ref that arrived with the repository" {
  # Round 6 M2, and the link that made the clone-to-execution chain fire at step 2
  # of the shipped review sequence. base-ref selects the tree this gate measures,
  # so a repository that commits its own decides what the changed-file list holds -
  # on a fresh clone, with no --base given, one line before any provenance guard
  # used to run. Containment accepts it: the file is exactly where it belongs.
  local h="$BATS_TEST_TMPDIR/gbr-h" c="$BATS_TEST_TMPDIR/gbr-c"
  mkdir -p "$h/.harmonia/tasks/T/receipts"
  printf 'a\n' > "$h/f.sh"
  git -C "$h" init -q
  git -C "$h" add -A -f
  git -C "$h" -c user.email=t@t -c user.name=t commit -qm b
  printf 'ref: %s\n' "$(git -C "$h" rev-parse HEAD)" > "$h/.harmonia/tasks/T/base-ref"
  git -C "$h" add -A -f
  git -C "$h" -c user.email=t@t -c user.name=t commit -qm p
  git clone -q "$h" "$c"
  git -C "$c" ls-files --error-unmatch -- .harmonia/tasks/T/base-ref >/dev/null

  run bash "$GATE" --repo "$c" --workspace "$c/.harmonia/tasks/T"
  echo "status=$status"
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" != *"gate: OK"* ]]
  grep -q '^gate: ' <<<"$output"

  # The accept side: a base-ref this machine minted is carried by nothing.
  local L="$BATS_TEST_TMPDIR/gbr-ok"
  mkdir -p "$L"
  git -C "$L" init -q
  printf 'a\n' > "$L/f.sh"
  git -C "$L" add -A
  git -C "$L" -c user.email=t@t -c user.name=t commit -qm b
  local id; id="$(bash "$REPO_ROOT/bin/workspace.sh" mint --repo "$L" --slug gbr)"
  printf 'notes\n' > "$L/notes.md"
  run bash "$GATE" --repo "$L" --workspace "$L/.harmonia/tasks/$id"
  echo "accept: status=$status $output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gate: OK"* ]]
}
