---
title: check-criteria.sh still passes an unguarded base ref to git diff
date: 2026-07-03
tags: [bash,harmonia,security,gates,testing]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

Review verdict of 2026-07-03-acceptance-hardening (PASS) routed four mechanical
defenses out of the diff (findings route out, not in); the workspace verdict is
gitignored, so this entry is the durable carrier for the scoper who picks them
up. All four were reproduced or verified first-hand by the review lead.

1. F-SEC-1, fast-follow, strongly recommended: bin/check-criteria.sh computes
   its receipt digest with no base guard. A base-ref of `ref: --output=/path`
   reaches `git diff` argv, writes an arbitrary file, and exits 0 with the
   empty-diff digest (reproduced). Pre-existing, not the parser swap's doing -
   the old sed hand-parse passed the same prefixed vector - and every sibling
   consumer (gate.sh, workspace.sh accept and verify-acceptance) already
   guards with base_resolves. The defense is one line before the digest,
   preserving the HEAD default:
       { [ -n "$BASE" ] && base_resolves "$REPO" "$BASE"; } || BASE="HEAD"
   Needs its own re-scope: check-criteria's refusal contract (receipt always
   written; exit 3 only for missing scope) was explicitly out of the
   acceptance-hardening goals.
2. F-CC-2, folds into the same scope: check-criteria.sh fails open if
   bin/base-ref-lib.sh fails to load. It runs set -u without set -e, so
   command-not-found still prints "check-criteria: OK", exits 0, and writes an
   empty-digest receipt; gate.sh and workspace.sh fail closed on the same
   fault. Defense: set -e after set -u (validated in review: the fault becomes
   a clean exit 1 with no receipt). Until it lands, gate.sh --verify-receipts
   flags the empty digest as stale at the next review.
3. F-TE-1: the whitespace strip in both tag loops (bin/memory/capture.sh:40,
   bin/memory/recall.sh:45, t="${t//[[:space:]]/}") is load-bearing - without
   it a space-padded tag list like --tags 'process, go' stops matching - but
   no test asserts its effect. The line is executed, so coverage passes and
   deleting it stays green. Defense: a bats case in tests/memory.bats
   asserting a space-padded language tag still passes the guard.
4. F-ADV-3, lower urgency: the single-parser invariant (exactly one
   parse_base_ref definition under bin/) is enforced only by the task's
   one-shot criterion 10. Defense: a permanent structural bats test mirroring
   tests/roster.bats' count pattern, so a future task cannot reintroduce a
   second parser undetected.

Ladder status: all four are mechanically checkable; per the ladder this entry
is a pointer to the defenses, not the defense. Supersede it when they land.
