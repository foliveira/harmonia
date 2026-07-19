#!/usr/bin/env bats
# Multi-harness install tests - bin/install-opencode.sh against scratch targets.
# Contract: design.md D9 of task 2026-07-12-multi-harness-install; the
# assertions map to scope deliverable 4's pinned list. No live harness binary
# is invoked; every target is a scratch dir under $BATS_TEST_TMPDIR.
#
# Invocation rule (design T5): behavior and guard tests run the REPO-PATH
# installer by path - the coverage gate runs kcov with --include-path=$REPO/bin
# over `bats $REPO/tests` (bin/coverage/bash.sh), and a changed script absent
# from coverage data hard-flags file:ALL with no exemption. The one
# staged-source test exists for fresh-clone honesty and asserts EQUALITY with
# a repo-path install rather than substituting for it. Repo-path runs are
# safe: the installer resolves its source script-relatively and writes only
# under the target.
#
# Staging note (design T4): the staged test takes the file SET from git
# ls-files but CONTENT from the working tree - edits to tracked files show up
# immediately, while a brand-new file is invisible until `git add`. If the
# staged test alone is red, add the missing file to the index.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  INSTALLER="$REPO_ROOT/bin/install-opencode.sh"
  TGT="$BATS_TEST_TMPDIR/opencode"
  # Fall-through guards: even a --target parsing bug must never let a test
  # reach the developer's real config dir or home. The resolution-order test
  # overrides these per-invocation with env(1).
  export OPENCODE_CONFIG_DIR="$BATS_TEST_TMPDIR/fallthrough-config"
  export HOME="$BATS_TEST_TMPDIR/fallthrough-home"
  mkdir -p "$OPENCODE_CONFIG_DIR" "$HOME"
}

# Path, exec bit, and content hash for every file under a root - the shape two
# trees must agree on for "converged" and "identical" to mean anything.
tree_snapshot() {
  ( cd "$1" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do
      x="-"
      [ -x "$f" ] && x="x"
      printf '%s %s %s\n' "$f" "$x" "$(sha256sum < "$f" | awk '{print $1}')"
    done )
}

# A refusal is the installer speaking, not the shell failing to reach it:
# 126/127 are the shell's not-executable / not-found codes, so a guard test
# that accepted them would pass before the installer even exists.
refused() { # refused <status>
  [ "$1" -ne 0 ] && [ "$1" -ne 126 ] && [ "$1" -ne 127 ]
}

@test "fresh install places one command per skill, the engine-home mirror, and byte-0 frontmatter" {
  run "$INSTALLER" --target "$TGT"
  [ "$status" -eq 0 ]
  # One generated command file per skills/<name>/ - derived, never a literal count.
  for d in "$REPO_ROOT"/skills/*/; do
    n="$(basename "$d")"
    f="$TGT/commands/harmonia-$n.md"
    [ -f "$f" ]
    # OpenCode parses frontmatter only when it starts at byte 0; the ownership
    # marker must sit after it, so the first line is exactly the opening fence.
    [ "$(head -n1 "$f")" = "---" ]
    awk '/^---$/{c++; next} c==1 && /^description: /{found=1} END{exit !found}' "$f"
  done
  [ "$(ls "$TGT/commands"/harmonia-*.md | wc -l)" -eq "$(ls -d "$REPO_ROOT"/skills/*/ | wc -l)" ]
  # Engine home mirrors the three repo dirs; core is readable at the target.
  [ -d "$TGT/harmonia/bin" ]
  [ -d "$TGT/harmonia/core" ]
  [ -d "$TGT/harmonia/skills" ]
  [ -r "$TGT/harmonia/core/RULES.md" ]
  [ -f "$TGT/harmonia/skills/onboard/CERTIFY.md" ]   # cross-referenced by placed bodies
}

