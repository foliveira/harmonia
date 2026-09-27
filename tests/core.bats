#!/usr/bin/env bats
# U2 core tests - lifecycle schema validation via fixtures, rules drift guard.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIX="$BATS_TEST_TMPDIR/fixture-repo"
  mkdir -p "$FIX/core/lenses"
  cp "$REPO_ROOT/core/lifecycle.schema.json" "$FIX/core/"
  cp "$REPO_ROOT/core/lifecycle.yaml" "$FIX/core/"
  # Fixture lens files so the resolution check passes unless a test breaks it.
  for l in adversarial security performance regression; do
    printf -- "---\ntriggers: [test]\n---\nfixture\n" > "$FIX/core/lenses/$l.md"
  done
}

@test "shipped lifecycle.yaml passes yamllint and schema" {
  run bash "$REPO_ROOT/bin/validate-core.sh" --repo "$FIX"
  [ "$status" -eq 0 ]
}

@test "removing a required stage field fails with a named error" {
  grep -v 'purpose: Turn a direction' "$REPO_ROOT/core/lifecycle.yaml" > "$FIX/core/lifecycle.yaml"
  run bash "$REPO_ROOT/bin/validate-core.sh" --repo "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"schema validation failed"* ]]
}

@test "schema rejects an unknown agent reference" {
  sed 's/\[scoper, rubber-duck\]/[scoper, intern]/' "$REPO_ROOT/core/lifecycle.yaml" > "$FIX/core/lifecycle.yaml"
  run bash "$REPO_ROOT/bin/validate-core.sh" --repo "$FIX"
  [ "$status" -eq 1 ]
}

@test "schema rejects a stage artifact without a workspace location" {
  sed 's|location: "workspace:ideas.md"|location: "nowhere.md"|' "$REPO_ROOT/core/lifecycle.yaml" > "$FIX/core/lifecycle.yaml"
  run bash "$REPO_ROOT/bin/validate-core.sh" --repo "$FIX"
  [ "$status" -eq 1 ]
}

@test "a review-stage lens with no matching lens file fails resolution" {
  rm "$FIX/core/lenses/performance.md"
  run bash "$REPO_ROOT/bin/validate-core.sh" --repo "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lens 'performance' has no file"* ]]
}

@test "schema rejects an implement stage missing its max-rounds cap" {
  sed '/max_rounds: 6/d' "$REPO_ROOT/core/lifecycle.yaml" > "$FIX/core/lifecycle.yaml"
  run bash "$REPO_ROOT/bin/validate-core.sh" --repo "$FIX"
  [ "$status" -eq 1 ]
}

@test "with check-jsonschema absent, validate-core exits with the cannot-validate code" {
  SHIM="$BATS_TEST_TMPDIR/shim"
  mkdir -p "$SHIM"
  for t in bash yamllint grep sed sort tr dirname cat cp mkdir rm; do
    p="$(command -v $t)" && ln -sf "$p" "$SHIM/$t"
  done
  run env PATH="$SHIM" bash "$REPO_ROOT/bin/validate-core.sh" --repo "$FIX"
  [ "$status" -eq 3 ]
  [[ "$output" == *"cannot validate"* ]]
}

@test "RULES.md carries each of the four rule names exactly once as a heading" {
  for rule in "Think Before Coding" "Simplicity First" "Surgical Changes" "Goal-Driven Execution"; do
    count=$(grep -c "^## .*$rule" "$REPO_ROOT/core/RULES.md")
    [ "$count" -eq 1 ]
  done
}

@test "coverage is the test engineer's aim and no stage gates on it" {
  # Coverage was a gate with its own tooling; it is retired to a judgment the
  # test engineer makes by reading the diff. A build that still ships the tooling,
  # declares the gate, or tells an agent to run it reds here. Absence checks use
  # `if grep; then false; fi`: `! grep` mid-body asserts nothing under errexit.
  for p in bin/coverage bin/trust.sh skills/trust skills/onboard/CERTIFY.md; do
    if [ -e "$REPO_ROOT/$p" ]; then echo "$p still ships"; false; fi
  done
  if grep -nE '^ +gates:.*coverage' "$REPO_ROOT/core/lifecycle.yaml"; then
    echo "a stage still declares a coverage gate"; false
  fi
  if grep -n '"coverage"' "$REPO_ROOT/core/lifecycle.schema.json"; then
    echo "the schema still admits a coverage gate"; false
  fi
  if grep -rnE 'coverage/gate\.sh|trust\.sh|diff-cover|kcov|gate-report|harmonia:exempt' \
       "$REPO_ROOT/skills" "$REPO_ROOT/agents" "$REPO_ROOT/core" "$REPO_ROOT/bin"; then
    echo "a shipped prompt or script still reaches for coverage tooling"; false
  fi
  # The presence half: the aim is stated where the test engineer reads it.
  grep -qi 'coverage is your judgment, not a gate' "$REPO_ROOT/core/charters/test-engineer.md"
}
