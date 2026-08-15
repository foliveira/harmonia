#!/usr/bin/env bats
# U7 coverage-gate tests - diff-cover adoption path, markers, receipts, routing.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export PATH="$PATH:$HOME/.local/bin"
  # Isolated consent store (tests/memory.bats:6, tests/hooks.bats:6). The
  # project-coverage tests below record consent to run a repository's command,
  # and without this they write into the developer's real ~/.harmonia and read
  # back whatever is already there (2026-07-31 learning: a fixture whose verdict
  # depends on an ambient environment value goes green against the build it
  # exists to reject). HOME is deliberately NOT overridden - the line above
  # derives PATH from it - and HARMONIA_HOME alone is sufficient isolation
  # because it wins over HOME wherever the store root is resolved.
  export HARMONIA_HOME="$BATS_TEST_TMPDIR/harmonia-home"
  GATE="$REPO_ROOT/bin/coverage/gate.sh"
  TRUST="$REPO_ROOT/bin/trust.sh"

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
  #
  # The work moved from the coverage: line into a wrapper script this round: a
  # value has to be one of the shapes consent can be recorded for, and a bare
  # `touch … && printf … > pycov.xml` is not one of them. It is also the shape the
  # round tells a repository to write, so this accept-side proof now runs the
  # spelling the documents recommend.
  cat > "$R/.harmonia/pycov.sh" <<'SH'
#!/bin/sh
touch cmd-ran.sentinel
printf '<?xml version="1.0"?>\n<coverage line-rate="0.5" version="1.9" timestamp="1">\n<packages><package name="c" line-rate="0.5"><classes>\n<class name="calc" filename="calc.py" line-rate="0.5"><lines>\n<line number="2" hits="1"/>\n<line number="4" hits="0"/>\n<line number="5" hits="0"/>\n</lines></class>\n</classes></package></packages>\n</coverage>\n' > pycov.xml
SH
  chmod +x "$R/.harmonia/pycov.sh"
  printf 'coverage: sh .harmonia/pycov.sh && echo pycov.xml\n' > "$R/.harmonia/project.yaml"

  # Consent, recorded on this machine for this tree, is what makes that value
  # runnable at all: the gate reads a record kept outside every repository before
  # it evals. This is the suite's ACCEPT-side proof of the widened firing domain -
  # gate.sh:202 widening the .py, gate.sh:260 running the command, and a report
  # genuinely consumed - which the task criteria cannot carry for long, because
  # they live in a gitignored workspace and stop being runnable when it closes.
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]

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

# Both seams this pins - the `|| exit 4` when the command fails and the `-f`
# guard when it names no readable report - now live BELOW the consent guard, so
# an unattested fixture never reaches either of them: it witnesses the refusal
# instead, and would go green on a build that refuses everything while exercising
# neither seam. Recording consent for each value before the run is what keeps the
# test about what it says it is about; the `!= *project.yaml*` assertions are how
# it says so out loud, since every consent refusal names that file and neither
# message below does.
@test "an attested project coverage command that fails yields cannot-measure, not the advisory path" {
  git -C "$R" checkout -q -- app.ts
  printf 'p1\np2\n' > "$R/calc.py"
  git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm pybase
  PB="$(git -C "$R" rev-parse HEAD)"
  printf 'p1\nCHANGED2\n' > "$R/calc.py"
  mkdir -p "$R/.harmonia"

  # A present command that exits non-zero exercises the seam's `|| { ... exit 4; }`.
  # Through a wrapper because a bare `exit 7` is not a shape consent can be
  # recorded for, and an unrecordable value never reaches this seam at all.
  printf '#!/bin/sh\nexit 7\n' > "$R/.harmonia/fail.sh"
  chmod +x "$R/.harmonia/fail.sh"
  printf 'coverage: sh .harmonia/fail.sh\n' > "$R/.harmonia/project.yaml"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  run bash "$GATE" --repo "$R" --base "$PB" --workspace "$WS"
  [ "$status" -eq 4 ]
  [[ "$output" == *"project coverage command"* ]]             # names the command path...
  [[ "$output" != *"unsupported language"* ]]                 # ...not the advisory path
  [[ "$output" != *"project.yaml"* ]]                         # ...and not the consent refusal above it

  # A present command that exits 0 but names no readable report exercises the -f guard.
  printf 'coverage: echo /nonexistent/nope.xml\n' > "$R/.harmonia/project.yaml"
  run bash "$TRUST" record --repo "$R"                        # a different string: the old record does not cover it
  [ "$status" -eq 0 ]
  run bash "$GATE" --repo "$R" --base "$PB" --workspace "$WS"
  [ "$status" -eq 4 ]
  [[ "$output" == *"project coverage command"* ]]
  [[ "$output" != *"unsupported language"* ]]
  [[ "$output" != *"project.yaml"* ]]
}

# --- project coverage command: consent, recorded outside every repository -----
# The value at .harmonia/project.yaml `coverage:` is a shell command this gate
# evals, and a repository can commit one. Provenance cannot answer it - a TRACKED
# project.yaml is the legitimate case - so what is asked instead is whether a
# human on THIS machine agreed to THIS command for THIS tree. The two tests below
# are the reject side of that; the .py measurement test above is its accept side.

@test "an unattested project coverage command is refused, never run, and leaves no report or receipt behind" {
  git -C "$R" checkout -q -- app.ts
  printf 'p1\np2\np3\np4\n' > "$R/calc.py"
  # COMMITTED, which is what a clone delivers and what onboard tells a repo to
  # produce: provenance answers "carried by the repository" for exactly the file
  # we are meant to honour, so nothing upstream of the eval refuses this.
  #
  # The value is one the recorder WOULD accept if anyone had recorded it, which is
  # what keeps this test about consent: a build with no consent machinery at all
  # can refuse a value it cannot parse, and a fixture that is unattestable as well
  # as unattested would pass against that build while proving nothing.
  cat > "$R/.harmonia/cov.sh" <<'SH'
#!/bin/sh
touch cmd-ran.sentinel
printf '<?xml version="1.0"?>\n<coverage line-rate="0.5" version="1.9" timestamp="1">\n<packages><package name="c" line-rate="0.5"><classes>\n<class name="calc" filename="calc.py" line-rate="0.5"><lines>\n<line number="2" hits="1"/>\n<line number="4" hits="0"/>\n</lines></class>\n</classes></package></packages>\n</coverage>\n' > pycov.xml
SH
  chmod +x "$R/.harmonia/cov.sh"
  printf 'coverage: sh .harmonia/cov.sh && echo pycov.xml\n' > "$R/.harmonia/project.yaml"
  git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm pybase
  PB="$(git -C "$R" rev-parse HEAD)"
  printf 'p1\nCHANGED2\np3\nCHANGED4\nNEW5\n' > "$R/calc.py"

  run bash "$GATE" --repo "$R" --base "$PB" --workspace "$WS"
  [ ! -f "$R/cmd-ran.sentinel" ]                   # the value did not execute
  [ "$status" -eq 4 ]                              # the gate.sh:71-72 shape, not a coverage verdict
  [[ "$output" == *"cannot measure"* ]]
  [[ "$output" == *".harmonia/project.yaml"* ]]    # names the file to read...
  [[ "$output" == *"/harmonia:trust"* ]]           # ...and the human command that authorises it
  [[ "$output" != *"trust.sh"* ]]                  # never the script path that clears the refusal
  [[ "$output" != *"adapter for"* ]]               # refused outright, not sanitized to empty and dropped
                                                   # through gate.sh:247 into the adapter and past :254
  [ ! -f "$WS/gate-report.md" ]
  # A receipt written at refusal time is fresh by construction and sets cov_seen,
  # so --verify-receipts would answer `receipts verified` over a tree nothing
  # measured. Refusing must leave the workspace exactly as it found it.
  [ ! -f "$WS/receipts/coverage.json" ]

  # No home to look the record up in: a named refusal on a path that runs at
  # every implement round, never an unbound-variable death under `set -u`
  # (bin/memory/store-lib.sh:7 dereferences $HOME bare; this seam may not).
  run env -u HOME -u HARMONIA_HOME bash "$GATE" --repo "$R" --base "$PB" --workspace "$WS"
  [ ! -f "$R/cmd-ran.sentinel" ]
  [ "$status" -eq 4 ]
  [[ "$output" == *"cannot measure"* ]]
  [[ "$output" != *"unbound variable"* ]]
  [ ! -f "$WS/receipts/coverage.json" ]
}

