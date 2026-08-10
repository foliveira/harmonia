#!/usr/bin/env bash
# Coverage gate (KTD6): diff-cover as the adopted line-intersection core, a
# native branch post-pass on branch-bearing Cobertura, in-code exemption
# markers, workspace report + receipt, and an append-only override audit log.
#
#   gate.sh [--repo R] [--base REF] [--workspace WS] [--report FILE]
#           [--lang ts|go|bash] [--no-branch] [--self]
#   gate.sh --record-override "path|lines|justification" [--workspace WS] [--repo R]
#   gate.sh --verify-receipts --workspace WS [--repo R] [--base REF]
#
# Exit: 0 pass | 1 uncovered changed lines (soft block), or --verify-receipts
# pointed at a receipt store outside the workspace | 2 marker without
# justification | 3 a workspace write did not land (I/O failure, not a coverage
# result) - including one refused because it would have landed outside the
# workspace | 4 cannot measure (unsupported language or missing tool, or a
# base-ref that does not resolve inside the workspace).
set -u

REPO="." BASE="HEAD" BASE_GIVEN=0 WS="" REPORT="" LANG_FORCE="" NO_BRANCH=0 SELF=0
OVERRIDE="" VERIFY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --base) BASE="$2"; BASE_GIVEN=1; shift 2 ;;
    --workspace) WS="$2"; shift 2 ;;
    --report) REPORT="$2"; shift 2 ;;
    --lang) LANG_FORCE="$2"; shift 2 ;;
    --no-branch) NO_BRANCH=1; shift ;;
    --self) SELF=1; shift ;;
    --record-override) OVERRIDE="$2"; shift 2 ;;
    --verify-receipts) VERIFY=1; shift ;;
    *) echo "gate: unknown argument '$1'" >&2; exit 1 ;;
  esac
done
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../base-ref-lib.sh"
. "$HERE/config-lib.sh"
[ "$SELF" -eq 1 ] && { REPO="$(cd "$HERE/../.." && pwd)"; LANG_FORCE="bash"; }
REPO="$(cd "$REPO" && pwd)"
TASK_ID="unknown"; [ -n "$WS" ] && TASK_ID="$(basename "$WS")"

# Every write this gate makes into a workspace goes through here first (FU-16).
# The report is the sharpest of them: symlink $WS/gate-report.md at a file the
# user owns and the unguarded gate overwrites it, prints `gate: OK` and exits 0.
# Exit 3 is this script's "a workspace write did not land" - a refusal is that
# case, decided before the write instead of after it.
ws_guard() {   # <rel-under-the-workspace>
  ws_contained "$WS" "$1" && return 0
  echo "gate: FAIL - $1 is not a real path inside the task workspace $WS (refusing to write through it)"
  exit 3
}

# Absent --base, a workspace's base-ref file supplies the base; parsing,
# base resolution, and the digest formula are shared (bin/base-ref-lib.sh).
# Absent --base the workspace supplies the base, which makes base-ref an audit
# input with the same standing as the receipts checked against it: redirected, it
# names a base the caller never chose, and the audit's answer flips on it - a
# receipt holding the empty-diff digest goes from `stale` to `receipts verified`
# when base-ref is symlinked at a file naming a ref the diff really is empty
# against. Cannot measure rather than a coverage verdict, and in both modes:
# what is untrustworthy is the base every diff here is taken against.
# base-ref is judged whenever a workspace names one, NOT only when this
# invocation is about to read it. Putting the guard behind `--base` being absent
# was measured wide open: all three shipped skills pass
# `--base <workspace base-ref>`, so the agent reads the repository's committed
# value and hands it straight back in, and the guard never ran. The shape that
# refused - no `--base` at all - is one no skill produces. A workspace whose
# base-ref a repository carries is not a workspace anyone here minted, and that
# is true regardless of which argument this call happens to use.
if [ -n "$WS" ] && [ -f "$WS/base-ref" ]; then
  ws_contained "$WS" base-ref || { echo "gate: cannot measure - base-ref is not a real path inside the task workspace $WS (refusing to take a base from outside it)"; exit 4; }
  [ "$BASE_GIVEN" -eq 0 ] && BASE="$(cat "$WS/base-ref")"
