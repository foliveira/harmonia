#!/usr/bin/env bats
# U3 roster tests - parity, frontmatter contracts, body guards, consume/produce closure.

ROLES="ideator scoper planner implementer test-engineer reviewer simplifier knowledge-curator committer doc-producer doc-reviewer rubber-duck"

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

fm() { # fm <file> <key> -> frontmatter value
  awk -v k="$2" 'BEGIN{inf=0} /^---$/{inf++; next} inf==1 && $1==k":" {sub("^"k": *",""); print; exit}' "$1"
}

@test "exactly twelve charters and twelve agents, names 1:1" {
  [ "$(ls "$REPO_ROOT"/core/charters/*.md | wc -l)" -eq 12 ]
  [ "$(ls "$REPO_ROOT"/agents/*.md | wc -l)" -eq 12 ]
  for r in $ROLES; do
    [ -f "$REPO_ROOT/core/charters/$r.md" ]
    [ -f "$REPO_ROOT/agents/$r.md" ]
  done
}

@test "every charter has role, model_affinity, consumes, produces" {
  for r in $ROLES; do
    f="$REPO_ROOT/core/charters/$r.md"
    [ "$(fm "$f" role)" = "$r" ]
    [ -n "$(fm "$f" model_affinity)" ]
    [ -n "$(fm "$f" consumes)" ]
    [ -n "$(fm "$f" produces)" ]
  done
}

@test "every agent has name, description, and a legal model value" {
  for r in $ROLES; do
    f="$REPO_ROOT/agents/$r.md"
    [ "$(fm "$f" name)" = "$r" ]
    [ -n "$(fm "$f" description)" ]
    m="$(fm "$f" model)"
    [[ "$m" =~ ^(haiku|sonnet|opus|inherit)$ ]]
  done
}

@test "every agent body carries literal plugin-root paths and the refusal clause" {
  for r in $ROLES; do
    f="$REPO_ROOT/agents/$r.md"
    grep -qF '${CLAUDE_PLUGIN_ROOT}/core/RULES.md' "$f"
    grep -qF "\${CLAUDE_PLUGIN_ROOT}/core/charters/$r.md" "$f"
    grep -qF '${CLAUDE_PLUGIN_ROOT}/bin/memory/recall.sh' "$f"
    grep -q "stop and report the failing path" "$f"
  done
}

@test "every charter consumes entry resolves to a produces, a lifecycle artifact, or a builtin" {
  allowed=" task-ask base-ref diff receipts audit-log "
  for r in $ROLES; do
    p="$(fm "$REPO_ROOT/core/charters/$r.md" produces | tr -d '[]' | tr ',' ' ')"
    allowed="$allowed$p "
  done
  arts="$(grep -oE 'name: [a-z-]+' "$REPO_ROOT/core/lifecycle.yaml" | awk '{print $2}' | sort -u | tr '\n' ' ')"
  allowed="$allowed$arts "
  for r in $ROLES; do
    c="$(fm "$REPO_ROOT/core/charters/$r.md" consumes | tr -d '[]' | tr ',' ' ')"
    for item in $c; do
      [[ "$allowed" == *" $item "* ]] || { echo "unresolved consume '$item' in $r"; false; }
    done
  done
}

@test "reviewer charter carries the evidence rule" {
  grep -q "reproduction" "$REPO_ROOT/core/charters/reviewer.md"
  grep -q "speculation" "$REPO_ROOT/core/charters/reviewer.md"
}

@test "reviewer charter carries test-integrity distinct from test-immutability" {
  grep -q "test-integrity" "$REPO_ROOT/core/charters/reviewer.md"
  grep -q "test-immutability" "$REPO_ROOT/core/charters/reviewer.md"
}

@test "knowledge-curator charter carries the mechanization ladder" {
  grep -qi "mechani" "$REPO_ROOT/core/charters/knowledge-curator.md"
}

@test "the four lens files exist with trigger frontmatter; security carries its fixed list" {
  for l in adversarial security performance regression; do
    [ -f "$REPO_ROOT/core/lenses/$l.md" ]
    grep -q '^triggers:' "$REPO_ROOT/core/lenses/$l.md"
  done
  sec="$REPO_ROOT/core/lenses/security.md"
  for t in auth secrets "input parsing" network-facing; do
    grep -q "$t" "$sec"
  done
  [ "$(fm "$sec" auto)" = "true" ]
}

@test "regression lens reads both learning tiers directly and reports countable outcomes" {
  f="$REPO_ROOT/core/lenses/regression.md"
  grep -q "docs/learnings" "$f"
  grep -qF ".harmonia" "$f"
  grep -qF -- '- regression:hit ' "$f"
  grep -qF -- '- regression:clean ' "$f"
  grep -qi "not-applicable" "$f"
  [ "$(fm "$f" auto)" = "true" ]
}

@test "upstream falsification: both seats dispatch, record, and the lens names its targets" {
  for c in scoper planner; do
    grep -qi "adversarial" "$REPO_ROOT/core/charters/$c.md"
    grep -qF "falsification.md" "$REPO_ROOT/core/charters/$c.md"
  done
  a="$REPO_ROOT/core/lenses/adversarial.md"
  grep -qF "scope.md" "$a"
  grep -qF "design.md" "$a"
  grep -qi "consumer-less" "$a"
}

@test "falsification record grammar: seam tags, dispositions, and the per-dispatch denominator line" {
  a="$REPO_ROOT/core/lenses/adversarial.md"
  grep -qF "falsification.md" "$a"
  grep -qF 'seam=' "$a"
  grep -qF 'discuss|plan-entry|design' "$a"
  grep -qF 'dispatched: findings=' "$a"
  grep -qF 'accepted:' "$a"
  grep -qF 'rejected:' "$a"
  grep -qF 'seam=discuss' "$REPO_ROOT/core/charters/scoper.md"
  grep -qF 'seam=plan-entry' "$REPO_ROOT/core/charters/scoper.md"
  grep -qF 'seam=design' "$REPO_ROOT/core/charters/planner.md"
}

@test "panel.md exists and names the synthesis step" {
  f="$REPO_ROOT/core/patterns/panel.md"
  [ -f "$f" ]
  grep -qi "synthesis step" "$f"
  grep -qi "attribute" "$f"
}
