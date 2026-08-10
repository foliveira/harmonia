#!/usr/bin/env bash
# Shared workspace helpers: the one owner of the workspace base-ref format
# ("ref: <sha>", written by workspace.sh mint), of the diff-digest formula
# that receipts and the acceptance marker share (KTD7), and of the
# containment predicate every workspace write and the receipt audit ask
# before they touch a path (FU-16). Sourced by bin/workspace.sh,
# bin/check-criteria.sh, and bin/coverage/gate.sh; never executed directly.
set -u

# The workspace base-ref file stores "ref: <sha>"; this parser owns that
# format so no caller hand-parses it. Input may or may not carry the prefix.
parse_base_ref() { local v="$1"; printf '%s' "${v#ref: }"; }

# True when <ref> resolves to a commit in <repo>. ^{commit} forces object
# existence - bare rev-parse --verify accepts any well-formed 40-hex sha
# unseen (recorded in the 2026-07-03-gate-baseref-guard boundary).
base_resolves() { git -C "$1" rev-parse --verify --quiet "$2^{commit}" >/dev/null; }

# The one diff-digest formula: gate receipts, check-criteria receipts,
# receipt verification, and the acceptance marker all hash these bytes.
diff_digest() { git -C "$1" diff "$2" 2>/dev/null | sha256sum | awk '{print $1}'; }

# True when <ws> is a real task workspace and <rel> (optional) is a path that
# will be written inside it - the one containment test every workspace mutation
# and the receipt audit ask first (FU-16). A symlink at .harmonia, at tasks, at
# <id>, at a directory under the workspace or at the artifact file itself
# redirects the write, and the redirect is invisible to the caller's own exit
# status, so the question is asked before the write rather than checked after.
#
# The anchor is derived from <ws> and NOT from --repo: `cd` strips the three
# trailing components logically before it resolves anything, so `root` is the
# physical location of the tree the caller named, and requiring the physically
# resolved workspace to sit under it refuses a redirect out of that tree without
# asking what --repo says. That matters because bin/check-criteria.sh may not be
# coupled to --repo at all (tests/hooks.bats:565-573 and :625-632 assert an
# unrelated plain --repo is accepted), and one predicate for one property beats
# two. Both sides resolve with `pwd -P`: a logical comparison breaks any checkout
# reached through a symlinked ancestor (the /var -> /private/var shape).
#
# Prefix, not equality: a redirect whose target stays inside the tree the caller
# named is contained - deciding whether that tree is itself hostile is
# provenance's job, not this one - and an equality anchor refuses it.
ws_contained() {   # <ws> [<rel-under-ws>] -> 0 inside, 1 refuse
  local ws="$1" rel="${2:-}" ws_real root wsid dir
  local CDPATH=''   # `cd` ECHOES its destination when CDPATH matches, and every path below is captured from a cd subshell
  ws_real="$(cd "$ws" 2>/dev/null && pwd -P)" || return 1
  # No separate shape test here. `pwd -P` is always absolute, so when a path is
  # NOT under .harmonia/tasks/ the strip below is a no-op and `wsid` keeps its
  # leading slash - which the single-component test on the next line refuses on
  # its own. A shape test would be a strict subset of it and could not be reached
  # by any constructible path. The single-component test is load-bearing and is
  # pinned by coverage.bats's `nested-task-path` cell.
  wsid="${ws_real##*/.harmonia/tasks/}"
  case "$wsid" in */*|"") return 1 ;; esac
  root="$(cd "$ws/../../.." 2>/dev/null && pwd -P)" || return 1
  [ "$root" = / ] && root=""   # else the pattern below is //* and refuses /.harmonia/tasks/<id>
  case "$ws_real" in "$root"/*) ;; *) return 1 ;; esac   # quoted, so a repo path holding glob metacharacters stays literal
  [ -n "$rel" ] || return 0
  dir="$(dirname "$rel")"
  [ "$dir" = "." ] || [ "$(cd "$ws/$dir" 2>/dev/null && pwd -P)" = "$ws_real/$dir" ] || return 1
  [ -L "$ws/$rel" ] && return 1
  return 0
}