fi
BASE="$(parse_base_ref "$BASE")"

# ---------- override audit log ----------
if [ -n "$OVERRIDE" ]; then
  IFS='|' read -r opath olines ojust <<< "$OVERRIDE"
  if [ -z "${ojust:-}" ]; then echo "gate: override needs 'path|lines|justification'" >&2; exit 1; fi
  L="$REPO/.harmonia/coverage-exemptions.yaml"
  mkdir -p "$(dirname "$L")"
  {
    echo "- date: $(date +%Y-%m-%d)"
    echo "  task: $TASK_ID"
    echo "  path: $opath"
    echo "  lines: $olines"
    echo "  justification: $ojust"
  } >> "$L"  # harmonia:exempt kcov cannot attribute brace-group redirect closers; the append is asserted by tests
  echo "gate: override recorded in .harmonia/coverage-exemptions.yaml"
  exit 0
fi

# ---------- base must resolve before any diff ----------
# Never gate a ref git cannot resolve: an unresolvable base makes every diff
# empty and the gate would pass vacuously.
if ! base_resolves "$REPO" "$BASE"; then
  echo "gate: cannot measure - base ref '$BASE' does not resolve"
  exit 4
fi

# ---------- receipt verification (review's tier-B audit, KTD7) ----------
if [ "$VERIFY" -eq 1 ]; then
  [ -n "$WS" ] || { echo "gate: --verify-receipts needs --workspace" >&2; exit 1; }
  [ -d "$WS/receipts" ] || { echo "gate: receipts missing at $WS/receipts"; exit 1; }
  # The audit half of containment, and the one a build closes last: nothing is
  # written here, so no escape detector sees it - what is wrong is the VERDICT.
  # Unguarded, this branch answers `gate: receipts verified` at exit 0 over a
  # store the gate never wrote into. Exit 1, because every other verdict in this
  # branch is 1 and nothing here writes.
  ws_contained "$WS" receipts || { echo "gate: FAIL - the receipts path does not resolve inside the task workspace $WS (refusing to certify receipts from outside it)"; exit 1; }
  cur="$(diff_digest "$REPO" "$BASE")"
  # cov_seen answers the question the audit is actually asked: did the COVERAGE
  # gate leave a fresh receipt for this tree. Counting code-dependent receipts
  # answered a different one, and criteria-run - code-dependent and fresh by
  # construction - satisfied that count alone while nothing had measured the tree.
  bad=0 cov_seen=0
  for r in "$WS"/receipts/*.json; do
    [ -f "$r" ] || { echo "gate: receipts missing at $WS/receipts"; exit 1; }
    # The directory check above stops one level of granularity short of the read.
    # This loop GLOBS, so it reaches names no writer knows to guard - the write
    # side guards three fixed ones - and a symlink at an individual receipt is
    # followed inside a receipts/ that is itself perfectly contained. Measured on
    # the build that shipped only the directory check: a forged receipt outside
    # the repository carrying the live digest answered `gate: receipts verified`
    # at exit 0, while the write side refused the identical shape.
    ws_contained "$WS" "receipts/${r##*/}" || { echo "gate: FAIL - receipts/${r##*/} does not resolve inside the task workspace $WS (refusing to certify a receipt from outside it)"; exit 1; }
    g="$(jq -r '.gate // empty' "$r")"
    # check-criteria validates scope.md (code-independent) but its receipt hashes
    # the diff at implement-start on a clean tree, so its digest goes code-stale
    # the moment implement writes code. Validate it by status, not freshness.
    if [ "$g" = "check-criteria" ]; then  # The waiver keys on this gate NAME, not on the script: the same script's review-time `--run` receipt (gate "criteria-run") is code-dependent and takes the freshness path below.
      if [ "$(jq -r '.status // empty' "$r")" != "pass" ]; then echo "gate: receipt $(basename "$r") did not pass (status not pass)"; bad=1; fi
      continue
    fi
    [ "$g" = "coverage" ] && cov_seen=1  # deliberately no `continue`: coverage still owes the freshness check below
    # criteria-run's exit code is the gate and its receipt witnesses freshness, so
    # `fail` there means the criteria ran and lost. coverage's status stays unread
    # by design: reading it would harden the soft block into a verify failure and
    # route the advisory cannot-measure case (which receipts `fail`) there too.
    if [ "$g" = "criteria-run" ] && [ "$(jq -r '.status // empty' "$r")" = "fail" ]; then
      echo "gate: receipt $(basename "$r") reports the criteria run failed"; bad=1
    fi
    stored="$(jq -r '.diff_digest // empty' "$r")"
    if [ -z "$stored" ]; then echo "gate: receipt $(basename "$r") carries no digest - stale"; bad=1
    elif [ "$stored" != "$cur" ]; then echo "gate: receipt $(basename "$r") is stale (diff digest mismatch)"; bad=1
    fi
  done
  [ "$bad" -eq 1 ] && exit 1
  [ "$cov_seen" -eq 0 ] && { echo "gate: no code-dependent receipt to verify - refusing (no coverage receipt)"; exit 1; }
  echo "gate: receipts verified"
  exit 0
fi

# ---------- classify changed files ----------
tracked_changed="$(git -C "$REPO" diff --name-only "$BASE" 2>/dev/null)"
untracked="$(git -C "$REPO" ls-files --others --exclude-standard 2>/dev/null)"
changed="$(printf '%s\n%s\n' "$tracked_changed" "$untracked" | sed '/^$/d' | sort -u)"

lang_of() {
  case "${1##*.}" in
    ts|tsx|js|jsx) echo ts ;;
    go)            echo go ;;
    sh)            echo bash ;;
    bats)          echo skip ;;  # test code is exercised by definition; the gate measures product code
    yaml|yml)      echo yaml ;;
    md|json|txt|lock|xml) echo skip ;;
    *)             echo unsupported ;;
  esac
}