@test "editing the coverage command after consent refuses it again, and restoring the attested string runs it" {
  git -C "$R" checkout -q -- app.ts
  printf 'p1\np2\np3\np4\n' > "$R/calc.py"
  git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm pybase
  PB="$(git -C "$R" rev-parse HEAD)"
  printf 'p1\nCHANGED2\np3\nCHANGED4\nNEW5\n' > "$R/calc.py"
  # The report fixture lives outside the repo so it joins no diff; the command
  # copies it in, which keeps the whole seam real (a consumed report) while the
  # attested string stays short enough to edit one byte of.
  cat > "$BATS_TEST_TMPDIR/pyfix.xml" <<'XML'
<?xml version="1.0" ?>
<coverage line-rate="0.5" version="1.9" timestamp="1">
  <packages><package name="c" line-rate="0.5"><classes>
    <class name="calc" filename="calc.py" line-rate="0.5"><lines>
      <line number="2" hits="1"/><line number="4" hits="0"/><line number="5" hits="0"/>
    </lines></class>
  </classes></package></packages>
</coverage>
XML
  # The copy runs from a wrapper because the attested string has to be a shape
  # consent can be recorded for; the sentinel and the copied report are unchanged.
  printf '#!/bin/sh\ntouch cmd-ran.sentinel\ncp %s/pyfix.xml pycov.xml\n' "$BATS_TEST_TMPDIR" > "$R/.harmonia/cov.sh"
  chmod +x "$R/.harmonia/cov.sh"
  attested="sh .harmonia/cov.sh && echo pycov.xml"
  printf 'coverage: %s\n' "$attested" > "$R/.harmonia/project.yaml"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]

  # One segment added in front of the attested string - the shape of a clone
  # editing a command the developer already agreed to, and of a developer changing
  # their own. The record digests the command, so it no longer covers this one.
  # The edit is itself attestable, so the only thing that can refuse it is the
  # consent check and not some parser upstream of it.
  printf '#!/bin/sh\ntouch edited.sentinel\n' > "$R/.harmonia/edited.sh"
  chmod +x "$R/.harmonia/edited.sh"
  printf 'coverage: sh .harmonia/edited.sh && %s\n' "$attested" > "$R/.harmonia/project.yaml"
  run bash "$GATE" --repo "$R" --base "$PB" --workspace "$WS"
  [ ! -f "$R/edited.sentinel" ]
  [ ! -f "$R/cmd-ran.sentinel" ]
  [ "$status" -eq 4 ]
  [[ "$output" == *"cannot measure"* ]]
  [[ "$output" == *".harmonia/project.yaml"* ]]
  [[ "$output" == *"/harmonia:trust"* ]]
  [ ! -f "$WS/receipts/coverage.json" ]

  # Restored: the same record covers the same string again. A consent guard that
  # cannot be satisfied is over-refusal, and the accept side needs its own proof.
  # The exit code is deliberately unasserted here - it depends on whether
  # diff-cover is installed, which is an environment fact and not a build one -
  # so what is asserted is that the command RAN and that nothing refused it.
  printf 'coverage: %s\n' "$attested" > "$R/.harmonia/project.yaml"
  run bash "$GATE" --repo "$R" --base "$PB" --workspace "$WS"
  [ -f "$R/cmd-ran.sentinel" ]
  [[ "$output" != *"/harmonia:trust"* ]]
  [[ "$output" != *".harmonia/project.yaml"* ]]
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
  # The two assertions above are satisfied by ANY cannot-measure refusal, so on
  # their own they go green against a build that refuses this repo for HAVING a
  # project.yaml - a guard keyed on the file existing rather than on a command
  # being about to run. These two say which cannot-measure this is: the adapter
  # was reached and reported its missing tool, and nothing refused the config.
  # Green at base by construction, and deliberately so - this is the over-refusal
  # side, and no reject-side test can force it.
  [[ "$output" == *"adapter for"* ]]
  [[ "$output" != *"project.yaml"* ]]
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

# --- where the consent guard fires, and on what it binds ----------------------
# The guard's firing DOMAIN was unpinned, and the cost of that was measured: a
# build with the same guard wrapped in `if [ -n "$WS" ]` passes the whole suite
# and every criterion of the round that introduced it while running an unattested
# payload, because every fixture that reached this seam happened to pass
# --workspace. A second one keyed on --base having been given behaves identically.
# A single extra cell does not close that - the gap is a domain - so both
# directions below are looped over the flag shapes a caller can produce, and the
# one shape that executes nothing is held to the opposite promise.

gate_shape() {   # <flag list>: the gate over $R with only these flags beside --repo
  rm -f "$R/cmd-ran.sentinel"
  run bash "$GATE" --repo "$R" $1   # deliberately unquoted: $1 is a flag list, not a path
}

@test "the consent guard fires in every flag shape that reaches the eval, and not on a run that executes nothing" {
  # A wrapper, because the value has to be recordable for the accept half of this
  # test to exist at all; the sentinel it touches is what both halves judge.
  printf '#!/bin/sh\ntouch cmd-ran.sentinel\n' > "$R/.harmonia/cov.sh"
  chmod +x "$R/.harmonia/cov.sh"
  printf 'coverage: sh .harmonia/cov.sh && echo /nonexistent/nope.xml\n' > "$R/.harmonia/project.yaml"
  # The report path is deliberately unreadable: what the accept side has to prove
  # is that the command RAN, and judging that by a sentinel on disk rather than by
  # an exit code keeps the cells independent of whether diff-cover is installed,
  # which is an environment fact and not a build one (2026-07-31 learning).
  local shapes=(
    ""                                   # --repo alone: no base, no workspace
    "--base $BASE"
    "--workspace $WS"
    "--base $BASE --workspace $WS"
    "--base $BASE --lang bash"
    "--base $BASE --no-branch"
  )
  local s
  for s in "${shapes[@]}"; do
    gate_shape "$s"
    [ ! -f "$R/cmd-ran.sentinel" ] || { echo "reject[$s]: an unattested command ran"; false; }
    [ "$status" -eq 4 ] || { echo "reject[$s]: exit $status, not 4 - $output"; false; }
    [[ "$output" == *".harmonia/project.yaml"* ]] || { echo "reject[$s]: not the consent refusal - $output"; false; }
  done
  # The other direction, and it is what keeps the guard inside `[ -z "$REPORT" ]`:
  # a run handed a report executes nothing, so there is nothing to have consented
  # to and refusing it would be over-refusal.
  write_ts_cov
  rm -f "$R/cmd-ran.sentinel"
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" --report "$R/cov.xml" --lang ts
  [ ! -f "$R/cmd-ran.sentinel" ]
  [[ "$output" != *".harmonia/project.yaml"* ]]
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  for s in "${shapes[@]}"; do
    gate_shape "$s"
    [ -f "$R/cmd-ran.sentinel" ] || { echo "accept[$s]: the attested command did not run - $output"; false; }
    [[ "$output" != *".harmonia/project.yaml"* ]] || { echo "accept[$s]: refused an attested command - $output"; false; }
  done
}

