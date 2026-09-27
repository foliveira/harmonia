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
#   4. the two cap exemptions still resolve, each to the one sentence it pins
#      verbatim, and are still exactly two;
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
# The grammar-card cell at 17a80ff:tests/skills.bats:562-571, removed in
# dcf4610 with the coverage gate, is the model for cell 2 (a delimited card,
# compared by digest over five NAMED files), and
# tests/context-budget.bats:29-35,85-89 for cell 3's ceiling on replicated
# prompt text.

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
# guard, so they sit over the cap by exemption. `grep -rn falsification bin/`
# returns nothing - the prose is the entire guard. Pinned verbatim and never on
# a line number, because a one-pass rewrite moves every line number in the file
# it edits.
#
#   <path> :: <the sentence as written, backtick spans and its stop included>
#
# Verbatim, because anything looser exempted a decoy. An anchor phrase matched a
# new sentence built to hold it while the clause itself was split in three; an
# anchor plus a bound phrase plus a word ceiling matched the same decoy. So the
# exemption names one sentence and exempts nothing else: a clause that is
# shortened, grown or split matches no entry, and cell 4 reds until this list
# says the new text. That edit is on the hash-locked side of tests/, which is
# the point. The spans and the stop are compared too. regression.md's guard is
# its span: masked, `grep -c` could become `wc -l` and the pin still matched,
# and `forge one.` could become `forge one?`. And only a paragraph of prose
# outside the block matches. A clause moved into a comment, a heading, the
# frontmatter or the block is no longer read as the guard.
EXEMPT=(
  "core/lenses/regression.md :: One line per hit or clean entry; every line single-line, never an embedded newline - the tally counts these anchored at line start (\`grep -c '^- regression:hit '\`), and free text must not be able to forge one."
  "core/lenses/adversarial.md :: The seat decides each finding and appends to the workspace's \`falsification.md\`, one event per line, free text single-line only - an embedded newline could forge a countable line:"
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
# heading that starts a block, a one-line comment anywhere, and every line of
# the frontmatter is a unit scanned on its own. Frontmatter is scanned because
# agents read the file raw (agents/*.md), so a sentence parked there is read.
# A frontmatter line is a unit only while it is one key and a value YAML cannot
# join to another line as one string: YAML does that to a wrapped, folded or
# quoted value, and a raw reader reads it as one sentence. Any other
# frontmatter line is refused. A
# `#` line inside a paragraph, or one with no space after the hashes, is more
# of the paragraph: a hard wrap that lands on `#42` is still the sentence it
# was wrapped from, and scanning it apart cut that sentence in two.
#
# A structural line is scanned apart. It does NOT end a paragraph. Only a blank
# line, a list marker or the sentinel does. Flushing on a structural line makes
# every such line a sentence terminator the writer places at will: thirty
# `<!-- -->` lines - which render as nothing - turned all six criteria green
# with a word-for-word identical prose stream, and the block itself puts two
# HTML comments into files that had none. Dropping the line instead hid
# whatever it carried: a 30-word heading or comment was never counted at all.
# The sentinel is the exception because the block is a region of its own: not
# flushing there let a lone `***` above the block run into the block's heading
# and count as the file's one sentence of prose.
#
# A list marker under prose that has not finished - no terminator, no colon,
# after the spans and abbreviations are shielded - is WRAP, unless that prose is
# an item at the same indent. Two bullets at one level are two units, and the
# lenses' report grammars are bullets with no full stop. A marker at any other
# depth under unfinished prose is a hard wrap that landed on `- ` or `1. `, or a
# child under a parent that has not ended; either way, reading it as an item
# splits one sentence in two. So a parent ends in a colon or a full stop before
# its children; none has children today.
#
# What the scan does not read, it refuses, one UNSCANNED line per offence, and
# cell 1 reds on any. Two review rounds patched one shape at a time - fence
# grammar, no-break spaces, em dashes, table cells - and each patch opened the
# next shape one hop out, and each round's attack pass on the refusals found
# more. So the scan promises less and keeps it. Refused:
#
#   - any byte outside printable ASCII and tab, which covers every Unicode
#     space, dash and look-alike, and CRLF;
#   - a frontmatter line that is not one key and a one-line value: a line
#     that is not `key: value`, which covers a wrapped or `|`/`>` value, and
#     a value holding a quote, a brace or a list that does not close on the
#     line;
#   - a character reference such as `&nbsp;` or `&#32;`, which is that same
#     space in ASCII clothing;
#   - any line that opens a code fence, backtick or tilde, indented, quoted or
#     not - no fence state exists, so no fence can hide the lines after it;
#   - any line indented four spaces or a tab, which CommonMark may read as a
#     code block whose backticks the scan would pair with the prose around it;
#   - any table row - no cell splitting exists, so no pipe rule can disagree
#     with GFM's;
#   - a comment that does not close on its own line, or that holds a second
#     `--`, or that sits inside prose, whose text no rule reads whole;
#   - any HTML tag, since `<script>` or `<pre>` opens a raw block that runs
#     past blank lines to its closing tag; a link, image or reference, whose
#     destination, title or label a renderer hides; and a processing
#     instruction, declaration or CDATA section. Each can carry a full stop
#     the reader never sees;
#   - an escaped, doubled, unpaired or angle-bracketed backtick, each of which
#     breaks the span pairing, and a mispaired span swallows the words between.
#
# Every structural test runs on the raw line. Nothing is normalised first, so
# no normalisation can turn a look-alike into the sentinel or a line of odd
# spaces into a blank one. None of the refused shapes occurs in the seventeen
# files; the first charter that wants a fence or a table is a test change here,
# and that is the point.
#
# What the scan does not claim. A full stop inside brackets or quotes before a
# space ends a sentence by the block's own rule, so `(x.)` dropped into the
# middle of one splits it, and a span of any length is one word. Both are
# visible in the raw file and in the diff. The scan catches overruns and the
# shapes a writer would not notice; deliberate, visible obfuscation is what the
# acceptance read in scope.md exists for.
#
# No field read from a file is coerced to a number anywhere below; the word
# count is a loop counter compared to a literal. awk coerces a field beginning
# `nan` to NaN and NaN fails both halves of a range test, so a numeric bound is
# not a validity check.
#
# Emits: OVER <file>:<line>: <n> words: <sentence>   over the cap, not exempt
#        WRAP <file>:<line>: <paragraph so far>      list marker under unfinished prose
#        UNSCANNED <file>:<line>: <why>              a refused line or paragraph
#        SCANNED <file> <n> <own>                    sentences read per file, and
#                                                    how many sit outside the block
#        ANCHOR <n> <path> :: <sentence>             sentences equal to an entry
#        MALFORMED <entry>                           unparseable exemption entry
cap_scan() { # cap_scan <file>...
  # Never with an empty argument list: awk would read stdin and the cell would
  # hang rather than fail.
  [ "$#" -gt 0 ] || { echo "the scan was handed no files" >&2; return 1; }
  awk -v cap="$CAP" -v sent="$SENT" -v ex="$(printf '%s\n' "${EXEMPT[@]}")" '
    BEGIN { P = "\001"; Q = "\002"; CL = "[]\"\047)*_]*"   # P shields a dot; CL is the closing marks
      m = split(ex, L, "\n")
      for (i = 1; i <= m; i++) { if (L[i] == "") continue
        k = split(L[i], F, / :: /)
        if (k != 2 || F[1] == "" || F[2] == "") { printf "MALFORMED %s\n", L[i]; continue }
        ne++; ef[ne] = F[1]; et[ne] = F[2]; ec[ne] = 0 } }
    FNR == 1 { flush(); fm = ($0 == "---"); inblk = 0 }
    /[^\t -~]/ { printf "UNSCANNED %s:%d: a byte outside printable ASCII, which this scan does not read\n", FILENAME, FNR; next }
    fm { if (FNR > 1 && $0 == "---") { fm = 0; next }
      if (FNR > 1 && !onekey($0)) { printf "UNSCANNED %s:%d: a frontmatter line that is not one key and a one-line value, which YAML may join to another line\n", FILENAME, FNR; next }
      scan($0, FILENAME, FNR, 0, 0); next }               # every frontmatter line is a unit: agents read it
    /^[ \t>]*(```|~~~)/ { printf "UNSCANNED %s:%d: a code fence, which this scan does not read\n", FILENAME, FNR; next }
    /^(    |\t)/ { printf "UNSCANNED %s:%d: an indented line, which may be a code block\n", FILENAME, FNR; next }
    $0 == sent { flush(); inblk = !inblk; next }          # the block is prose too, and counted apart
    /^[[:space:]]*$/ { flush(); next }                    # a blank line ends a paragraph
    /^[[:space:]]*\|/ { printf "UNSCANNED %s:%d: a table row, which this scan does not read\n", FILENAME, FNR; next }
    para == "" && /^#[#]?[#]?[#]?[#]?[#]?([ \t]|$)/ { t = $0; sub(/^#+[ \t]*/, "", t); sub(/[ \t]+#+[ \t]*$/, "", t); scan(t, FILENAME, FNR, inblk, 0); next }
    /^<!--/ { if ($0 !~ /^<!--([^-]|-[^-])*-->[ \t]*$/) { printf "UNSCANNED %s:%d: a comment that does not close on its own line, or holds another\n", FILENAME, FNR; next }
      t = $0; sub(/^<!--/, "", t); sub(/-->[ \t]*$/, "", t); scan(t, FILENAME, FNR, inblk, 0); next }
    /^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]/ { ind = match($0, /[^[:space:]]/) - 1
      if (para != "" && !ended(para) && !(plist && ind == pind)) printf "WRAP %s:%d: %s\n", FILENAME, FNR, para
      flush(); sub(/^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+/, ""); li = 1 }
    { sub(/^[[:space:]]*>[[:space:]]?/, ""); sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, "")
      if (para == "") { pf = FILENAME; pl = FNR; pb = inblk; plist = li; pind = ind }
      li = 0; para = (para == "" ? $0 : para " " $0) }
    END { flush()
      for (f in seen) printf "SCANNED %s %d %d\n", f, seen[f], own[f] + 0
      for (i = 1; i <= ne; i++) printf "ANCHOR %d %s :: %s\n", ec[i], ef[i], et[i] }
    function flush() { if (para == "") return; scan(para, pf, pl, pb, 1); para = "" }
    function onekey(t) {   # 1 for `key: value` whose value YAML cannot join to another line as one string
      if (t !~ /^[A-Za-z_][A-Za-z0-9_-]*:([ \t]|$)/) return 0
      sub(/^[^:]*:[ \t]*/, "", t); sub(/^\[[^]["\047]*\][ \t]*$/, "", t)   # a one-line list is plain
      return t !~ /[[{"\047]/ }                          # a quote, a brace or an open list may run on
    function shield(t,   o, n) {   # spans to `X`, kept in SP in order; a dot that ends nothing to P
      o = ""; n = 0
      while (match(t, /`[^`]*`/)) { SP[++n] = substr(t, RSTART, RLENGTH); o = o substr(t, 1, RSTART - 1) "`X`"; t = substr(t, RSTART + RLENGTH) }
      t = o t; gsub(/\.\.\./, P P P, t)
      gsub(/(^|[^[:alnum:]])([Ee]\.[Gg]|[Ii]\.[Ee]|[Ee][Tt][Cc]|[Cc][Ff]|[Vv][Ss]|[Aa][Pp][Pp][Rr][Oo][Xx])\./, "&" P, t); gsub("\\." P, P, t)
      return t }
    function unmask(s,   r) {   # each `X` back to the span it stands for, in order
      r = ""; while (match(s, /`X`/)) { r = r substr(s, 1, RSTART - 1) SP[++sj]; s = substr(s, RSTART + RLENGTH) }
      return r s }
    function ended(t) { return shield(t) ~ ("[.!?:]" CL "$") }
    function ticks(t, f, l) {   # 1 when the backticks in t cannot be paired into spans
      if (index(t, "\\`")) { printf "UNSCANNED %s:%d: an escaped backtick, which this scan does not read\n", f, l; return 1 }
      if (t ~ /<[^>]*`/) { printf "UNSCANNED %s:%d: a backtick inside angle brackets, which this scan does not read\n", f, l; return 1 }
      if (index(t, "``")) { printf "UNSCANNED %s:%d: a double backtick, which this scan does not pair\n", f, l; return 1 }
      if (gsub(/`/, "`", t) % 2) { printf "UNSCANNED %s:%d: an unpaired backtick, which would swallow the words after it\n", f, l; return 1 }
      return 0 }
    function markup(t, f, l) {   # 1 when the shielded text holds markup the scan does not read
      if (index(t, "<!--") || index(t, "-->")) { printf "UNSCANNED %s:%d: an HTML comment inside prose, which this scan does not read\n", f, l; return 1 }
      if (t ~ /<[?!]/) { printf "UNSCANNED %s:%d: a processing instruction, declaration or CDATA section, which this scan does not read\n", f, l; return 1 }
      if (t ~ /<\/?[a-zA-Z]/) { printf "UNSCANNED %s:%d: an HTML tag, with or without attributes, which this scan does not read\n", f, l; return 1 }
      if (t ~ /&[#[:alnum:]]+;/) { printf "UNSCANNED %s:%d: a character reference, which this scan does not read\n", f, l; return 1 }
      if (t ~ /\]\(|\]\[|\]:/) { printf "UNSCANNED %s:%d: a link, image or reference, whose destination, title or label this scan does not read\n", f, l; return 1 }
      return 0 }
    function scan(t, f, l, b, prose,   k, A, i, s, v, w, W, x, n, hit) {
      if (!(f in seen)) seen[f] = 0
      if (ticks(t, f, l)) return
      t = shield(t); sj = 0
      if (markup(t, f, l)) return
      t = t " "; gsub("[.!?]" CL "[ \t]+", "&" Q, t); k = split(t, A, Q)
      for (i = 1; i <= k; i++) {
        s = A[i]; gsub(P, ".", s); sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); v = unmask(s)
        w = 0; n = split(s, W, /[ \t]+/); for (x = 1; x <= n; x++) if (W[x] ~ /[[:alnum:]]/) w++
        if (w == 0) continue                              # or a lone `---` passes for prose
        seen[f]++; if (prose && !b) own[f]++
        hit = 0
        for (x = 1; x <= ne; x++) if (prose && !b && ef[x] == f && v == et[x]) { ec[x]++; hit = 1 }   # verbatim, in prose, or it exempts a decoy
        if (!hit && w > cap) printf "OVER %s:%d: %d words: %s\n", f, l, w, v } }
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
    echo "<file>:<line of the paragraph they sit in>: <words>: <sentence>"
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
  # writes out. Both entries match their clause verbatim at the base ref, so this
  # cell is a regression guard on a property that is true before the round
  # starts, not a gap in it.
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
    echo "malformed exemption entry, want '<repo-relative path> :: <sentence>': ${line#MALFORMED }"
    bad=1
  done < <(grep '^MALFORMED ' "$scan" || true)

  # One ANCHOR line per entry, or the loop below reads nothing and passes. A
  # scan that stopped reporting anchors left all five cells green.
  n="$(grep -c '^ANCHOR ' "$scan" || true)"
  if [ "$n" -ne "${#EXEMPT[@]}" ]; then
    echo "the scan reported $n ANCHOR lines for ${#EXEMPT[@]} exemption entries"
    bad=1
  fi

  # An entry that matches nothing is a failure, not a no-op: the clause was
  # shortened, grown or split, and whichever it was, the text the exemption was
  # granted for is gone. A stale citation has been a finding in this repo twice
  # already. Two matches would mean the clause appears twice, which is not the
  # file this cell knows either.
  while read -r _ n f _ a; do
    if [ "$n" -eq 0 ]; then
      echo "no sentence in $f is exactly the pinned clause, so it was shortened, grown or split; if that was meant, pin the new text here:"
      echo "  $a"
      bad=1
    elif [ "$n" -ne 1 ]; then
      echo "$n sentences in $f are exactly the pinned clause; one is the guard and the others are unknown"
      bad=1
    fi
  done < <(grep '^ANCHOR ' "$scan" || true)

  [ "$bad" -eq 0 ]
}

