#!/usr/bin/env bats
# House-style guards. Harmonia's writing rule ships as one byte-identical block
# inside each of the twelve charters and five lenses - the live prompt set - and
# this file is the whole of the check behind it. ASD-STE100 is the ancestry of
# the one rule enforced here, a 25-word sentence cap; it is not a conformance
# check, because STE's controlled dictionary is licensed, this repo does not
# carry it, and a cap is one structural rule out of fifty-three.
#
#   1. no sentence in the seventeen files runs past the cap;
#   2. all seventeen carry the same block, byte for byte, last in the file,
#      between exactly two sentinel lines;
#   3. the block is fit to be carried - inside its word budget, stating the same
#      cap this file enforces, and carrying no phrase the suite greps out of a
#      converted file;
#   4. the two cap exemptions still resolve, each to one whole clause no longer
#      than its ceiling, and are still exactly two;
#   5. the scan itself reds the shapes that once hid a long sentence from it and
#      passes the compliant shapes it once over-counted.
#
# The cap, the budget and the exemption list live here rather than in the
# shipped block: a number the implementer can edit is the number a seat under
# pressure edits when the check reds, and tests/ is hash-locked against the
# implementer (bin/workspace.sh:229-230 selects by ^tests?/, KTD12). An
# exemption list on the other side of that line is a kill switch - one harvested
# anchor per over-cap sentence turns every criterion green with the charters
# byte-identical to the base ref.
#
# The grammar-card cell at 17a80ff:tests/skills.bats:562-571, retired with the
# consent machinery, is the model for cell 2 (a delimited card, compared by
# digest over five NAMED files), and tests/context-budget.bats:29-35,85-89 for
# cell 3's ceiling on replicated prompt text.

CAP=25       # words; STE's descriptive sentence cap, one cap for the whole set
BUDGET=165   # words the block may cost each of the seventeen files it lands in
SENT='<!-- harmonia:style -->'

# Named, never globbed: a glob silently covers fewer files when one goes
# missing, and this list is what makes "seventeen files agree" mean anything.
FILES=(
  core/charters/committer.md
  core/charters/doc-producer.md
  core/charters/doc-reviewer.md
  core/charters/ideator.md
  core/charters/implementer.md
  core/charters/knowledge-curator.md
  core/charters/planner.md
  core/charters/reviewer.md
  core/charters/rubber-duck.md
  core/charters/scoper.md
  core/charters/simplifier.md
  core/charters/test-engineer.md
  core/lenses/adversarial.md
  core/lenses/blindspot.md
  core/lenses/performance.md
  core/lenses/regression.md
  core/lenses/security.md
)

# The two protected clauses: anti-forgery rules whose causal binding IS the
# guard, so they may be shortened but not split, and they sit over the cap by
# exemption. `grep -rn falsification bin/` returns nothing - the prose is the
# entire guard. Anchored on a distinctive substring and never on a line number,
# because a one-pass rewrite moves every line number in the file it edits.
#
#   <path> :: <anchor> :: <bound> :: <ceiling>
#
# The anchor names the clause's consequence and the bound names the rule it
# binds; both must sit in the one sentence, or the clause was split. The ceiling
# is the clause's word count today, so the exemption cannot grow into a place to
# park text the cap would refuse anywhere else. Matching runs against the masked
# sentence, where every backtick span has become `X`, so a phrase holding a
# backtick is malformed rather than unlucky.
EXEMPT=(
  "core/lenses/regression.md :: free text must not be able to forge one :: never an embedded newline :: 33"
  "core/lenses/adversarial.md :: an embedded newline could forge a countable line :: single-line only :: 27"
)

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  cd "$REPO_ROOT" || return 1   # cap_scan compares exempt paths against FILENAME
  # Cells 1 to 4 loop over FILES, and a loop over nothing passes. This is the
  # one shape that would satisfy all four and prove nothing.
  [ "${#FILES[@]}" -gt 0 ] || { echo "the named file list is empty; every cell here would pass by iterating it"; return 1; }
}

