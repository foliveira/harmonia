---
title: Acceptance marker attests a diff it never saw
date: 2026-07-02
tags: [bash,harmonia,acceptance,gates,process]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

Adversarial lens finding A-1 (major) from the review of 2026-07-02-adlc-adoptions.
Review PASS: the implementation faithfully delivers the pinned scope, which mirrors
the bare done marker; the finding falsifies the strength of that product decision,
not the diff, so it was arbitrated to the developer as a follow-up. The workspace
verdict is gitignored - this entry is the durable carrier.

Current behavior, verified: bin/workspace.sh:90 - accept writes only a UTC
timestamp to the `accepted` marker; skills/capture/SKILL.md step 2 checks marker
presence only. The marker therefore attests a diff it never saw.

Reproduction recipe (lens experiments E1/E2, throwaway repo against the real
script): run accept, then change the tree - capture's presence check still passes
while `git diff <base> | sha256sum` has moved, so acceptance silently covers code
the developer never exercised. The marker is also writable immediately after mint,
so the delivered ordering guarantee is only "present at capture time", not "after
review" - this corrects design D2's claim that ordering is the skills' job
(finding A-2 collapses into this one).

Contrast with the repo's own standard: KTD7's receipt minimum is task-id +
timestamp + diff digest, mismatch means stale
(docs/plans/2026-07-02-001-feat-personal-sdlc-plan.md:227). The one record
representing human judgment is the only attestation without a digest.

Proposed mechanical defense, liftable into a scope declaration:
- accept writes the diff digest beside the timestamp (the base ref is already in
  the workspace base-ref file);
- capture step 2 recomputes the digest and refuses on mismatch, telling the
  developer to re-accept; re-accept already overwrites the marker (deliberate D2
  mirror behavior) and becomes load-bearing in this flow;
- the digest helper must not inherit the gate.sh empty-diff hole (see
  2026-07-02-coverage-gate-passes-vacuously-on-an-unresolvable-base-ref.md) and
  must handle mint's `ref: none` fallback.

Ladder status: mechanically checkable; entry is a pointer pending the developer's
decision - the fix exceeds the originally pinned scope, so it needs its own task.
