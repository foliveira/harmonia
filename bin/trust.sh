#!/usr/bin/env bash
# Consent to run a repository's .harmonia/project.yaml `coverage:` value.
# Sourceable by the coverage gate; also a small CLI a human runs:
#
#   trust.sh record [--repo <path>]   -> print the command, then record consent to it
#
# One record per tree, kept OUTSIDE every repository under
# ${HARMONIA_HOME:-$HOME/.harmonia}/trust/, named by the sha256 of that tree's
# physically resolved path and holding the path itself, the sha256 of the command
# as the gate will run it, and when it was agreed to. The gate asks one question
# above its eval: does a well-formed record for THIS resolved path carry the
# digest of THIS exact string.
#
# CONSENT COVERS THE STRING. IT COVERS NO FILE. A `coverage:` value that names a
# script is a pointer, and pointing at a script means trusting whatever that
# script contains when the gate runs it, including contents that arrive after
# consent was recorded. Rounds 1-4 digested the named files as well, and the
# claim could never be stated: `sh .harmonia/cov.sh` names one file whose whole
# job is to run the repository's suite, so a repository that wants to run
# different code rewrites any of the hundreds of files behind that pointer and
# consent holds. The mechanism stopped the rewrite of exactly one file and
# nothing behind it. What is kept instead is what never failed a review - the
# bytes, the string, and a grammar small enough that the words say what runs.
#
# "Outside every repository" holds while HARMONIA_HOME is unset or absolute. A
# RELATIVE HARMONIA_HOME is resolved against the caller's cwd, so `HARMONIA_HOME=.hh`
# run from a repository root keeps the store inside the tree being measured. It is
# not refused: HARMONIA_HOME is a declared trusted input (SECURITY.md), and anyone
# who can set the gate's environment can run the command directly.
#
# Provenance cannot answer the question either - a TRACKED project.yaml is the
# legitimate case, so "carried by the repository" is true of exactly the file we
# are meant to honour. What is asked instead is whether a human on this machine
# agreed to the string it carries.
set -u
# The verdict may not depend on anything outside the string, and one shell option
# read from the environment does: `case` folds case while nocasematch is set, and
# BASHOPTS carries it in before any startup file, so `SH ./cov.sh` refused and
# recorded depending on a variable. No payload where the filesystem is
# case-sensitive, and one where it is not.
shopt -u nocasematch

# The store root, restated rather than shared with bin/memory/store-lib.sh:7:
# that one is a bare ${HARMONIA_HOME:-$HOME/.harmonia}, which dies on an unbound
# variable when neither is set, and this path runs at every implement round. A
# named refusal instead, the shape bin/install-opencode.sh:78-82 ships.
trust_root() {   # -> the store directory, 1 when there is no home to look in
  [ -n "${HARMONIA_HOME:-}" ] && { printf '%s/trust' "$HARMONIA_HOME"; return 0; }
  [ -n "${HOME:-}" ] && { printf '%s/.harmonia/trust' "$HOME"; return 0; }
  return 1
}

# The identity key: the physically resolved absolute path of the tree named, and
# no answer git gives. A remote URL is chosen by the clone, a delivered `.git`
# gitfile supplies the common dir, and a tree delivered INSIDE an attested
# repository answers that repository's toplevel - each was measured executing a
# payload. Lookup is exact equality on this string; nothing here walks upwards.
trust_key() {   # <path> -> the resolved key on stdout, 1 when there is none
  # Empty and dash-leading are refused BEFORE the cd rather than by it. `cd ""`
  # returns 0 and leaves the cwd where it is, so an unguarded key answers $PWD
  # for a tree the caller never named - and gate.sh:40's own `cd` is unguarded,
  # so REPO="" is reachable from the gate too. `cd -` prints its destination into
  # the command substitution, the same class of hazard base-ref-lib.sh:23 refuses.
  case "${1:-}" in ""|-*) return 1 ;; esac
  # CDPATH cleared before the cd for that same echo reason (base-ref-lib.sh:71).
  ( CDPATH=''; cd "$1" 2>/dev/null && pwd -P ) || return 1
}

# printf '%s', never echo: no trailing newline on either side, and no option
# interpretation on a command that begins with -n. Same formula shape as
# base-ref-lib.sh:45-46, which is where this pipeline already lives.
trust_digest() {   # <string> -> the sha256 of exactly those bytes
  printf '%s' "$1" | sha256sum | awk '{print $1}'
}

