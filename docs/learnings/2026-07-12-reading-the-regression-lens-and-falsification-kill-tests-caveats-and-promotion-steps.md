---
title: Reading the regression-lens and falsification kill tests: caveats and promotion steps
date: 2026-07-12
tags: [harmonia,process,review,kill-tests]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

Context: 2026-07-12-capability-gaps shipped two experiments whose verdicts are
deferred - the regression lens (item A, per-dispatch hit/clean/not-applicable
block in verdict.md) and upstream falsification (item B, per-seam lines in
falsification.md). The kill tests run over subsequent tasks; scope.md and
design.md die with the gitignored workspace, so this entry carries the reading
protocol and the promotion steps. The named reader is the developer.

Tally mechanics (preserved from design.md before it dies):
- Item A, per review dispatch: `grep -c '^- regression:hit ' <ws>/verdict.md`;
  novelty judgment (did the panel already have it) stays human. First dispatch:
  4 hits, 1 novel.
- Item B, per seam across workspaces:
  `grep -hc '^- seam=plan-entry accepted:' .harmonia/tasks/*/falsification.md`
  against the matching `dispatched:` count; same for seam=discuss and
  seam=design. Never summed - an aggregate zero, dominated by discuss-seated
  runs, would kill the plan-entry clause exactly where its n=1 evidence (BROKE
  #2) lives. The per-seam rule is shipped in core/lenses/adversarial.md; it is
  restated here only because the tally reader works from workspaces.
- Both records live in gitignored workspaces with no aggregation point (an
  accepted non-goal). Tally before clearing old workspaces or the denominator
  silently shrinks.

Reading caveats, from the verdict's arbitration of adversarial F2/F4/F5/F6:
- The regression denominator is per-triggering-dispatch, never a base rate over
  all diffs - the lens fires where the store predicts recurrence.
- A `dispatched: findings=0` line is indistinguishable from a skipped real
  dispatch; zero survivors can mean a lazy seam. Read the accepted/rejected
  texture, not only the counts - same trust model as every charter-bound
  self-report in the engine.
- The seam tag is self-asserted. Cross-check `seam=discuss` against insights.md
  existing in the same workspace (the rubber-duck's artifact).
- M, the store total in the not-applicable line, is self-reported; the review
  lead must recompute it against the live stores each dispatch. The first
  dispatch proved the need: the design doc claimed 12 entries while the live
  store had 13.

Promotion steps if the experiments survive (neither is on a shipped surface):
- Item A: add the one-line reviewer.md clause obliging the lead to include the
  lens's countable block in verdict.md unedited. Today that duty lives only in
  regression.md:29-31, a file a minimal lead might read for frontmatter alone;
  item B amended its writers' charters while item A did not. The first dispatch
  worked without the clause, so it waits for survival evidence.
- Item B: promote the charter-clause dispatch into lifecycle.yaml wiring - the
  scope deliberately pinned the cheapest-to-revert shape.

Reversal: zero scope- or design-changing survivors across the next few runs of a
seam kills that seam's dispatch only; the other seams keep their own counts.

Tier: project. Ladder: a human protocol - novelty and texture judgments are not
mechanizable; the greps above are the mechanical part.
