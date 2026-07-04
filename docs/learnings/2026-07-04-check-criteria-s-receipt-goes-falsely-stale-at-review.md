---
title: check-criteria's receipt goes falsely stale at review
date: 2026-07-04
tags: [bash,harmonia,coverage,gates,receipts]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

Found by dogfooding the review of 2026-07-04-lifecycle-runner (PASS with required
follow-ups). The verdict lives in the gitignored workspace, so this entry is the
durable carrier. The staleness fix shipped in this task's concern 2; the residual
gaps below are routed here for the next scoper.

The bug, verified. diff_digest (bin/base-ref-lib.sh:20) hashes `git diff <base>`.
It is the one formula shared by gate receipts, check-criteria receipts, receipt
verification, and the acceptance marker. check-criteria runs at implement-start on
a clean tree, so its receipt records the empty-diff digest
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 (sha256 of no
bytes). gate.sh --verify-receipts required every receipt to be digest-fresh
against the current diff, so the moment implement wrote code the check-criteria
receipt mismatched and verify called it stale. Every code-writing task trips this,
and the flow runner automates implement then review in one session, so it would
trip on every run.

The root cause is a category error. check-criteria validates scope.md, which is
code-independent, but its receipt carries a code-diff digest. Digest-freshness is
the wrong invariant for a receipt whose subject is not the code diff.

The fix, shipped (bin/coverage/gate.sh:78-81). --verify-receipts branches on the
receipt's gate field. A check-criteria receipt is validated by presence plus
`status: pass`, then the loop continues. Every other gate (coverage, any future
gate) still takes the byte-identical digest-freshness path, so a stale coverage
receipt still fails. The continue (not break) keeps the coverage freshness check
running even when check-criteria.json sorts first in the glob. coverage.bats test
24 pins this by mutation: swapping continue for break makes test 24 fail.

Same theme as the acceptance-marker entry
(2026-07-02-acceptance-marker-attests-a-diff-it-never-saw.md) and the
vacuous-base entry
(2026-07-02-coverage-gate-passes-vacuously-on-an-unresolvable-base-ref.md, which
names this same empty-diff digest): every attestation built on `git diff <base>`
inherits the diff's blind spots. A sibling blind spot in the same formula,
untracked files, is recorded in
2026-07-04-the-diff-digest-excludes-untracked-files.md.

Residual gaps the fix unmasked, routed as follow-ups (the verdict carries the full
arbitration; it is not repeated here):

- Required (F1, MEDIUM-HIGH, reproduced). --verify-receipts never asserts a
  coverage receipt is present. A receipts dir holding only a passing
  check-criteria.json returns "gate: receipts verified", exit 0, on a drifted
  tree. The fix did not create this. Before it, the lone check-criteria receipt
  failed verify for the staleness reason above, which accidentally masked the gap.
  Defense: assert a coverage receipt is present and its status is pass, or track
  that at least one receipt was freshness-checked.
- Lower (F4, LOW-MEDIUM, reproduced). The check-criteria waiver keys on the
  receipt's own gate field, which is unauthenticated. Only check-criteria.sh
  writes it in the honest flow, but anyone who can write the receipt can write any
  value, so it is bounded by the existing workspace-write trust boundary. Folds
  into the F1 redesign.
- Accepted cost (F7). With freshness waived, scope.md drift after implement-start
  is invisible to --verify-receipts. This is the ratified cost of the chosen
  option; rebinding check-criteria's receipt digest to scope.md would restore
  meaning to its freshness if drift becomes a concern.

Ladder status: partially mechanized. The false-staleness fix landed in this task
(concern 2, its own commit). The coverage-presence assertion (F1) is the open
mechanical follow-up. Supersede this entry when F1 lands.
