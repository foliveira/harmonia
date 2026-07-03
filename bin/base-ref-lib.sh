#!/usr/bin/env bash
# Shared base-ref helpers: the one owner of the workspace base-ref format
# ("ref: <sha>", written by workspace.sh mint) and of the diff-digest
# formula that receipts and the acceptance marker share (KTD7). Sourced by
# bin/workspace.sh, bin/check-criteria.sh, and bin/coverage/gate.sh;
# never executed directly.
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
