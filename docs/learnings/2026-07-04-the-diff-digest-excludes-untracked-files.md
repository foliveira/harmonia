---
title: The diff digest excludes untracked files
date: 2026-07-04
tags: [bash,git,harmonia,acceptance,gates,receipts]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

Found at acceptance of 2026-07-04-lifecycle-runner. The workspace is gitignored,
so this entry is the durable carrier.

Current behavior, verified. diff_digest (bin/base-ref-lib.sh:20) is
`git -C <repo> diff <base> | sha256sum`. git diff <base> reports tracked changes
only and omits untracked files. So a new-file deliverable is absent from the
hashed bytes and is attested by nothing built on this formula: not the acceptance
marker, not gate receipts, not check-criteria receipts, not --verify-receipts.

Reproduction, this task. Concern 1's two deliverables (skills/flow/SKILL.md,
tests/lifecycle-runner.bats) were still untracked at acceptance (git status shows
??). The accepted marker's digest therefore covered only concern 2's tracked
gate.sh edit and its test, not the runner it was accepting. `git diff <base>`
alone also drops the runner from any diff audit, which is why the workspace docs'
"shipped" wording misleads a reviewer auditing by diff (verdict finding 2). The
bytes hash clean and the marker looks valid; the new files are simply not in what
was signed.

Another instance of "attests a diff it never saw"
(2026-07-02-acceptance-marker-attests-a-diff-it-never-saw.md), and a different
failure from it. That entry's gap was that the marker carried no digest at all; it
is mechanized and closed. Here the digest exists and verifies, yet the thing it
hashes (git diff) structurally excludes new files, so the attestation is silently
incomplete instead of absent. Same shared formula as the check-criteria staleness
bug (2026-07-04-check-criteria-s-receipt-goes-falsely-stale-at-review.md). Both
are blind spots inherited from `git diff <base>`.

The general git fact underneath: a sha over `git diff <base>` never covers
untracked files, so any digest-based attestation has to stage or otherwise account
for new files before it hashes. Kept at project tier because every consumer here
(base-ref-lib.sh, the marker, the receipts) is Harmonia's own.

Proposed mechanical defense, liftable into a scope:

- make diff_digest cover new files, for example by hashing `git diff <base>`
  together with the content of `git ls-files --others --exclude-standard`, or by
  diffing against an index that includes intent-to-add (git add -N) untracked
  files; keep the empty and unresolvable-base guards the formula already depends
  on; or
- make accept and --verify-receipts refuse, or at least warn, when the workspace
  boundary names files that are untracked at attest time, so a new-file
  deliverable cannot be signed while it is invisible to the digest.

Ladder status: mechanizable, not yet mechanized. This entry is the reproduction
record until a guard lands.

Second instance, 2026-07-12-capability-gaps - caught pre-acceptance. The
regression lens's first-ever dispatch hit this entry: core/lenses/regression.md
(the task's central new file, and the lens's own carrier) was untracked at review
while diff_digest still hashed only `git diff <base>`. The verdict issued a
staging caveat; the developer staged the file before `workspace.sh accept`, and
the accepted marker's digest (2d0dc796...) verifiably covers it - a staged new
file is visible to `git diff <base>`; only a fully untracked one is not. Two
facts this instance adds: stage every new-file deliverable (`git add`, or
`git add -N`) before accept, and the rejection-staleness comparison reuses the
same digest formula, so it inherits the same blind spot. The durable fix - one of
the two defenses proposed above - is queued as a named future task out of this
task's verdict. The lens now surfaces this entry whenever a reviewed diff carries
an untracked deliverable, but the formula itself is still unguarded. Ladder at
that point: mechanizable, not yet mechanized, with two reproduction records.

Third instance, 2026-07-31-receipt-integrity - escalated to a major review finding,
because the blind spot moved from incidental to load-bearing.

That task made `--verify-receipts` require a coverage receipt fresh for the tree, by
name. The freshness test is this formula. So the digest's blindness is now what the
restored protection stands on, and the asymmetry sits inside one script: `gate.sh`
builds its changed-file set as `git diff --name-only <base>` unioned with
`git ls-files --others --exclude-standard`, while `diff_digest` hashes `git diff`
alone. One script, two answers to "what changed":

    add brand-new.sh (untracked):  digest unchanged;  audit: receipts verified, exit 0
      the same gate's classifier:  gate: FAIL - brand-new.sh:ALL (absent from coverage data)
    after git add -A:              digest moves;      audit: stale, exit 1

During review, before the committer has run, new files are exactly the untracked ones.
A fresh coverage receipt an earlier stage left behind can therefore certify a tree
holding code that no coverage run measured.

What got the finding escalated was not the hole, which is this entry's, but a false
justification built on it: the task's scope declaration declined to fix a residual on
the grounds that "that claim is true - the digest matches, the tree has not moved". The
digest can match while the tree has moved. The clause was withdrawn in a second review
round and replaced with the mechanism.

Second axis, and it does not have the same remedy. `git ls-files --others
--exclude-standard` excludes ignored paths, so the classifier is wider than the digest
and still blind to anything gitignored. The task workspace is ignored by design
(`.gitignore:3`), which means the criteria a `criteria-run` receipt certifies can never
be covered by any git digest - measured, `git ls-files .harmonia/tasks` is empty. The
global sibling entry's remedy, "commit anything a reviewer is asked to judge", is
unavailable for a path ignored on purpose. There the fix has to be a digest of the
artifact carried inside the receipt that certifies it. See
2026-07-04-check-criteria-s-receipt-goes-falsely-stale-at-review.md, F7.

Ladder unchanged: mechanizable, not yet mechanized, now with three reproduction
records. The filed defense is the first one proposed above - hash `git diff` together
with the untracked set the classifier already computes, which this gate computes twelve
lines away.
