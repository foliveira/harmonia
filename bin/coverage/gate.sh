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
# Exit: 0 pass | 1 uncovered changed lines (soft block) | 2 marker without
# justification | 4 cannot measure (unsupported language or missing tool).
set -u

REPO="." BASE="HEAD" WS="" REPORT="" LANG_FORCE="" NO_BRANCH=0 SELF=0
OVERRIDE="" VERIFY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
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
[ "$SELF" -eq 1 ] && { REPO="$(cd "$HERE/../.." && pwd)"; LANG_FORCE="bash"; }
REPO="$(cd "$REPO" && pwd)"
TASK_ID="unknown"; [ -n "$WS" ] && TASK_ID="$(basename "$WS")"

diff_digest() { git -C "$REPO" diff "$BASE" 2>/dev/null | sha256sum | awk '{print $1}'; }

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

# ---------- receipt verification (review's tier-B audit, KTD7) ----------
if [ "$VERIFY" -eq 1 ]; then
  [ -n "$WS" ] || { echo "gate: --verify-receipts needs --workspace" >&2; exit 1; }
  [ -d "$WS/receipts" ] || { echo "gate: receipts missing at $WS/receipts"; exit 1; }
  cur="$(diff_digest)"
  bad=0
  for r in "$WS"/receipts/*.json; do
    [ -f "$r" ] || { echo "gate: receipts missing at $WS/receipts"; exit 1; }
    stored="$(jq -r '.diff_digest // empty' "$r")"
    if [ -z "$stored" ]; then echo "gate: receipt $(basename "$r") carries no digest - stale"; bad=1
    elif [ "$stored" != "$cur" ]; then echo "gate: receipt $(basename "$r") is stale (diff digest mismatch)"; bad=1
    fi
  done
  [ "$bad" -eq 1 ] && exit 1
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

CODE_FILES="" YAML_FILES="" UNSUPPORTED=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in .harmonia/*) continue ;; esac
  l="$(lang_of "$f")"
  [ -n "$LANG_FORCE" ] && [ "$l" != yaml ] && [ "$l" != skip ] && l="$LANG_FORCE"
  case "$l" in
    yaml) YAML_FILES="$YAML_FILES$f"$'\n' ;;
    skip) : ;;
    unsupported) UNSUPPORTED="$UNSUPPORTED$f"$'\n' ;;
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
    lang="$LANG_FORCE"
    [ -z "$lang" ] && lang="$(echo "$CODE_FILES" | head -1 | xargs -I{} bash -c 'f="{}"; case "${f##*.}" in ts|tsx|js|jsx) echo ts;; go) echo go;; sh|bats) echo bash;; esac')"
    REPORT="$(bash "$HERE/$lang.sh" --repo "$REPO")" || { echo "gate: cannot measure - adapter for '$lang' reported a missing tool" ; exit 4; }
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
  mkdir -p "$WS/receipts"
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
  TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  st="pass"; [ "$STATUS" -ne 0 ] && st="fail"
  cat > "$WS/receipts/coverage.json" <<EOF
{
  "gate": "coverage",
  "task_id": "$TASK_ID",
  "timestamp": "$TS",
  "diff_digest": "$(diff_digest)",
  "status": "$st"
}
EOF
fi

# ---------- stdout summary ----------
case "$STATUS" in
  0) echo "gate: OK${YAML_NOTE:+ - $YAML_NOTE}${HONORED:+ (exemptions honored - see report)}" ;;
  1) echo "gate: FAIL - uncovered changed lines:"; { echo "$REPORT_LINES"; echo "$BRANCH_VIOL" | sed '/^$/d; s/$/ (branch)/'; } | sed '/^$/d; s/^/  /' ;;
  2) echo "gate: FAIL - exemption marker without a justification:"; echo "$MARKER_FAIL" | sed '/^$/d; s/^/  /' ;;
  4) echo "gate: cannot measure - unsupported language for:"; echo "$ADVISORY" | sed '/^$/d; s/^/  /'; echo "  (advisory at review; no override required)" ;;
esac
exit "$STATUS"
