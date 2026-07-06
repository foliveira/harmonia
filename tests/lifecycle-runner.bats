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

@test "the runner requires a pinned scope and refuses to discuss" {
  # scope: entry contract - requires an already-pinned scope.md; refuses without
  # one and points to /harmonia:discuss; never mints or auto-scopes
  grep -qF 'workspace.sh resolve' "$F"
  grep -qF 'scope.md' "$F"
  grep -q '/harmonia:discuss' "$F"
  grep -qi 'refuse' "$F"
  grep -qi 'never mints\|never auto-scope' "$F"
}

@test "the runner clears stale prior-run out-artifacts via clear-span, not an inline file list" {
  # scope: F3/item B - the five-file list + path-confinement moved into
  # `workspace.sh clear-span` (behaviorally tested in tests/workspace.bats); the
  # runner must CALL clear-span and no longer restate the file list inline. The
  # HEAD scope.md-never-removed assert moves to workspace.bats criterion 1, where
  # the shell actually enforces it (DRY).
  grep -qF 'workspace.sh clear-span' "$F"                                       # step 1 delegates clearing to the subcommand
  grep -qiE 'stale prior-run|prior-run out|leftover' "$F"                       # still framed as stale prior-run clearing
  ! grep -qiE 'remove .*design\.md.*boundary\.md.*diff-summary\.md.*verdict\.md.*gate-report\.md' "$F"  # the inline five-file list is gone
}

@test "the runner guards scope criteria at entry, refusing a criteria-less scope" {
  # scope: F5 - step 1 rejects a scope.md with no machine-checkable criteria by
  # running the check-criteria gate at entry (HEAD only names the gate in step 3),
  # refusing to /harmonia:discuss.
  grep -qF 'bin/check-criteria.sh' "$F"                                   # step 1 INVOKES the criteria script at entry
  grep -qiE 'criteria-less|no .*success criteria|machine-checkable' "$F"  # names what it rejects
  grep -q '/harmonia:discuss' "$F"                                     # same refusal target as no-scope
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

@test "the runner names the inspectable criteria-halt signal in step 3" {
  # scope: F6 - step 3 must name the signal it inspects to halt, not just "if the
  # gate fails": the check-criteria receipt's status, or a non-zero exit. Pin the
  # tokens to the step-3 line ONLY - step 1's entry-guard prose now also carries
  # `receipts/check-criteria.json` and `non-zero`, so a whole-file grep is
  # satisfied by step 1 and blind to a gutted step 3 (F-A). Extract the line that
  # starts with `3. ` and assert within it, so a step-3 regression turns RED
  # while step 1 alone cannot satisfy the pin.
  step3="$(grep -E '^3\. ' "$F")"
  [ -n "$step3" ]                                        # the step-3 line exists
  grep -qF 'receipts/check-criteria.json' <<<"$step3"    # the inspectable artifact, named in step 3
  grep -qiE 'status.*pass|non-zero' <<<"$step3"          # the signal: status != pass / non-zero exit
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