# One file per tree rather than one appended index: re-recording is a plain
# overwrite with no dedup and no lock, and lookup is one path computation.
trust_record_path() {   # <key> -> that tree's record, 1 when there is no home
  local root
  root="$(trust_root)" || return 1
  printf '%s/%s' "$root" "$(trust_digest "$1")"
}

# --- which commands can be attested at all ------------------------------------
# The digest binds a POINTER, and this file says so out loud rather than trying
# to follow it. What the grammar buys instead is that the pointer is READABLE:
# a value admitted here is short enough and plain enough to take in, its first
# word per part is the program that runs, a word where a file goes is a file and
# not an option, and no word reaches through a `..`. Everything else is REFUSED
# while a human is standing there to read the refusal, and there is deliberately
# NO FALLBACK ARM: an unrecognised spelling is a refusal a person answers, not a
# silent admission the next review finds.
#
# ADMISSION IS A PURE FUNCTION OF THE STRING. Nothing below opens, stats or
# resolves anything, and that is a property with a test rather than a style
# preference: the same value gets the same verdict, byte for byte, against any
# tree and from any working directory. Rounds 1-4 decided the first word by
# where it resolved, which made admission a function of the string AND the tree,
# and every criterion written over it agreed with the wrong build as readily as
# with the right one. What can be decided from the string is decided here; what
# cannot is declared in SECURITY.md.
#
# The grammar is stated ONCE, here, and carried identically by SECURITY.md,
# skills/trust/SKILL.md, skills/onboard/SKILL.md and skills/onboard/CERTIFY.md.
# Five prose copies drifted twice - one wrong rule restated three times, then a
# byte cap missing from one of them - and a grep over prose cannot tell a list from
# a list's negation. So the block between the two sentinels is compared across all
# five files by the digest of its bytes, and against the set this recorder admits:
#
# harmonia:grammar-card
#   interpreters: sh bash dash python python3 node
#   inert: echo true
#   bytes: 1024
#   words-per-part: 64
#   byte-class: 0x20-0x7e
# harmonia:grammar-card
#
#   - BYTES. At most 1024, every one of them inside the byte class on the card.
#     TAB is outside it: the cap is sized in what a person can read on a screen,
#     and a byte worth eight columns turns 1024 bytes into 8192.
#   - TOKENS. `;`, `&&`, `||` and `|` are separators glued or spaced; any other run
#     of those characters is refused. Between separators, words split on spaces,
#     at most 64 of them, each `[A-Za-z0-9_.,:=+@/-]+` or that class inside
#     one matching pair of quotes, and none of them carrying a `..` component.
#   - PARTS. A part begins with one of NINE WORDS and nothing else: an
#     interpreter from the card spelled bare and exact, a leading `cd`, or
#     `echo`/`true`. A bare word that is not on the card is refused because PATH
#     decides what it names and PATH is not in the value.
#   - A PATH IS NOT A PROGRAM. A first word carrying a `/` is refused whatever
#     its basename and whatever it points at: `/bin/sh`, `./sh`, `./gradlew`,
#     `./node_modules/.bin/vitest`, `/usr/bin/env`. Rounds 3, 4 and 5 each gave
#     that spelling a class and each shipped a hole one spelling over - the last
#     of them left the later words of `/usr/bin/env PATH=fakebin sh ./cov.sh`
#     unconstrained, and the repository's own `fakebin/sh` ran. There is nothing
#     left to constrain when the class is gone. The cost is declared and it is
#     real: `./gradlew jacoco` is refused, and the remedy is one word in front
#     (`sh ./gradlew jacoco`) or a wrapper script of the repository's own.
#   - AN ASSIGNMENT IS NOT A PROGRAM. A first word carrying `=` anywhere is
#     refused. The shell runs the first word that is not an assignment, so a rule
#     describing this one describes something that will not run - and asking
#     instead "is this an assignment" means reimplementing the shell's assignment
#     syntax, which missed `NAME+=value` and classified `BASH_ENV+=./evil.sh` as
#     the program while bash preloaded it. `=` keeps its place in later words.
#   - AN OPTION IS NOT A FILE. A leading `-` and a leading `+` are both refused
#     where the grammar needs the name of a script or a directory: every POSIX
#     shell reads `+x` as readily as `-x`, and `cd -P` consumes its own operand and
#     lands in $HOME while the words in front of the reader say otherwise.
#   - AN INTERPRETER'S SCRIPT CARRIES A `/`. `bash cov.sh` with no cov.sh beside
#     it searches PATH and runs a file the value does not name; `bash ./cov.sh`
#     is one character longer and is the file it says it is. And it is not under
#     `/dev/` or `/proc/`: `sh ./gen.sh | sh /dev/stdin` hands an interpreter the
#     pipe it is reading as though it were a script, so what runs is bytes the
#     part before it generated and no word of the value names. Those two
#     filesystems are the only ones that give a process its own input a name.
#   - A `cd` OPERAND IS RELATIVE. An absolute `cd` is the one `cd` shape this
#     file can decide from the string, and it costs one `case` arm: where a
#     relative operand LEADS is a fact about the tree, and nothing here asks the
#     tree anything. So `cd /etc && sh ./cov.sh` is refused and `cd esc`, with
#     `esc` a committed link out of the tree, is admitted and declared - same
#     destination, opposite verdicts, and the line between them is what the
#     string says rather than how well it hides.
#   - ONLY WHAT A TOKEN CAN SEE. `$(cat x)`, a variable and a glob are refused
#     rather than ignored: the recorder cannot read what they would become.
#   - NOT A CLAIM ABOUT CONTENTS. No file is opened, hashed or listed. A script
#     the value names runs with whatever it contains at that moment, a repository
#     you clone can change that script, and the developer is told so in the same
#     act that records their consent.
# No answer git gives decides any of this: `git ls-files` executes a delivered
# core.fsmonitor, the hazard gate.sh:169 declares, and this file runs no git.