@test "a generated command body carries its full transformed source skill body, not a truncated prefix" {
  run "$INSTALLER" --target "$TGT"
  [ "$status" -eq 0 ]
  # BODY COMPLETENESS - the payload a user actually invokes. A command body is
  # the source SKILL.md body (everything past the second frontmatter fence)
  # after the two D4 rewrites: ${CLAUDE_PLUGIN_ROOT} -> the engine home and
  # /harmonia: -> /harmonia-. Frontmatter, file-count and residue checks all
  # pass on a silently truncated body, so this pins the whole body against its
  # transformed source: any dropped or altered line diverges. Skill: implement.
  skill="$REPO_ROOT/skills/implement/SKILL.md"
  cmd="$TGT/commands/harmonia-implement.md"
  [ -f "$cmd" ]
  # Extract the source body exactly as the installer does, then apply the same
  # two rewrites - transform and body-extraction commute, so this equals what a
  # faithful install places.
  expected="$(awk 'b{print; next} /^---$/{if(++n==2) b=1}' "$skill" \
    | sed -e 's|[$]{CLAUDE_PLUGIN_ROOT}|'"$TGT/harmonia"'|g' -e 's|/harmonia:|/harmonia-|g')"
  # Non-vacuity: the source body runs well past the 5-line prefix a truncation
  # mutant leaves, so an empty-against-empty match cannot pass by accident.
  [ "$(printf '%s\n' "$expected" | grep -c .)" -gt 5 ]
  # The command file heads with four lines - fence, description, fence, marker -
  # then the body; that body must equal the transformed source byte-for-byte.
  actual="$(tail -n +5 "$cmd")"
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual")
}

@test "install success is loud about the roots and the two not-ported capabilities" {
  # Scope: "a silent partial install is a defect." Success output names what
  # was placed and what was NOT ported (roster dispatch, session-start
  # injection), with a pointer to the README section. Words, not phrasing.
  run "$INSTALLER" --target "$TGT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TGT"* ]]
  echo "$output" | grep -qi dispatch
  echo "$output" | grep -qi session
  echo "$output" | grep -qi readme
}

@test "no placed artifact carries the literal plugin-root variable" {
  run "$INSTALLER" --target "$TGT"
  [ "$status" -eq 0 ]
  # Whole-target and unqualified: the closed literal ${CLAUDE_PLUGIN_ROOT}
  # appears nowhere in bin/ (only the :-guarded expansion does), so no
  # carve-out is needed. Status 1 means searched-and-clean; 2 would be a
  # grep error masquerading as a pass.
  run grep -rF -- '${CLAUDE_PLUGIN_ROOT}' "$TGT"
  [ "$status" -eq 1 ]
}

@test "placed md and yaml carry no /harmonia: residue and the /harmonia- spelling replaces it" {
  run "$INSTALLER" --target "$TGT"
  [ "$status" -eq 0 ]
  # Scoped by --include: bin/inject-context.sh ships byte-copied and its
  # runtime /harmonia: string only surfaces where the SessionStart hook is
  # wired, which is Claude Code - a deliberate survivor (design D4).
  # Several source lines carry more than one occurrence, so any residue here
  # means the rewrite was not per-line global.
  run grep -r --include='*.md' --include='*.yaml' -F -- '/harmonia:' "$TGT"
  [ "$status" -eq 1 ]
  # Vacuity guard: the new spelling actually arrived.
  grep -rqF -- '/harmonia-' "$TGT/commands"
}

@test "every engine-home path referenced by a placed body resolves at the target" {
  run "$INSTALLER" --target "$TGT"
  [ "$status" -eq 0 ]
  refs="$(grep -rhoE --include='*.md' --include='*.yaml' -- "$TGT/harmonia/[A-Za-z0-9._/-]+" "$TGT" \
    | sed 's/[.,;:]*$//' | LC_ALL=C sort -u)"
  [ -n "$refs" ]
  # Non-vacuity: the one path every stage body cites must be among them.
  echo "$refs" | grep -qF -- "$TGT/harmonia/core/RULES.md"
  missing=""
  while IFS= read -r p; do
    [ -e "$p" ] || missing="$missing$p"$'\n'
  done <<< "$refs"
  if [ -n "$missing" ]; then
    echo "unresolved engine-home references:"
    echo "$missing"
    false
  fi
}