@test "a commit that rewrites the script the attested command names runs at the gate, while an edit to the command itself does not" {
  # INVERTED IN ROUND 5, at the seam, and judged by a sentinel on disk rather than
  # by the absence of a phrase: five of seven admitted shapes exit 4 with `cannot
  # measure - produced no readable report` whichever way consent went, so an
  # accept cell written as "the refusal is not printed" proves nothing on its own.
  #
  # This is the retirement's end-to-end cell. `sh .harmonia/cov.sh` is what
  # onboard's certification flow produces, and its whole job is to run the
  # repository's test suite - hundreds of files no record ever covered - so
  # refusing the rewrite of that one file stopped a repository editing its own
  # coverage wrapper and stopped nothing else. What the developer agreed to is the
  # string, and the string is what the gate compares.
  printf '#!/bin/sh\ntouch script-ran.sentinel\necho /nonexistent/nope.xml\n' > "$R/.harmonia/cov.sh"
  chmod +x "$R/.harmonia/cov.sh"
  printf 'coverage: sh .harmonia/cov.sh\n' > "$R/.harmonia/project.yaml"
  # COMMITTED, which is what a clone delivers: provenance answers "carried by the
  # repository" for exactly the files we are meant to honour.
  git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm cov
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ -f "$R/script-ran.sentinel" ]                  # control: the tree as the developer read it runs
  [[ "$output" != *".harmonia/project.yaml"* ]]
  rm -f "$R/script-ran.sentinel"

  printf '#!/bin/sh\ntouch payload.sentinel\ntouch script-ran.sentinel\necho /nonexistent/nope.xml\n' > "$R/.harmonia/cov.sh"
  # COMMITTED, which is what the cell's title says and what its assertions are
  # about. Without this line the rewrite is a working-tree edit, and a build
  # binding COMMITTED state - a `tree-head:` line in the record, a digest of `git
  # rev-parse HEAD`, anything keyed on what a clone delivers rather than on what
  # is on disk - passes this cell and the whole of `bats tests/` while refusing
  # every repository that lands a commit. The rewrite a clone delivers is a
  # commit, and this is the retirement's end-to-end cell.
  git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm rewrite
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ -f "$R/payload.sentinel" ] || { echo "a commit that rewrote the script the attested command names stopped the gate running it - $output"; false; }
  [ -f "$R/script-ran.sentinel" ] || { echo "the rewritten script did not reach the line that was there before - $output"; false; }
  [[ "$output" != *".harmonia/project.yaml"* ]]

  # ...and the half that keeps this from being "the gate runs anything": one
  # character of the command, with the script left exactly as it was.
  rm -f "$R/payload.sentinel" "$R/script-ran.sentinel"
  printf 'coverage: sh .harmonia/cov.sh \n' > "$R/.harmonia/project.yaml"   # a trailing blank: the same bytes
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ -f "$R/script-ran.sentinel" ]                  # config-lib strips it, so this is not a different string
  rm -f "$R/payload.sentinel" "$R/script-ran.sentinel"
  printf 'coverage: sh .harmonia/cov.sh && echo /nonexistent/nope.xml\n' > "$R/.harmonia/project.yaml"
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ ! -f "$R/script-ran.sentinel" ]                # an edited command runs nothing at all
  [ "$status" -eq 4 ]
  [[ "$output" == *"cannot measure"* ]]
  [[ "$output" == *".harmonia/project.yaml"* ]]    # names what to read...
  [[ "$output" == *"/harmonia:trust"* ]]           # ...and the human command that authorises it
  [[ "$output" != *"trust.sh"* ]]                  # never the script path that clears the refusal
  [ ! -f "$WS/gate-report.md" ]
  [ ! -f "$WS/receipts/coverage.json" ]            # a receipt written at refusal time is fresh by construction

  # Re-recording is the remedy the refusal names, so the gate has to run the
  # edited command once a human has read it.
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ -f "$R/script-ran.sentinel" ]
  [[ "$output" != *".harmonia/project.yaml"* ]]
}

@test "a report the attested command rewrites on every run does not break the next run" {
  # The over-refusal side of binding the files a command names, and the reason it
  # needs its own test: skills/onboard/CERTIFY.md runs the coverage command once,
  # so by the time consent is recorded the report is already a file the command
  # names and rewrites. A build that binds every token naming an existing file
  # passes every reject-side cell of this round and then refuses this repository
  # on its SECOND gate run - measured, and it also passes the whole of `bats
  # tests/`. The report is named twice on purpose (bare and as --out=<path>) and a
  # directory is named as an operand, because a rule broadened to flag values or
  # to directory operands reds only there.
  git -C "$R" checkout -q -- app.ts
  printf 'p1\np2\np3\np4\n' > "$R/calc.py"
  mkdir -p "$R/.harmonia"
  cat > "$R/.harmonia/cov.sh" <<'SH'
#!/bin/sh
# a coverage run that appends to its own log and stamps the report with its size,
# so consecutive reports differ by content without asking a clock for it (`date
# +%s%N` is GNU-only, and two runs inside one second would compare equal).
mkdir -p "$1"
echo run >> "$1/seq"
cat cov.tpl > "$1/cov.xml"
printf '<!-- %s -->\n' "$(wc -c < "$1/seq")" >> "$1/cov.xml"
SH
  chmod +x "$R/.harmonia/cov.sh"
  cat > "$R/cov.tpl" <<'XML'
<?xml version="1.0" ?>
<coverage line-rate="0.5" version="1.9" timestamp="1">
  <packages><package name="c" line-rate="0.5"><classes>
    <class name="calc" filename="calc.py" line-rate="0.5"><lines>
      <line number="2" hits="1"/><line number="4" hits="0"/><line number="5" hits="0"/>
    </lines></class>
  </classes></package></packages>
</coverage>
XML
  printf 'coverage: sh .harmonia/cov.sh out --out=out/cov.xml && echo out/cov.xml\n' > "$R/.harmonia/project.yaml"
  git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm pybase
  PB="$(git -C "$R" rev-parse HEAD)"
  printf 'p1\nCHANGED2\np3\nCHANGED4\nNEW5\n' > "$R/calc.py"

  # The ordinary post-onboarding state: certification ran the command once, so the
  # report and its directory exist when consent is recorded.
  ( cd "$R" && sh .harmonia/cov.sh out )
  local h0 h1 h2
  h0="$(sha256sum "$R/out/cov.xml" | awk '{print $1}')"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  run bash "$GATE" --repo "$R" --base "$PB" --workspace "$WS"
  [[ "$output" != *".harmonia/project.yaml"* ]]
  h1="$(sha256sum "$R/out/cov.xml" | awk '{print $1}')"
  run bash "$GATE" --repo "$R" --base "$PB" --workspace "$WS"
  [[ "$output" != *".harmonia/project.yaml"* ]]
  h2="$(sha256sum "$R/out/cov.xml" | awk '{print $1}')"
  # Both runs executed the command, which is what makes the two assertions above
  # mean something rather than passing over a gate that never reached the seam.
  [ "$h0" != "$h1" ]
  [ "$h1" != "$h2" ]
}

@test "a coverage value hiding a payload behind a control byte is never recorded and never runs, and a tabbed one is refused with it" {
  # The printed line is the control three shipped files name, and a repository can
  # make the string a developer READS differ from the string that EXECUTES:
  # trust_record prints the value raw and config-lib.sh:17 strips only
  # surrounding blanks, so an interior CR survives into the print, the digest and
  # the eval. The shell stops at the `#`; the terminal returns to column zero and
  # is left showing the benign tail. A value that is never recorded can never be
  # attested, which is why the refusal belongs at the recorder.
  printf 'coverage: touch %s/PWNED; echo cov.xml #\rnpx vitest run --coverage && echo cov.xml\n' "$BATS_TEST_TMPDIR" > "$R/.harmonia/project.yaml"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -ne 0 ]
  [ "$(find "$HARMONIA_HOME" -type f 2>/dev/null | wc -l)" -eq 0 ]
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ ! -e "$BATS_TEST_TMPDIR/PWNED" ]
  [ "$status" -eq 4 ]
  [[ "$output" == *"cannot measure"* ]]
  [[ "$output" == *".harmonia/project.yaml"* ]]
  # TAB LEFT THE BYTE CLASS IN ROUND 5, and this half inverts with it: the cap is
  # 1024 bytes because that is what a person can read before agreeing, and a byte
  # worth eight columns makes 1024 bytes into 8192 - 83 wrapped lines, with the
  # payload scrolled off the top of a 24-line terminal. The end-to-end half is
  # what this file adds over tests/trust.bats: refused at the recorder, and then
  # never run by the gate.
  printf '#!/bin/sh\ntouch TABRAN\n' > "$R/.harmonia/tab.sh"
  chmod +x "$R/.harmonia/tab.sh"
  printf 'coverage: sh\t.harmonia/tab.sh && echo /nonexistent/nope.xml\n' > "$R/.harmonia/project.yaml"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -ne 0 ] || { echo "a value carrying a TAB was recorded, and 1024 bytes of TAB is 8192 columns"; false; }
  [ "$(find "$HARMONIA_HOME" -type f 2>/dev/null | wc -l)" -eq 0 ]
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ ! -f "$R/TABRAN" ]
  [ "$status" -eq 4 ]
  [[ "$output" == *".harmonia/project.yaml"* ]]
  # The control, and the reason this is a byte rule rather than a refusal of
  # whitespace: the same value with a space where the TAB was records and runs.
  printf 'coverage: sh .harmonia/tab.sh && echo /nonexistent/nope.xml\n' > "$R/.harmonia/project.yaml"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ -f "$R/TABRAN" ]
  [[ "$output" != *".harmonia/project.yaml"* ]]
  # REVERSED FROM ROUND 2, end to end, and it is the specification that moved. The
  # round-2 rule refused C0 and DEL because those bytes can make the terminal show
  # a command other than the one that runs, and let every byte >= 0x80 through on
  # the argument that é and ç are made of them. U+202E is made of them too - it is
  # the Trojan Source class, CVE-2021-42574, and it reorders the rendered line -
  # and so are U+0085, U+009B, U+200B and a pasted U+00A0. Round 3 refuses every
  # byte outside 0x20-0x7e plus TAB, so all of them die on one rule with no list
  # of codepoints to keep in sync, and a value carrying é is no longer runnable.
  printf 'coverage: sh .harmonia/tab.sh \303\251\303\247 && echo /nonexistent/nope.xml\n' > "$R/.harmonia/project.yaml"
  rm -f "$R/TABRAN"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -ne 0 ]
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ ! -f "$R/TABRAN" ]                             # the value never ran
  [ "$status" -eq 4 ]
  [[ "$output" == *"cannot measure"* ]]
  [[ "$output" == *".harmonia/project.yaml"* ]]
  local before; before="$(find "$HARMONIA_HOME" -type f 2>/dev/null | wc -l)"
  printf 'coverage: sh .harmonia/tab.sh \342\200\256 && echo /nonexistent/nope.xml\n' > "$R/.harmonia/project.yaml"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -ne 0 ]
  [ "$(find "$HARMONIA_HOME" -type f 2>/dev/null | wc -l)" -eq "$before" ]   # no record for a value nothing can print honestly
}

