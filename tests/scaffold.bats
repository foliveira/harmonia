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

@test "plugin.json declares no version (auto-update per commit)" {
  run jq -e 'has("version")' "$REPO_ROOT/.claude-plugin/plugin.json"
  [ "$output" = "false" ]
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
