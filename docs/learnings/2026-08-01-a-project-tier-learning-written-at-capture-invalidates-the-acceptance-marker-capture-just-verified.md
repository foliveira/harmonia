---
title: A project-tier learning written at capture invalidates the acceptance marker capture just verified
date: 2026-08-01
tags: [bash,harmonia,acceptance,gates,receipts,process]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

Found while curating 2026-07-31-receipt-integrity, by measuring my own writes rather than
by reading anything. Not a defect in any one script; a consequence of the stage order and
the shared digest formula.

Measured, in this order:

    before the curator wrote anything
      accepted marker: digest e4b87362e9f79c26...   verify-acceptance: exit 0
    after updating two tracked entries under docs/learnings/
      live diff_digest: 8985bc25236e9888...
      verify-acceptance: exit 1 - "acceptance is stale - the accepted digest does not
        match the live diff; the developer must re-accept"
      gate.sh --verify-receipts: exit 1 - coverage.json stale, criteria-run.json stale

The cause is structural. `docs/learnings/` is tracked, the digest is
`git diff <base> | sha256sum` (bin/base-ref-lib.sh), and `skills/capture/SKILL.md` gates on
`verify-acceptance` at step 2 and dispatches the curator at step 3. The curator's product
is therefore a tracked write that lands after the attestation it is gated by. The human act
cannot survive its own stage.

Every gate above is right in isolation: the tracked diff really did move. What moved is
documentation the developer has no behaviour to exercise, and the script's remedy message
("the developer exercises the current behavior and re-accepts") points at a change that
does not exist.

Why this has not surfaced before, and the timing, which differs by write. Global-tier entries
land in `$HARMONIA_HOME`, outside the repo, and move no tracked byte; the immediately
preceding task captured nine entries, all global, and its digest never moved. An edit to an
existing tracked `docs/learnings/` entry moves the digest during the curator's own turn -
that is what produced the measurement above, and it is exactly what a scope declaration asks
for when it puts a `docs/learnings/` file in boundary "at capture". A brand-new project entry
is untracked, so it moves nothing until the committer stages it (the sibling entry below is
why), and the marker then goes stale one seat later instead. Same end state, two different
moments, and the second one is harder to attribute because the curator has already returned.

Nothing in the wired flow breaks today, and that is worth stating plainly: capture's
`gates:` list is empty, step 2 runs once before the curator, and the committer that follows
re-runs neither check. The cost lands in two places instead.

Operational tell. After the curator has run, a `verify-acceptance` exit 1 or a stale-receipt
refusal whose entire delta is under `docs/learnings/` is the capture stage's own doing, not a
post-acceptance code change. Distinguish them with
`git diff --name-only <base>`: if every path outside the reviewed set is a learnings file,
nothing needs exercising and a plain re-accept clears it. Do not go looking for a behaviour
change.

Second cost: an interrupted capture is not resumable without a human. Step 2 refuses on any
non-zero exit and stops before dispatching the curator (correctly - see the global entry
"Gate on non-zero, not on an enumerated exit-code set"), so a session that dies between the
curator and `workspace.sh complete` cannot be resumed until the developer re-accepts, for a
staleness the stage caused itself.

Mechanical defenses, liftable into a scope, none shipped:

- exclude the curator's own output paths from the attested diff, so acceptance attests the
  reviewed diff and not the record of it; or
- have capture record the digest it verified at step 2 and re-attest automatically after the
  curator when the only delta is under the curator's own output paths; or
- cheapest and least satisfying: say it in `skills/capture/SKILL.md` step 2, so the resume
  path names the cause instead of sending the developer to exercise nothing.

Ladder status: mechanizable, not mechanized. Filed as a follow-up out of this task's capture.

Third consequence of one formula. Siblings, same digest, different stages:
2026-07-04-check-criteria-s-receipt-goes-falsely-stale-at-review.md (a receipt whose subject
is not the code diff carrying a code-diff digest) and
2026-07-04-the-diff-digest-excludes-untracked-files.md (the same formula blind to files it
should cover). Here the formula is accurate and the stage order is what defeats it.
