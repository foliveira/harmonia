#!/usr/bin/env bats
# U5 tests - skill parity and lint guards, plus the workspace.sh matrix.

STAGES="ideate discuss plan implement review capture quick"
RUNNER="flow"   # meta-skill spanning plan->implement->review; not a lifecycle stage
TOUCHPOINTS="accept abandon reject recall status remember"   # human-touchpoint skills; not lifecycle stages
SETUP="onboard trust"   # non-stage setup skills; not lifecycle stages, not the runner, not touchpoints

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
  # count stays exact: seven stage skills, the runner, the six touchpoints, and the two setup skills, nothing unaccounted
  n_stages="$(echo $STAGES | wc -w | tr -d ' ')"
  n_touchpoints="$(echo $TOUCHPOINTS | wc -w | tr -d ' ')"
  n_setup="$(echo $SETUP | wc -w | tr -d ' ')"
  [ "$(ls "$REPO_ROOT"/skills/*/SKILL.md | wc -l)" -eq "$((n_stages + 1 + n_touchpoints + n_setup))" ]
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

@test "the six human-touchpoint skills exist, are named, and scope to explicit /harmonia: invocation" {
  # scope: six first-class human-touchpoint commands, each a skills/<name>/SKILL.md
  # invoked namespaced as /harmonia:<name>. They are NOT lifecycle stages (absent
  # from lifecycle.yaml, not held to the stage body rules), so this pins only the
  # shared frontmatter shape - the per-command contracts are pinned below.
  for t in $TOUCHPOINTS; do
    f="$REPO_ROOT/skills/$t/SKILL.md"
    [ -f "$f" ]
    grep -q "^name: $t$" "$f"
    grep -q "^description: " "$f"
    grep -q "ONLY when explicitly invoked as /harmonia:$t" "$f"
    ! grep -q "^  $t:" "$REPO_ROOT/core/lifecycle.yaml"   # a touchpoint is not a lifecycle stage
  done
}

@test "the setup skills exist, are named, and scope to explicit /harmonia: invocation" {
  # scope: onboard and trust are non-stage setup skills - a skills/<name>/SKILL.md
  # invoked namespaced as /harmonia:<name>. Like the touchpoints they are NOT lifecycle
  # stages (absent from lifecycle.yaml, not held to the stage body rules), so this pins
  # only the shared frontmatter shape and their non-stage status - the onboard and trust
  # contract vocabularies are pinned by the coverage/trust criteria, not here.
  # trust is deliberately SETUP and not a seventh touchpoint: README.md:95 states
  # "Six commands act on a task outside the lifecycle stages", and a touchpoint here
  # would make a shipped sentence false.
  for s in $SETUP; do
    f="$REPO_ROOT/skills/$s/SKILL.md"
    [ -f "$f" ]
    grep -q "^name: $s$" "$f"
    grep -q "^description: " "$f"
    grep -q "ONLY when explicitly invoked as /harmonia:$s" "$f"
    # RESTORED IN ROUND 5. This was `! grep -q ...`, and bash suppresses errexit
    # for a command whose status is inverted with `!`, so an absence check in that
    # form asserts nothing unless it is the LAST statement of the body. It was the
    # last statement while SETUP held one element; the round that added `trust`
    # turned it into a loop, and from then on only the final iteration was
    # guarded - `onboard` could be added to lifecycle.yaml with this test green.
    # Measured both ways at the time it was found.
    if grep -q "^  $s:" "$REPO_ROOT/core/lifecycle.yaml"; then
      echo "$s is a setup skill and lifecycle.yaml lists it as a stage"; false
    fi
  done
}