@test "a spelling the grammar cannot attest is refused at the recorder, so the gate never runs the file it names" {
  # B1's table, end to end. All six record today. Four of them bind nothing a file
  # could match - `. cov.sh` and `npx vitest --coverage` name no reference at all,
  # `sh -c '…'` names the token `'sh` and `sh <cov.sh` names `<` - and each was
  # measured running a rewritten .harmonia/cov.sh under the consent recorded for
  # the old one, with the coverage: line untouched and nothing for the developer to
  # re-read. The other two bind the script correctly today, by scanning every token
  # of the value for an interpreter word: that scan is the predicate this round
  # retires, and it is the same scan that emitted `/bin/sh` as its own reference
  # and `'a` for `sh 'a b.sh'`. The answer is not a better scan - it is that a value
  # the recorder cannot describe honestly is refused while a human is there to read
  # the refusal, and a value that is never recorded can never be attested. This is
  # the gate-side half of that: the recorder refuses, and the gate then refuses the
  # same value for want of a record, running nothing.
  printf '#!/bin/sh\ntouch %s/PWNED\necho /nonexistent/nope.xml\n' "$BATS_TEST_TMPDIR" > "$R/.harmonia/cov.sh"
  chmod +x "$R/.harmonia/cov.sh"
  # ROUND 4's spellings, in the same loop and for the same reason, and ROUND 5's
  # three new ones at the end: `V+=x/y` is the assignment spelling the old regex
  # missed, which classified the assignment itself as the program and preloaded a
  # payload through BASH_ENV in the same shape; `sh cov.sh` is the slash-less
  # operand a bare interpreter PATH-searches, so what runs is a file the value
  # does not name; and `/bin/sh -c payload` is `sh -c payload` spelled to dodge a
  # rule keyed on the bare word. Each is refused at the recorder, and the gate
  # then runs nothing.
  #
  # ONE VALUE LEFT THIS LOOP IN ROUND 5 AND COMES BACK IN ROUND 6, along with
  # three more, and they are the whole of the change here: `<ext>/launch sh
  # .harmonia/cov.sh` is an out-of-tree program as the first word, which round 5
  # admitted on the argument that a word carrying a `/` names a file the reader
  # can go and look at. What that class bought was a launcher whose LATER words
  # nothing constrained: `/usr/bin/env PATH=fakebin sh ./cov.sh` recorded and ran
  # the repository's own `fakebin/sh` end to end, with the value's own words
  # naming a script that never ran. The class goes, and with it the three
  # spellings below - a launcher, an interpreter named by its path, and a tool
  # named by its path - each refused at the recorder, each running nothing.
  mkdir -p "$BATS_TEST_TMPDIR/ext" "$R/-P" "$R/node_modules/.bin"
  printf '#!/bin/sh\nexec "$@"\n' > "$BATS_TEST_TMPDIR/ext/launch"
  chmod +x "$BATS_TEST_TMPDIR/ext/launch"
  printf '#!/bin/sh\ntouch %s/PWNED\necho /nonexistent/nope.xml\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/ext/cov.sh"
  chmod +x "$BATS_TEST_TMPDIR/ext/cov.sh"
  cp "$R/.harmonia/cov.sh" "$R/-P/cov.sh"
  ln -sfn "$BATS_TEST_TMPDIR/ext/launch" "$R/sh"
  # The tool is written HERE, above the loop, so that its own refusal is about
  # the spelling and not about a missing file - and it touches both sentinels, so
  # the loop can prove it never ran while the control below proves it does run
  # once a card word is in front of it.
  printf '#!/bin/sh\ntouch %s/PWNED\ntouch %s/TOOL-RAN\necho /nonexistent/nope.xml\n' \
    "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" > "$R/node_modules/.bin/vitest"
  chmod +x "$R/node_modules/.bin/vitest"
  local v
  for v in \
    'env sh .harmonia/cov.sh && echo cov.xml' \
    'VAR=1 sh .harmonia/cov.sh && echo cov.xml' \
    '. .harmonia/cov.sh && echo cov.xml' \
    "sh -c 'sh .harmonia/cov.sh'" \
    'sh < .harmonia/cov.sh && echo cov.xml' \
    'npx vitest --coverage && echo cov.xml' \
    './sh bash .harmonia/cov.sh && echo cov.xml' \
    'V=x/y sh .harmonia/cov.sh && echo cov.xml' \
    'sh +x .harmonia/cov.sh && echo cov.xml' \
    'sh ../ext/cov.sh && echo cov.xml' \
    'cd -P && sh ./cov.sh && echo cov.xml' \
    'V+=x/y sh .harmonia/cov.sh && echo cov.xml' \
    'sh cov.sh && echo cov.xml' \
    '/bin/sh -c payload && echo cov.xml' \
    '/bin/sh .harmonia/cov.sh && echo cov.xml' \
    './node_modules/.bin/vitest run --coverage' \
    "$BATS_TEST_TMPDIR/ext/launch sh .harmonia/cov.sh && echo cov.xml" \
    "$BATS_TEST_TMPDIR/ext/launch PATH=$R/node_modules/.bin sh ./cov.sh && echo cov.xml" \
    'sh /dev/stdin && echo cov.xml'
  do
    rm -rf "$HARMONIA_HOME" "$BATS_TEST_TMPDIR/PWNED" "$WS/gate-report.md" "$WS/receipts/coverage.json"
    printf 'coverage: %s\n' "$v" > "$R/.harmonia/project.yaml"
    run bash "$TRUST" record --repo "$R"
    [ "$status" -ne 0 ] || { echo "[$v]: the recorder attested a value it cannot say what it binds"; false; }
    [ "$(find "$HARMONIA_HOME" -type f 2>/dev/null | wc -l)" -eq 0 ] || { echo "[$v]: a record landed for a refused value"; false; }
    run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
    [ ! -e "$BATS_TEST_TMPDIR/PWNED" ] || { echo "[$v]: the gate ran a value nobody could record consent for"; false; }
    [ "$status" -eq 4 ] || { echo "[$v]: exit $status, not 4 - $output"; false; }
    [[ "$output" == *"cannot measure"* ]] || { echo "[$v]: not a cannot-measure refusal - $output"; false; }
    [[ "$output" == *".harmonia/project.yaml"* ]] || { echo "[$v]: does not name the file to read - $output"; false; }
    [ ! -f "$WS/gate-report.md" ] || { echo "[$v]: wrote a report on a refusal"; false; }
    [ ! -f "$WS/receipts/coverage.json" ] || { echo "[$v]: wrote a receipt on a refusal"; false; }
  done
  # THE CONTROL, RESPELLED IN ROUND 6 AND NOT DELETED, because it is what stops
  # every cell above being satisfied by a build that refuses every repository on
  # the machine. It used to be `./node_modules/.bin/vitest run --coverage`, which
  # is now one of the refusals above - so the control moves to what this round
  # tells that developer to write instead: the same tool, with the interpreter
  # that runs it in front. WHICH interpreter is a fact about the file rather than
  # a free choice, and it is the thing the documents have to say: this shim is
  # `#!/bin/sh` (the pnpm and yarn shape), an npm-style shim is a `.js` file that
  # needs `node`, and a native binary - esbuild, swc, biome, turbo - runs under
  # neither and needs a wrapper. The recorder opens no file, so it cannot tell a
  # developer which; they read the first line.
  rm -rf "$HARMONIA_HOME" "$BATS_TEST_TMPDIR/PWNED" "$BATS_TEST_TMPDIR/TOOL-RAN"
  printf 'coverage: sh ./node_modules/.bin/vitest run --coverage\n' > "$R/.harmonia/project.yaml"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ] || { echo "the remedy this round advises for a tool named by its path was itself refused at the recorder: $output"; false; }
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ -f "$BATS_TEST_TMPDIR/TOOL-RAN" ] || { echo "the respelled tool did not run at the gate - $output"; false; }
  [[ "$output" != *".harmonia/project.yaml"* ]]
  # ...and the second remedy, which is the one for everything that is not a script
  # in one of the card's six languages: a wrapper of the repository's own, which
  # is where a launcher, a timeout and a native binary all go now that no value
  # can spell them.
  rm -rf "$HARMONIA_HOME" "$BATS_TEST_TMPDIR/WRAPPED"
  printf '#!/bin/sh\nexec %s/ext/launch %s/ext/cov.sh\n' "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" > "$R/.harmonia/wrap.sh"
  chmod +x "$R/.harmonia/wrap.sh"
  printf 'coverage: sh ./.harmonia/wrap.sh && echo /nonexistent/nope.xml\n' > "$R/.harmonia/project.yaml"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ] || { echo "the wrapper remedy was refused at the recorder: $output"; false; }
  rm -f "$BATS_TEST_TMPDIR/PWNED"
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ -e "$BATS_TEST_TMPDIR/PWNED" ] || { echo "the wrapper remedy did not reach the gate, so the class the round refuses has no working replacement - $output"; false; }
  [[ "$output" != *".harmonia/project.yaml"* ]]
}

