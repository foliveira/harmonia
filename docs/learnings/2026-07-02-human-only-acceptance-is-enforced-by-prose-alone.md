---
title: Human-only acceptance is enforced by prose alone
date: 2026-07-02
tags: [bash,harmonia,acceptance,process]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

Adversarial lens finding A-3 (major) from the review of 2026-07-02-adlc-adoptions,
arbitrated to the developer as a product-decision follow-up. The workspace verdict
is gitignored - this entry is the durable carrier.

The invariant "agents never run accept on the developer's behalf" is the system's
first human-only act, and it is enforced by one prose sentence in
skills/capture/SKILL.md step 2 - addressed to the party it constrains, with the
refusal message handing that same party the unblocking command.

Reproduction (lens E8): a piped, non-interactive `bash bin/workspace.sh accept
--repo .` exits 0; an agent-written marker is byte-indistinguishable from a
human-written one.

The repo's precedent for the same incentive shape is mechanical, not prose: the
implementer is kept out of tests by KTD12 hash checks, and even orchestrator-run
gates leave KTD7 digest receipts
(docs/plans/2026-07-02-001-feat-personal-sdlc-plan.md:227,232). Honest mitigations
per the verdict: violating the prose requires direct disobedience of an
unambiguous prohibition, transcripts expose it after the fact, and this is a
personal plugin.

Defense options, in the verdict's value order:
(a) the acceptance diff digest (see
    2026-07-02-acceptance-marker-attests-a-diff-it-never-saw.md) restores
    after-the-fact auditability - a marker minted before the final diff cannot
    match it;
(b) a `[ -t 0 ]` check in the accept arm of bin/workspace.sh makes the marker
    tty-only: mechanical and one line, but it blocks legitimate scripted human
    use. That usability cost is the developer's to price; it is why this stayed
    prose in the shipped diff.

Deliberate asymmetry to preserve (lens A-6): acceptance is the first in-artifact
no charter consumes, and the roster closure test checks only the
charter-to-artifact direction, so the asymmetry is invisible to it. Do not "fix"
it by putting an agent in the consumption path of a human act; if a guard is
wanted, a bats test asserting no charter consumes the acceptance artifact pins the
asymmetry mechanically.

Ladder status: superseded in its auditability half, decided in the other, by
task 2026-07-03-acceptance-hardening (no commit sha existed at capture time;
this status ships in that task's own commit). Option (a) landed: the marker
carries the diff digest and capture verifies it via `workspace.sh
verify-acceptance`, so a marker minted before the final diff cannot match it
once tracked files move (untracked-only changes stay outside the digest - a
recorded limit of the shared receipts formula), making a violation auditable
after the fact, bats-pinned. Option (b), the `[ -t 0 ]` check, was considered
and declined by the developer - it would break the scripted accept flow he
actually uses - so human-only acceptance stays a prose rule as a decided
trade-off, no longer a pending choice. The entry stays as the decision record.
