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
#
# A dash-leading value is refused before git is asked anything. The base-ref
# file's CONTENT is repository-suppliable, and every git command here takes it
# in argument position, where a value that starts with `-` is an OPTION rather
# than a ref. Git refnames cannot begin with `-`, so nothing legitimate is lost.
base_resolves() {
  case "$2" in -*) return 1 ;; esac
  git -C "$1" rev-parse --verify --quiet "$2^{commit}" >/dev/null
}

# The one diff-digest formula: gate receipts, check-criteria receipts,
# receipt verification, and the acceptance marker all hash these bytes.
#
# The base is verified HERE rather than only at the call sites, because this is
# the sink: `git diff --output=<path>` writes that path, and a repository that
# commits `ref: --output=/somewhere` in its workspace's base-ref reaches this
# function through shape mode - which executes nothing, is deliberately not
# provenance-guarded, and runs at every implement round. Measured from a clone:
# a file outside the repository truncated at exit 0 under `check-criteria: OK`,
# with no symlink and no local write access. Four of the five call sites already
# gated and lose nothing; bin/check-criteria.sh was the one that did not.
#
# An unresolvable base yields the empty-diff digest instead of an error because
# that is byte-identical to what this has always returned for the shipped shape
# it describes: `mint` writes `ref: none` in a non-git tree, and `git diff none`
# already failed to empty output. The guard changes where the emptiness comes
# from, not what any legitimate caller records.
diff_digest() {
  base_resolves "$1" "$2" || { printf '' | sha256sum | awk '{print $1}'; return 0; }
  git -C "$1" diff "$2" 2>/dev/null | sha256sum | awk '{print $1}'
}

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

# True when <rel> inside <ws> arrived WITH the repository rather than from the
# user. Containment (above) says where bytes land; this says who put them there,
# and neither implies the other: a tracked artifact sitting exactly where it
# belongs passes every containment test there is. Task workspaces are gitignored,
# so a legitimate artifact is never tracked - the same discriminator the scope
# declaration's own guard uses.
#
# Fail CLOSED, and that is the whole design. Every way git can be made to answer
# "not tracked" is a way to make a hostile file look like yours, and four of them
# need no access to the repository at all. Each was measured executing a tracked
# payload against the build that read any git failure as "no repository":
# GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE and GIT_CEILING_DIRECTORIES from the
# environment; a .git the caller cannot read, a dangling gitfile, and
# core.repositoryformatversion=99 from the repository itself. The environment
# four are not one class with the other three, which is why unsetting them is not
# redundant with the fail-closed branch: GIT_WORK_TREE and GIT_INDEX_FILE leave
# `rev-parse --is-inside-work-tree` answering `true` at exit 0 and defeat
# `git ls-files` instead. Only those four were measured executing a payload; the
# remaining GIT_* names are unset defensively rather than on evidence, and are
# named here as such rather than implied to be load-bearing.
#
# The one true negative is a tree with no .git at or above it, and it is walked
# for in shell rather than asked of git - asking git is exactly what a tampered
# repository gets to answer. A hand-made workspace in a non-git tree is a shipped
# shape and keeps working.
# Exit codes are three, not two, because "it arrived with the repository" and
# "git will not tell me" need different words to the user: the first has a
# remedy (untrack it), the second does not, and round 2 shipped one message for
# both - telling a developer their own minted marker arrived with the repo, and
# sending them to a command that rewrites content when the property is index
# membership.
#   0 = tracked: it arrived with the repository
#   1 = provably the user's
#   2 = undecidable: a repository is here and git cannot be trusted to answer
# One repository's answer, about a path relative to ITS root.
#   0 = it has <path>   1 = it does not   2 = it cannot answer
#
# Two questions, both O(path depth), and nothing else. The property is pinned in
# scope.md's round-9 section: the index, or the tree of the commit checked out.
# History that is not checked out is not consulted - an earlier build walked all
# refs and paid for it with false refusals (a live stash, a fetched colleague's
# branch, a deleted-then-recreated task id) and with an O(reachable commits) audit
# measured at 13.2s on a million-commit repository.
_repo_claims() {   # <repo-dir> <path-relative-to-that-dir>
  local dir="$1" path="$2" top rc
  # Is a repository OPEN here at all? An empty `.git` directory and a dangling or
  # looping `.git` symlink all answer no, and the caller walks past them - that is
  # what stops an unusable .git in some unrelated ancestor refusing every
  # legitimate run, without the position rule whose bypass was round 8's B2.
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || return 1

  # A repository IS open. From here every failure is a refusal, at any level.
  # core.bare and a redirected core.worktree land here rather than in the skip
  # above: git opens a repository and then answers about a different tree.
  [ "$(git -C "$dir" rev-parse --is-inside-work-tree 2>/dev/null)" = true ] || return 2
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 2
  [ -n "$top" ] || return 2
  top="$(cd "$top" 2>/dev/null && pwd -P)" || return 2
  [ "$top" = "$dir" ] || return 2

  git -C "$dir" ls-files --error-unmatch -- "$path" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && return 0
  # 1 is "not in the index"; anything else is a failure wearing the same shape.
  [ "$rc" -eq 1 ] || return 2

  # The checked-out tree, by direct lookup rather than any revision walk. HEAD
  # failing to resolve is not an error and needs no discriminator: nothing is
  # checked out, so nothing is carried by it. That is what makes a repository
  # between `git add` and its first commit, and an orphan checkout, both work.
  git -C "$dir" rev-parse --verify --quiet "HEAD:$path" >/dev/null 2>&1 && return 0
  return 1
}

