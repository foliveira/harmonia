#!/usr/bin/env bats
# U1 scaffold tests — manifest, marketplace, license, hygiene, naming rationale.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

@test "plugin.json parses and has a kebab-case name" {
  run jq -er '.name' "$REPO_ROOT/.claude-plugin/plugin.json"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[a-z][a-z0-9-]*$ ]]
}

@test "plugin.json declares a CalVer version" {
  # The shape, never the literal: the version is a dated label over the released
  # tree and moves every release, so pinning the string would red the next one.
  # Zero-padded by construction, which rejects 2026.8.16 and a swapped 2026.16.08.
  run jq -er '.version' "$REPO_ROOT/.claude-plugin/plugin.json"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]{4}\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01])$ ]]
}

@test "marketplace.json parses and references the plugin source" {
  run jq -er '.plugins[0].name' "$REPO_ROOT/.claude-plugin/marketplace.json"
  [ "$status" -eq 0 ]
  [ "$output" = "harmonia" ]
  run jq -er '.plugins[0].source' "$REPO_ROOT/.claude-plugin/marketplace.json"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "LICENSE is MIT with current year and holder" {
  grep -q "MIT License" "$REPO_ROOT/LICENSE"
  grep -q "Copyright (c) 2026 Fabio Oliveira" "$REPO_ROOT/LICENSE"
}

@test "task workspaces are gitignored; the exemptions audit log is not" {
  mkdir -p "$REPO_ROOT/.harmonia/tasks/fixture"
  touch "$REPO_ROOT/.harmonia/tasks/fixture/file"
  git -C "$REPO_ROOT" check-ignore -q ".harmonia/tasks/fixture/file"
  ! git -C "$REPO_ROOT" check-ignore -q ".harmonia/coverage-exemptions.yaml"
  rm -rf "$REPO_ROOT/.harmonia/tasks/fixture"
}

@test "README carries the naming rationale" {
  grep -qi "Portuguese" "$REPO_ROOT/README.md"
  grep -qi "goddess" "$REPO_ROOT/README.md"
  grep -qi "Music of the Spheres" "$REPO_ROOT/README.md"
}