@test "the scan reds what it claims to count and passes what it claims to allow" {
  # Cells 1 and 4 only ever read the seventeen real files, and those are
  # compliant, so neither can tell a working splitter from one that splits at
  # every line. These fixtures can. Each flag case hides one long sentence
  # behind a shape the splitter once misread; each pass case is compliant prose
  # it once over-counted. A case that no longer behaves names itself.
  local fx="$BATS_TEST_TMPDIR/fx" scan="$BATS_TEST_TMPDIR/fx.scan" c kind f n pat clause sclause bad=0
  words() { seq -f 'w%g' -s ' ' "$1" "$2"; }
  clause="$(words 1 20) never a newline, so free text could forge a line."
  sclause="$(words 1 20) never a newline, so \`grep -c x\` could not forge a line."
  local EXEMPT=(
    "whole.md :: $clause"
    "split.md :: $clause"
    "grown.md :: $clause"
    "short.md :: $clause"
    "decoy.md :: $clause"
    "parked.md :: $clause"
    "term.md :: $clause"
    "span-order.md :: $sclause"
    "span.md :: $sclause"
    "span-swap.md :: $sclause"
  )
  mkdir -p "$fx" && cd "$fx" || return 1

  # Flag cases.
  printf '%s.\n' "$(words 1 26)" > over.md
  printf '%s\n- %s.\n' "$(words 1 15)" "$(words 16 30)" > wrap.md
  printf '%s... %s.\n' "$(words 1 15)" "$(words 16 30)" > ellipsis.md
  printf '%s E.g. %s.\n' "$(words 1 14)" "$(words 15 29)" > eg.md
  printf '# %s\n' "$(words 1 30)" > heading.md
  printf '| a | b |\n|---|---|\n| %s | c |\n' "$(words 1 30)" > table.md
  printf '<!-- %s -->\n' "$(words 1 30)" > comment.md
  printf '<!-- %s\n-->\n' "$(words 1 30)" > comment-open.md
  printf '%s\n<!-- c -->\n# h\n%s.\n' "$(words 1 15)" "$(words 16 30)" > interrupted.md   # 31: the heading joins, the comment does not
  printf '%s\n#%s.\n' "$(words 1 15)" "$(words 16 30)" > wrapped-hash.md
  printf '#%s\n%s.\n' "$(words 1 15)" "$(words 16 30)" > hash-first.md
  printf '%s\n| %s.\n' "$(words 1 15)" "$(words 16 30)" > wrapped-pipe.md
  printf '```x``` w1\n\n%s.\n' "$(words 1 30)" > inline-fence.md
  printf 'Lead.\n\n```sh\n%s.\n' "$(words 1 30)" > open-fence.md
  printf '````\n```\n````\n\n%s.\n\n```sh\nx\n```\n' "$(words 1 30)" > phantom-fence.md
  printf '~~~\n%s.\n~~~\n' "$(words 1 30)" > tilde.md
  printf '%s %s.\n' "$(words 1 15)" "$(words 16 30 | sed 's/ /\xc2\xa0/g')" > nbsp.md
  printf '%s %s.\n' "$(words 1 15)" "$(words 16 30 | sed 's/ /\xe2\x80\x94/g')" > emdash.md
  printf '%s %s.\n' "$(words 1 15)" "$(words 16 30 | sed 's/ /\xe2\x80\xaf/g')" > narrow-space.md
  printf -- '---\r\nrole: x\r\n---\r\n\r\n%s.\r\n' "$(words 1 20)" > crlf.md
  printf '``a ` b`` %s `c.\n' "$(words 1 30)" > double-tick.md   # even count, and still mispaired
  printf 'w1 ` %s `x`.\n' "$(words 2 30)" > odd-tick.md
  printf 'w1 \\` %s \\` w31.\n' "$(words 2 30)" > escaped-tick.md
  printf '<x`y> %s `z.\n' "$(words 1 30)" > autolink.md          # even count, and still mispaired
  printf '%s never a newline. So free text could forge a line.\n' "$(words 1 20)" > split.md
  printf '%s, %s.\n' "${clause%.}" "$(words 21 26)" > grown.md                # the pinned text, and more
  printf '%s\n\nNo newline may be embedded, since %s.\n' "$clause" "$(words 1 24)" > decoy.md
  printf '%s\n' "$clause" > copy.md                                     # the clause, in a file no entry names
  printf -- '---\nnote: Parked. %s\n---\n\n<!-- %s -->\n\n# %s\n\nLead.\n\n%s\n%s\n%s\n' "$clause" "$clause" "$clause" "$SENT" "$clause" "$SENT" > parked.md   # the clause, only where no reader sees it as the guard
  printf '%s?\n' "${clause%.}" > term.md                                  # the pinned text with its stop changed
  printf 'Count with `grep -c x`. %s\n' "${sclause/grep -c x/wc -l}" > span-order.md   # the pinned span sits in the sentence before
  printf '%s\n' "${sclause/grep -c x/wc -l}" > span-swap.md              # the pinned text with its span changed
  printf '%s %s&nbsp;%s.\n' "$(words 1 15)" w16 "$(words 17 30)" > entity.md
  printf 'Lead.\n\n    grep -c x\n%s.\n' "$(words 1 30)" > indented.md
  printf '> ~~~\n> x\n> ~~~\n%s.\n' "$(words 1 30)" > quoted-fence.md
  printf '%s <!-- x --> %s.\n' "$(words 1 15)" "$(words 16 30)" > inline-comment.md
  printf '%s\n<!-- --> %s <!-- -->\n' "$(words 1 15)" "$(words 16 30)" > two-comments.md
  printf '%s <a title="Why?"> %s.\n' "$(words 1 15)" "$(words 16 30)" > tag-attr.md
  printf '%s [x](y "Read it.") %s.\n' "$(words 1 15)" "$(words 16 30)" > link-title.md
  printf -- '---\nrole: x\nnote: %s\n---\n\nLead.\n' "$(words 1 29)" > frontmatter.md
  printf -- '---\nnote: %s\n  %s\n---\n\nLead.\n' "$(words 1 14)" "$(words 15 28)" > fm-wrap.md   # YAML reads one 28-word value
  printf -- '---\nnote: "%s\nnext: %s"\n---\n\nLead.\n' "$(words 1 14)" "$(words 15 28)" > fm-quoted.md
  printf -- "---\nnote: '%s\nnext: %s'\n---\n\nLead.\n" "$(words 1 14)" "$(words 15 28)" > fm-single.md
  printf -- '---\nnote: {a: %s,\nnext: %s}\n---\n\nLead.\n' "$(words 1 14)" "$(words 15 28)" > fm-brace.md
  printf -- '---\nnote: [%s,\nnext: %s]\n---\n\nLead.\n' "$(words 1 14)" "$(words 15 28)" > fm-list.md
  printf -- '---\nnote: [a, "%s]\nnext: [%s", b]\n---\n\nLead.\n' "$(words 1 14)" "$(words 15 28)" > fm-dq-list.md   # the ] sits inside an open string
  printf -- "---\nnote: [a, '%s]\nnext: [%s', b]\n---\n\nLead.\n" "$(words 1 14)" "$(words 15 28)" > fm-sq-list.md
  printf -- '---\nnote: >\n  a: %s\n  b: %s\n---\n\nLead.\n' "$(words 1 13)" "$(words 14 28)" > fm-folded.md   # key-shaped body lines, one folded value
  printf -- '---\nrole: x\n# %s\n---\n\nLead.\n' "$(words 1 30)" > fm-comment.md
  printf -- '---\nnote:%s\nnext:%s\n---\n\nLead.\n' "$(words 1 14)" "$(words 15 28)" > fm-nosep.md   # no key at all: YAML reads one 28-word string
  printf -- '---\nnote: %s %s\n---\n\nLead.\n' "$(words 1 15)" "$(words 16 30 | sed 's/ /\xc2\xa0/g')" > fm-nbsp.md   # refused before the frontmatter rule reads it
  printf '%s [the spec](https://example.com/v1.) %s.\n' "$(words 1 20)" "$(words 21 40)" > link-dest.md
  printf '%s [the spec][v1.] %s.\n' "$(words 1 20)" "$(words 21 40)" > ref-label.md
  printf 'Lead.\n\n[v1]: /x "%s."\n' "$(words 1 10)" > ref-def.md
  printf '%s <?x . ?> %s.\n' "$(words 1 15)" "$(words 16 30)" > pi.md
  printf '%s <!X . > %s.\n' "$(words 1 15)" "$(words 16 30)" > decl.md
  printf '%s <![CDATA[ . ]]> %s.\n' "$(words 1 15)" "$(words 16 30)" > cdata.md
  printf '%s <? . ?> %s.\n' "$(words 1 15)" "$(words 16 30)" > pi-space.md
  printf '> Lead.\n>\n> [v1]: /x "%s. %s"\n' "$(words 1 15)" "$(words 16 30)" > quoted-def.md   # a definition after a quoted blank line
  printf '<script>\n\n%s.\n' "$(words 1 10)" > tag.md   # a raw block that runs past blank lines, and never closes
  printf '%s </b> %s.\n' "$(words 1 15)" "$(words 16 30)" > close-tag.md
  printf '####### %s\n%s.\n' "$(words 1 15)" "$(words 16 30)" > seven-hash.md   # seven hashes is not a heading
  printf '%s (e.g. %s).\n' "$(words 1 14)" "$(words 15 29)" > paren-eg.md
  printf '   ~~~\n%s.\n   ~~~\n' "$(words 1 30)" > indented-fence.md
  printf 'Lead.\n\n\tgrep -c x\n%s.\n' "$(words 1 30)" > tab-indent.md
  printf -- '---\nrole: x\n---\n\n***\n%s\n## House style\n\nText here.\n%s\n' "$SENT" "$SENT" > gutted.md
  printf -- '- %s\n  %s\n  - %s.\n' "$(words 1 15)" "$(words 16 20)" "$(words 21 30)" > list-wrap.md   # a deeper marker under an unfinished item; four spaces would be refused as indented
  printf '%s etc.\n- %s.\n' "$(words 1 15)" "$(words 16 30)" > wrap-etc.md

  # Pass cases.
  printf '%s.\n' "$(words 1 25)" > at-cap.md
  printf '"%s." %s.\n' "$(words 1 15)" "$(words 16 30)" > quote.md
  printf '(%s.) %s.\n' "$(words 1 15)" "$(words 16 30)" > paren.md
  printf '**%s.** %s.\n' "$(words 1 15)" "$(words 16 30)" > bold.md
  printf '%s - %s - %s.\n' "$(words 1 10)" "$(words 11 20)" "$(words 21 25)" > dash.md
  printf 'A lead:\n- %s\n  %s\n- %s.\n' "$(words 1 10)" "$(words 11 20)" "$(words 1 20)" > list.md   # a wrapped item with no stop, then a sibling
  printf 'Never a newline, so free text could forge a line.\n' > short.md   # shortened, and the pin not updated
  printf '%s\n' "$clause" > whole.md
  printf '%s\n' "$sclause" > span.md
  printf -- '---\nrole: x\n---\n\n---\n\n- -\n' > wordless.md
  printf -- '- %s\n- %s\n' "$(words 1 10)" "$(words 11 20)" > siblings.md   # two bullets, no full stop, one level
  printf -- '---\nconsumes: [a, b-c]\n---\n\n%s.\n' "$(words 1 25)" > fm-list-ok.md   # a list closed on its line is one plain value

  cap_scan *.md > "$scan"

  # <kind> <file> [<words> | <reason word> | <matches>]: the report each flag
  # case must raise. An UNSCANNED case names a word from the reason it expects,
  # so each fixture holds its own refusal and not whichever one happened to
  # fire. An ANCHOR case names how many sentences equal the pinned clause.
  for c in "OVER over.md 26" "WRAP wrap.md" "OVER ellipsis.md 30" "OVER eg.md 30" \
           "OVER heading.md 30" "OVER comment.md 30" "UNSCANNED comment-open.md close" \
           "OVER interrupted.md 31" "OVER wrapped-hash.md 30" "OVER hash-first.md 30" \
           "UNSCANNED table.md table" "UNSCANNED wrapped-pipe.md table" \
           "UNSCANNED inline-fence.md fence" "OVER inline-fence.md 30" "UNSCANNED open-fence.md fence" \
           "UNSCANNED phantom-fence.md fence" "OVER phantom-fence.md 30" "UNSCANNED tilde.md fence" \
           "UNSCANNED quoted-fence.md fence" "UNSCANNED indented.md indented" \
           "UNSCANNED nbsp.md ASCII" "UNSCANNED emdash.md ASCII" "UNSCANNED narrow-space.md ASCII" "UNSCANNED crlf.md ASCII" \
           "UNSCANNED entity.md reference" \
           "UNSCANNED double-tick.md double" "UNSCANNED odd-tick.md unpaired" \
           "UNSCANNED escaped-tick.md escaped" "UNSCANNED autolink.md angle" \
           "UNSCANNED inline-comment.md inside" "UNSCANNED two-comments.md another" \
           "UNSCANNED tag-attr.md attributes" "UNSCANNED link-title.md title" \
           "OVER frontmatter.md 30" "WRAP list-wrap.md" "WRAP wrap-etc.md" \
           "UNSCANNED fm-wrap.md key" "UNSCANNED fm-quoted.md key" "UNSCANNED fm-single.md key" \
           "UNSCANNED fm-brace.md key" "UNSCANNED fm-list.md key" "UNSCANNED fm-nbsp.md ASCII" \
           "UNSCANNED fm-dq-list.md key" "UNSCANNED fm-sq-list.md key" \
           "UNSCANNED tag.md tag" "UNSCANNED close-tag.md tag" \
           "UNSCANNED fm-folded.md key" "UNSCANNED fm-comment.md key" "UNSCANNED fm-nosep.md key" \
           "UNSCANNED cdata.md CDATA" "UNSCANNED pi-space.md instruction" "UNSCANNED quoted-def.md link" \
           "UNSCANNED link-dest.md link" "UNSCANNED ref-label.md link" "UNSCANNED ref-def.md link" \
           "UNSCANNED pi.md instruction" "UNSCANNED decl.md declaration" \
           "OVER seven-hash.md 30" "OVER paren-eg.md 30" \
           "UNSCANNED indented-fence.md fence" "UNSCANNED tab-indent.md indented" \
           "ANCHOR split.md 0" "ANCHOR grown.md 0" "OVER grown.md 36" "ANCHOR short.md 0" \
           "ANCHOR decoy.md 1" "OVER decoy.md 30" "OVER copy.md 30" \
           "ANCHOR parked.md 0" "OVER parked.md 30" "ANCHOR term.md 0" "OVER term.md 30" \
           "ANCHOR span-order.md 0" "OVER span-order.md 30" \
           "ANCHOR span.md 1" "ANCHOR span-swap.md 0" "OVER span-swap.md 30"; do
    read -r kind f n <<< "$c"
    case "$kind" in
      OVER)      pat="^$kind $f:[0-9]+: $n words" ;;
      UNSCANNED) pat="^$kind $f:[0-9]+: .*$n" ;;
      ANCHOR)    pat="^ANCHOR $n $f ::" ;;
      *)         pat="^$kind $f:" ;;
    esac
    if ! grep -qE "$pat" "$scan"; then
      echo "$f should raise $kind${n:+ ($n)}, and the scan said:"
      grep " $f:" "$scan" | sed 's/^/  /' || echo "  nothing"
      bad=1
    fi
  done

  for f in at-cap.md quote.md paren.md bold.md dash.md list.md siblings.md whole.md span.md fm-list-ok.md; do
    grep -q "^SCANNED $f " "$scan" || { echo "$f passes because the scan read nothing out of it"; bad=1; }
    if grep -E "^[A-Z]+ $f:" "$scan" > "$BATS_TEST_TMPDIR/fx.hit"; then
      echo "$f is compliant, and the scan flagged it:"
      sed 's/^/  /' "$BATS_TEST_TMPDIR/fx.hit"
      bad=1
    fi
  done
  # A line of punctuation is not a sentence. Counted as one, it lets a file
  # gutted to rules and dashes pass cell 1's check that each file has prose.
  # The frontmatter line is a unit and counts as read, never as the file's own.
  if ! grep -qx 'SCANNED wordless.md 1 0' "$scan"; then
    echo "wordless.md holds no word, and the scan counted sentences in it: $(grep 'SCANNED wordless.md' "$scan")"
    bad=1
  fi
  # And a `***` directly above the block must not run into the block's heading
  # and count as the file's own prose: the sentinel ends a paragraph.
  if ! grep -qE '^SCANNED gutted.md [0-9]+ 0$' "$scan"; then
    echo "gutted.md holds no prose of its own, and the scan counted some: $(grep 'SCANNED gutted.md' "$scan")"
    bad=1
  fi
  grep -qx 'ANCHOR 1 whole.md :: '"$clause" "$scan" || { echo "whole.md holds the pinned clause once, and the scan said: $(grep 'ANCHOR . whole.md' "$scan")"; bad=1; }
  # OVER prints the sentence with its spans put back, as the pin compares it.
  grep -q '^OVER span-swap.md:.*`wc -l`' "$scan" || { echo "span-swap.md's OVER line does not show its span: $(grep '^OVER span-swap.md:' "$scan")"; bad=1; }
  if grep '^MALFORMED ' "$scan"; then bad=1; fi
  [ "$bad" -eq 0 ]
}