@test "a monorepo command that changes directory first runs at the gate, and keeps running when the script it names is rewritten" {
  # `cd sub && sh ./cov.sh && echo sub/cov.xml` is a working repository and the
  # ceiling cell that says so. Its `./` is R10's: an interpreter's script operand
  # carries a `/`, because a slash-less one is PATH-searched and what runs is then
  # a file the value does not name.
  #
  # INVERTED IN ROUND 5 on its last leg. Round 2 declared the `cd` unfollowed and
  # bound a name that was never there; round 3 followed it and bound sub/cov.sh;
  # round 5 binds nothing, so what this cell holds is the accept side - a monorepo
  # keeps running through every edit its own developers make, including to the
  # script the command names.
  mkdir -p "$R/sub"
  printf '#!/bin/sh\ntouch script-ran.sentinel\necho /nonexistent/nope.xml\n' > "$R/sub/cov.sh"
  chmod +x "$R/sub/cov.sh"
  printf 'console.log(1)\n' > "$R/sub/src.js"
  printf 'coverage: cd sub && sh ./cov.sh && echo /nonexistent/nope.xml\n' > "$R/.harmonia/project.yaml"
  git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm sub
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ -f "$R/sub/script-ran.sentinel" ]               # control: the tree as the developer read it runs
  [[ "$output" != *".harmonia/project.yaml"* ]]
  # An ordinary edit to ordinary product code beside the script.
  printf 'console.log(2)\n' > "$R/sub/src.js"
  rm -f "$R/sub/script-ran.sentinel"
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ -f "$R/sub/script-ran.sentinel" ]
  [[ "$output" != *".harmonia/project.yaml"* ]]
  # And the script the command runs after the cd, which rounds 3 and 4 refused.
  printf '#!/bin/sh\ntouch %s/PWNED\ntouch script-ran.sentinel\necho /nonexistent/nope.xml\n' "$BATS_TEST_TMPDIR" > "$R/sub/cov.sh"
  rm -f "$R/sub/script-ran.sentinel"
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ -e "$BATS_TEST_TMPDIR/PWNED" ] || { echo "rewriting the script a monorepo value names stopped the gate running it - $output"; false; }
  [ -f "$R/sub/script-ran.sentinel" ] || { echo "the rewritten script did not reach the line that was there before - $output"; false; }
  [[ "$output" != *".harmonia/project.yaml"* ]]
  # The string still decides, at this seam too: the same monorepo value with its
  # cd operand spelled differently is a value nobody agreed to, and nothing runs.
  rm -f "$BATS_TEST_TMPDIR/PWNED" "$R/sub/script-ran.sentinel"
  printf 'coverage: cd sub/ && sh ./cov.sh && echo /nonexistent/nope.xml\n' > "$R/.harmonia/project.yaml"
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ ! -e "$BATS_TEST_TMPDIR/PWNED" ]
  [ "$status" -eq 4 ]
  [[ "$output" == *"cannot measure"* ]]
  [[ "$output" == *".harmonia/project.yaml"* ]]
  [[ "$output" == *"/harmonia:trust"* ]]
  [ ! -f "$WS/gate-report.md" ]
  # Re-recording is the remedy the refusal names, so it has to work for this shape
  # too - a monorepo that can never re-consent is a monorepo that is refused.
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ -e "$BATS_TEST_TMPDIR/PWNED" ]
  [[ "$output" != *".harmonia/project.yaml"* ]]
}

@test "an exported CDPATH does not send the one cd the grammar admits into a sibling tree" {
  # `cd sub && sh ./cov.sh` is the monorepo shape the grammar admits. POSIX `cd`
  # searches CDPATH before the current directory for an operand that does not
  # begin with `/`, `./` or `../`, so a developer with `CDPATH=$HOME/src` in their
  # .bashrc - which is an ordinary line, not an attack - has the gate change into
  # a SIBLING repository's `sub/` and run that tree's `cov.sh` under this tree's
  # recorded consent. It needs nobody hostile, and no rule about the string can
  # close it: the disagreement is in the shell rather than in the path. G1 is what
  # makes `cd sub` mean this repository's `sub`, and with the resolver retired it
  # is the only thing that does.
  #
  # trust_key and bin/base-ref-lib.sh:71-72 already clear CDPATH before
  # their own cd; the one cd the grammar admits is the third site.
  mkdir -p "$R/sub" "$BATS_TEST_TMPDIR/sibling/sub"
  printf '#!/bin/sh\ntouch %s/attested-ran\necho /nonexistent/nope.xml\n' "$BATS_TEST_TMPDIR" > "$R/sub/cov.sh"
  printf '#!/bin/sh\ntouch %s/SIBLING-RAN\necho /nonexistent/nope.xml\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/sibling/sub/cov.sh"
  chmod +x "$R/sub/cov.sh" "$BATS_TEST_TMPDIR/sibling/sub/cov.sh"
  printf 'coverage: cd sub && sh ./cov.sh && echo /nonexistent/nope.xml\n' > "$R/.harmonia/project.yaml"
  git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm sub
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  # The control first, with no CDPATH: this value runs the script it names.
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ -f "$BATS_TEST_TMPDIR/attested-ran" ]
  [ ! -f "$BATS_TEST_TMPDIR/SIBLING-RAN" ]
  rm -f "$BATS_TEST_TMPDIR/attested-ran"
  run env CDPATH="$BATS_TEST_TMPDIR/sibling" bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ ! -f "$BATS_TEST_TMPDIR/SIBLING-RAN" ] || { echo "an exported CDPATH ran a sibling tree's script under this tree's consent - $output"; false; }
  [ -f "$BATS_TEST_TMPDIR/attested-ran" ] || { echo "the attested script did not run with CDPATH set - $output"; false; }
}