@test "a placed bin script runs by path with the plugin root unset and reads the placed core" {
  run "$INSTALLER" --target "$TGT"
  [ "$status" -eq 0 ]
  ISO="$BATS_TEST_TMPDIR/iso"
  mkdir -p "$ISO/home" "$ISO/proj"
  # By path, no bash prefix: the exec bit is load-bearing. CLAUDE_PLUGIN_ROOT
  # unset exercises exactly the script-relative fallback the scope cites.
  # HOME/HARMONIA_HOME point at scratch so recall never reads the developer's
  # real store; recall fails open, so a bare store still emits the digest.
  run env -u CLAUDE_PLUGIN_ROOT -u HARMONIA_DISABLE \
    HOME="$ISO/home" HARMONIA_HOME="$ISO/home/.harmonia" \
    CLAUDE_PROJECT_DIR="$ISO/proj" \
    "$TGT/harmonia/bin/inject-context.sh"
  [ "$status" -eq 0 ]
  # The hook exits 0 even on internal failure by contract, so the output
  # assertions are the real probe: the rule name proves the placed script
  # found and parsed the PLACED core/RULES.md through its own fallback.
  [[ "$output" == *"Harmonia is active"* ]]
  [[ "$output" == *"Simplicity First"* ]]
}

@test "re-run converges: marked strays vanish, unmarked user files survive, tree equals fresh install" {
  "$INSTALLER" --target "$TGT"
  tree_snapshot "$TGT" > "$BATS_TEST_TMPDIR/snap-fresh"
  # A stale generated file is what a removed upstream skill leaves behind: a
  # byte copy of a generated file at a name no skill produces. Ownership must
  # ride the marker the installer stamps - not the filename and not this
  # test's knowledge of the marker's text.
  cp "$TGT/commands/harmonia-plan.md" "$TGT/commands/harmonia-zombie.md"
  printf 'user custom command' > "$TGT/commands/harmonia-custom.md"   # unmarked, prefixed, non-generated name
  printf 'user notes' > "$TGT/commands/notes.md"                      # unmarked, unrelated name
  printf 'stray' > "$TGT/harmonia/stray.txt"                          # engine-home stray: rebuild removes it
  # The README's update act is `git pull && bash bin/install-opencode.sh`;
  # this re-run is that act minus the pull (nothing to pull in a scratch
  # target) with --target standing in for the default config dir.
  run "$INSTALLER" --target "$TGT"
  [ "$status" -eq 0 ]
  [ ! -e "$TGT/commands/harmonia-zombie.md" ]
  [ ! -e "$TGT/harmonia/stray.txt" ]
  [ "$(cat "$TGT/commands/harmonia-custom.md")" = "user custom command" ]
  [ "$(cat "$TGT/commands/notes.md")" = "user notes" ]
  # Minus the two survivors, the updated tree is byte-identical to fresh.
  tree_snapshot "$TGT" | grep -vF -e './commands/harmonia-custom.md ' -e './commands/notes.md ' \
    > "$BATS_TEST_TMPDIR/snap-after"
  run diff -u "$BATS_TEST_TMPDIR/snap-fresh" "$BATS_TEST_TMPDIR/snap-after"
  [ "$status" -eq 0 ]
}

@test "an unmarked user file at a generated name aborts the install before anything is placed" {
  mkdir -p "$TGT/commands"
  printf 'my own plan command' > "$TGT/commands/harmonia-plan.md"
  run "$INSTALLER" --target "$TGT"
  refused "$status"
  [[ "$output" == *"harmonia-plan.md"* ]]   # the conflicting file is listed
  [ "$(cat "$TGT/commands/harmonia-plan.md")" = "my own plan command" ]
  [ ! -e "$TGT/harmonia" ]
  [ "$(ls "$TGT/commands" | wc -l)" -eq 1 ]   # nothing else placed
}

@test "an empty target is refused" {
  run "$INSTALLER" --target ""
  refused "$status"
  [[ "$output" == *target* ]]
}

@test "a root target is refused" {
  run "$INSTALLER" --target /
  refused "$status"
  [[ "$output" == *target* ]]
  [ ! -e /harmonia ]
}

