#!/usr/bin/env bats
# U5 tests - skill parity and lint guards, plus the workspace.sh matrix.

STAGES="ideate discuss plan implement review capture quick"
RUNNER="flow"   # meta-skill spanning plan->implement->review; not a lifecycle stage

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WSH="$REPO_ROOT/bin/workspace.sh"
  R="$BATS_TEST_TMPDIR/target"
  mkdir -p "$R"
  git -C "$R" init -q
  echo x > "$R/f"
  git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm x
}

@test "skill names match the lifecycle stages, plus the one meta-runner" {
  # the seven stages each have exactly their own skill (parity unchanged)
  for s in $STAGES; do
    [ -f "$REPO_ROOT/skills/$s/SKILL.md" ]
    grep -q "^name: $s$" "$REPO_ROOT/skills/$s/SKILL.md"
    grep -q "^description: " "$REPO_ROOT/skills/$s/SKILL.md"
  done
  # the runner is the one non-stage skill: present, named, absent from lifecycle.yaml
  [ -f "$REPO_ROOT/skills/$RUNNER/SKILL.md" ]
  grep -q "^name: $RUNNER$" "$REPO_ROOT/skills/$RUNNER/SKILL.md"
  ! grep -q "^  $RUNNER:" "$REPO_ROOT/core/lifecycle.yaml"
  # count stays exact: seven stage skills plus the runner, nothing unaccounted
  n_stages="$(echo $STAGES | wc -w | tr -d ' ')"
  [ "$(ls "$REPO_ROOT"/skills/*/SKILL.md | wc -l)" -eq "$((n_stages + 1))" ]
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

@test "accept writes the digest of the attested diff beside the timestamp, matching the gate receipt" {
  id="$(bash "$WSH" mint --repo "$R" --slug ship)"
  WS="$R/.harmonia/tasks/$id"
  echo y >> "$R/f"
  # f has no extension: the gate exits 4 (unsupported), but still writes the receipt
  bash "$REPO_ROOT/bin/coverage/gate.sh" --repo "$R" --workspace "$WS" || true
  [ -f "$WS/receipts/coverage.json" ]
  run bash "$WSH" accept --repo "$R"
  [ "$status" -eq 0 ]
  [ "$output" = "$id accepted" ]
  [ "$(wc -l < "$WS/accepted")" -eq 2 ]
  sed -n 1p "$WS/accepted" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$'
  sed -n 2p "$WS/accepted" | grep -Eq '^digest: [0-9a-f]{64}$'
  d="$(sed -n 's/^digest: //p' "$WS/accepted")"
  [ "$d" = "$(jq -r .diff_digest "$WS/receipts/coverage.json")" ]
  [ "$d" = "$(git -C "$R" diff "$(sed 's/^ref: //' "$WS/base-ref")" | sha256sum | awk '{print $1}')" ]
}

@test "re-accept overwrites the marker with a fresh digest for the moved diff" {
  id="$(bash "$WSH" mint --repo "$R" --slug reship)"
  WS="$R/.harmonia/tasks/$id"
  echo a >> "$R/f"
  bash "$WSH" accept --repo "$R" >/dev/null
  d1="$(sed -n 's/^digest: //p' "$WS/accepted")"
  echo b >> "$R/f"
  run bash "$WSH" accept --repo "$R"
  [ "$status" -eq 0 ]
  d2="$(sed -n 's/^digest: //p' "$WS/accepted")"
  [ -n "$d2" ]
  [ "$d2" != "$d1" ]
  [ "$d2" = "$(git -C "$R" diff "$(sed 's/^ref: //' "$WS/base-ref")" | sha256sum | awk '{print $1}')" ]
  [ "$(wc -l < "$WS/accepted")" -eq 2 ]
  sed -n 1p "$WS/accepted" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$'
  sed -n 2p "$WS/accepted" | grep -Eq '^digest: [0-9a-f]{64}$'
}

@test "accept refuses an unresolvable base and writes no marker" {
  id="$(bash "$WSH" mint --repo "$R" --slug noref)"
  WS="$R/.harmonia/tasks/$id"
  echo "ref: none" > "$WS/base-ref"
  run bash "$WSH" accept --repo "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not resolve"* ]]
  [[ "$output" == *"'none'"* ]]
  [ ! -f "$WS/accepted" ]
  # a well-formed unknown sha - the ^{commit} peel case bare rev-parse would accept
  echo "ref: 0123456789012345678901234567890123456789" > "$WS/base-ref"
  run bash "$WSH" accept --repo "$R"
  [ "$status" -eq 1 ]
  [ ! -f "$WS/accepted" ]
}

@test "verify-acceptance is fresh only while the diff matches the accepted digest" {
  bash "$WSH" mint --repo "$R" --slug fresh >/dev/null
  echo y >> "$R/f"
  bash "$WSH" accept --repo "$R" >/dev/null
  run bash "$WSH" verify-acceptance --repo "$R"
  [ "$status" -eq 0 ]
  [[ "$output" == *"acceptance verified"* ]]
  echo z >> "$R/f"   # the diff moves past the accepted digest
  run bash "$WSH" verify-acceptance --repo "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stale"* ]]
  [[ "$output" == *"re-accept"* ]]
}

@test "verify-acceptance distinguishes a missing marker with exit 5" {
  bash "$WSH" mint --repo "$R" --slug bare >/dev/null
  run bash "$WSH" verify-acceptance --repo "$R"
  [ "$status" -eq 5 ]
  [[ "$output" == *"no acceptance marker"* ]]
}

@test "verify-acceptance treats a digestless marker as stale" {
  id="$(bash "$WSH" mint --repo "$R" --slug oldmark)"
  WS="$R/.harmonia/tasks/$id"
  # a pre-digest-era marker planted by hand: timestamp line only, no digest
  date -u +%Y-%m-%dT%H:%M:%SZ > "$WS/accepted"
  run bash "$WSH" verify-acceptance --repo "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stale"* ]]
}

@test "usage output names verify-acceptance" {
  run bash "$WSH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"verify-acceptance"* ]]
}

@test "the capture skill verifies the acceptance digest and instructs re-accept on mismatch, never running accept" {
  f="$REPO_ROOT/skills/capture/SKILL.md"
  grep -qF 'workspace.sh verify-acceptance' "$f"
  grep -qi digest "$f"
  grep -qi mismatch "$f"
  grep -qi 're-accept' "$f"
  grep -q 'Never run accept' "$f"
}

@test "verify-acceptance refuses an unresolvable base and names it" {
  id="$(bash "$WSH" mint --repo "$R" --slug baseless)"
  WS="$R/.harmonia/tasks/$id"
  echo y >> "$R/f"
  bash "$WSH" accept --repo "$R" >/dev/null   # marker exists: the missing-marker exit 5 is bypassed
  echo "ref: none" > "$WS/base-ref"           # mint's no-repo sentinel: unresolvable at verify time
  run bash "$WSH" verify-acceptance --repo "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot verify acceptance"* ]]
  [[ "$output" == *"does not resolve"* ]]
  [[ "$output" == *"'none'"* ]]   # the message names what could not resolve
}