@test "accept, abandon, reject are human-invoked-only wrappers that forbid flow acting for the developer" {
  # scope integrity section + 2026-07-02 learning: human-only acceptance/rejection
  # is PROSE-enforced. Each of the three states it is a human-invoked touchpoint
  # that no other skill or agent - flow named explicitly - runs on the developer's
  # behalf, and wraps its workspace.sh subcommand rather than forking the logic.
  for t in accept abandon reject; do
    f="$REPO_ROOT/skills/$t/SKILL.md"
    grep -qF "workspace.sh $t" "$f"          # wraps the subcommand; scripts stay the single source of truth
    grep -qi 'human-invoked' "$f"            # declares itself a human-invoked touchpoint
    grep -qiw 'flow' "$f"                    # names flow explicitly as forbidden from invoking it
    grep -qiF "developer's behalf" "$f"      # no other skill or agent runs it for the human
  done
  grep -q -- '--reason' "$REPO_ROOT/skills/reject/SKILL.md"   # reject surfaces its required --reason
}

@test "recall wraps the recall script and carries no human-only clause" {
  # scope command 3: recall is the human-facing convenience over bin/memory/recall.sh;
  # NOT human-only - roster agents invoke the script directly (tests/roster.bats),
  # so it carries no forbid-flow clause and this pins only that it wraps the script.
  grep -qF 'bin/memory/recall.sh' "$REPO_ROOT/skills/recall/SKILL.md"
}

@test "status is a read-only readout that derives the stage from the lifecycle contract as data" {
  # scope command 4 + design section 5: status composes resolve + the lifecycle.yaml
  # artifact contract into a readout and writes NOTHING (no marker/receipt/file). It
  # is the one touchpoint that must read lifecycle.yaml as data and carry the R9 /
  # do-not-hardcode discipline, because its job is deriving a stage from the contract.
  f="$REPO_ROOT/skills/status/SKILL.md"
  grep -qF 'workspace.sh resolve' "$f"                 # gets the active task id via resolve
  grep -qF 'core/lifecycle.yaml' "$f"                  # reads the artifact contract...
  grep -q 'do not hardcode' "$f"                       # ...as data, not a hardcoded stage table (R9)
  grep -q 'R9' "$f"
  grep -qiE 'read-only|writes no|writes nothing' "$f"  # the core promise: it writes no marker
}

