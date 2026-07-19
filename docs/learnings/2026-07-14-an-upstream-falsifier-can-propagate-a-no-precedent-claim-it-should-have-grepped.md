---
title: An upstream falsifier can propagate a no-precedent claim it should have grepped
date: 2026-07-14
tags: [harmonia,process,review,design-attack]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

Instance: 2026-07-14-installer-hardening made the OpenCode installer dual-mode -
executable, and sourceable for tests via a `BASH_SOURCE[0] != "$0"` guard. design.md
(~L454-463) and boundary.md (L79-84) both called this a new pattern with no precedent,
on the reasoning that "the existing sourced libs carry no guard and are never run
directly." The design-attack seam, dispatched to break the design, echoed the same claim
in its novelty note (L95-103) instead of testing it. It is false: `bin/memory/store-lib.sh:66`
is the same `if [ "${BASH_SOURCE[0]}" = "$0" ]` guard, its header (line 2) reads
"Sourceable; also a small CLI", and `tests/memory.bats:88-89` drives it by direct
invocation. A guarded dual-mode executable-and-sourceable bash file already ships and is
already tested. The review lead's adversarial lens found this first-hand; nothing between
the design and the verdict did.

Part one: "no precedent" / "nothing already does this" / "no existing mechanism" is a
checkable factual claim, and the check is usually one grep. Asserted from memory, it
mis-drew the design here - it manufactured a "novel maintenance cost" trade-off for an
idiom the repo already carries. Run the grep at the point you make the claim. This is the
design-stage sibling of the global "check checkable scope claims at scoping time" learning:
same failure, later stage.

Part two, and the reason this earns its own entry: the upstream falsifier did not save us.
The design-attack seam exists to break the design's claims, and it reinforced this one -
because it reasoned inside the design's frame ("the libs I know of carry no guard") instead
of checking the primitive against the tree (grep for a `BASH_SOURCE` guard). A same-frame
adversary confirms shared premises rather than breaking them; independence has to come from
checking existence claims against ground truth, not from a second reasoning pass off the
same assumptions. When a falsification dispatch accepts a premise, read whether it tested
the premise or inherited it - the accepted/rejected texture the kill-test protocol already
asks for (2026-07-12 kill-tests learning).

Ladder: not mechanizable - spotting which prose is a checkable existence claim takes
judgment, and a falsifier sharing the author's frame cannot be gated. Prose is the right
rung. Verdict correction C1 already bars capturing the guard itself as novel; store-lib.sh:66
is the precedent.