ws_tracked() {   # <ws> <rel>
  # The environment is not an input these guards may trust. CDPATH belongs to the
  # same class as the GIT_* names and must be cleared BEFORE the first cd, not
  # after it: `cd` echoes its destination when CDPATH matches, and that echo
  # lands in the command substitution below.
  ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CEILING_DIRECTORIES \
          GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_ALTERNATE_OBJECT_DIRECTORIES CDPATH
    # The path below is BUILT from directory names, and git reads it in pathspec
    # position, where a leading `:` is magic. One directory named `:x` anywhere
    # between the workspace and a repository root made git answer about something
    # else - ls-files rc=1, ls-tree rc=0 and empty, the exact pair that reads as
    # "not carried" - and turned every provenance guard here off on a plain clone.
    export GIT_LITERAL_PATHSPECS=1
    cd "$1" 2>/dev/null || exit 2
    d="$(pwd -P)"; suffix="$2"
    # Ask EVERY repository at or above the workspace, not the first one found.
    # Stopping at the first was the whole of round 4's B1: one `git init` dropped
    # into a delivered tree answers "not tracked" perfectly truthfully, because
    # the payload is tracked in the repository ABOVE it, and the outer one was
    # never asked. Requiring the resolved toplevel to match does not catch it -
    # the nested repository's toplevel legitimately is where the walk stopped.
    while :; do
      if [ -e "$d/.git" ] || [ -L "$d/.git" ]; then
        _repo_claims "$d" "$suffix"; c=$?
        [ "$c" -eq 0 ] && exit 0     # a repository here has it
        # No position rule. An earlier build made "cannot answer" fatal for the
        # nearest repository only, so an attacker added an honest empty
        # repository BELOW the one they had broken: the honest one answered
        # truthfully, cleared the flag, and the unanswerable carrier above was
        # skipped. Undecidable refuses wherever it sits; what keeps that from
        # refusing legitimate work is _repo_claims walking past levels where git
        # opens no repository at all.
        [ "$c" -eq 2 ] && exit 2
      fi
      [ -z "$d" ] && break           # "" is the root: "$d/.git" was /.git on this pass
      suffix="${d##*/}/$suffix"      # the path as the NEXT level up spells it
      d="${d%/*}"
    done
    exit 1 )
}

# The provenance verdict in words, once, for every consumer. Returns 0 when <rel>
# is provably the user's; otherwise prints the reason and returns 1, so a caller
# is one line: `r="$(ws_provenance_reason "$WS" x)" || { echo "me: $r"; exit N; }`.
#
# One text rather than one per script, because the REMEDY has been wrong twice.
# It named `workspace.sh accept`, which rewrites content when the property is
# where the file came from; then `git rm --cached`, which stopped working the
# moment committed history joined the index in the question. Five call sites
# meant five places to leave stale, and a test that pinned one of them.
ws_provenance_reason() {   # <ws> <rel>
  ws_tracked "$1" "$2"
  case $? in
    0) printf '%s is carried by a git repository at or above this workspace, so it arrived with the repository rather than from you - mint a fresh workspace (task workspaces are gitignored) and redo this step yourself; removing the file from the index does not clear this, because committed history is checked too' "$2"
       return 1 ;;
    2) printf 'a git repository is present but cannot be asked whether %s arrived with it - this is NOT a claim that it is carried; repair that repository and re-run' "$2"
       return 1 ;;
  esac
  return 0
}
