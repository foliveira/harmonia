#!/usr/bin/env bats
# Receipt audit tests - bin/verify-receipts.sh, review's tier-B honesty gate
# (KTD7): freshness against the live diff, the check-criteria status waiver, the
# criteria-run requirement, and containment and provenance of everything it reads.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  AUDIT="$REPO_ROOT/bin/verify-receipts.sh"
  CHECK="$REPO_ROOT/bin/check-criteria.sh"

  R="$BATS_TEST_TMPDIR/target"
  mkdir -p "$R"
  git -C "$R" init -q
  printf 'line1\nline2\n' > "$R/app.sh"
  git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm base
  BASE="$(git -C "$R" rev-parse HEAD)"
  # A tracked change, so every digest under audit is content-bearing: against the
  # sha256 of an empty diff a freshness check matches whatever it is handed.
  printf 'line1\nCHANGED\n' > "$R/app.sh"

  WS="$R/.harmonia/tasks/2026-07-02-audit"
  mkdir -p "$WS/receipts"
  # Mirror what mint writes (bin/workspace.sh): the tasks tree ignores itself, so
  # a workspace is never committable and the provenance guard accepts it.
  printf '*\n' > "$R/.harmonia/tasks/.gitignore"
  echo "ref: $BASE" > "$WS/base-ref"
  EMPTY="$(printf '' | sha256sum | awk '{print $1}')"
}

live_digest() { git -C "$R" diff "$BASE" | sha256sum | awk '{print $1}'; }

receipt() {   # <gate> <digest> <status>: a hand-written receipt in $WS
  cat > "$WS/receipts/$1.json" <<JSON
{ "gate": "$1", "task_id": "2026-07-02-audit", "timestamp": "2026-07-31T00:00:00Z", "diff_digest": "$2", "status": "$3" }
JSON
}

run_criteria() {   # a real criteria run, so the receipt under audit is the gate's own
  printf '## Success Criteria\n- run: true\n' > "$WS/scope.md"
  bash "$CHECK" --run --workspace "$WS" --repo "$R" >/dev/null </dev/null
  [ "$(jq -r .status "$WS/receipts/criteria-run.json")" = pass ]
}

@test "the audit verifies the fresh criteria-run receipt the criteria gate wrote" {
  run_criteria
  [ "$(jq -r .diff_digest "$WS/receipts/criteria-run.json")" = "$(live_digest)" ]
  run bash "$AUDIT" --repo "$R" --workspace "$WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"receipts verified"* ]]
}

@test "a criteria-run receipt goes stale when the tree moves after the run" {
  run_criteria
  echo 'drift' >> "$R/app.sh"
  run bash "$AUDIT" --repo "$R" --workspace "$WS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"criteria-run.json is stale"* ]]
}

# check-criteria validates scope.md (code-independent) but its receipt hashes the
# diff at implement-start on a clean tree, so its digest goes code-stale the
# moment implement writes code. The audit validates it by status, while
# criteria-run stays required digest-fresh.

@test "a code-stale check-criteria receipt is waived beside a fresh criteria-run receipt" {
  receipt check-criteria "$EMPTY" pass
  run_criteria
  [ "$EMPTY" != "$(live_digest)" ]   # the shape receipt really is code-stale
  run bash "$AUDIT" --repo "$R" --workspace "$WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"receipts verified"* ]]
}

@test "a check-criteria receipt whose status is fail fails the audit" {
  receipt check-criteria "$EMPTY" fail
  run_criteria
  run bash "$AUDIT" --repo "$R" --workspace "$WS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not pass"* ]]
}

@test "a stale criteria-run receipt still fails beside a passing check-criteria receipt" {
  # check-criteria sorts first, so a `break` where the waiver needs `continue`
  # would stop the loop there and certify the stale receipt behind it.
  receipt check-criteria "$EMPTY" pass
  run_criteria
  echo 'drift' >> "$R/app.sh"
  run bash "$AUDIT" --repo "$R" --workspace "$WS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"criteria-run.json is stale"* ]]
  [[ "$output" != *"check-criteria"* ]]   # its freshness is waived, so it is not named
}

@test "a store holding only a passing check-criteria receipt certifies nothing" {
  # The shape receipt is validated by status alone, so on its own it says nothing
  # about the tree: nothing executed against it.
  receipt check-criteria "$EMPTY" pass
  run bash "$AUDIT" --repo "$R" --workspace "$WS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no code-dependent receipt"* ]]
  [[ "$output" != *"receipts verified"* ]]
}

