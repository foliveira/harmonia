---
title: Coverage gate passes vacuously on an unresolvable --base ref
date: 2026-07-02
tags: [bash,harmonia,coverage,gates]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

Found mid-task in 2026-07-02-adlc-adoptions, outside that task's boundary; the
reproduction lived in the workspace observations file, which is gitignored - this
entry is the durable carrier.

Reproduction:
- command: bash bin/coverage/gate.sh --repo . --base "ref: e4819aa73a42c2f46676c756cf3c4f0307b72cbb" --workspace .harmonia/tasks/2026-07-02-adlc-adoptions
- input: a --base value that is not a resolvable git ref (here the leading "ref: "
  prefix, fed verbatim from the workspace base-ref file)
- observed: exit 0, "gate: OK", receipt written with diff_digest = sha256 of the
  empty string (e3b0c442...). An empty diff passed the gate instead of an error.

Mechanism, verified at the line: bin/coverage/gate.sh:36 diff_digest() runs
`git -C "$REPO" diff "$BASE" 2>/dev/null`; the redirect swallows git's
unresolvable-ref error, sha256sum hashes empty input, and the gate proceeds on an
empty changed-line set. The stale-receipt check at review catches the digest
mismatch downstream, but the gate itself should refuse.

Caller-side trigger, worth fixing in the same task: bin/workspace.sh mint writes
the base-ref file as `ref: <sha>` (workspace.sh:79; the value can be `none`), so
any orchestrator reading the file verbatim into --base reproduces this - which is
how it was found.

Proposed mechanical defense, liftable into a scope declaration:
1. bin/coverage/gate.sh guards --base with `git rev-parse --verify` and exits with
   the cannot-measure code on failure, never a pass verdict; plus a bats case that
   feeds an unresolvable ref and asserts non-zero exit.
2. Close the caller-side trap: either gate.sh resolves the base itself from the
   workspace's base-ref file (it already takes --workspace), or a shared parser
   owns the `ref: ` prefix and the `ref: none` fallback so no caller hand-parses.

Constraint on adjacent work: the acceptance-digest proposal (see
2026-07-02-acceptance-marker-attests-a-diff-it-never-saw.md) must not inherit this
hole - the same guard applies to any new digest helper.

Ladder status: mechanically checkable; this entry is a pointer per the
mechanization ladder. Supersede it when the guard lands with its bats case.
