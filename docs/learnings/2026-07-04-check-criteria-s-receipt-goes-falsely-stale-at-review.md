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

Ladder status: mechanized. Superseded: F1's guard landed in task
2026-07-31-receipt-integrity (no commit sha existed at capture time; this status
ships in that task's own commit); the false-staleness fix landed earlier, in this
entry's own task (concern 2, its own commit). The entry stays as the reproduction
record.

F1 as shipped, against F1 as proposed above. This entry offered two defenses -
"assert a coverage receipt is present and its status is pass, or track that at least
one receipt was freshness-checked". July took the second, and that counter is what
2026-07-31-receipt-integrity had to retire: the criteria gate added in
2026-07-28-verification-loops writes a code-dependent receipt of its own, so the count
was satisfied by that receipt alone and a review could pass with nothing having
measured coverage. The new gate takes the FIRST defense minus its status clause. The
audit sets `cov_seen=1` when a receipt's `.gate` field reads `coverage` and otherwise
refuses with "no code-dependent receipt to verify - refusing (no coverage receipt)".
Coverage's own status stays deliberately unread: reading it would harden the
uncovered-lines soft block into a verify failure and would also refuse the advisory
cannot-measure route, which legitimately receipts `status: fail`. The coverage arm
carries no `continue`, so a coverage receipt still owes the freshness check below and a
stale one is still refused as stale - the `coverage) cov_seen=1; continue` shape, the
natural copy from the check-criteria arm above it, certifies a stale receipt and is
red in the shipped suite.

Measured both directions before shipping: 20 receipt states against the pre-fix and
post-fix builds, 4 changed, every change PASS to REFUSE and none the reverse; an
independent 375-state sweep found 39 differences, all in that direction. The quick
lane, whose receipts directory holds `coverage.json` alone, passes identically on both.

F4 above was re-ratified rather than closed, and F1 raises its stakes. The waiver still
keys on the receipt's unauthenticated `gate` field, and that field stops being a
routing hint: it is now the certificate that the coverage gate ran against this tree.
The assumption is not newly weakened - under the old counter a legitimately written
criteria-run receipt was already sufficient - it lives in one inline comment beside the
waiver, and it stays bounded by the workspace-write trust boundary.

F7 above got wider, and the widening is worth writing down. The criteria gate's own
receipt (`criteria-run.json`) certifies "ten criteria executed, all pass" while its
freshness digest is the shared `git diff` formula. The criteria live in `scope.md`
under `.harmonia/tasks/`, which `.gitignore:3` ignores, so they appear neither in
`git diff` nor in `git ls-files --others --exclude-standard` - measured,
`git ls-files .harmonia/tasks` is empty. No digest built on git can witness the set of
criteria that receipt is about, and an edit between the criteria run and the review is
invisible to every mechanical check. This is the same category error named under "The
root cause" above, in a receipt whose freshness IS checked, which makes it read
stronger than the waived one while being just as blind to its own subject. The
2026-07-31 review lead caught the negative by byte-comparing all ten criteria against
the gate's per-criterion report by hand: zero mismatches, and no gate performs that
check and no charter asks for it. Filed: put a digest of the criteria block inside the
receipt.
