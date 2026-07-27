#!/usr/bin/env bats
# U3 roster tests - parity, frontmatter contracts, body guards, consume/produce closure.

ROLES="ideator scoper planner implementer test-engineer reviewer simplifier knowledge-curator committer doc-producer doc-reviewer rubber-duck"
DISPATCHERS="scoper planner reviewer ideator"   # the four whose charters spawn subagents
SURVEY="scoper ideator"                         # the two that survey source material before a direction is fixed

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

fm() { # fm <file> <key> -> frontmatter value
  awk -v k="$2" 'BEGIN{inf=0} /^---$/{inf++; next} inf==1 && $1==k":" {sub("^"k": *",""); print; exit}' "$1"
}

tools_of() { # tools_of <role> -> the role's declared tool names, one per line, ENDS trimmed only
  # Trim the ends, never the middle. An earlier `s/[[:space:]]//g` squeezed
  # internal space too, so `Web Fetch` normalised to `WebFetch` and certified
  # clean while the harness - which reads the literal frontmatter text - saw an
  # unregistered name and silently dropped it. With two two-word names in the
  # registered set, the internal-space typo is the likeliest shape there is, and
  # it was the one shape this reader could not see.
  fm "$REPO_ROOT/agents/$1.md" tools | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d'
}

has() { # has <role> <tool> -> 0 when the role declares EXACTLY that name (not a substring)
  tools_of "$1" | grep -qxF -- "$2"
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

@test "every agent declares a frontmatter tools: manifest of registered names, each carrying Read and Bash" {
  # An omitted tools: key inherits the harness's ENTIRE tool manifest on every
  # spawn - measured at 6.4-7.5k of the ~15-16.6k tokens a spawn costs before
  # doing any work - so the key's presence is the point of the slice.
  #
  # Three properties, none of which a raw `grep '^tools: '` would give:
  #   - FRONTMATTER, not body: fm() reads only between the two `---` lines, so a
  #     body line the harness never parses cannot satisfy this.
  #   - EXACT names, from the seven this harness registers. Grep, Glob and Task
  #     are NOT registered here (search is a Bash capability), and an
  #     unresolvable name is silently DROPPED at spawn rather than refused - the
  #     seat launches missing a capability it was written to have, and nothing
  #     at runtime notices. This test is the only thing that does. Exact
  #     matching also rejects the two shapes shipped plugins use that would not
  #     work here: the JSON-array form `tools: ["Read", "Write"]` and the
  #     `Agent(pkg:type)` spawn-scoping form.
  #   - Read and Bash on every seat: the wrapper body orders two file reads and
  #     a bin/memory/recall.sh run, so no seat can go below those two.
  registered=" Read Write Edit Bash Agent WebFetch WebSearch "
  for r in $ROLES; do
    t="$(tools_of "$r")"
    [ -n "$t" ] || { echo "$r declares no frontmatter tools: line - it inherits the whole manifest"; false; }
    for name in $t; do
      [[ "$registered" == *" $name "* ]] || { echo "$r declares '$name', which this harness does not register - it is silently dropped"; false; }
    done
    has "$r" Read || { echo "$r cannot read its charter: no Read"; false; }
    has "$r" Bash || { echo "$r cannot run recall.sh or search: no Bash"; false; }
  done
}

@test "the four dispatchers declare Agent, and only the two survey seats declare the web pair" {
  # Restriction here is soft except ONCE. A seat without Write can heredoc
  # through Bash, a seat without a search tool runs grep, and - measured, not
  # assumed - a web-free seat still reaches the network by running curl through
  # Bash. So the web pair is a declared confinement, not an enforced denial.
  # Agent is the one hard denial: nothing available in Bash spawns a subagent.
  #
  # The pair is pinned anyway, on the contract and on this: confining it to the
  # two survey seats is what makes a single line pasted across all twelve
  # structurally impossible - one shared value either carries the pair
  # everywhere (breaching the ceiling below) or nowhere (breaching the floor
  # above). The non-survey set is DERIVED from $ROLES rather than restated, so a
  # seat added to the roster is held web-free by default rather than by an
  # edit nobody remembers to make.
  for r in $DISPATCHERS; do
    has "$r" Agent || { echo "$r dispatches subagents per its charter but declares no Agent"; false; }
  done
  for r in $SURVEY; do
    has "$r" WebFetch || { echo "$r surveys source material but declares no WebFetch"; false; }
    has "$r" WebSearch || { echo "$r surveys source material but declares no WebSearch"; false; }
  done
  for r in $ROLES; do
    case " $SURVEY " in *" $r "*) continue ;; esac
    ! has "$r" WebFetch || { echo "$r is held web-free but declares WebFetch"; false; }
    ! has "$r" WebSearch || { echo "$r is held web-free but declares WebSearch"; false; }
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

@test "blind spot discovery: the scoper dispatches the lens and the lens names its target" {
  # Mirrors how the adversarial upstream mode is pinned above - dispatching seat
  # names the lens, lens names its target - rather than asserting triggers:/auto:
  # frontmatter, which would have no reader: every lens consumer reads only the
  # lenses a stage names in core/lifecycle.yaml, and no stage names this one.
  #
  # The three tokens must co-occur on ONE line. scoper.md ALREADY carries
  # `falsification.md` in its adversarial clause, so a whole-file grep would pass
  # on the strength of an unrelated paragraph. Charter paragraphs are single
  # physical lines here, so co-occurrence pins the dispatch to one real clause.
  s="$REPO_ROOT/core/charters/scoper.md"
  grep -i 'blindspot' "$s" | grep -F 'falsification.md' | grep -qF 'seam=blindspot'
  b="$REPO_ROOT/core/lenses/blindspot.md"
  [ -f "$b" ]
  grep -qF 'scope.md' "$b"           # the lens names the artifact a finding must move
  grep -qF 'falsification.md' "$b"   # ...and the existing log it records into, not a second one
}

@test "blind spot record grammar: the seam tag, the per-dispatch denominator, and both dispositions" {
  # Anchored prefixes only, not the rationale sentences (2026-07-12: state the
  # guard once, pin behaviour rather than phrasing - the single-line rule and its
  # anti-forgery reason live once in adversarial.md and are referenced, not
  # restated). The denominator line is what makes a zero-finding dispatch
  # countable, so it is pinned whole rather than as two loose fragments.
  b="$REPO_ROOT/core/lenses/blindspot.md"
  [ -f "$b" ] || { echo "core/lenses/blindspot.md does not exist"; false; }
  grep -qF 'seam=blindspot dispatched: findings=' "$b"
  grep -qF 'seam=blindspot accepted:' "$b"
  grep -qF 'seam=blindspot rejected:' "$b"
}

@test "the planner must ground a precedent claim in a search it actually ran" {
  # Both halves of the obligation on ONE line, for the same reason as the scoper
  # clause above: a whole-file pair could be satisfied by two unrelated mentions
  # in different paragraphs, which is exactly the drift this clause exists to
  # stop. Written against a logged failure - on 2026-07-14 a no-precedent claim
  # was asserted rather than grepped, and the same-frame design attack repeated
  # it instead of breaking it.
  p="$REPO_ROOT/core/charters/planner.md"
  grep -iE 'precedent|prior art|already implements' "$p" | grep -qiE 'grep|searched|looked for'
}

@test "every lens file is introduced in the README roster section" {
  # GREEN ON ARRIVAL, and correctly so. This mirrors criterion 22, which is
  # self-activating: it short-circuits while core/lenses/ holds four files and
  # binds the moment a fifth lands. A conditional guard cannot be red before its
  # condition exists - that is the shape, not a gap in the round.
  #
  # Generalised over the directory rather than grepping the literal `blindspot`,
  # so it guards every future lens and pins the behaviour (the README introduces
  # what the directory holds) rather than one sentence's wording. -F and -- per
  # the leading-dash learning: a basename is data here, never a pattern.
  for f in "$REPO_ROOT"/core/lenses/*.md; do
    l="$(basename "$f" .md)"
    grep -qiF -- "$l" "$REPO_ROOT/README.md" || { echo "lens '$l' is not named in README.md"; false; }
  done
}

@test "panel.md exists and names the synthesis step" {
  f="$REPO_ROOT/core/patterns/panel.md"
  [ -f "$f" ]
  grep -qi "synthesis step" "$f"
  grep -qi "attribute" "$f"
}
