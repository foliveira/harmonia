---
title: A resolvable base-ref can still be the wrong base
date: 2026-07-03
tags: [bash,harmonia,workspace,gates,process]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

Trap hit in 2026-07-03-acceptance-hardening, caught manually at plan time.
workspace.sh mint records "ref: <HEAD of the current checkout>". The workspace
was minted while the recall-guard branch was checked out (tip 7dcc093), but
the task based on post-merge master (2ed6806). The recorded base resolved, so
the gate's unresolvable-base refusal - landed one task earlier precisely to
guard this input - had nothing to object to. Left stale, the coverage gate,
both receipts, and the acceptance digest would all have measured the diff
against the wrong base. The fix was rewriting the workspace base-ref by hand
before plan, recorded in scope.md's base-precondition note.

Why no gate can catch the general case: wrong-but-resolvable is
indistinguishable from right at check time; the intent lives only in the
developer's head at mint.

Partial mechanical defense for a future scoper: an ancestry check at gate time
- git merge-base --is-ancestor "$BASE" HEAD - would have caught this instance
(verified: 7dcc093 was squash-merged away, so it is not an ancestor of the
task branch). Residual blindspot: a stale base that IS an ancestor (workspace
minted on old master, task built on new master) passes ancestry and stays
uncatchable. A full defense needs mint-time intent: an explicit base argument
to mint, or minting only after the base exists.

Ladder status: partially mechanizable - the ancestry check narrows the trap
and is worth a scope; the stale-ancestor case stays judgment. Working rule
until a guard lands: any task whose base precondition is unmerged work
re-checks the workspace base-ref between merge and plan.