@test "a whitespace-bearing target is refused and receives no install" {
  # Placed bodies embed the engine home in unquoted shell instructions; a
  # spaced path would hand the model broken commands (design D5).
  WS_TGT="$BATS_TEST_TMPDIR/with space"
  run "$INSTALLER" --target "$WS_TGT"
  refused "$status"
  [[ "$output" == *target* ]]
  [ ! -e "$WS_TGT/harmonia" ]
  [ ! -e "$WS_TGT/commands" ]
}

@test "an unknown argument is refused with usage" {
  run "$INSTALLER" --frobnicate
  refused "$status"
  echo "$output" | grep -qi usage
}

@test "a foreign directory at the engine home is refused and left intact" {
  mkdir -p "$TGT/harmonia"
  printf 'precious' > "$TGT/harmonia/precious.txt"
  # No core/RULES.md inside: not ours, so the swap must abort, name the path,
  # and delete nothing.
  run "$INSTALLER" --target "$TGT"
  refused "$status"
  [[ "$output" == *"$TGT/harmonia"* ]]
  [ "$(cat "$TGT/harmonia/precious.txt")" = "precious" ]
  [ "$(ls "$TGT/harmonia" | wc -l)" -eq 1 ]
}

@test "a relative trailing-slashed target normalizes to a clean absolute engine home" {
  # A relative or trailing-slashed target would otherwise splice a
  # cwd-dependent or double-slashed path into every placed body.
  mkdir -p "$BATS_TEST_TMPDIR/wd"
  cd "$BATS_TEST_TMPDIR/wd"
  run "$INSTALLER" --target "rel-tgt/"
  [ "$status" -eq 0 ]
  ABS="$BATS_TEST_TMPDIR/wd/rel-tgt"
  [ -r "$ABS/harmonia/core/RULES.md" ]
  grep -rqF -- "$ABS/harmonia/core/RULES.md" "$ABS/commands"   # absolute form spliced
  run grep -rF -- '//harmonia' "$ABS/commands"                 # no double-slash splice
  [ "$status" -eq 1 ]
}

@test "a target bearing a shell metacharacter is refused and nothing is placed" {
  # Placed bodies embed the engine home in unquoted shell instructions (design
  # D5), and the referential-integrity test above already assumes targets stay
  # within [A-Za-z0-9._/-]. A target outside that charset - here an ampersand,
  # which would also re-inject in a sed replacement - is refused whole, before
  # anything is placed. Behavior and reason pinned, not exact phrasing: a safe
  # non-trivial target still exercises the literal splice via the relative
  # trailing-slash test above (a '-'-bearing engine home), so no line is
  # stranded when this case stops being a positive.
  AMP="$BATS_TEST_TMPDIR/amp&home"
  run "$INSTALLER" --target "$AMP"
  refused "$status"
  [[ "$output" == *"$AMP"* ]]   # names the offending target, which shows the bad char
  echo "$output" | grep -qiE 'character|charset|allow|invalid|unsupported|illegal|disallow|must match|outside'
  [ ! -e "$AMP/harmonia" ]      # no engine home
  [ ! -e "$AMP/commands" ]      # no command files placed
}

@test "target resolution: HOME default, OPENCODE_CONFIG_DIR overrides, --target overrides both" {
  H="$BATS_TEST_TMPDIR/rhome"
  mkdir -p "$H"
  run env -u OPENCODE_CONFIG_DIR HOME="$H" "$INSTALLER"
  [ "$status" -eq 0 ]
  [ -r "$H/.config/opencode/harmonia/core/RULES.md" ]
  [ -f "$H/.config/opencode/commands/harmonia-plan.md" ]
  E="$BATS_TEST_TMPDIR/envcfg"
  run env OPENCODE_CONFIG_DIR="$E" HOME="$H" "$INSTALLER"
  [ "$status" -eq 0 ]
  [ -r "$E/harmonia/core/RULES.md" ]
  F="$BATS_TEST_TMPDIR/flagcfg"
  run env OPENCODE_CONFIG_DIR="$BATS_TEST_TMPDIR/never" HOME="$H" "$INSTALLER" --target "$F"
  [ "$status" -eq 0 ]
  [ -r "$F/harmonia/core/RULES.md" ]
  [ ! -e "$BATS_TEST_TMPDIR/never" ]
}