@test "remember routes a single learning through capture.sh with an explicit tier and R21 discipline" {
  # scope command 6 + success criterion 4: remember elicits an explicit --tier and
  # passes it through bin/memory/capture.sh; never a bare or defaulted global write.
  # States the tier discipline - client content never reaches global (R21/--client).
  f="$REPO_ROOT/skills/remember/SKILL.md"
  grep -qF 'bin/memory/capture.sh' "$f"
  grep -q -- '--tier' "$f"
  grep -qiE 'R21|--client|client' "$f"
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
  # the human hand-back points at the command, not the bare script; the underlying
  # verify-acceptance mechanism is pinned by the separate capture-skill test below.
  grep -qF '/harmonia:accept' "$REPO_ROOT/skills/capture/SKILL.md"
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

@test "the capture skill refuses on ANY non-zero verify-acceptance exit (code-agnostic), verifies the digest, never runs accept" {
  # F1 follow-up: step 2 gates capture on the verify-acceptance mechanism and must
  # refuse CODE-AGNOSTICALLY - on ANY non-zero exit, not only the enumerated 5/1.
  # That mechanizes the exit-6 (live-rejection) block this task introduced instead
  # of leaving it to agent inference. RED today: the prose enumerates exit 5 and
  # exit 1 but carries no "non-zero" clause. The digest/mismatch/re-accept and
  # never-run-accept invariants stay pinned (nothing dropped - only the clause added).
  f="$REPO_ROOT/skills/capture/SKILL.md"
  grep -qF 'workspace.sh verify-acceptance' "$f"   # the mechanism (invariant, kept)
  grep -qiE 'non[ -]?zero' "$f"                    # code-agnostic refusal: ANY non-zero exit (NEW, RED)
  grep -qi digest "$f"
  grep -qi mismatch "$f"
  grep -qi 're-accept' "$f"
  grep -q 'Never run accept' "$f"                  # never self-accept (invariant, kept)
}

@test "the trust skill states that consent covers the string and no file, that a script it names may change, and that a control-byte value is refused" {
  # INVERTED IN ROUND 5, and the inversion is the point. Until this round the two
  # greps below REQUIRED this file to say that consent binds the files the command
  # names; that claim is retired, so a file still making it is now the defect and
  # the patterns say the opposite. The patterns are the task criterion's own, so a
  # build that satisfies one satisfies both, and no third phrasing is invented.
  #
  # What this proves is that the SUBJECTS are addressed, and not that what the
  # file says about them is true: a nine-line replacement whose body stated the
  # negation of all three claims matched every pattern in the round-3 version of
  # this test and printed ok. That is not a reason for a cleverer regex - a fourth
  # phrasing is only another string to keep in sync - it is a reason no future
  # round may read this green as "the prose is still right". Whether it is right
  # is a reading job, and the review does it by running each sentence.
  f="$REPO_ROOT/skills/trust/SKILL.md"
  grep -qEi 'whatever it contains|contents it has when it runs|trusting that script' "$f"
  grep -qEi 'arrive|later commit|after you' "$f"     # ...including code that arrives after consent
  grep -qEi 'clone|cloned' "$f"                      # ...and what a repository you clone can change
  grep -qEi 'control (byte|character)' "$f"          # a value that can lie to the terminal is refused
  # The absence half, which is what a comment cannot satisfy: the sentences the
  # retirement makes false, in the `if grep; then …; false; fi` shape, because
  # `! grep` mid-body asserts nothing under errexit.
  local claim
  for claim in 'binds-sha256' 'the files it names' 'and what consent binds' 'listed but not bound'; do
    if grep -qF "$claim" "$f"; then
      echo "skills/trust/SKILL.md still claims '$claim', which consent no longer covers"; false
    fi
  done
}

@test "the shipped files say what a command they will not record should become, and stop claiming more than the record binds" {
  # Round 2 failed on documentation as much as on code: four shipped files told a
  # developer the files their command runs were bound, and for `/bin/sh cov.sh`,
  # `env ./cov.sh`, `. ./cov.sh`, `VAR=1 ./cov.sh`, `sh <cov.sh` and `sh -c '…'`
  # they were not - each measured running a rewritten payload under recorded
  # consent. Round 3 makes the printed list the whole of the promise, so these
  # files have two new things to say - a value outside the recordable shapes is
  # refused when consent is recorded, and here is what to do with one - and three
  # sentences to stop saying, because each restates the rule that under-bound those
  # six spellings. Same discipline as the test above: the criterion's own patterns,
  # subjects rather than truth, and the absence checks are the half a comment
  # cannot satisfy.
  local f
  for f in "$REPO_ROOT/SECURITY.md" "$REPO_ROOT/skills/trust/SKILL.md"; do
    grep -qEi 'cannot be recorded|will not record|refuses to record|refuses the value' "$f"
    grep -qEi 'into a script|put it in a script|attest the script|inside a script' "$f"
    # ROUND 5. The sentence a developer has to be able to find, in both files: the
    # record covers the string, and the code behind every name in it is trusted
    # for whatever it holds when it runs. Its absence half is below.
    grep -qEi 'whatever it contains|contents it has when it runs|trusting that script' "$f"
    grep -qEi 'arrive|later commit|after you' "$f"
    # ...and the sharpest single thing the retirement gives up, which the round
    # requires in both files in those words: consent is keyed by the path, so a
    # tree swapped in at that path inherits it.
    grep -qEi 'clone|cloned' "$f"
    if grep -qF 'binds-sha256' "$f"; then
      echo "$f still documents the binding digest, which the record no longer carries"; false
    fi
    if grep -qF 'the files it names' "$f"; then
      echo "$f still says consent extends to the files the command names"; false
    fi
  done
  # Written as `if grep; then … false; fi` rather than `! grep`, because bash
  # suppresses errexit for a command whose status is inverted with `!` - so an
  # absence check in that form asserts nothing at all unless it happens to be the
  # LAST line of the test. Two of these three were in that position when they
  # shipped, and both would have gone green with the sentence they name still in
  # the file.
  if grep -qF 'Those two interpreter words and no others' "$REPO_ROOT/skills/trust/SKILL.md"; then
    echo "skills/trust/SKILL.md still states round 2's two-interpreter rule"; false
  fi
  if grep -qF 'the script operand of `sh` or `bash`' "$REPO_ROOT/SECURITY.md"; then
    echo "SECURITY.md still states round 2's reference rule"; false
  fi
  # Whitespace-normalised because this one wraps across two lines in the file, and
  # a line-oriented grep for it can never fire - which is how it survived a round
  # that checked for it.
  if tr '\n' ' ' < "$REPO_ROOT/skills/onboard/SKILL.md" | tr -s ' ' | grep -qF 'the contents of the files that command runs'; then
    echo "skills/onboard/SKILL.md still claims the record binds the contents of the files the command runs"; false
  fi
}

@test "the shipped files stop advising the shape the recorder now refuses, and say which interpreter to put in front instead" {
  # ROUND 6, and it is a retirement of ADVICE rather than of a claim. "Name the
  # program by its path" was the remedy rounds 4 and 5 printed - `npx jest
  # --coverage` becomes `./node_modules/.bin/jest --coverage`, `mvn` becomes
  # `./mvnw`, `gradle` becomes `./gradlew` - and a first word carrying a `/` is
  # refused now, so every file still carrying that sentence routes a developer
  # into a refusal. The behaviour half is pinned in tests/trust.bats, where the
  # recorder's own refusal message is asserted not to offer it; this is the
  # documentation half, and it is here because a criterion lives in a workspace
  # and this file ships.
  #
  # Absence checks in the `if grep; then … false; fi` shape, never `! grep`: bash
  # suppresses errexit for an inverted status, so the other spelling asserts
  # nothing unless it is the last line of the body.
  local f claim
  for f in SECURITY.md skills/trust/SKILL.md skills/onboard/SKILL.md skills/onboard/CERTIFY.md; do
    [ -f "$REPO_ROOT/$f" ] || { echo "$f is missing"; false; }
    for claim in 'named by a path' 'Naming the program by a path' 'basename is on the card' 'later words are its data'; do
      if grep -qF "$claim" "$REPO_ROOT/$f"; then
        echo "$f still offers '$claim', which the recorder refuses - so the file sends a developer to a value that cannot be recorded"; false
      fi
    done
  done
  # The presence half, in the three files a developer or a proposing agent is
  # actually sent to. What it proves is that the SUBJECT is addressed and not that
  # what is said about it is true - the same limit every grep over prose has, and
  # the review reads the sentences by running them. CERTIFY.md is a certification
  # checklist rather than a cookbook, so it carries the absence half only.
  for f in SECURITY.md skills/trust/SKILL.md skills/onboard/SKILL.md; do
    grep -qEi 'first word.*(carry|carries|carrying|with) a `?/|/.*in (the|its) first word.*refus|refus.*first word.*/' "$REPO_ROOT/$f" \
      || { echo "$f does not say that a first word carrying a / is refused, which is the sharpest cost this round adds"; false; }
    # ...and the remedy that replaces it: a card interpreter in front of the file.
    grep -qE '(sh|bash|node|python3) \./' "$REPO_ROOT/$f" \
      || { echo "$f shows no interpreter-in-front respelling, so it states a refusal with no way out of it"; false; }
    # WHICH interpreter is not a free choice - an npm shim is JavaScript, a pnpm
    # shim is `#!/bin/sh`, a native binary is neither - and the recorder opens no
    # file, so it cannot tell a developer which. The documents have to.
    grep -qEi 'first line|shebang|#!' "$REPO_ROOT/$f" \
      || { echo "$f tells a developer to put an interpreter in front without telling them how to choose it, and the three shapes under node_modules/.bin need three different answers"; false; }
  done
}

@test "SECURITY.md does not deny that the gate asks the grammar again above the eval, which is what it does and what the migration paragraph rests on" {
  # ROUND 7. `SECURITY.md` says both of these, sixteen lines apart: that the gate
  # "does not re-apply the recording rules" and that "the only string it ever
  # parses is one a record already matched"; and, in the migration paragraph, that
  # "the gate asks the grammar again above the `eval` rather than trusting the
  # record to have been written by this recorder". The second is what the code
  # does - a record whose repo: and digest both match is still refused when the
  # value has since been narrowed away - and it is the sentence the whole
  # migration story is built on. The first denies it, and it is a line this diff
  # added.
  #
  # A reader who stops at the earlier sentence takes away the opposite of what the
  # gate will do to them, and it is the sentence that reads like a guarantee: it
  # says an out-of-grammar string can never reach the parser, which is the claim
  # tests/trust.bats and tests/coverage.bats both red against.
  #
  # THE FIRST VERSION OF THIS CELL WENT GREEN ON A DOCUMENT CARRYING THE EXACT
  # SENTENCE IT WAS WRITTEN FOR, and both halves were wrong in different ways.
  # It is recorded here rather than quietly replaced, because the shape recurs.
  #
  #   The absence half was two `grep -qF` literals, so one word defeated each:
  #   `The gate never re-applies the recording rules` and `…one a record HAS
  #   already matched` both walked through. The second is not hypothetical - the
  #   true sentence below now contains `not one a record has already matched`, so
  #   the file itself handed the next editor the evading form.
  #
  #   The presence half was worse than weak, it was inverted: its middle
  #   alternative matched `re-apply the recording rules`, which is a substring of
  #   the denial, so "the truth is still stated" was satisfied BY THE FALSEHOOD.
  #   A document carrying only the round-6 claim passed both halves.
  #
  # The absence half is now anchored on the two things every spelling of the
  # denial has to contain: a negation in front of the verb, or the clause that
  # only the denial uses. The presence half asks for the true sentence and
  # nothing that a denial can also satisfy.
  local f="$REPO_ROOT/SECURITY.md"
  if grep -qEi '(does not|never|no longer|doesn.t) re-?appl(y|ies)|only string it ever parses' "$f"; then
    echo "SECURITY.md denies that the gate re-applies the recording rules, and the gate calls the grammar above the digest compare - so the file denies the behaviour its own migration paragraph rests on:"
    grep -nEi '(does not|never|no longer|doesn.t) re-?appl(y|ies)|only string it ever parses' "$f"
    false
  fi
  # The presence half, so the denial cannot be answered by deleting the subject:
  # the file has to say that the grammar is asked again at the gate. Satisfied
  # today by the sentence above the migration paragraph, and no longer satisfiable
  # by the denial - which is what the middle alternative used to do.
  grep -qEi 'asks the grammar again|the grammar is asked again' "$f" \
    || { echo "SECURITY.md no longer states that the gate asks the grammar again above the eval, which is the sentence a developer holding a record for a narrowed-away value needs"; false; }
  # WHAT THIS STILL CANNOT DO, stated rather than left for the next review to
  # find: both halves are string matches over prose and the absence half
  # enumerates four negations. A fresh paraphrase that avoids them - "the
  # recording rules are applied once, at record time" - passes it, and no regex
  # over English closes that. What it does close is the class that produced the
  # defect: a respelling of the sentence that was there. Whether the replacement
  # is TRUE stays a reading job, and the review does it by running the sentence
  # against the code; the behaviour itself is pinned in tests/coverage.bats and
  # tests/trust.bats, which is where a build that stopped re-applying would red.
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

@test "the grammar the recorder enforces is stated once and carried identically by the code and by every document that repeats it" {
  # The closed interpreter list, the inert words and the two caps are written out
  # in five places, and until this round nothing held them equal: round 2's blocker
  # was one wrong rule restated three times, and round 3 shipped a list whose byte
  # cap is missing from skills/onboard/SKILL.md's copy of it. The obvious check -
  # grep each file for the names - was written by this round's own attack and
  # passed three ways, including by a sentence stating the NEGATION of the list
  # ("Do NOT propose any of `sh bash dash python python3 node` - the recorder now
  # takes only `zsh`") and by a stale list left standing beside its correction. A
  # grep over prose cannot tell a list from a list's negation.
  #
  # So the grammar is a delimited card, compared by the digest of the bytes between
  # its sentinels rather than by a regex over sentences. A file may say whatever it
  # likes around the card; it still has to carry one, and a card cannot mean
  # something else. What this does NOT check is that the sentences around it are
  # true, or that the card itself is right - the first is a reading job for the
  # review, and the second is held against the shipped recorder by
  # tests/trust.bats, because five identical copies of a wrong card would satisfy
  # everything here.
  local f card h first='' firstfile='' bad=0
  for f in bin/trust.sh SECURITY.md skills/trust/SKILL.md skills/onboard/SKILL.md skills/onboard/CERTIFY.md; do
    [ -f "$REPO_ROOT/$f" ] || { echo "$f is missing"; bad=1; continue; }
    card="$(awk '/harmonia:grammar-card/{ if (n++) exit; next } n==1' "$REPO_ROOT/$f" | sed 's/^[[:space:]#*-]*//; s/[[:space:]`]*$//' | grep -v '^$' || true)"
    [ -n "$card" ] || { echo "$f carries no harmonia:grammar-card block, so nothing keeps its copy of the grammar aligned with the code"; bad=1; continue; }
    h="$(printf '%s\n' "$card" | sha256sum | awk '{print $1}')"
    if [ -z "$first" ]; then first="$h"; firstfile="$f"; printf '%s\n' "$card" > "$BATS_TEST_TMPDIR/card"; fi
    [ "$h" = "$first" ] || { echo "$f's grammar card differs from $firstfile's:"; diff "$BATS_TEST_TMPDIR/card" <(printf '%s\n' "$card") | head -8; bad=1; }
  done
  [ "$bad" -eq 0 ]
}

@test "the shipped files stop saying that an out-of-tree reference is unbound and unlisted, and stop explaining a pipeline by pipefail" {
  # Two sentences this round makes false, both of them load-bearing for a
  # developer deciding what they have agreed to.
  #
  # "listed but not bound" describes a list nobody sees: the recorder drops every
  # out-of-tree reference before printing while keeping it inside the digest, so a
  # developer told they will see `sh /opt/evil/x.sh` in the list they read does not
  # see it. Round 4 prints it AND binds where it resolves, so both halves of the
  # sentence change - the location is bound, the contents are not.
  #
  # "it records, but the gate sets no pipefail" is a caveat about a value that does
  # not record: `tail` is a bare word and the grammar refuses it, so the advice
  # explains a failure mode the reader can never reach and hides the real one.
  # The spelling that WOULD record it, `| /usr/bin/tail -1`, is this round's
  # blocker wearing a helpful voice, and it is refused too.
  #
  # An absence check is the half a comment cannot satisfy, and it is all a grep
  # can honestly do here: whether what replaces these sentences is true is a
  # reading job, done against the code. Each one is written so that it actually
  # fails - `! grep` in the middle of a bats body is not an assertion, because
  # bash suppresses errexit for an inverted status.
  local f
  for f in SECURITY.md skills/trust/SKILL.md; do
    if grep -qF 'listed but not bound' "$REPO_ROOT/$f"; then
      echo "$f still says an out-of-tree reference is listed but not bound, while the recorder lists none of them and the record binds where they resolve"; false
    fi
  done
  for f in skills/trust/SKILL.md skills/onboard/SKILL.md; do
    if grep -qF 'the gate sets no' "$REPO_ROOT/$f"; then
      echo "$f still explains a pipeline through the gate's missing pipefail, which is a caveat about a value the grammar refuses outright"; false
    fi
  done
  # ...and the truncation absolute, which is unqualified where the code is not: a
  # truncation that eats only the unread trailing line leaves the record
  # semantically complete and still attests. bin/trust.sh's own comment says so.
  if grep -qF 'a truncated or unreadable one' "$REPO_ROOT/SECURITY.md"; then
    echo "SECURITY.md still states the truncation refusal without the qualification the code carries"; false
  fi
}