block_of() { # block_of <file> -> the bytes between the first two sentinel lines
  awk -v s="$SENT" '$0 == s { if (n++) exit; next } n == 1' "$1"
}

strip_block() { # strip_block <file>: drop the block, both sentinels included
  awk -v s="$SENT" '$0 == s { n++; next } n != 1' "$1" > "$1.stripped" && mv "$1.stripped" "$1"
}

roster_tap() { # roster_tap <tree> -> "PASS|FAIL <cell name>", one per cell
  ( cd "$1" && bats tests/roster.bats --tap 2>/dev/null ) \
    | sed -n 's/^ok [0-9][0-9]* /PASS /p; s/^not ok [0-9][0-9]* /FAIL /p'
}

# The splitter, stated for the writer in the block itself: a sentence ends at
# `.`, `?` or `!`, plus closing quotes, brackets or emphasis, before a space or
# a line end; a backtick span never ends one and counts as one word; `e.g.`, its
# five siblings and `...` never end one; a wrapped paragraph counts whole, so a
# line break is not a full stop. Joining is the axis that matters and it is
# chosen deliberately - core/lenses/regression.md's guard is one sentence across
# three physical lines, and a line-by-line splitter never sees it whole.
#
# Three rules the block leaves unstated because no writer is surprised by them:
# the abbreviations match in either case, so `E.g.` is `e.g.`; a word is a token
# holding a letter or a digit, so a dash between clauses is not one; and a
# heading, a table cell or a one-line comment is a unit scanned on its own.
#
# A structural line is scanned apart. It does NOT end a paragraph. Only a blank
# line does. Flushing on a structural line makes every such line a sentence
# terminator the writer places at will: thirty `<!-- -->` lines - which render
# as nothing - turned all six criteria green with a word-for-word identical
# prose stream, and the block itself puts two HTML comments into files that had
# none. Dropping the line instead hid whatever it carried: a 30-word heading,
# table cell or comment was never counted at all.
#
# Two shapes fail closed, because the scanner cannot tell what the writer meant.
# A list marker directly under prose that has not finished - no terminator, no
# colon - is either a new item or a hard wrap that happened to land on `- ` or
# `1. `, and reading it as an item splits one sentence in two. A comment that
# does not close on its own line has a first line no rule reads.
#
# No field read from a file is coerced to a number anywhere below; the word
# count is a loop counter compared to a literal. awk coerces a field beginning
# `nan` to NaN and NaN fails both halves of a range test, so a numeric bound is
# not a validity check. The ceilings are coerced, but they come from EXEMPT and
# are checked against ^[0-9]+$ first.
#
# Emits: OVER <file>:<line>: <n> words: <sentence>   over the cap, not exempt
#        WRAP <file>:<line>: <paragraph so far>      list marker under unfinished prose
#        UNSCANNED <file>:<line>: <why>              a line the scan cannot read
#        SPLIT <file>:<line>: <bound> :: <sentence>  anchor without its bound
#        GROWN <file>:<line>: <n> words, ...         exempt, past its ceiling
#        SCANNED <file> <n> <own>                    sentences read per file, and
#                                                    how many sit outside the block
#        ANCHOR <n> <path> :: <anchor>               sentences an entry matched
#        MALFORMED <entry>                           unparseable exemption entry
cap_scan() { # cap_scan <file>...
  # Never with an empty argument list: awk would read stdin and the cell would
  # hang rather than fail.
  [ "$#" -gt 0 ] || { echo "the scan was handed no files" >&2; return 1; }
  awk -v cap="$CAP" -v sent="$SENT" -v ex="$(printf '%s\n' "${EXEMPT[@]}")" '
    BEGIN { P = "\001"; CL = "[]\"\047)*_]*"   # P shields a dot; CL is the closing marks
      m = split(ex, L, "\n")
      for (i = 1; i <= m; i++) { if (L[i] == "") continue
        k = split(L[i], F, / :: /)
        if (k != 4 || F[1] == "" || F[2] == "" || F[3] == "" || F[2] F[3] ~ /`/ || F[4] !~ /^[0-9]+$/) { printf "MALFORMED %s\n", L[i]; continue }
        ne++; ef[ne] = F[1]; ea[ne] = tolower(F[2]); eb[ne] = tolower(F[3]); eg[ne] = F[4] + 0; ec[ne] = 0 } }
    { sub(/\r$/, "") }                                    # or CRLF hides the frontmatter and the sentinels
    FNR == 1 { flush(); fm = ($0 == "---"); fence = 0; inblk = 0 }   # or an unclosed fence hides the next file
    fm { if (FNR > 1 && $0 == "---") fm = 0; next }
    /^```/ { fence = !fence; next }
    fence { next }
    $0 == sent { inblk = !inblk; next }                   # the block is prose too, and counted apart
    /^[[:space:]]*$/ { flush(); next }                    # only a blank line ends a paragraph
    /^#/ { t = $0; sub(/^#+[ \t]*/, "", t); sub(/[ \t]+#+[ \t]*$/, "", t); scan(t, FILENAME, FNR, inblk, 0); next }
    /^<!--/ { if ($0 !~ /-->[ \t]*$/) { printf "UNSCANNED %s:%d: a comment that does not close on its own line\n", FILENAME, FNR; next }
      t = $0; sub(/^<!--/, "", t); sub(/-->[ \t]*$/, "", t); scan(t, FILENAME, FNR, inblk, 0); next }
    /^[[:space:]]*\|/ { t = $0; gsub(/`[^`]*`/, "`X`", t); k = split(t, C, /\|/)          # masked first: a span may hold a pipe
      for (i = 1; i <= k; i++) scan(C[i], FILENAME, FNR, inblk, 0); next }
    /^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]/ {
      if (para != "" && !plist && para !~ ("[.!?:]" CL "$")) printf "WRAP %s:%d: %s\n", FILENAME, FNR, para
      flush(); sub(/^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+/, ""); li = 1 }
    { sub(/^[[:space:]]*>[[:space:]]?/, ""); sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, "")
      if (para == "") { pf = FILENAME; pl = FNR; pb = inblk; plist = li }
      li = 0; para = (para == "" ? $0 : para " " $0) }
    END { flush()
      for (f in seen) printf "SCANNED %s %d %d\n", f, seen[f], own[f] + 0
      for (i = 1; i <= ne; i++) printf "ANCHOR %d %s :: %s\n", ec[i], ef[i], ea[i] }
    function flush() { if (para == "") return; scan(para, pf, pl, pb, 1); para = "" }
    function scan(t, f, l, b, prose,   k, A, i, s, w, W, x, n, hit) {
      if (!(f in seen)) seen[f] = 0
      gsub(/`[^`]*`/, "`X`", t); gsub(/\.\.\./, P P P, t)
      gsub(/(^|[^[:alnum:]])([Ee]\.[Gg]|[Ii]\.[Ee]|[Ee][Tt][Cc]|[Cc][Ff]|[Vv][Ss]|[Aa][Pp][Pp][Rr][Oo][Xx])\./, "&" P, t); gsub("\\." P, P, t)
      t = t " "; k = split(t, A, "[.!?]" CL "[ \t]+")
      for (i = 1; i <= k; i++) {
        s = A[i]; gsub(P, ".", s); sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s)
        w = 0; n = split(s, W, /[ \t]+/); for (x = 1; x <= n; x++) if (W[x] ~ /[[:alnum:]]/) w++
        if (w == 0) continue                              # or a lone `---` passes for prose
        seen[f]++; if (prose && !b) own[f]++
        hit = 0
        for (x = 1; x <= ne; x++) if (ef[x] == f && index(tolower(s), ea[x])) { ec[x]++   # a shortened clause may open on either phrase
          if (!index(tolower(s), eb[x])) { printf "SPLIT %s:%d: %s :: %s\n", f, l, eb[x], s; continue }
          hit = 1
          if (w > eg[x]) printf "GROWN %s:%d: %d words, past its %d-word ceiling: %s\n", f, l, w, eg[x], s }
        if (!hit && w > cap) printf "OVER %s:%d: %d words: %s\n", f, l, w, s } }
  ' "$@" < /dev/null
}

@test "no sentence runs past the 25-word cap" {
  local f n line scan="$BATS_TEST_TMPDIR/scan" bad=0
  for f in "${FILES[@]}"; do
    [ -f "$f" ] || { echo "$f is named by this cell and is not on disk"; bad=1; }
  done
  [ "$bad" -eq 0 ] || return 1

  cap_scan "${FILES[@]}" > "$scan"

  # Non-vacuity. A cell that passes because it iterated an empty list satisfies
  # its criterion and proves nothing, so the files the scan actually read prose
  # out of have to be the files this cell names - not merely as many of them.
  if ! diff <(printf '%s\n' "${FILES[@]}" | sort) \
            <(sed -n 's/^SCANNED \([^ ][^ ]*\) .*$/\1/p' "$scan" | sort) \
            > "$BATS_TEST_TMPDIR/unscanned"; then
    echo "the scan did not read prose out of every named file (< named, > scanned):"
    cat "$BATS_TEST_TMPDIR/unscanned"
    bad=1
  fi

  # ...counted OUTSIDE the block, which is why the scan reports both numbers.
  # Every file carries the block from round 1 on, so no file can yield zero
  # sentences after that and a file gutted to its frontmatter would satisfy the
  # check above on the strength of seventeen copies of the same prose.
  while read -r f n; do
    if [ "$n" -eq 0 ]; then
      echo "$f yields no sentence of its own; the cap check reads nothing there but the style block"
      bad=1
    fi
  done < <(sed -n 's/^SCANNED \([^ ][^ ]*\) [0-9][0-9]* \([0-9][0-9]*\)$/\1 \2/p' "$scan")

  n="$(grep -c '^OVER ' "$scan" || true)"
  if [ "$n" -ne 0 ]; then
    sed -n 's/^OVER //p' "$scan" | sort -t: -k1,1 -k2,2n
    echo "--"
    echo "$n sentences run past the $CAP-word cap, listed above as"
    echo "<file>:<line of the paragraph they sit in>: <words>: <sentence, backtick spans masked to \`X\`>"
    bad=1
  fi

  while IFS= read -r line; do
    echo "a list marker continues a sentence that has not ended: ${line#WRAP }"
    echo "  end the line above with a full stop or a colon, or rewrap so no line starts with the marker"
    bad=1
  done < <(grep '^WRAP ' "$scan" || true)
  while IFS= read -r line; do
    echo "the scan cannot read this line, so it cannot vouch for it: ${line#UNSCANNED }"
    bad=1
  done < <(grep '^UNSCANNED ' "$scan" || true)
  [ "$bad" -eq 0 ]
}

@test "the same style block, byte for byte" {
  local f n last blk h maj ref agree bad=0
  local hashes="$BATS_TEST_TMPDIR/blocks"
  : > "$hashes"

  # The named list has to be the whole surface, or "seventeen files agree" is a
  # claim about whichever files the list still remembers. tests/roster.bats:30-32
  # pins twelve charters on disk, but nothing pins that this list names them, and
  # nothing in the repo counts the lens files at all - :255 only iterates the
  # directory for README mentions. A sixth lens, or a name dropped from FILES,
  # would leave every cell here green over a file nothing checks.
  if ! diff <(printf '%s\n' "${FILES[@]}" | sort) \
            <(ls core/charters/*.md core/lenses/*.md | sort) \
            > "$BATS_TEST_TMPDIR/unnamed"; then
    echo "the named list and core/charters + core/lenses have drifted apart (< named here, > on disk):"
    cat "$BATS_TEST_TMPDIR/unnamed"
    bad=1
  fi

  for f in "${FILES[@]}"; do
    [ -f "$f" ] || { echo "$f is named by this cell and is not on disk"; bad=1; continue; }

    # Exactly two sentinel lines, matched whole-line. Anywhere-in-line lets a
    # prose mention open the block early and an empty extraction read as
    # agreement; and with the block last in the file, "after the opening
    # sentinel" and "between the sentinels" are the same bytes, so without this
    # count the closing sentinel is enforced by nothing - dropping it from all
    # seventeen passed, as did a second sentinel pair carrying arbitrary text
    # and a trailing space on every close, which silently bought three words of
    # budget.
    n="$(grep -cxF -- "$SENT" "$f" || true)"
    if [ "$n" -ne 2 ]; then
      echo "the sentinel '$SENT' is a whole line $n times in $f; the block is delimited by exactly two"
      bad=1
      continue
    fi

    # Position, which the digest cannot see: a byte-identical block placed above
    # the frontmatter kept every criterion green while the charters' --- lines
    # stopped being frontmatter, and placed mid-sentence it dissolved the
    # sentence around it. A block is a solvent wherever it lands.
    last="$(awk '/[^[:space:]]/ { l = $0 } END { print l }' "$f")"
    if [ "$last" != "$SENT" ]; then
      echo "$f does not end with the style block; its last non-empty line is: $last"
      bad=1
    fi

    blk="$(block_of "$f")"
    if [ -z "$blk" ]; then
      echo "$f's style block is empty, and an empty block is not agreement"
      bad=1
      continue
    fi
    # Hashed straight off the pipe, never out of $blk: command substitution
    # strips trailing newlines, so a blank line added before the closing
    # sentinel in one file was invisible to the comparison.
    h="$(block_of "$f" | sha256sum | awk '{print $1}')"
    printf '%s\t%s\n' "$h" "$f" >> "$hashes"
  done

  # Name the minority, never the first file. Against FILES[0] as the reference,
  # one word changed in ITS block prints sixteen failure lines every one of
  # which names an honest file - and committer.md is the smallest charter, the
  # natural place to trial a block edit.
  if [ -s "$hashes" ]; then
    maj="$(cut -f1 "$hashes" | sort | uniq -c | sort -k1,1nr -k2,2 | awk 'NR == 1 { print $2 }')"
    agree="$(cut -f1 "$hashes" | grep -cxF "$maj" || true)"
    ref="$(awk -F'\t' -v h="$maj" '$1 "" == h { print $2; exit }' "$hashes")"   # "": a field is a strnum, and h is not
    block_of "$ref" > "$BATS_TEST_TMPDIR/reference"
    while IFS=$'\t' read -r h f; do
      if [ "$h" != "$maj" ]; then
        echo "$f's style block differs from the $agree that agree with $ref:"
        diff "$BATS_TEST_TMPDIR/reference" <(block_of "$f") | head -8
        bad=1
      fi
    done < "$hashes"
  fi
  [ "$bad" -eq 0 ]
}

@test "the style block is fit to be carried by every file that carries it" {
  local f blk words stated blocks=0 bad=0

  for f in "${FILES[@]}"; do
    [ -f "$f" ] || { echo "$f is named by this cell and is not on disk"; bad=1; continue; }
    blk="$(block_of "$f")"
    if [ -z "$blk" ]; then
      echo "$f carries no style block between two '$SENT' lines"
      bad=1
      continue
    fi
    blocks=$((blocks + 1))

    # The block is replicated seventeen times, so its cost is paid seventeen
    # times and a sentence added to it lands in every dispatched prompt. The
    # budget is measured over the extraction, never the raw file, so the number
    # this cell enforces and the number the design states are one measurement.
    words="$(printf '%s\n' "$blk" | wc -w)"
    if [ "$words" -gt "$BUDGET" ]; then
      echo "$f's style block is $words words, past the $BUDGET-word budget"
      bad=1
    fi

    # The cap, pinned in BOTH directions. A grep for "25 words" in the block
    # leaves CAP free to move: at CAP=999 the block still says 25 words, cell 1
    # goes green and nothing is enforced. Compared as strings, so no field read
    # out of a file is ever coerced to a number.
    stated="$(printf '%s\n' "$blk" | grep -oE '[0-9]+[ -]words?' | grep -oE '[0-9]+' | sort -u)"
    if [ -z "$stated" ]; then
      echo "$f's style block states no word cap, so the rule the writer reads and the rule cell 1 runs are not pinned together"
      bad=1
    elif [ "$stated" != "$CAP" ]; then
      echo "$f's style block states a cap of '$(printf '%s' "$stated" | tr '\n' ' ')' and this file enforces $CAP"
      bad=1
    fi
  done

  # The pin check, behavioural. tests/roster.bats runs whole-file greps against
  # these seventeen files, so any phrase the block carries satisfies that pin in
  # all seventeen at once - and the pin then passes whether or not the file's
  # own prose still carries it. A phrase list cannot see this: a literal harvest
  # of roster.bats misses `auth`, `secrets`, `input parsing` and `network-facing`
  # because they are loop-variable values at :163, and the alternation at :242
  # is satisfiable by one plausible block sentence while planner.md's real
  # clause is deleted and the suite stays green.
  #
  # So: strip the block from a copied tree and run roster.bats there. Any cell
  # that passes with the block and fails without it is a pin the block is
  # carrying. No list, nothing to drift, and it updates itself when roster.bats
  # does.
  if [ "$blocks" -gt 0 ] && [ "$blocks" -eq "${#FILES[@]}" ]; then
    local tree="$BATS_TEST_TMPDIR/stripped" name before after
    mkdir -p "$tree"
    cp -R core agents README.md tests "$tree/"
    roster_tap "$tree" > "$BATS_TEST_TMPDIR/with.tap"
    for f in "${FILES[@]}"; do
      before="$(wc -l < "$tree/$f")"
      strip_block "$tree/$f"
      after="$(wc -l < "$tree/$f")"
      if [ "$after" -ge "$before" ]; then
        echo "stripping the block from $tree/$f removed nothing, so the run below compares a tree with itself"
        bad=1
      fi
    done
    roster_tap "$tree" > "$BATS_TEST_TMPDIR/without.tap"

    # Both runs have to have happened, and to have run the same cells. A nested
    # bats that never started prints nothing, and "nothing failed here that
    # passed there" is true of two empty files.
    if [ ! -s "$BATS_TEST_TMPDIR/with.tap" ]; then
      echo "tests/roster.bats reported no cells in the copied tree, so the comparison below is over nothing"
      bad=1
    elif ! diff <(cut -d' ' -f2- "$BATS_TEST_TMPDIR/with.tap" | sort) \
                <(cut -d' ' -f2- "$BATS_TEST_TMPDIR/without.tap" | sort) \
                > "$BATS_TEST_TMPDIR/cells"; then
      echo "tests/roster.bats runs different cells with the block and without it (< with, > without):"
      cat "$BATS_TEST_TMPDIR/cells"
      bad=1
    fi

    while IFS= read -r name; do
      if grep -qxF "PASS $name" "$BATS_TEST_TMPDIR/with.tap"; then
        echo "removing the style block reds tests/roster.bats: $name"
        echo "  so that pin is being satisfied by the block's words, in all seventeen files at once, rather than by the file's own prose"
        bad=1
      fi
    done < <(sed -n 's/^FAIL //p' "$BATS_TEST_TMPDIR/without.tap")
  fi
  [ "$bad" -eq 0 ]
}

@test "the cap exemptions still name what they exempt" {
  # GREEN ON ARRIVAL, and correctly so - the same shape tests/roster.bats:245-259
  # writes out. Both anchors resolve and both protected clauses are whole and at
  # their ceilings at the base ref, so this cell is a regression guard on a
  # property that is true before the round starts, not a gap in it.
  local line n f a scan="$BATS_TEST_TMPDIR/scan" want got bad=0

  # The exempt set is these two paths, named rather than counted, one entry
  # each. Counting is what a widening slips past: a third entry is a red cell,
  # not a quiet extension of the exemption to another sentence.
  want="$(printf '%s\n' core/lenses/adversarial.md core/lenses/regression.md)"
  got="$(printf '%s\n' "${EXEMPT[@]}" | sed 's/ :: .*$//' | sort)"
  if [ "$got" != "$want" ]; then
    echo "the exemption list names:"
    printf '%s\n' "$got" | sed 's/^/  /'
    echo "and this cell exempts exactly:"
    printf '%s\n' "$want" | sed 's/^/  /'
    bad=1
  fi

  cap_scan "${FILES[@]}" > "$scan"

  while IFS= read -r line; do
    echo "malformed exemption entry, want '<repo-relative path> :: <anchor> :: <bound> :: <ceiling>', phrases without a backtick: ${line#MALFORMED }"
    bad=1
  done < <(grep '^MALFORMED ' "$scan" || true)

  # An entry whose anchor matches nothing is a failure, not a no-op: a stale
  # exemption re-exposes the clause it was written to protect, and a stale
  # citation has been a finding in this repo twice already.
  while read -r _ n f _ a; do
    if [ "$n" -eq 0 ]; then
      echo "no sentence in $f matches the exemption anchor '$a'"
      bad=1
    elif [ "$n" -ne 1 ]; then
      echo "$n sentences in $f match the exemption anchor '$a'; an anchor that exempts more than one sentence exempts an unknown one"
      bad=1
    fi
  done < <(grep '^ANCHOR ' "$scan" || true)

  # A split reds. Without the bound an anchor cannot detect the split it exists
  # to prevent: the protected clause was cut into two independent statements
  # with the anchor phrase kept verbatim, every cell stayed green, and the causal
  # binding the guard IS was gone. Redding any exempt sentence that dropped under
  # the cap caught that too, and also redded the shortening the clause is
  # allowed.
  while IFS= read -r line; do
    echo "the exemption anchor sits in a sentence without its bound phrase, so the clause was split: ${line#SPLIT }"
    bad=1
  done < <(grep '^SPLIT ' "$scan" || true)

  # Growth reds. An exempt sentence with no ceiling is the one place in the
  # seventeen files where any amount of text passes the cap.
  while IFS= read -r line; do
    echo "an exempt clause grew: ${line#GROWN }"
    echo "  the clause may be shortened, never lengthened; the ceiling is its word count when the exemption was granted"
    bad=1
  done < <(grep '^GROWN ' "$scan" || true)

  [ "$bad" -eq 0 ]
}

@test "the scan reds what it claims to count and passes what it claims to allow" {
  # Cells 1 and 4 only ever read the seventeen real files, and those are
  # compliant, so neither can tell a working splitter from one that splits at
  # every line. These fixtures can. Each flag case hides one long sentence
  # behind a shape the splitter once misread; each pass case is compliant prose
  # it once over-counted. A case that no longer behaves names itself.
  local fx="$BATS_TEST_TMPDIR/fx" scan="$BATS_TEST_TMPDIR/fx.scan" c kind f n bad=0
  local EXEMPT=(
    "split.md :: could forge a line :: never a newline :: 30"
    "grown.md :: could forge a line :: never a newline :: 30"
    "short.md :: could forge a line :: never a newline :: 30"
    "whole.md :: could forge a line :: never a newline :: 30"
  )
  words() { seq -f 'w%g' -s ' ' "$1" "$2"; }
  mkdir -p "$fx" && cd "$fx" || return 1

  # Flag cases.
  printf '%s.\n' "$(words 1 26)" > over.md
  printf '%s\n- %s.\n' "$(words 1 15)" "$(words 16 30)" > wrap.md
  printf '%s... %s.\n' "$(words 1 15)" "$(words 16 30)" > ellipsis.md
  printf '%s E.g. %s.\n' "$(words 1 14)" "$(words 15 29)" > eg.md
  printf '# %s\n' "$(words 1 30)" > heading.md
  printf '| a | b |\n|---|---|\n| %s `x|y` %s | c |\n' "$(words 1 15)" "$(words 16 29)" > table.md
  printf '<!-- %s -->\n' "$(words 1 30)" > comment.md
  printf '<!-- %s\n-->\n' "$(words 1 30)" > comment-open.md
  printf '%s\n<!-- c -->\n# h\n| t |\n%s.\n' "$(words 1 15)" "$(words 16 30)" > interrupted.md
  printf '%s never a newline. So free text could forge a line.\n' "$(words 1 20)" > split.md
  printf '%s never a newline, so free text could forge a line.\n' "$(words 1 21)" > grown.md

  # Pass cases.
  printf '%s.\n' "$(words 1 25)" > at-cap.md
  printf '"%s." %s.\n' "$(words 1 15)" "$(words 16 30)" > quote.md
  printf '(%s.) %s.\n' "$(words 1 15)" "$(words 16 30)" > paren.md
  printf '**%s.** %s.\n' "$(words 1 15)" "$(words 16 30)" > bold.md
  printf '%s - %s - %s.\n' "$(words 1 10)" "$(words 11 20)" "$(words 21 25)" > dash.md
  printf -- '---\r\ndescription: %s\r\n---\r\n\r\n%s.\r\n' "$(words 1 30)" "$(words 1 20)" > crlf.md
  printf 'A lead:\n- %s\n  %s\n- %s.\n' "$(words 1 10)" "$(words 11 20)" "$(words 1 20)" > list.md
  printf 'Never a newline, so free text could forge a line.\n' > short.md
  printf '%s never a newline, so free text could forge a line.\n' "$(words 1 20)" > whole.md
  printf -- '---\nrole: x\n---\n\n---\n\n- -\n\n| --- |\n' > wordless.md

  cap_scan *.md > "$scan"

  # <kind> <file> [<words>]: the report each flag case must raise.
  for c in "OVER over.md 26" "WRAP wrap.md" "OVER ellipsis.md 30" "OVER eg.md 30" \
           "OVER heading.md 30" "OVER table.md 30" "OVER comment.md 30" \
           "UNSCANNED comment-open.md" "OVER interrupted.md 30" \
           "SPLIT split.md" "GROWN grown.md 31"; do
    read -r kind f n <<< "$c"
    if ! grep -qE "^$kind $f:[0-9]+: ${n:+$n words}" "$scan"; then
      echo "$f should raise $kind${n:+ at $n words}, and the scan said:"
      grep " $f:" "$scan" | sed 's/^/  /' || echo "  nothing"
      bad=1
    fi
  done

  for f in at-cap.md quote.md paren.md bold.md dash.md crlf.md list.md short.md whole.md; do
    grep -q "^SCANNED $f " "$scan" || { echo "$f passes because the scan read nothing out of it"; bad=1; }
    if grep -E "^[A-Z]+ $f:" "$scan" > "$BATS_TEST_TMPDIR/fx.hit"; then
      echo "$f is compliant, and the scan flagged it:"
      sed 's/^/  /' "$BATS_TEST_TMPDIR/fx.hit"
      bad=1
    fi
  done
  # A line of punctuation is not a sentence. Counted as one, it lets a file
  # gutted to rules and dashes pass cell 1's check that each file has prose.
  if ! grep -qx 'SCANNED wordless.md 0 0' "$scan"; then
    echo "wordless.md holds no word, and the scan counted sentences in it: $(grep 'SCANNED wordless.md' "$scan")"
    bad=1
  fi
  if grep '^MALFORMED ' "$scan"; then bad=1; fi
  [ "$bad" -eq 0 ]
}