@test "an install staged from tracked files only equals the repo-path install byte-for-byte" {
  # Fresh-clone honesty (falsification line 7): the file SET comes from the
  # index, content and modes from the working tree. A helper that exists only
  # gitignored or untracked makes the staged run fail or the trees differ.
  # Both installs use the SAME target path serially: the engine-home absolute
  # path is spliced into placed bodies, so only a shared target makes
  # byte-identity well-defined (design D9's "second target" read accordingly).
  run "$INSTALLER" --target "$TGT"
  [ "$status" -eq 0 ]
  tree_snapshot "$TGT" > "$BATS_TEST_TMPDIR/snap-repo"
  rm -rf "$TGT"

  SRC="$BATS_TEST_TMPDIR/src"
  mkdir -p "$SRC"
  git -C "$REPO_ROOT" ls-files -z | (cd "$REPO_ROOT" && tar --null -T - -cf -) | tar -xf - -C "$SRC"
  [ -f "$SRC/core/RULES.md" ]                # staging sanity
  [ -x "$SRC/bin/install-opencode.sh" ]      # untracked or bit-less installer fails a fresh clone here

  run "$SRC/bin/install-opencode.sh" --target "$TGT"
  [ "$status" -eq 0 ]
  tree_snapshot "$TGT" > "$BATS_TEST_TMPDIR/snap-staged"
  run diff -u "$BATS_TEST_TMPDIR/snap-repo" "$BATS_TEST_TMPDIR/snap-staged"
  [ "$status" -eq 0 ]

  # Copy, not symlink: the install must survive the source tree going away.
  rm -rf "$SRC"
  [ -r "$TGT/harmonia/core/RULES.md" ]
}

@test "swap-time ownership re-check refuses a foreign engine home staged mid-window and leaves it byte-intact" {
  # Pre-stage a foreign (unmarked) dir at the engine home AND a valid staged
  # tree, then drive ONLY the swap step through the sourceable seam. This
  # reproduces a foreign dir appearing during the build-and-swap window, which
  # pre-flight (install-opencode.sh:82) cannot catch. Deterministic - no race.
  mkdir -p "$TGT/harmonia"
  printf 'precious' > "$TGT/harmonia/precious.txt"          # foreign: no core/RULES.md
  STAGED="$TGT/harmonia.new.staged"
  mkdir -p "$STAGED/core"
  printf 'staged' > "$STAGED/core/RULES.md"                 # a valid tree mv would install
  run bash -c 'source "$1"; swap_engine_home "$2" "$3"' _ "$INSTALLER" "$TGT/harmonia" "$STAGED"
  refused "$status"
  [[ "$output" == *"$TGT/harmonia"* ]]                      # names the path (RED on base)
  [[ "$output" == *"not removed"* ]]                        # the swap-time refusal (RED on base)
  [ "$(cat "$TGT/harmonia/precious.txt")" = "precious" ]    # byte-intact, not rm -rf'd
  [ "$(ls "$TGT/harmonia" | wc -l)" -eq 1 ]
}

@test "a --target symlinked to the filesystem root is refused by the root guard" {
  # FU-1 defense-in-depth: a symlink whose PHYSICAL location is / must be caught
  # by the root guard, not slip to a later mkdir failure. Assert the SPECIFIC
  # guard message ("filesystem root"): on base the logical pwd returns the
  # symlink path, the guard misses, and the install instead dies at the tmp
  # mkdir with exit 1 (which refused() accepts) - so a bare refused() passes
  # vacuously. The message is the discriminator (red on base, green after).
  ln -s / "$BATS_TEST_TMPDIR/rootlink"
  run "$INSTALLER" --target "$BATS_TEST_TMPDIR/rootlink"
  refused "$status"
  [[ "$output" == *"filesystem root"* ]]
  [ ! -e /harmonia ]
}