@test "a fresh criteria-run receipt reporting fail fails the audit" {
  # The exit code of the criteria run is the gate; its receipt witnesses
  # freshness. A `fail` there means the criteria ran and lost.
  receipt criteria-run "$(live_digest)" fail
  run bash "$AUDIT" --repo "$R" --workspace "$WS"
  [ "$status" -ne 0 ]
  [[ "$output" == *"criteria run failed"* ]]
  [[ "$output" != *"receipts verified"* ]]
  [[ "$output" != *"stale"* ]]   # the receipt is fresh, so the status is what refused
}

@test "a missing or empty receipts directory fails the audit" {
  rm -rf "$WS/receipts"
  run bash "$AUDIT" --repo "$R" --workspace "$WS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"receipts missing"* ]]
  mkdir -p "$WS/receipts"
  run bash "$AUDIT" --repo "$R" --workspace "$WS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"receipts missing"* ]]
}

@test "an unresolvable base cannot verify, and names the ref" {
  run_criteria
  run bash "$AUDIT" --repo "$R" --base "no-such-ref" --workspace "$WS"
  [ "$status" -eq 4 ]
  [[ "$output" == *"cannot verify"* ]]
  [[ "$output" == *"no-such-ref"* ]]
  # a well-formed sha absent from the object db must not slip through either
  run bash "$AUDIT" --repo "$R" --base "0123456789012345678901234567890123456789" --workspace "$WS"
  [ "$status" -eq 4 ]
}

@test "a --base in the base-ref file format verifies identically to the bare sha" {
  run_criteria
  run bash "$AUDIT" --repo "$R" --base "$BASE" --workspace "$WS"
  bare_status="$status"; bare_output="$output"
  [ "$bare_status" -eq 0 ]
  run bash "$AUDIT" --repo "$R" --base "ref: $BASE" --workspace "$WS"
  [ "$status" -eq "$bare_status" ]
  [ "$output" = "$bare_output" ]
}

@test "with no --base the audit reads the workspace base-ref file" {
  # Commit the change, so HEAD and the base-ref name different trees: the receipt
  # is fresh against the base-ref and stale against HEAD, which is what tells the
  # two defaults apart.
  git -C "$R" add app.sh && git -C "$R" -c user.email=t@t -c user.name=t commit -qm drift
  run_criteria
  run bash "$AUDIT" --repo "$R" --workspace "$WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"receipts verified"* ]]
  run bash "$AUDIT" --repo "$R" --base HEAD --workspace "$WS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stale"* ]]
}

@test "the audit requires --workspace and rejects an unknown argument" {
  run bash "$AUDIT" --repo "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--workspace is required"* ]]
  run bash "$AUDIT" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown argument"* ]]
}

# --- FU-16: the audit's reads ---------------------------------------------------
# Nothing is written by the audit, so no escape detector can see a redirect - what
# is wrong is the VERDICT. Each cell plants a VALID, FRESH receipt at the far end
# of the redirect, so an unguarded build answers `receipts verified` and the cell
# reds; a junk receipt would be refused for being unparseable and prove nothing.

stage_audit() {   # <form>: one self-contained cell; sets CELL, GR, GWS, GBASE
  local form="$1" real
  CELL="$BATS_TEST_TMPDIR/au-$form"
  mkdir -p "$CELL/out" "$CELL/real"
  real="$CELL/real/r"; mkdir -p "$real"
  git -C "$real" init -q
  printf 'a\n' > "$real/f.sh"
  git -C "$real" add -A
  git -C "$real" -c user.email=t@t -c user.name=t commit -qm b
  GR="$real"; GBASE="$(git -C "$real" rev-parse HEAD)"
  GWS="$real/.harmonia/tasks/T"
  mkdir -p "$GWS/receipts"
  printf 'a\nb\n' > "$real/f.sh"   # a TRACKED change: the audited digest is content-bearing
  case "$form" in
    clean) ;;
    receipts-dir)
        rm -rf "$GWS/receipts"; mkdir -p "$CELL/out/receipts"
        ln -s "$CELL/out/receipts" "$GWS/receipts" ;;
    tasks-tree)
        mv "$real/.harmonia/tasks" "$CELL/out/tasks"; ln -s "$CELL/out/tasks" "$real/.harmonia/tasks" ;;
    shaped)
        # A redirect target itself named .harmonia/tasks, which a guard that only
        # pattern-matches the resolved path accepts.
        mkdir -p "$CELL/out/.harmonia"
        mv "$real/.harmonia/tasks" "$CELL/out/.harmonia/tasks"
        ln -s "$CELL/out/.harmonia/tasks" "$real/.harmonia/tasks" ;;
    receipt-file)
        ln -s "$CELL/out/criteria-run.json" "$GWS/receipts/criteria-run.json" ;;
    receipt-unguarded-name)
        # The audit GLOBS, so it reaches a name no writer will ever guard.
        ln -s "$CELL/out/zz.json" "$GWS/receipts/zz.json" ;;
    in-repo-shape)
        # Contained but not a workspace: the redirect target is a real directory
        # INSIDE the repository, so the anchor prefix test accepts it and only the
        # single-component test refuses.
        mkdir -p "$real/src/receipts"
        rm -rf "$GWS"; ln -s "$real/src" "$GWS" ;;
    nested-task-path)
        # Contained AND correctly shaped, but one component too deep. Only the
        # single-component test in ws_contained refuses this, so it is the cell
        # that pins that line by itself (bin/base-ref-lib.sh cites it by name).
        mkdir -p "$GWS/sub/receipts"
        GWS="$GWS/sub" ;;
  esac
}

