#!/usr/bin/env bats
# Context-budget guards (2026-07-11 token audit). Harmonia's standing cost in
# EVERY session of EVERY project (the plugin is installed user-scoped) is the
# sum of its model-visible skill descriptions, its agent descriptions, and the
# session hook payload (hooks.bats caps that last one). Skill BODIES cost
# nothing until invoked. These tests pin the conventions so a new skill,
# agent, or command cannot silently re-grow the budget:
#   - skills ship hidden from the model (disable-model-invocation: true);
#     only the Skill-tool-chained five are visible, by explicit allowlist;
#   - descriptions stay one lean line;
#   - nothing reinstates the unconditional RULES.md read - the session hook
#     injects the rules digest at startup, resume, and compact;
#   - the stage skills the flow runner chains never instruct a re-read of
#     lifecycle.yaml into the same context;
#   - a SKILL.md body stays under the progressive-disclosure ceiling; move
#     reference material an average run never needs into a sibling file read
#     on demand (skills/onboard/CERTIFY.md is the pattern).

# The five skills the session transcripts show being invoked via the Skill
# tool: flow and quick from prose, plan/implement/review chained by the
# runners. Everything else is human-typed only. Adding a name here is a
# deliberate act - its description re-enters every session's system prompt.
MODEL_VISIBLE="flow quick plan implement review"

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

fm_hidden() {  # frontmatter carries disable-model-invocation: true
  awk '/^---$/{c++; next} c==1' "$1" | grep -q '^disable-model-invocation: true$'
}

desc_bytes() {  # byte length of the frontmatter description line
  awk '/^---$/{c++; next} c==1 && /^description: /' "$1" | head -1 | wc -c
}

@test "every skill is hidden from the model unless allowlisted as Skill-tool-chained" {
  for f in "$REPO_ROOT"/skills/*/SKILL.md; do
    s="$(basename "$(dirname "$f")")"
    if [[ " $MODEL_VISIBLE " == *" $s "* ]]; then
      ! fm_hidden "$f"   # chained skills must stay visible to the Skill tool
    else
      fm_hidden "$f"     # new skills ship hidden; widen the allowlist deliberately
    fi
  done
}

@test "model-visible skill descriptions stay one lean line" {
  for s in $MODEL_VISIBLE; do
    n="$(desc_bytes "$REPO_ROOT/skills/$s/SKILL.md")"
    [ "$n" -gt 0 ] && [ "$n" -le 240 ]
  done
}

@test "agent descriptions stay one lean line" {
  # every registered agent's description sits in every session's agent list
  for f in "$REPO_ROOT"/agents/*.md; do
    n="$(desc_bytes "$f")"
    [ "$n" -gt 0 ] && [ "$n" -le 200 ]
  done
}

@test "no skill reinstates the unconditional RULES.md read" {
  # The old line forced a ~436-token read on every invocation while the hook
  # had already injected the digest. Skills that name RULES.md keep the read
  # conditional on the digest's absence. Agents are exempt by design: their
  # spawned contexts never contain the hook payload, so they read in full
  # (roster.bats pins that).
  for f in "$REPO_ROOT"/skills/*/SKILL.md; do
    ! grep -q 'Read your working contract first' "$f"
    if grep -q 'core/RULES.md' "$f"; then
      grep -q 'only if that digest is not in your context' "$f"
    fi
  done
}

@test "flow-chained stage skills mark lifecycle.yaml as already loaded" {
  # flow reads lifecycle.yaml once; plan/implement/review execute inside that
  # same context and must not instruct a second read of the same file.
  for s in plan implement review; do
    grep -q 'do not re-read' "$REPO_ROOT/skills/$s/SKILL.md"
  done
}

@test "skill bodies stay under the progressive-disclosure ceiling" {
  # a body loads whole on every invocation; 10,000 bytes is the ceiling
  for f in "$REPO_ROOT"/skills/*/SKILL.md; do
    [ "$(wc -c < "$f")" -le 10000 ]
  done
}