@test "a PATH entry the repository can write does not decide what the bare word sh names, while the developer's own toolchain stays reachable" {
  # G2, and it is the one place round 5 ADDS code rather than removing it. The
  # interpreter arm is the whole reason a bare word is admitted at all, on the
  # premise that `sh` is the machine's: a repository commit cannot change what
  # /bin/sh is. `PATH_add node_modules/.bin` in an .envrc is repository content
  # that makes the premise false, and a repository that ships its own `sh` then
  # decides what every value in the grammar's largest class runs.
  #
  # BOTH HALVES ARE NEEDED, and the second is why a resolve-and-compare filter is
  # not enough: a RELATIVE entry is resolved against the directory the value runs
  # in, and the gate's own `cd "$REPO"` is what moves it inside the tree - so an
  # entry that looked outside when the filter ran is inside by the time the shell
  # searches it. Reproduced with the plainest value in the set.
  mkdir -p "$R/node_modules/.bin" "$BATS_TEST_TMPDIR/tools"
  printf '#!/bin/sh\ntouch %s/MINE\necho /nonexistent/nope.xml\n' "$BATS_TEST_TMPDIR" > "$R/cov.sh"
  chmod +x "$R/cov.sh"
  printf 'coverage: sh ./cov.sh && echo /nonexistent/nope.xml\n' > "$R/.harmonia/project.yaml"
  git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm cov
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  # The control: with an ordinary PATH the value runs, so every cell below is
  # about which `sh` ran and not about whether anything ran.
  rm -f "$BATS_TEST_TMPDIR/MINE"
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ -f "$BATS_TEST_TMPDIR/MINE" ] || { echo "the attested value did not run with an ordinary PATH - $output"; false; }
  # An absolute entry inside the repository.
  printf '#!/bin/sh\ntouch %s/REPO-SH-RAN\nexec /bin/sh "$@"\n' "$BATS_TEST_TMPDIR" > "$R/node_modules/.bin/sh"
  chmod +x "$R/node_modules/.bin/sh"
  rm -f "$BATS_TEST_TMPDIR/MINE" "$BATS_TEST_TMPDIR/REPO-SH-RAN"
  run env PATH="$R/node_modules/.bin:$PATH" bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ ! -f "$BATS_TEST_TMPDIR/REPO-SH-RAN" ] || { echo "an absolute PATH entry inside the repository decided what the bare word sh names - $output"; false; }
  [ -f "$BATS_TEST_TMPDIR/MINE" ] || { echo "the value did not run with a repository PATH entry present - $output"; false; }
  # A RELATIVE entry, run from the repository root so it is the same directory
  # spelled without a leading slash. This is the half that defeats resolving each
  # entry and comparing it: at filter time the cwd is wherever the gate was
  # invoked, and `cd "$REPO"` happens afterwards.
  printf '#!/bin/sh\ntouch %s/RELATIVE-SH-RAN\nexec /bin/sh "$@"\n' "$BATS_TEST_TMPDIR" > "$R/node_modules/.bin/sh"
  chmod +x "$R/node_modules/.bin/sh"
  rm -f "$BATS_TEST_TMPDIR/MINE" "$BATS_TEST_TMPDIR/RELATIVE-SH-RAN"
  # Captured rather than `run`, because the cwd is what this cell varies and `run`
  # cannot carry a subshell's status back out (`env -C` is GNU-only).
  local relout
  relout="$( cd "$R" && PATH="node_modules/.bin:$PATH" bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS" 2>&1 )" || true
  [ ! -f "$BATS_TEST_TMPDIR/RELATIVE-SH-RAN" ] || { echo "a relative PATH entry decided what the bare word sh names, because cd \$REPO moved it inside the tree - $relout"; false; }
  [ -f "$BATS_TEST_TMPDIR/MINE" ] || { echo "the value did not run with a relative PATH entry present - $relout"; false; }
  # ...and the fix cannot be "empty the PATH": an absolute entry OUTSIDE the
  # repository is the developer's own toolchain, and it stays reachable.
  printf '#!/bin/sh\ntouch %s/OUTSIDE-TOOL-RAN\nexec /bin/sh "$@"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/tools/sh"
  chmod +x "$BATS_TEST_TMPDIR/tools/sh"
  rm -f "$BATS_TEST_TMPDIR/MINE" "$BATS_TEST_TMPDIR/OUTSIDE-TOOL-RAN"
  run env PATH="$BATS_TEST_TMPDIR/tools:$PATH" bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ -f "$BATS_TEST_TMPDIR/OUTSIDE-TOOL-RAN" ] || { echo "an absolute PATH entry outside the repository was dropped, so the developer's own toolchain stopped being reachable - $output"; false; }
  [ -f "$BATS_TEST_TMPDIR/MINE" ] || { echo "the value did not run with an outside PATH entry present - $output"; false; }
  # ROUND 6: PATH IDENTITY IS NOT STRING IDENTITY, and a filter written as four
  # `case` patterns over two spellings is an author who has enumerated two members
  # of an infinite set. `//repo/bin` names the same directory as `/repo/bin` on
  # Linux and matches none of the four; `export PATH="/$PWD/bin:$PATH"` in an
  # .envrc produces exactly that entry and costs one character. A symlinked
  # parent and a bind mount are the same gap with a different spelling, and the
  # loop is written over spellings rather than as one cell because what is being
  # asserted is that the filter compares DIRECTORIES.
  #
  # ONE MEASUREMENT FOR WHOEVER WRITES THE FILTER, because the obvious fix does
  # not close the obvious spelling: `cd "$p" && pwd -P` does NOT normalise a
  # leading double slash. POSIX reserves a path beginning with exactly two
  # slashes, and bash's own `pwd -P` answers `//tmp/x` for `cd //tmp/x` - so a
  # resolve-and-compare built on `cd`+`pwd -P` keeps the entry that B3 was
  # reproduced with, while three or more leading slashes collapse and every other
  # spelling in this loop resolves correctly. `readlink -f` and `realpath` both
  # answer `/tmp/x`. Measured here, on this machine, against a build carrying the
  # `cd`+`pwd -P` form: only the `//` row fails.
  #
  # Every spelling is measured before the cell decides, so a build closes them in
  # one round rather than in five.
  local spelling repo_link bad=''
  repo_link="$BATS_TEST_TMPDIR/via-link"
  ln -sfn "$R" "$repo_link"
  for spelling in \
    "/$R/node_modules/.bin" \
    "$R/node_modules/.bin/" \
    "$R/./node_modules/.bin" \
    "$R/node_modules/../node_modules/.bin" \
    "$repo_link/node_modules/.bin"
  do
    printf '#!/bin/sh\ntouch %s/SPELLED-SH-RAN\nexec /bin/sh "$@"\n' "$BATS_TEST_TMPDIR" > "$R/node_modules/.bin/sh"
    chmod +x "$R/node_modules/.bin/sh"
    rm -f "$BATS_TEST_TMPDIR/MINE" "$BATS_TEST_TMPDIR/SPELLED-SH-RAN"
    run env PATH="$spelling:$PATH" bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
    [ ! -f "$BATS_TEST_TMPDIR/SPELLED-SH-RAN" ] || bad="$bad
  [$spelling] decided what the bare word sh names"
    [ -f "$BATS_TEST_TMPDIR/MINE" ] || bad="$bad
  [$spelling] the value did not run at all, so that row proves nothing - $output"
  done
  [ -z "$bad" ] || { echo "a second spelling of a directory inside the repository reached the interpreter:$bad"; false; }
}

