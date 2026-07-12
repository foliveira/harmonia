---
title: A roster-size change strands stale count words in dispatched prose
date: 2026-07-12
tags: [harmonia,process,scoping,docs]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

Instance: 2026-07-12-capability-gaps dropped the debugger, moving the roster
from thirteen to twelve. core/lenses/performance.md:13 still says "a bounded
thirteen-element roster" - live dispatched prose, false since the change,
disclosed by the implementer mid-task, confirmed by two review seats, and
correctly left unfixed because the file sat outside the pinned boundary (R3,
Surgical Changes). The pending fix is one word, thirteen to twelve. This entry
is the durable pointer (the design doc that named the fix dies with the
workspace); the regression lens should surface it on future diffs until the
word changes.

Why the criteria missed it: criterion D2 grepped live surfaces for "debugger"
tokens and criterion 10 checked "thirteen" in README.md only. Neither swept
dispatched prose for the count word, and the boundary was pinned before anyone
looked at performance.md.

The class: hand-written size claims ("thirteen-element", "N-agent") in prose
assets drift when the roster or list they describe changes size. At scoping
time for any size-changing task, grep both the old and the new count words
across all live dispatched surfaces - core/, agents/, skills/, README.md - and
pull every hit into the boundary. Same scoping-time discipline as the global
entry "Check checkable scope claims at scoping time", applied to the blast
radius of a count change rather than to the scope's own claims.

Ladder: the instance fix is one word, to ride the next task that can carry it.
A permanent mechanization (a test deriving the roster count from ls
core/charters and sweeping prose for mismatching count words) is possible but
judged not worth its false-positive surface while this entry plus the lens
covers the gap.

Tier: project - the roster, the lens prose, and the criteria style are this
repo's own.