# A project-supplied coverage command (.harmonia/project.yaml) widens the gate:
# read it ONCE here so both the classifier (below) and the report seam consult
# the same value. Empty when absent - then classification and the report source
# are byte-identical to the no-command path.
COV_CMD="$(project_config "$REPO" coverage "")"

CODE_FILES="" YAML_FILES="" UNSUPPORTED=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in .harmonia/*) continue ;; esac
  l="$(lang_of "$f")"
  case "$f" in tests/*) l=skip ;; esac  # test suites and fixtures are not product code
  [ -n "$LANG_FORCE" ] && [ "$l" != yaml ] && [ "$l" != skip ] && l="$LANG_FORCE"
  case "$l" in
    yaml) YAML_FILES="$YAML_FILES$f"$'\n' ;;
    skip) : ;;
    # unsupported extension: a project coverage command measures any extension
    # (widen into CODE_FILES); with no command this stays advisory (byte-identical to today).
    unsupported) if [ -n "$COV_CMD" ]; then CODE_FILES="$CODE_FILES$f"$'\n'; else UNSUPPORTED="$UNSUPPORTED$f"$'\n'; fi ;;
    *) CODE_FILES="$CODE_FILES$f"$'\n' ;;
  esac
done <<< "$changed"

REPORT_LINES="" HONORED="" MARKER_FAIL="" BRANCH_VIOL="" ADVISORY="" YAML_NOTE=""
STATUS=0

# ---------- yaml route: validation instead of coverage (R15) ----------
if [ -n "$YAML_FILES" ]; then
  yfail=0
  while IFS= read -r y; do
    [ -z "$y" ] && continue
    if command -v yamllint >/dev/null 2>&1; then
      yamllint -d '{extends: relaxed, rules: {line-length: disable}}' "$REPO/$y" >/dev/null 2>&1 || yfail=1
    fi
  done <<< "$YAML_FILES"
  YAML_NOTE="yaml files routed to validation (no coverage requirement)"
  [ "$yfail" -eq 1 ] && { YAML_NOTE="yaml validation FAILED"; STATUS=1; }
fi

# ---------- unsupported languages: advisory cannot-measure ----------
if [ -n "$UNSUPPORTED" ]; then
  ADVISORY="$(echo "$UNSUPPORTED" | sed '/^$/d')"
fi

# ---------- measurable code: diff-cover core + native passes ----------
BRANCH_NOTE=""
if [ -n "$CODE_FILES" ]; then
  if [ -z "$REPORT" ]; then
    if [ -n "$COV_CMD" ]; then
      # Project-supplied coverage command: run it FRESH from $REPO each
      # invocation (never a pre-produced report). The command must print ONLY the
      # report path to stdout; this seam captures $(...) stdout, and the gate does
      # NOT redirect the command's stderr (unlike the adapters, which >/dev/null 2>&1
      # their own subprocess), so silencing tool chatter is the command's job per the
      # SKILL, not the gate's. eval honors the shell grammar (pipes/redirs/&&) the
      # wrapper needs, and runs the value AFTER config-lib strips one quote layer, so
      # a quoted coverage: value is not a literal - it executes identically to bare
      # and must be scrutinized as executable. Trusted repo config run from $REPO -
      # the same footing as the adapters running the repo's own suite.
      REPORT="$( cd "$REPO" && eval "$COV_CMD" )" \
        || { echo "gate: cannot measure - project coverage command failed"; exit 4; }
      case "$REPORT" in /*) : ;; *) REPORT="$REPO/$REPORT" ;; esac  # resolve repo-relative echo
      [ -f "$REPORT" ] \
        || { echo "gate: cannot measure - project coverage command produced no readable report"; exit 4; }
    else
      # Byte-identical to today: adapter fallback for the detected language.
      # Reached only when COV_CMD is empty. A --lang/--self-forced extension can
      # reach this branch (byte-identical to base, which forced it too); only a
      # COV_CMD-widened file cannot - widening needs COV_CMD non-empty, which routes
      # to the command branch above.
      lang="$LANG_FORCE"
      [ -z "$lang" ] && lang="$(echo "$CODE_FILES" | head -1 | xargs -I{} bash -c 'f="{}"; case "${f##*.}" in ts|tsx|js|jsx) echo ts;; go) echo go;; sh|bats) echo bash;; esac')"
      REPORT="$(bash "$HERE/$lang.sh" --repo "$REPO")" || { echo "gate: cannot measure - adapter for '$lang' reported a missing tool" ; exit 4; }
    fi
  fi
  command -v diff-cover >/dev/null 2>&1 || { echo "gate: cannot measure - diff-cover is not installed"; exit 4; }

  DC_JSON="$(mktemp)"
  # Derive --src-roots from the report's <source> elements so reports rooted
  # below the repo (kcov roots at bin/) still match git-relative diff paths.
  SRCROOTS="."
  while IFS= read -r s; do
    case "$s" in
      "$REPO"/*) rel="${s#"$REPO"/}"; rel="${rel%/}"; [ -n "$rel" ] && SRCROOTS="$SRCROOTS $rel" ;;
    esac
  done < <(grep -o '<source>[^<]*</source>' "$REPORT" 2>/dev/null | sed -e 's/<source>//' -e 's|</source>||')  # harmonia:exempt kcov cannot attribute process-substitution feeder lines; derivation is asserted by the sub-root matching test
  # shellcheck disable=SC2086
  ( cd "$REPO" && diff-cover "$REPORT" --compare-branch="$BASE" --include-untracked --src-roots $SRCROOTS --format "json:$DC_JSON" --quiet >/dev/null 2>&1 )

  # Files diff-cover measured, with their violation lines.
  MEASURED_FILES="$(jq -r '.src_stats | keys[]' "$DC_JSON" 2>/dev/null)"
  VIOLATIONS="$(jq -r '.src_stats | to_entries[] | .key as $f | .value.violation_lines[] | "\($f):\(.)"' "$DC_JSON" 2>/dev/null)"

  # Absent-means-uncovered: changed code files missing from the coverage data.
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if ! echo "$MEASURED_FILES" | grep -qxF "$f"; then
      VIOLATIONS="$VIOLATIONS"$'\n'"$f:ALL (absent from coverage data - counts as uncovered)"
    fi
  done <<< "$CODE_FILES"

  # Branch post-pass: only for branch-bearing reports, unless suppressed.
  if [ "$NO_BRANCH" -eq 0 ] && grep -q 'branch="true"' "$REPORT" 2>/dev/null; then
    # changed line numbers per file from the diff (unified=0 hunks) + untracked whole files
    changed_lines() { # file -> newline list of changed line numbers
      local f="$1"
      if echo "$untracked" | grep -qxF "$f"; then
        awk 'END{for(i=1;i<=NR;i++) print i}' "$REPO/$f" 2>/dev/null
      else
        git -C "$REPO" diff -U0 "$BASE" -- "$f" 2>/dev/null \
          | sed -nE 's/^@@ [^+]*\+([0-9]+)(,([0-9]+))?.*/\1 \3/p' \
          | while read -r s c; do c="${c:-1}"; i=0; while [ "$i" -lt "$c" ]; do echo $((s+i)); i=$((i+1)); done; done
      fi
    }
    BR_UNCOV="$(awk '
      /filename="/ { if (match($0, /filename="[^"]*"/)) { fn=substr($0, RSTART+10, RLENGTH-11) } }
      /<line / && /branch="true"/ {
        n=""; cc=""
        if (match($0, /number="[0-9]+"/)) n=substr($0, RSTART+8, RLENGTH-9)
        if (match($0, /condition-coverage="[0-9]+%/)) cc=substr($0, RSTART+20, RLENGTH-21)
        if (n != "" && cc != "" && cc+0 < 100) print fn":"n
      }' "$REPORT")"
    while IFS= read -r bl; do
      [ -z "$bl" ] && continue
      bf="${bl%%:*}"; bn="${bl##*:}"
      if changed_lines "$bf" | grep -qxF "$bn"; then
        BRANCH_VIOL="$BRANCH_VIOL$bl"$'\n'
      fi
    done <<< "$BR_UNCOV"
  elif [ "$NO_BRANCH" -eq 0 ]; then
    BRANCH_NOTE="branches unmeasured (coverage format carries no branch records)"
  fi

  # Exemption markers: content-anchored, justification required (KTD6).
  FINAL_VIOL=""
  while IFS= read -r v; do
    [ -z "$v" ] && continue
    vf="${v%%:*}"; vrest="${v#*:}"; vn="${vrest%% *}"
    line_text=""
    [[ "$vn" =~ ^[0-9]+$ ]] && line_text="$(sed -n "${vn}p" "$REPO/$vf" 2>/dev/null)"
    if [[ "$line_text" == *"harmonia:exempt"* ]]; then
      just="$(echo "$line_text" | sed -e 's/.*harmonia:exempt//' -e 's|\*/.*||' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      if [ -z "$just" ]; then
        MARKER_FAIL="$MARKER_FAIL$vf:$vn"$'\n'
      else
        HONORED="$HONORED$vf:$vn - $just"$'\n'
      fi
    else
      FINAL_VIOL="$FINAL_VIOL$v"$'\n'
    fi
  done <<< "$VIOLATIONS"
  rm -f "$DC_JSON"

  [ -n "$(echo "$FINAL_VIOL" | sed '/^$/d')" ] && STATUS=1
  [ -n "$(echo "$BRANCH_VIOL" | sed '/^$/d')" ] && STATUS=1
  [ -n "$(echo "$MARKER_FAIL" | sed '/^$/d')" ] && STATUS=2
  REPORT_LINES="$FINAL_VIOL"
fi

[ -n "$ADVISORY" ] && [ "$STATUS" -eq 0 ] && STATUS=4

# ---------- workspace report + receipt (KTD10, KTD7) ----------
if [ -n "$WS" ]; then
  ws_guard receipts          # the mkdir below creates a directory outside through a redirected receipts/
  mkdir -p "$WS/receipts"
  ws_guard gate-report.md
  {
    echo "# Coverage gate report"
    echo
    echo "- task: $TASK_ID"
    echo "- base: $BASE"
    echo "- status: $STATUS (0 pass, 1 uncovered, 2 marker validation, 4 cannot measure)"
    echo
    echo "## Uncovered changed lines"
    if [ -n "$(echo "$REPORT_LINES" | sed '/^$/d')" ]; then echo "$REPORT_LINES" | sed '/^$/d; s/^/- /'; else echo "- none"; fi
    echo
    echo "## Branch coverage"
    if [ -n "$(echo "$BRANCH_VIOL" | sed '/^$/d')" ]; then echo "$BRANCH_VIOL" | sed '/^$/d; s/^/- uncovered branch: /'
    elif [ -n "$BRANCH_NOTE" ]; then echo "- $BRANCH_NOTE"
    else echo "- none"; fi
    echo
    echo "## Exemptions honored"
    if [ -n "$(echo "$HONORED" | sed '/^$/d')" ]; then echo "$HONORED" | sed '/^$/d; s/^/- /'; else echo "- none"; fi
    if [ -n "$(echo "$MARKER_FAIL" | sed '/^$/d')" ]; then
      echo
      echo "## Markers missing a justification (validation FAILED)"
      echo "$MARKER_FAIL" | sed '/^$/d; s/^/- /'
    fi
    if [ -n "$ADVISORY" ]; then
      echo
      echo "## Advisory - cannot measure (no adapter for these files)"
      echo "$ADVISORY" | sed '/^$/d; s/^/- /'
      echo
      echo "No override entry is required for unmeasurable files; the log stays reserved for measurable-but-uncovered lines."
    fi
    [ -n "$YAML_NOTE" ] && { echo; echo "## YAML"; echo "- $YAML_NOTE"; }
  } > "$WS/gate-report.md"
  # The report is judged by its RESULT on disk, because the status of the command
  # that wrote it is unusable: a brace group returns its LAST command's status (the
  # yaml-note test, false on any diff carrying no yaml) and `{ ...; } > /dev/full`
  # exits 0 while every write inside it failed. -f rejects a non-file planted at the
  # path, -s a create that landed no bytes. What no file test can see is an open that
  # failed over an EXISTING report, leaving the previous round's bytes there.
  if [ ! -f "$WS/gate-report.md" ] || [ ! -s "$WS/gate-report.md" ]; then
    echo "gate: FAIL - report did not land at $WS/gate-report.md (I/O failure, not a coverage result)"
    exit 3
  fi
  TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  st="pass"; [ "$STATUS" -ne 0 ] && st="fail"
  ws_guard receipts/coverage.json   # refuse before the receipt, never after
  cat > "$WS/receipts/coverage.json" <<EOF
{
  "gate": "coverage",
  "task_id": "$TASK_ID",
  "timestamp": "$TS",
  "diff_digest": "$(diff_digest "$REPO" "$BASE")",
  "status": "$st"
}
EOF
  wrote=$?  # cat's own status, usable where the report group's is not: it is what catches an open that failed over an existing receipt
  # The receipt is the audit's certificate that the coverage gate ran against this
  # tree, so it goes down only after the report it points at is on disk, and both
  # halves of "did it land" are asked: the writer's status catches a write that never
  # happened, the file tests catch one that "succeeded" into a device or a non-file.
  # The mkdir above needs no check of its own - a receipts path that is not a usable
  # directory reappears here as a receipt that did not land.
  if [ "$wrote" -ne 0 ] || [ ! -f "$WS/receipts/coverage.json" ] || [ ! -s "$WS/receipts/coverage.json" ]; then
    echo "gate: FAIL - receipt did not land at $WS/receipts/coverage.json (I/O failure, not a coverage result)"
    exit 3
  fi
fi

# ---------- stdout summary ----------
case "$STATUS" in
  0) echo "gate: OK${YAML_NOTE:+ - $YAML_NOTE}${HONORED:+ (exemptions honored - see report)}" ;;
  1) echo "gate: FAIL - uncovered changed lines:"; { echo "$REPORT_LINES"; echo "$BRANCH_VIOL" | sed '/^$/d; s/$/ (branch)/'; } | sed '/^$/d; s/^/  /' ;;
  2) echo "gate: FAIL - exemption marker without a justification:"; echo "$MARKER_FAIL" | sed '/^$/d; s/^/  /' ;;
  4) echo "gate: cannot measure - unsupported language for:"; echo "$ADVISORY" | sed '/^$/d; s/^/  /'; echo "  (advisory at review; no override required)" ;;
esac
exit "$STATUS"