@test "a second spelling of /dev/stdin is refused at both doors, and the bytes on the other side of the pipe never run" {
  # ROUND 7's BLOCKER, END TO END, because a recorder verdict is not what this is
  # about: the reproduction that matters is a payload executing at the gate. The
  # operand rule compares two strings - `/dev/*` and `/proc/*` - and the hazard is
  # two filesystems, so `//dev/stdin` reaches the same door at a cost of one
  # character and recorded, attested and ran on the build that shipped the rule.
  #
  # No word of this value names what runs: the first part prints a command and the
  # second executes whatever arrived on its standard input. That is the class
  # bin/trust.sh says out loud it has closed.
  printf '#!/bin/sh\necho "touch %s/PWNED-VIA-DEV"\n' "$BATS_TEST_TMPDIR" > "$R/gen.sh"
  chmod +x "$R/gen.sh"
  local v='sh ./gen.sh | sh //dev/stdin'
  # DOOR ONE, the recorder: a value that is never recorded can never be attested.
  printf 'coverage: %s\n' "$v" > "$R/.harmonia/project.yaml"
  rm -f "$BATS_TEST_TMPDIR/PWNED-VIA-DEV"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -ne 0 ] || { echo "the recorder attested a second spelling of /dev/stdin, so a value whose words name nothing that runs is one character from being recordable: $output"; false; }
  [ "$(find "$HARMONIA_HOME" -type f 2>/dev/null | wc -l)" -eq 0 ] || { echo "a record landed for a second spelling of /dev/stdin"; false; }
  # DOOR TWO, the gate, which re-applies the grammar above the eval - so a record
  # this recorder did not write must not carry the same value through either. The
  # record is hand-written at the path the recorder itself chose, taken by
  # recording a value the grammar does admit and then rewriting that file, so
  # nothing here pins the store's layout.
  printf 'coverage: echo cov.xml\n' > "$R/.harmonia/project.yaml"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  local rec; rec="$(find "$HARMONIA_HOME" -type f | head -1)"
  [ -n "$rec" ]
  printf 'repo: %s\ncoverage-sha256: %s\nrecorded: 2026-08-11T00:00:00Z\n' \
    "$( cd "$R" && pwd -P )" \
    "$(printf '%s' "$v" | sha256sum | awk '{print $1}')" \
    > "$rec"
  printf 'coverage: %s\n' "$v" > "$R/.harmonia/project.yaml"
  rm -f "$BATS_TEST_TMPDIR/PWNED-VIA-DEV"
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ ! -e "$BATS_TEST_TMPDIR/PWNED-VIA-DEV" ] || { echo "a second spelling of /dev/stdin reached the eval and ran the bytes the first part of the value printed, which no word of that value names - $output"; false; }
  [ "$status" -eq 4 ] || { echo "exit $status, not 4 - $output"; false; }
  [[ "$output" == *"cannot measure"* ]]
  [ ! -f "$WS/gate-report.md" ]
  # A SECOND SPELLING AT THE SAME SEAM, because the leading `//` is the one a fix
  # is most likely to reach for and the one the gate's own PATH filter already
  # normalises: `/./dev/stdin` is untouched by that normalisation and opens the
  # same door. Measured, both of them run the bytes.
  local w='sh ./gen.sh | sh /./dev/stdin'
  printf 'repo: %s\ncoverage-sha256: %s\nrecorded: 2026-08-11T00:00:00Z\n' \
    "$( cd "$R" && pwd -P )" \
    "$(printf '%s' "$w" | sha256sum | awk '{print $1}')" \
    > "$rec"
  printf 'coverage: %s\n' "$w" > "$R/.harmonia/project.yaml"
  rm -f "$BATS_TEST_TMPDIR/PWNED-VIA-DEV"
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ ! -e "$BATS_TEST_TMPDIR/PWNED-VIA-DEV" ] || { echo "a /./ spelling of /dev/stdin reached the eval and ran the bytes the first part of the value printed - $output"; false; }
  [ "$status" -eq 4 ] || { echo "exit $status, not 4 for the /./ spelling - $output"; false; }
  # The control, in the same cell: the pipeline shape itself is not what is being
  # refused, and a repository that pipes its coverage run into a script it names
  # still records and still runs.
  rm -rf "$HARMONIA_HOME"
  printf '#!/bin/sh\n: > %s/PIPED-RAN\necho /nonexistent/nope.xml\n' "$BATS_TEST_TMPDIR" > "$R/sink.sh"
  chmod +x "$R/sink.sh"
  printf 'coverage: sh ./gen.sh | sh ./sink.sh\n' > "$R/.harmonia/project.yaml"
  rm -f "$BATS_TEST_TMPDIR/PIPED-RAN"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ] || { echo "the rule refused an ordinary pipeline into a script the value names, which is over-refusal rather than the class: $output"; false; }
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ -f "$BATS_TEST_TMPDIR/PIPED-RAN" ] || { echo "an attested pipeline into a script the value names did not run - $output"; false; }
}

@test "a record the recorder did not write does not let a value the grammar refuses reach the eval" {
  # THE GRAMMAR HAS ONLY EVER BEEN A RECORD-TIME FILTER, and this is what that
  # costs at the seam. The gate asks whether a well-formed record carries this
  # string's digest; it never asks whether the string is one the grammar admits.
  # So a record this recorder did not write - hand-written, forged, or written by
  # an earlier round, which the migration deliberately keeps valid - puts an
  # unfiltered string into `eval`. Every record written while round 5 was live
  # covers a value round 6 refuses, and the people most likely to hold one are the
  # people a launcher value was recorded for: without the re-check, the narrowing
  # reaches new records only.
  #
  # The value is `sh ./gen.sh | /bin/sh`, which is bin/trust.sh's own worked
  # example of "runs bytes no word names" - refused at the door by this build and,
  # measured, run to completion at this seam. The payload is generated by the
  # first part and executed by the second, so no word of the value names it.
  printf '#!/bin/sh\necho "touch %s/PWNED-VIA-PIPE"\n' "$BATS_TEST_TMPDIR" > "$R/gen.sh"
  chmod +x "$R/gen.sh"
  local v='sh ./gen.sh | /bin/sh'
  printf 'coverage: %s\n' "$v" > "$R/.harmonia/project.yaml"
  # The recorder refuses it, which is the half that already holds - and the store
  # is left empty, so the record below is the only one there is.
  run bash "$TRUST" record --repo "$R"
  [ "$status" -ne 0 ]
  [ "$(find "$HARMONIA_HOME" -type f 2>/dev/null | wc -l)" -eq 0 ]
  # ...and a record for it, written by hand in the shape the recorder itself
  # writes, at the path it itself chooses. Nothing here pins the store's layout:
  # the path is taken by recording a value the grammar does admit and then
  # rewriting that file.
  printf 'coverage: echo cov.xml\n' > "$R/.harmonia/project.yaml"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  local rec; rec="$(find "$HARMONIA_HOME" -type f | head -1)"
  [ -n "$rec" ]
  printf 'repo: %s\ncoverage-sha256: %s\nrecorded: 2026-08-11T00:00:00Z\n' \
    "$( cd "$R" && pwd -P )" \
    "$(printf '%s' "$v" | sha256sum | awk '{print $1}')" \
    > "$rec"
  printf 'coverage: %s\n' "$v" > "$R/.harmonia/project.yaml"
  rm -f "$BATS_TEST_TMPDIR/PWNED-VIA-PIPE"
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ ! -e "$BATS_TEST_TMPDIR/PWNED-VIA-PIPE" ] || { echo "a record this recorder could not have written put a value the grammar refuses into the eval, and it ran bytes no word of that value names - $output"; false; }
  [ "$status" -eq 4 ] || { echo "exit $status, not 4 - $output"; false; }
  [[ "$output" == *"cannot measure"* ]]
  [ ! -f "$WS/gate-report.md" ]
  # The migration this does NOT break, in the same cell: a hand-written record for
  # a value the grammar still admits attests exactly as before, which is the
  # promise the round keeps while narrowing the one it does not.
  printf 'coverage: echo /nonexistent/nope.xml\n' > "$R/.harmonia/project.yaml"
  printf 'repo: %s\ncoverage-sha256: %s\nrecorded: 2026-08-11T00:00:00Z\n' \
    "$( cd "$R" && pwd -P )" \
    "$(printf '%s' 'echo /nonexistent/nope.xml' | sha256sum | awk '{print $1}')" \
    > "$rec"
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [[ "$output" != *".harmonia/project.yaml"* ]] || { echo "the re-check refused a legacy record for a value the grammar still admits, which is the migration this round does not reopen - $output"; false; }
}