# The whole of admission, and the whole of what a record depends on besides the
# bytes: it walks the value's words, part by part, in the order a reader reads
# them, and answers yes or no.
trust_refs() {   # <command> -> 0 when the string is inside the grammar; else the reason, 1
  local cmd="$1" rest pre run w first arg canon kind nseg=0 ntok bad off code what
  # BYTES FIRST, before the recorder prints or writes anything it read. Two texts
  # on one rule: a C0 byte or 0x7f keeps the deception story, because that is what
  # a reader needs told there - a TAB included, since eight columns of nothing is
  # how a payload is scrolled off the top of a terminal; every other refused byte
  # names itself and its offset, because its common instance is invisible - a
  # pasted U+00A0, a smart quote, or the U+202E of CVE-2021-42574, which reorders
  # the rendered line in any renderer implementing the bidi algorithm. One rule
  # kills all of them, and no list of codepoints has to be kept in sync. Asked
  # through `tr` under LC_ALL=C rather than a bracket expression, whose ranges are
  # never echoed back, only named as a number. (The bracket expression in the token
  # class below has ranges of its own and no LC_ALL=C: every byte reaching it is
  # already ASCII, which is what this test guarantees.)
  #
  # THE SECOND `tr` IS NOT DECORATION AND ITS POSITION IS THE FIX. The whole
  # pipeline runs inside a command substitution, which strips trailing newlines,
  # so a value whose only out-of-class bytes are LFs answered empty here, passed
  # the byte rule, and was then split on those LFs into words - `sh ./cov.sh<LF>
  # touch /tmp/x` read as one part. Mapping LF to a printable AFTER the delete
  # leaves a byte standing where the substitution cannot eat it; mapping before
  # the delete turns the LF into a byte the delete then removes, which looks like
  # the same edit and leaves the hole exactly where it was.
  if [ -n "$(printf '%s' "$cmd" | LC_ALL=C tr -d '\40-\176' | tr '\n' 'N')" ]; then
    bad="$(printf '%s' "$cmd" | LC_ALL=C od -An -v -tu1 | tr -s ' ' '\n' | grep -v '^$' | awk '($1 < 32 || $1 > 126) { print NR-1, $1; exit }')"
    bad="${bad:-0 0}"; off="${bad% *}"; code="${bad#* }"   # a default rather than a `[: integer expression expected` on stderr if od ever answers nothing
    if [ "$code" -lt 32 ] || [ "$code" -eq 127 ]; then
      printf 'carries a control byte (0x%02x, at offset %s), which can leave your terminal showing a command other than the one that would run' "$code" "$off"
    else
      printf 'carries the byte 0x%02x at offset %s, which is outside the printable ASCII a recordable command is written in - a non-breaking space, a smart quote or an accented letter reads on screen like an ordinary character and is not one' "$code" "$off"
    fi
    return 1
  fi
  # Every byte is ASCII by now, so this counts bytes whatever the locale is. The
  # cap is what a person can read in one line rather than what a machine survives:
  # a 2179-byte value wraps to 28 terminal lines with one code-running segment in
  # it, and a printed control nobody reads is not a control.
  [ "${#cmd}" -le 1024 ] || { printf 'is %s bytes long, and only a command of at most 1024 bytes can be printed for you to read before it is recorded' "${#cmd}"; return 1; }
  rest="$cmd"
  while :; do
    pre="${rest%%[;&|]*}"
    run=''
    if [ "$pre" = "$rest" ]; then
      rest=''
    else
      rest="${rest#"$pre"}"
      # A run of separator characters is exactly one separator or it is refused:
      # `&` alone backgrounds the command, `;;` ends a case arm, `|&` pipes stderr,
      # and none of them is a shape this can describe to you honestly.
      while :; do
        case "$rest" in [\;\&\|]*) run="$run${rest:0:1}"; rest="${rest:1}" ;; *) break ;; esac
      done
      case "$run" in ';'|'&&'|'||'|'|') ;; *) printf "cannot be recorded: '%s' is not one of the four ways a recordable command joins its parts (; && || |)" "$run"; return 1 ;; esac
    fi
    nseg=$((nseg+1)); ntok=0; kind=''; first=''; arg=''
    # Split by reading lines rather than by expanding the segment, so no token is
    # ever glob-expanded: the recorder and the gate run from different working
    # directories, and an unguarded split admits `sh *.sh` at one of them and
    # classifies it differently at the other.
    while IFS= read -r w; do
      [ -n "$w" ] || continue
      ntok=$((ntok+1))
      [ "$ntok" -le 64 ] || { printf 'cannot be recorded: one part of it is more than the 64 words a recordable command is read in'; return 1; }
      # One layer of matching quotes off the token, both spellings in one arm, the
      # way config-lib.sh:22-25 takes them off the value. The split above is on
      # spaces, so `sh 'a b.sh'` is never one quoted token: it is two words, the
      # first of which is not a word this grammar has - a refusal, where round 2
      # emitted the junk reference `'a` and bound a file that does not exist.
      case "$w" in \"*\"|\'*\') w="${w:1:${#w}-2}" ;; esac
      case "$w" in ''|*[!A-Za-z0-9_.,:=+@/-]*) printf "cannot be recorded: '%s' is not a word a recordable command is written in (letters, digits and _ . , : = + @ / -)" "$w"; return 1 ;; esac
      # A `..` PATH COMPONENT, at every token and not only the first: `--out=..x`
      # and `a..b` are ordinary words and stay admitted, while `../x` and
      # `src/../lib` are refused. A path walk is physical where the shell's own
      # `cd` is logical, so the two read `a/../b` differently the moment a link is
      # involved - and a reader following the words cannot tell which reading they
      # are getting.
      case "/$w/" in *"/../"*) printf "cannot be recorded: '%s' reaches through a .. component, which a path walk and the shell itself read differently the moment a link is involved" "$w"; return 1 ;; esac
      if [ "$ntok" = 1 ]; then
        first="$w"
        # An assignment is not the program, and the rule is `=` ANYWHERE rather
        # than a match on the shell's assignment syntax: `NAME+=value` is an
        # assignment too, and a rule that missed it read `BASH_ENV+=./evil.sh` as
        # the program while bash preloaded that file into the interpreter behind
        # it. The same shape sets CDPATH from inside the value and walks past
        # every `cd` rule below. `=` keeps its place in later words (`--cov=src`).
        case "$w" in
          *=*) printf "cannot be recorded: '%s' carries an = where the program has to be, and the shell runs the first word that is not an assignment - so what would run is a later word and not this one" "$w"; return 1 ;;
        esac
        # NINE LITERALS AND NOTHING ELSE. One `case`, matched on the whole word:
        # a near miss is a refusal rather than a quiet downgrade (`python3.12` is
        # not `python3`), and so is every spelling that carries a path. There is
        # no arm for a word carrying a `/` because there is no honest one - and
        # the ordering that mattered while a basename could name an interpreter
        # from any path stops mattering when no word can be two things.
        case "$w" in
          sh|bash|dash|python|python3|node) kind=interp ;;
          cd) kind=cd; [ "$nseg" = 1 ] || { printf 'cannot be recorded: a cd is only recordable as the first thing the command does'; return 1; } ;;
          echo|true) kind=inert ;;
          *) printf "cannot be recorded: '%s' is not a word a recordable command can start with - a part begins with an interpreter (sh bash dash python python3 node), a leading cd, or echo/true, and a first word carrying a / is refused whatever it points at. Put an interpreter in front of the file, or put the command in a script of your own" "$w"; return 1 ;;
        esac
      elif [ "$ntok" = 2 ]; then
        arg="$w"
        # One rule, two sites, because a shell reads a leading `+` exactly as it
        # reads a leading `-`: `sh +x cov.sh` takes `+x` as the script and makes
        # the real one data, and `cd -P` consumes its own operand and lands in
        # $HOME while the words say a directory in this repository.
        case "$kind $w" in
          'cd '[-+]*|'interp '[-+]*)
            [ "$kind" = cd ] && what='directory a cd changes into' || what='script an interpreter runs'
            printf "cannot be recorded: '%s' is read as its own option by the program that receives it, where the %s has to be" "$w" "$what"; return 1 ;;
        esac
        # Every word after a `cd` is read from where the cd lands, so an absolute
        # operand leaves the rest of the value naming files somewhere else while
        # still reading as repository-relative paths. A leading `/` is decidable
        # from the string; where a relative name leads is not, and is declared.
        case "$kind $w" in
          'cd '/*) printf "cannot be recorded: '%s' is an absolute directory, and every word after a cd is read from where it lands - so the rest of this command would name files somewhere else while still reading as paths inside this repository" "$w"; return 1 ;;
        esac
      fi
    done <<< "${pre// /$'\n'}"
    [ "$ntok" -gt 0 ] || { printf 'cannot be recorded: it has an empty part, from a leading, doubled or trailing ; && || or |'; return 1; }
    case "$kind" in
      cd)
        # One cd, one operand, and `&&` after it. With `;` allowed,
        # `cd nosuchdir ; sh ./cov.sh` runs cov.sh at the root while the words read
        # as though it ran in sub/: the cd fails and `;` carries on regardless.
        [ "$ntok" = 2 ] || { printf 'cannot be recorded: a recordable cd names exactly one directory'; return 1; }
        [ "$run" = '&&' ] || { printf 'cannot be recorded: what follows a cd has to be joined to it with && , or the rest of the command runs somewhere else when the cd fails'; return 1; } ;;
      interp)
        [ "$ntok" -ge 2 ] || { printf "cannot be recorded: '%s' has no script operand, so nothing in this command names the file it would run" "$first"; return 1; }
        # The operand carries a `/` or the interpreter searches PATH for it, and
        # what runs is then a file the value does not name. Asked as a prefix
        # strip rather than a `case` with an empty admit arm, because an empty arm
        # and its `esac` are physical lines kcov never credits.
        [ "${arg#*/}" != "$arg" ] || { printf "cannot be recorded: '%s' has no / in it, so '%s' searches PATH for that name and what runs is a file this command does not name - write it as ./%s" "$arg" "$first" "$arg"; return 1; }
        # ...and it is a file rather than this process's own input wearing a
        # path. `sh ./gen.sh | sh /dev/stdin` runs the bytes the first part
        # printed, `/dev/fd/0` and `/proc/self/fd/0` are the same door, and no
        # word of such a value names what runs. Two prefixes, not a judgement
        # about paths: those are the only two filesystems that do this.
        #
        # THE SPELLING IS COLLAPSED BEFORE THE PREFIXES ARE ASKED, because the
        # hazard is two filesystems and a `case` compares two strings.
        # `//dev/stdin`, `///dev/stdin` and `/./dev/stdin` are the file
        # `/dev/stdin` as far as the kernel is concerned, and each of them
        # recorded, attested and ran the bytes on the other side of the pipe
        # against a bare prefix test - the rule cost one character. A leading run
        # of slashes becomes one slash and a leading `/./` goes, repeatedly,
        # which is the whole of what can put those two names anywhere but the
        # front: `..` is already refused at every token above, and no expansion
        # survives the token class. Only the front of the path is rewritten, and
        # only for the comparison - `sh /opt/tools/./cov.sh` is left alone and
        # still records, where refusing `//` and `/./` outright would take it
        # too, and it is an ordinary path a wrapper generator writes without
        # thinking. What is refused is the two filesystems, not the punctuation
        # that reaches them, and the message quotes the value as it was written.
        canon="$arg"; while :; do case "$canon" in //*) canon="/${canon#//}" ;; /./*) canon="/${canon#/./}" ;; *) break ;; esac; done
        case "$canon" in /dev/*|/proc/*) printf "cannot be recorded: '%s' is not a script this command names, it is this command's own input given a path - so what '%s' would run is bytes produced somewhere else in the same value" "$arg" "$first"; return 1 ;; esac ;;
    esac
    [ -n "$run" ] || break
  done
  return 0
}

# The verdict in words, once, for the gate and for the recorder's own read-back -
# ws_provenance_reason (base-ref-lib.sh:214) shaped, so a caller is one line and
# the remedy cannot go stale in five places. Every reason ends in the same
# remedy: it names the file to read and the command a human types, and it names
# no script path, because handing an agent the path that clears a refusal is the
# one thing the refusal itself must not do.
trust_reason() {   # <repo> <command> -> 0 attested; else print the reason, return 1
  local repo="${1:-}" cmd="${2:-}" key rec seen stored why
  local remedy=' - read the coverage: command in .harmonia/project.yaml, and record your consent with /harmonia:trust if you want it run'
  # A SECOND REMEDY, for the one refusal the first one cannot clear. The four
  # reasons above mean "nobody has agreed yet" and /harmonia:trust is the answer
  # to them. For a value the grammar refuses it is not: the recorder refuses the
  # same string, so a reader sent there goes in a circle and the only way out -
  # editing the value - is never said. Written out rather than composed from the
  # first, because the two sentences share no advice.
  local rewrite=' - /harmonia:trust refuses this value too, so the way out is to edit the coverage: value in .harmonia/project.yaml: name the program with one of the words the grammar starts a part with, or put the command in a script of your own and record `sh ./<script> && echo <report>`'
  key="$(trust_key "$repo")" || { printf "the tree at '%s' cannot be resolved, so no consent record can be found for it%s" "$repo" "$remedy"; return 1; }
  rec="$(trust_record_path "$key")" || { printf '%s%s' 'the consent record for this repository cannot be looked up: neither HARMONIA_HOME nor HOME is set' "$remedy"; return 1; }
  [ -e "$rec" ] || { printf "%s%s" "nobody on this machine has agreed to run this repository's coverage command" "$remedy"; return 1; }
  # A record that cannot be read refuses. The memory tier under this same root is
  # deliberately fail-open and torn-line-tolerant (recall.sh:37,:50,:73); a
  # consent record is not. Read with the sed idiom bin/workspace.sh:187 already
  # uses for the markers - flat, known-key, one scalar per physical line is the
  # same contract config-lib.sh:2-4 states for project.yaml. `[ -f ]` and `[ -r ]`
  # before `sed`, because a record that is a named pipe would otherwise block the
  # gate forever.
  [ -f "$rec" ] && [ -r "$rec" ] || { printf '%s%s' 'the consent record for this repository is unreadable or incomplete' "$remedy"; return 1; }
  seen="$(sed -n 's/^repo: //p' "$rec" | head -1)"
  stored="$(sed -n 's/^coverage-sha256: //p' "$rec" | head -1)"
  # `repo:` is checked against the key rather than trusted from the file name: it
  # is what turns a truncated record into a refusal with no completeness field to
  # keep. Stated exactly, and the document says the same: the record holds
  # `repo:`, `coverage-sha256:` and `recorded:`, so a truncation refuses when it
  # reaches either of the first two and a truncation that eats only `recorded:`
  # leaves the record semantically complete and still accepts.
  #
  # Any other line is ignored text. A record written by an earlier version
  # carries two more keys below these, about files, and it still attests: the
  # human read that string and agreed to it, which is exactly what is covered
  # now, so no re-record is forced on anybody.
  if [ "$seen" != "$key" ] || [[ ! "$stored" =~ ^[0-9a-f]{64}$ ]]; then
    printf '%s%s' 'the consent record for this repository is unreadable or incomplete' "$remedy"
    return 1
  fi
  # THE GRAMMAR, RE-ASKED HERE AND NOT ONLY AT RECORD TIME, and asked before the
  # digest so an out-of-grammar record fails closed. Until this line the grammar
  # was a record-time filter, and its consumer is every record this recorder did
  # not write: a hand-written one, a forged one, and above all one written by an
  # earlier round, which the migration deliberately keeps valid. Each of those
  # can cover a value this build refuses - `sh ./gen.sh | /bin/sh` was refused at
  # the door and run to completion at the gate - so without this the narrowing
  # reaches new records only. A value the grammar still admits is untouched,
  # which is the whole of the migration promise.
  why="$(trust_refs "$cmd")" || { printf 'a consent record covers this command, and the coverage: value in %s/.harmonia/project.yaml %s%s' "$key" "$why" "$rewrite"; return 1; }
  # The digest covers exactly the bytes eval receives - the value AFTER
  # config-lib.sh:22-25 strips one quote layer - so a re-quoted value, a swapped
  # &&, a changed pipe and a renamed report file are all a different string. It
  # is also the only question left: nothing here opens a file, so a rewritten
  # script, one that arrives later and one that has gone all read the same.
  [ "$stored" = "$(trust_digest "$cmd")" ] || {
    printf "%s%s" "this repository's coverage command has changed since consent was recorded for it" "$remedy"
    return 1
  }
  return 0
}

# The human act. It prints the string it is about to make executable, and what
# consent does not cover, and then writes one file; it never runs the command.
# (2026-07-31 learning: automating a hand-run step keeps the privileges and drops
# the incidental controls - the printing is the control that survives automation,
# which is why it happens even though no code reads it.)
trust_record() {   # <repo> -> 0 recorded; else print the reason, return 1
  # config-lib.sh is sourced HERE and not at the top of the file: the gate has
  # its own copy (gate.sh:37) and the recorder is the only consumer of
  # project_config in this file, so a `. trust.sh` from the seam pulls nothing in
  # behind it. Inline dirname, assigning no top-level variable - gate.sh:35 sets
  # HERE and reads it again at :300 to find the adapter, so a sourced file that
  # assigns it would silently redirect the adapter lookup.
  . "$(dirname "${BASH_SOURCE[0]}")/coverage/config-lib.sh"
  local repo="$1" key cmd root rec reason landed
  # ONE remedy text now that every refusal is about the shape of the value. The
  # wrapper leads because it is the rewrite that always terminates, and it
  # carries both of its conditions: a script that prints anything ELSE to stdout
  # records and then breaks the gate, which is worse than a refusal, because the
  # seam captures the whole of stdout as the report path.
  local remedy='Correct the value in place if that was a typo; otherwise put the command in a script of your own and record `sh ./<script> && echo <report>`, which always works. Both halves matter: the value has to end in `&& echo <report>`, and the script has to print nothing else to stdout, because the gate reads the whole of stdout as the path to the report.'
  key="$(trust_key "$repo")" || { printf "trust: the tree at '%s' cannot be entered, so there is nothing to record consent for\n" "$repo" >&2; return 1; }
  # The record is line-oriented, so a path carrying a newline could forge a
  # second coverage-sha256: line in it - the guard and the reason bin/workspace.sh:154 uses for --reason.
  case "$key" in *$'\n'*) printf 'trust: refusing to record a repository path that contains a newline\n' >&2; return 1 ;; esac
  # Read through the reader the GATE uses, so the two cannot drift: what is
  # digested is the value project_config returns, not the raw file line.
  cmd="$(project_config "$key" coverage "")"
  if [ -z "$cmd" ]; then
    # Two messages, not one. The skill's wrapper is `--repo .`, so the shape a
    # developer actually hits is running it from a subdirectory, and one message
    # for both causes tells them their config is wrong when their cwd is wrong.
    if [ -f "$key/.harmonia/project.yaml" ]; then
      printf 'trust: %s/.harmonia/project.yaml carries no coverage: value, so there is nothing to agree to\n' "$key" >&2
    else
      printf 'trust: there is no .harmonia/project.yaml at %s - run this from the repository root, or pass --repo <the repository>\n' "$key" >&2
    fi
    return 1
  fi
  # ADMISSION, and it runs before anything read from the repository is printed or
  # written. A value that is never recorded can never be attested, so this is the
  # one place the whole class can be stopped; and it is refused rather than
  # escaped for display, because an escaped form is a second string to keep honest
  # against the one that executes.
  reason=''
  reason="$(trust_refs "$cmd")" || { printf 'trust: the coverage: value in %s/.harmonia/project.yaml %s\ntrust: nothing recorded. %s\n' "$key" "$reason" "$remedy" >&2; return 1; }
  root="$(trust_root)" || { printf 'trust: neither HARMONIA_HOME nor HOME is set, so there is nowhere outside the repository to keep your consent\n' >&2; return 1; }
  printf 'recording your consent to run this command for %s:\n' "$key"
  # The bytes that are digested, and the bytes the gate will later evaluate, on
  # their own line and with nothing done to them. A byte rule that stops a
  # terminal showing a command other than the one that would run is worth nothing
  # beside a printer that shows a cleaned-up form of it, so there is no escaping
  # and no quoting here - a second display format is a second string to keep
  # honest against the one that executes.
  printf '%s\n' "$cmd"
  # ...and, in the same act, what is NOT covered. Not a list of files: there is
  # no bound set for a list to be about, and rounds 2-4 shipped one anyway, which
  # let a repository choose the annotation on the line these documents call the
  # control. One statement a developer can act on instead.
  printf 'consent covers the string above and no file: every file this command names is trusted for whatever it contains when the gate runs it, including contents that arrive after today, and a repository you clone can change that file\n'
  mkdir -p "$root" || { printf 'trust: the consent store at %s cannot be created\n' "$root" >&2; return 1; }
  rec="$(trust_record_path "$key")"
  # A plain redirect, not the .tmp + mv of bin/memory/capture.sh:67-68: a torn
  # write leaves a partial record and a partial record already refuses, so
  # atomicity would change which refusal a developer sees and nothing else. What
  # the write IS checked by is the read-back below, through the very predicate the
  # gate asks - a redirect's own exit status cannot say whether the file landed
  # (2026-08-01 learning), and nothing else keeps writer and reader from drifting.
  # Written as two redirects rather than one redirected brace group, because kcov
  # credits a group to its closing line and reads the writes inside it as
  # uncovered; and with stderr redirected FIRST, so a store path that cannot be
  # written puts the read-back's one named refusal on the terminal instead of two
  # copies of the shell's own message (a redirect failure is reported to whatever
  # stderr is when the redirect is performed, and they are performed left to right).
  printf 'repo: %s\ncoverage-sha256: %s\n' "$key" "$(trust_digest "$cmd")" 2>/dev/null > "$rec"
  printf 'recorded: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" 2>/dev/null >> "$rec"
  # Removed before the message rather than left where the developer cannot see it:
  # the read-back failing means this is not consent to anything, and a file that
  # says otherwise sitting under the store while the terminal says nothing was
  # recorded is a second thing to be wrong about.
  landed="$(trust_reason "$key" "$cmd")" || { rm -f "$rec" 2>/dev/null; printf 'trust: %s does not read back as consent to this command, so nothing has been recorded: %s\n' "$rec" "$landed" >&2; return 1; }
  printf 'consent recorded at %s - delete that file to withdraw it\n' "$rec"
}

# CLI dispatch when executed rather than sourced (bin/memory/store-lib.sh:66-73).
# `record` and nothing else: revocation is deleting the record, and no other
# subcommand has a consumer. One failure code, because no caller distinguishes
# them.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  CMD="${1:-}"; shift || true
  REPO="."
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) REPO="$2"; shift 2 ;;
      *) echo "trust: unknown argument '$1'" >&2; exit 1 ;;
    esac
  done
  case "$CMD" in
    record) trust_record "$REPO" || exit 1 ;;
    *) echo "usage: trust.sh record [--repo <path>]" >&2; exit 1 ;;
  esac
fi