@test "the audit refuses to certify a receipt store that lives outside the workspace" {
  for form in clean receipts-dir tasks-tree shaped receipt-file receipt-unguarded-name in-repo-shape nested-task-path; do
    stage_audit "$form"
    cur="$(git -C "$GR" diff "$GBASE" | sha256sum | awk '{print $1}')"
    fresh="{ \"gate\": \"criteria-run\", \"task_id\": \"T\", \"timestamp\": \"2026-01-01T00:00:00Z\", \"diff_digest\": \"$cur\", \"status\": \"pass\" }"
    case "$form" in
      receipt-file)           printf '%s\n' "$fresh" > "$CELL/out/criteria-run.json" ;;
      receipt-unguarded-name) printf '%s\n' "$fresh" > "$CELL/out/zz.json"
                              printf '%s\n' "$fresh" > "$GWS/receipts/criteria-run.json" ;;
      *)                      printf '%s\n' "$fresh" > "$GWS/receipts/criteria-run.json" ;;
    esac
    echo "--- redirect form: $form, workspace $GWS"
    run bash "$AUDIT" --repo "$GR" --base "$GBASE" --workspace "$GWS"
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
      grep -q '^verify-receipts: ' <<<"$output"
    fi
  done
}

@test "the audit refuses a base-ref that resolves outside the workspace" {
  # Absent --base the workspace supplies the base, so base-ref is an audit input
  # with the same standing as the receipts. The receipt below carries the
  # EMPTY-diff digest while the tree really has a change, so an honest base-ref
  # reports staleness, and a redirect at a ref the diff really is empty against
  # would turn that into `receipts verified`.
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
  cat > "$ws/receipts/criteria-run.json" <<JSON
{ "gate": "criteria-run", "task_id": "T", "timestamp": "2026-01-01T00:00:00Z", "diff_digest": "$EMPTY", "status": "pass" }
JSON

  # The control: an honest base-ref naming the FIRST commit, so the empty-diff
  # receipt is stale. Without it the redirect cell cannot be read as a flip.
  printf 'ref: %s\n' "$first" > "$ws/base-ref"
  run bash "$AUDIT" --repo "$real" --workspace "$ws"
  echo "honest: status=$status $output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"stale"* ]]

  printf 'ref: %s\n' "$head" > "$cell/out/base-ref"
  rm -f "$ws/base-ref"; ln -s "$cell/out/base-ref" "$ws/base-ref"
  run bash "$AUDIT" --repo "$real" --workspace "$ws"
  echo "redirected: status=$status $output"
  [ "$status" -ne 0 ]
  [[ "$output" != *"receipts verified"* ]]
  grep -q '^verify-receipts: ' <<<"$output"
}