@test "the seam clears the environment channels that put code inside an interpreter, and leaves the toolchain variable it declares inherited" {
  # The card says these are the machine's interpreters, and three of the six take
  # code from the environment: `BASH_ENV` runs a file before bash reads the script
  # it was given, `NODE_OPTIONS=--require` does the same for node, and `PYTHONPATH`
  # plus a `sitecustomize.py` does it for python3 - all three measured firing. The
  # deletion of the `/`-carrying class makes this worse rather than better,
  # because after it the interpreter arm is the only arm that executes anything at
  # all, and an `.envrc` exports arbitrary names rather than only PATH_add.
  #
  # ASKED BY HAVING THE VALUE ITSELF REPORT ITS ENVIRONMENT, which is the only way
  # to assert a clearing rather than assert that a payload happened not to fire:
  # the gate is bash and reads BASH_ENV at its own startup, which is the declared
  # class this sits in (anyone who can set the gate's environment can run the
  # command directly). What the seam owes is that the interpreter it starts for
  # the repository's command does not carry those channels.
  #
  # The list is a denylist and cannot be completed, so what it is NOT is asserted
  # in the same cell: LD_LIBRARY_PATH stays inherited, because it is a toolchain
  # input for nix and conda and not a code-injection path for a card interpreter,
  # and a build that clears everything it can name would pass a one-sided cell.
  cat > "$R/.harmonia/envcov.sh" <<'SH'
#!/bin/sh
{
  echo "BASH_ENV=[${BASH_ENV-}]"
  echo "ENV=[${ENV-}]"
  echo "LD_PRELOAD=[${LD_PRELOAD-}]"
  echo "PYTHONSTARTUP=[${PYTHONSTARTUP-}]"
  echo "NODE_OPTIONS=[${NODE_OPTIONS-}]"
  echo "PYTHONPATH=[${PYTHONPATH-}]"
  echo "LD_LIBRARY_PATH=[${LD_LIBRARY_PATH-}]"
} > "$1"
echo /nonexistent/nope.xml
SH
  chmod +x "$R/.harmonia/envcov.sh"
  local seen="$BATS_TEST_TMPDIR/seam-env"
  printf 'coverage: sh .harmonia/envcov.sh %s && echo /nonexistent/nope.xml\n' "$seen" > "$R/.harmonia/project.yaml"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  run env \
    BASH_ENV="$BATS_TEST_TMPDIR/hook.sh" \
    ENV="$BATS_TEST_TMPDIR/hook.sh" \
    LD_PRELOAD="$BATS_TEST_TMPDIR/evil.so" \
    PYTHONSTARTUP="$BATS_TEST_TMPDIR/hook.py" \
    NODE_OPTIONS="--require $BATS_TEST_TMPDIR/evil.js" \
    PYTHONPATH="$BATS_TEST_TMPDIR/sitedir" \
    LD_LIBRARY_PATH="$BATS_TEST_TMPDIR/libs" \
    bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ -f "$seen" ] || { echo "the attested value did not run, so this cell measured nothing - $output"; false; }
  local name
  for name in BASH_ENV ENV LD_PRELOAD PYTHONSTARTUP NODE_OPTIONS PYTHONPATH; do
    grep -qxF "$name=[]" "$seen" || {
      echo "$name reached the interpreter the seam starts for the repository's command, and it is a channel that puts a file of somebody else's choosing inside it: $(grep "^$name=" "$seen")"; false; }
  done
  grep -qxF "LD_LIBRARY_PATH=[$BATS_TEST_TMPDIR/libs]" "$seen" || {
    echo "LD_LIBRARY_PATH is declared inherited - it is a toolchain input for nix and conda - and the seam cleared it, which breaks a repository whose command works everywhere else: $(grep '^LD_LIBRARY_PATH=' "$seen")"; false; }
  # SHELLOPTS AND BASHOPTS ARE READONLY IN BASH AND CANNOT JOIN THAT LIST, and
  # this is the leg that keeps the two fixes apart: a shell that folds case is a
  # real defect and it is fixed in the RECORDER with `shopt -u`, not by adding two
  # more names here. Merging them stops the gate running any coverage command at
  # all - the unset fails, and under a shell that stops on error it takes the
  # subshell the value runs in down with it. Asserted as "the value still runs",
  # because that is the failure a developer would meet.
  rm -f "$seen"
  run env BASHOPTS=nocasematch SHELLOPTS=braceexpand \
    bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ -f "$seen" ] || { echo "with BASHOPTS and SHELLOPTS set in the environment the attested value did not run at all, which is what happens when two readonly names are added to the seam's unset list - $output"; false; }
}

@test "a repository that vendors its toolchain does not become the interpreter, because the filtered PATH falls back to an absolute default rather than to here" {
  # THIS IS THE CELL THE ROUND TURNS ON, and it is the one place where deleting
  # the `/`-carrying first-word class is NOT what closes the hole. `sh ./cov.sh`
  # is the plainest value the grammar admits and the one spelling round 6
  # blesses; the filter above drops every PATH entry that is relative or inside
  # the tree; and a repository that vendors its toolchain - the direnv case the
  # gate's own comment names - has NOTHING LEFT. An empty PATH does not mean "no
  # directories": bash searches the current directory, which after the `cd` is the
  # repository root, so the repository's own `./sh` runs as the interpreter under
  # recorded consent, with the head class already gone.
  #
  # THE SPELLING OF THE FLOOR IS WHAT DECIDES IT. An assignment of an absolute
  # default when the filter produced nothing closes it; a JOIN onto what the
  # filter produced - `PATH="${COV_PATH}:/usr/bin:/bin"` - reopens it byte for
  # byte, because a leading, trailing or doubled `:` is an empty field and an
  # empty field means here. Both builds pass every other cell in this file, and
  # this one separates them. Measured against a joining build: the repository's
  # own `./sh` ran.
  #
  # THE SENTINELS ARE REDIRECTS, NEVER `touch`. Inside that subshell the external
  # tools are gone by construction, so a cell that writes its sentinel with a
  # command goes green for a reason that has nothing to do with the guard.
  mkdir -p "$R/vendor/bin"
  printf '#!/bin/sh\n: > %s/MINE\necho /nonexistent/nope.xml\n' "$BATS_TEST_TMPDIR" > "$R/cov.sh"
  chmod +x "$R/cov.sh"
  # The repository's own interpreter, at the root, which is where an empty PATH
  # entry looks. It hands the arguments on to the real shell, so a build that
  # runs it looks exactly like a build that did not - the sentinel is the only
  # difference, which is the whole shape of this hazard.
  printf '#!/bin/sh\n: > %s/REPO-SH-RAN\nexec /bin/sh "$@"\n' "$BATS_TEST_TMPDIR" > "$R/sh"
  chmod +x "$R/sh"
  printf 'coverage: sh ./cov.sh && echo /nonexistent/nope.xml\n' > "$R/.harmonia/project.yaml"
  git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm vendored
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  # The control, with an ordinary PATH: the value runs and the machine's sh is
  # what ran it.
  rm -f "$BATS_TEST_TMPDIR/MINE" "$BATS_TEST_TMPDIR/REPO-SH-RAN"
  run bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ -f "$BATS_TEST_TMPDIR/MINE" ] || { echo "the attested value did not run with an ordinary PATH - $output"; false; }
  [ ! -f "$BATS_TEST_TMPDIR/REPO-SH-RAN" ]
  # The vendored toolchain: every tool the gate itself needs, reachable at an
  # absolute path INSIDE the repository. This is a repository that works - it is
  # nix, direnv and `PATH_add` - and the filter is right to drop the entry. What
  # it must not do is leave the search list empty.
  ln -sfn /usr/bin/* "$R/vendor/bin/" 2>/dev/null || true
  ln -sfn /bin/* "$R/vendor/bin/" 2>/dev/null || true
  [ -x "$R/vendor/bin/git" ] || skip "this machine has no /usr/bin/git or /bin/git to vendor"
  rm -f "$BATS_TEST_TMPDIR/MINE" "$BATS_TEST_TMPDIR/REPO-SH-RAN"
  run env PATH="$R/vendor/bin" bash "$GATE" --repo "$R" --base "$BASE" --workspace "$WS"
  [ ! -f "$BATS_TEST_TMPDIR/REPO-SH-RAN" ] || { echo "with every PATH entry filtered away, the bare word sh resolved from the current directory and the repository's own ./sh ran as the interpreter - $output"; false; }
  [ -f "$BATS_TEST_TMPDIR/MINE" ] || { echo "with every PATH entry filtered away the attested value did not run at all, so the floor is missing rather than wrong - $output"; false; }
}
