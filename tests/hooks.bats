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
