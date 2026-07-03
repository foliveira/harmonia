#!/usr/bin/env bats
# U5 tests - skill parity and lint guards, plus the workspace.sh matrix.

STAGES="ideate brainstorm plan implement review capture quick"

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WSH="$REPO_ROOT/bin/workspace.sh"
  R="$BATS_TEST_TMPDIR/target"
  mkdir -p "$R"
  git -C "$R" init -q
  echo x > "$R/f"
  git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm x
}

@test "the seven skill names match the lifecycle stages" {
  [ "$(ls "$REPO_ROOT"/skills/*/SKILL.md | wc -l)" -eq 7 ]
  for s in $STAGES; do
    [ -f "$REPO_ROOT/skills/$s/SKILL.md" ]
    grep -q "^name: $s$" "$REPO_ROOT/skills/$s/SKILL.md"
    grep -q "^description: " "$REPO_ROOT/skills/$s/SKILL.md"
  done
  grep -q "^  quick:" "$REPO_ROOT/core/lifecycle.yaml"
}

@test "every skill body references the rules, the lifecycle, and workspace paths - no hardcoded agent lists" {
  for s in $STAGES; do
    f="$REPO_ROOT/skills/$s/SKILL.md"
    grep -qF '${CLAUDE_PLUGIN_ROOT}/core/RULES.md' "$f"
    grep -qF '${CLAUDE_PLUGIN_ROOT}/core/lifecycle.yaml' "$f"
    grep -qF '${CLAUDE_PLUGIN_ROOT}/bin/workspace.sh' "$f"
    grep -q "do not hardcode" "$f"
    grep -q "R9" "$f"
  done
}

@test "skill descriptions scope to explicit /harmonia: invocation during coexistence" {
  for s in $STAGES; do
    grep -q "ONLY when explicitly invoked as /harmonia:$s" "$REPO_ROOT/skills/$s/SKILL.md"
  done
}

@test "mint creates a workspace with base ref and a self-ignoring gitignore" {
  run bash "$WSH" mint --repo "$R" --slug "Fix Thing"
  [ "$status" -eq 0 ]
  id="$output"
  [ -f "$R/.harmonia/tasks/$id/base-ref" ]
  grep -q "^ref: $(git -C "$R" rev-parse HEAD)$" "$R/.harmonia/tasks/$id/base-ref"
  touch "$R/.harmonia/tasks/$id/probe"
  git -C "$R" check-ignore -q ".harmonia/tasks/$id/probe"
}

@test "mint refuses over an incomplete workspace and names it; --new forces" {
  first="$(bash "$WSH" mint --repo "$R" --slug one)"
  run bash "$WSH" mint --repo "$R" --slug two
  [ "$status" -eq 4 ]
  [[ "$output" == *"$first"* ]]
  run bash "$WSH" mint --repo "$R" --slug two --new
  [ "$status" -eq 0 ]
}

@test "resolve finds the single incomplete workspace" {
  id="$(bash "$WSH" mint --repo "$R" --slug solo)"
  run bash "$WSH" resolve --repo "$R"
  [ "$status" -eq 0 ]
  [ "$output" = "$id" ]
}

@test "resolve errors on ambiguity, enumerating task ids and mint dates" {
  bash "$WSH" mint --repo "$R" --slug one >/dev/null
  bash "$WSH" mint --repo "$R" --slug two --new >/dev/null
  run bash "$WSH" resolve --repo "$R"
  [ "$status" -eq 2 ]
  [[ "$output" == *"one"* ]]
  [[ "$output" == *"two"* ]]
  [[ "$output" == *"minted:"* ]]
}

@test "resolve exits no-active-task when none exists or all are closed" {
  run bash "$WSH" resolve --repo "$R"
  [ "$status" -eq 3 ]
  id="$(bash "$WSH" mint --repo "$R" --slug done-soon)"
  bash "$WSH" complete --repo "$R" --task "$id" >/dev/null
  run bash "$WSH" resolve --repo "$R"
  [ "$status" -eq 3 ]
}

@test "abandon retires a workspace so resolution skips it" {
  bash "$WSH" mint --repo "$R" --slug dropme >/dev/null
  bash "$WSH" abandon --repo "$R" >/dev/null
  run bash "$WSH" resolve --repo "$R"
  [ "$status" -eq 3 ]
}

@test "moved test hashes fail verification and write the violation record" {
  id="$(bash "$WSH" mint --repo "$R" --slug hashes)"
  mkdir -p "$R/tests"
  echo "assert true" > "$R/tests/a.bats"
  bash "$WSH" record-test-hashes --repo "$R" >/dev/null
  run bash "$WSH" verify-test-hashes --repo "$R"
  [ "$status" -eq 0 ]
  echo "assert weakened" > "$R/tests/a.bats"
  run bash "$WSH" verify-test-hashes --repo "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *"violation"* ]]
  grep -q "VIOLATION" "$R/.harmonia/tasks/$id/violations"
}

@test "unknown arguments and unknown commands exit with usage" {
  run bash "$WSH" mint --repo "$R" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown argument"* ]]
  run bash "$WSH" frobnicate
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "accept writes the acceptance marker and leaves the workspace active" {
  id="$(bash "$WSH" mint --repo "$R" --slug ship)"
  run bash "$WSH" accept --repo "$R"
  [ "$status" -eq 0 ]
  [ "$output" = "$id accepted" ]
  [ -f "$R/.harmonia/tasks/$id/accepted" ]
  run bash "$WSH" resolve --repo "$R"
  [ "$status" -eq 0 ]
  [ "$output" = "$id" ]   # accepted is not done; resolution still finds it
}

@test "usage output names accept" {
  run bash "$WSH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"accept"* ]]
}

@test "the capture stage carries the acceptance contract" {
  grep -q 'name: acceptance' "$REPO_ROOT/core/lifecycle.yaml"
  grep -q 'workspace:accepted' "$REPO_ROOT/core/lifecycle.yaml"
  grep -qF 'workspace.sh accept' "$REPO_ROOT/skills/capture/SKILL.md"
}
