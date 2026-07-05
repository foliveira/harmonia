#!/usr/bin/env bats
# Pins the flow runner's written contract. The runner is a SKILL.md, so its
# behavior IS its written contract; these grep that prose the same way
# skills.bats pins capture's acceptance contract - no live model runs here.
# Each assertion maps to a scope-required behavior; the comments name the map.

RUNNER="flow"

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  F="$REPO_ROOT/skills/$RUNNER/SKILL.md"
}

@test "the runner is a skill but not a lifecycle stage" {
  # scope: is a skill but NOT a lifecycle stage - absent from lifecycle.yaml,
  # so it forces no schema change (decision 7)
  [ -f "$F" ]
  grep -q "^name: $RUNNER$" "$F"
  ! grep -q "^  $RUNNER:" "$REPO_ROOT/core/lifecycle.yaml"
}

@test "the runner requires a pinned scope and refuses to brainstorm" {
  # scope: entry contract - requires an already-pinned scope.md; refuses without
  # one and points to /harmonia:brainstorm; never mints or auto-scopes
  grep -qF 'workspace.sh resolve' "$F"
  grep -qF 'scope.md' "$F"
  grep -q '/harmonia:brainstorm' "$F"
  grep -qi 'refuse' "$F"
  grep -qi 'never mints\|never auto-scope' "$F"
}

@test "the runner names its plan-implement-review span as one unattended pass" {
  # scope: chains plan, then implement, then review in one unattended session.
  # NB: the three bare-word greps the design listed here are vacuous - the
  # delegation test below already forces plan/implement/review to appear via the
  # SKILL.md paths - so pin the ordered span and the single-session framing.
  grep -qiE 'plan.*implement.*review' "$F"   # the span names the three stages, in order
  grep -qi 'unattended' "$F"                 # the three invocations collapsed into one run
}

@test "the runner advances to review on the implement cap, not halts" {
  # scope: an incomplete implement loop advances unconditionally, it does not
  # stop; the max_rounds cap is not a gate failure.
  # NB: dropped the design's bare `grep -qi cap` - it is satisfied by "capture"
  # (which step 6 must mention), so it asserts nothing about the cap.
  grep -qF 'max_rounds' "$F"
  grep -qi 'advance to review' "$F"
  grep -qi 'unconditional' "$F"
  grep -qi 'not a gate failure' "$F"
}

@test "the runner halts on a failing pre-implement criteria gate" {
  # scope: before implement writes any code, check-criteria must pass; on
  # failure the run stops before implement and hands back
  grep -qF 'check-criteria' "$F"
  grep -qi 'writes no code' "$F"
  grep -qi 'halt' "$F"
}

@test "the runner halts on a failing review coverage or receipts gate" {
  # scope: a failing coverage/receipts gate at review halts the run; the runner
  # never records a coverage override to keep going
  grep -qi 'coverage' "$F"
  grep -qi 'receipts' "$F"
  grep -qi 'halt' "$F"
  grep -qi 'never record a coverage override' "$F"
}

@test "the runner stops before capture and never accepts" {
  # scope: pauses before capture; never writes accepted, never runs accept.
  # Reuses capture's exact token so the human-only-acceptance invariant holds on
  # this second automated path to the boundary (per the 2026-07-02 learning).
  grep -q 'Never run accept' "$F"           # the exact token from capture/SKILL.md
  grep -qF 'workspace.sh accept' "$F"        # names the human command in the handback
  grep -q '/harmonia:capture' "$F"           # points there as the manual next step
  grep -qi 'acceptance is a human act' "$F"
  grep -qi 'never enters capture\|ends after review' "$F"
}

@test "the runner is a thin orchestrator bound to the rules and lifecycle" {
  # scope: thin orchestrator (R9, KTD3) - reads lifecycle.yaml, hardcodes no
  # agent list. Mirrors the body rules skills.bats enforces on every stage.
  grep -qF '${CLAUDE_PLUGIN_ROOT}/core/RULES.md' "$F"
  grep -qF '${CLAUDE_PLUGIN_ROOT}/core/lifecycle.yaml' "$F"
  grep -qF '${CLAUDE_PLUGIN_ROOT}/bin/workspace.sh' "$F"
  grep -q 'do not hardcode' "$F"
  grep -q 'R9' "$F"
}

@test "the runner delegates to the stage skills rather than duplicating them" {
  # scope: delegates to skills/{plan,implement,review}/SKILL.md and never
  # restates the red-green loop, the panel, or the gate invocations (R9)
  grep -qF 'skills/plan/SKILL.md' "$F"
  grep -qF 'skills/implement/SKILL.md' "$F"
  grep -qF 'skills/review/SKILL.md' "$F"
}

@test "the runner description scopes to explicit /harmonia:flow invocation" {
  # scope: scopes to /harmonia:flow - the coexistence guard every stage skill carries
  grep -q "ONLY when explicitly invoked as /harmonia:$RUNNER" "$F"
}