@test "the audit refuses receipts that arrived with the repository" {
  # Nothing is redirected and containment correctly accepts every path: the
  # receipts are exactly where receipts belong. What is wrong is that the
  # repository WROTE them, and on a fresh clone nothing here ran against the tree.
  local h="$BATS_TEST_TMPDIR/rp-host" c="$BATS_TEST_TMPDIR/rp-clone"
  local w="$h/.harmonia/tasks/T"
  mkdir -p "$w/receipts"
  printf 'x\n' > "$h/README.md"
  cat > "$w/receipts/criteria-run.json" <<JSON
{ "gate": "criteria-run", "task_id": "T", "timestamp": "2026-01-01T00:00:00Z", "diff_digest": "$EMPTY", "status": "pass" }
JSON
  git -C "$h" init -q
  git -C "$h" add -A -f
  git -C "$h" -c user.email=t@t -c user.name=t commit -qm x
  git clone -q "$h" "$c"
  local cw="$c/.harmonia/tasks/T"
  git -C "$c" ls-files --error-unmatch -- ".harmonia/tasks/T/receipts/criteria-run.json" >/dev/null
  # base-ref written after the clone, so the receipts are what this cell tests: a
  # carried base-ref refuses one step earlier and the receipt branch never runs.
  printf 'ref: HEAD\n' > "$cw/base-ref"

  run bash "$AUDIT" --repo "$c" --workspace "$cw"
  echo "clone absolute: status=$status $output"
  [ "$status" -ne 0 ]
  [[ "$output" != *"receipts verified"* ]]

  ( cd "$c" && run bash "$AUDIT" --repo "." --workspace ".harmonia/tasks/T"
    [ "$status" -ne 0 ]
    [[ "$output" != *"receipts verified"* ]] )

  # The accept side: a workspace whose receipts this machine actually wrote.
  local L="$BATS_TEST_TMPDIR/rp-ok"
  mkdir -p "$L"
  git -C "$L" init -q
  printf 'a\n' > "$L/f.sh"
  git -C "$L" add -A
  git -C "$L" -c user.email=t@t -c user.name=t commit -qm b
  local id; id="$(bash "$REPO_ROOT/bin/workspace.sh" mint --repo "$L" --slug mine)"
  local lw="$L/.harmonia/tasks/$id"
  printf '## Success Criteria\n- run: true\n' > "$lw/scope.md"
  bash "$CHECK" --run --workspace "$lw" --repo "$L" >/dev/null </dev/null
  run bash "$AUDIT" --repo "$L" --workspace "$lw"
  echo "honest: status=$status $output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"receipts verified"* ]]
}

@test "the audit refuses a base-ref that arrived with the repository" {
  # base-ref selects the tree every receipt is checked against, so a repository
  # that commits its own decides what the audit compares with. Containment
  # accepts it: the file is exactly where it belongs.
  local h="$BATS_TEST_TMPDIR/vbr-h" c="$BATS_TEST_TMPDIR/vbr-c"
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
  # A receipt fresh against the carried base, so an unguarded build certifies.
  local d; d="$(git -C "$c" diff "$(sed 's/^ref: //' "$c/.harmonia/tasks/T/base-ref")" | sha256sum | awk '{print $1}')"
  mkdir -p "$c/.harmonia/tasks/T/receipts"
  cat > "$c/.harmonia/tasks/T/receipts/criteria-run.json" <<JSON
{ "gate": "criteria-run", "task_id": "T", "timestamp": "2026-01-01T00:00:00Z", "diff_digest": "$d", "status": "pass" }
JSON

  run bash "$AUDIT" --repo "$c" --workspace "$c/.harmonia/tasks/T"
  echo "status=$status"
  echo "$output"
  [ "$status" -eq 4 ]
  [[ "$output" != *"receipts verified"* ]]
  grep -q '^verify-receipts: cannot verify' <<<"$output"
}

@test "an exported CDPATH does not poison the containment predicate" {
  # `cd` ECHOES the directory it lands in when CDPATH is set and the target
  # matches an entry, so a command substitution around it captures that echo
  # instead of the path. Fail-closed only, but a guard that refuses correct work
  # is still wrong. The relative call shape is the one the skills use.
  local real="$BATS_TEST_TMPDIR/cdp/r"
  mkdir -p "$real"
  git -C "$real" init -q
  printf 'a\n' > "$real/f.sh"
  git -C "$real" add -A
  git -C "$real" -c user.email=t@t -c user.name=t commit -qm b
  local id; id="$(bash "$REPO_ROOT/bin/workspace.sh" mint --repo "$real" --slug cdp)"
  printf '## Success Criteria\n- run: true\n' > "$real/.harmonia/tasks/$id/scope.md"
  bash "$CHECK" --run --workspace "$real/.harmonia/tasks/$id" --repo "$real" >/dev/null </dev/null

  ( cd "$real" && CDPATH=. run bash "$AUDIT" --repo "." --workspace ".harmonia/tasks/$id"
    echo "status=$status"
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"receipts verified"* ]] )
}
