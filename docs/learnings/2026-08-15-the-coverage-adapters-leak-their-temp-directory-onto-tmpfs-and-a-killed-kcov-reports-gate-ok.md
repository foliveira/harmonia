---
title: The coverage adapters leak their temp directory onto tmpfs, and a killed kcov reports gate: OK
date: 2026-08-15
tags: [bash,coverage,gates,harmonia,testing]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

Filed from review round 7 of 2026-08-11-project-config-trust, findings M8 and M9. Both sit
outside that task's boundary and are UNFIXED at master `762c48e`. They are one bug with two
faces, and M8 is the cause.

M8. All three adapters create an output directory and never remove it.
`bin/coverage/bash.sh:15`, `bin/coverage/ts.sh:12` and `bin/coverage/go.sh:14` each `mktemp
-d`, and no adapter contains a `trap` or an `rm`. It cannot simply be deleted at exit inside
the adapter, because the adapter prints a path INSIDE that directory and the gate then reads
it. The cleanup belongs at the gate's end of the contract, once per adapter, or in a trap
after the report is consumed.

The suite is the multiplier, not the gate. `tests/coverage.bats` invokes the gate 101 times
through `"$GATE"` alone (the review counted 104 gate invocations in total), and every
invocation that reaches an adapter leaks one directory that outlives the test's own
`BATS_TEST_TMPDIR`. One `bats tests/` run leaves on the order of a thousand directories
behind. Measured at the close of that review: 1,677 in `/tmp` - 4 kcov, 554 gocov, 1,108
tscov - after the developer had already removed 664.

`/tmp` here is tmpfs, so the leak is memory. The gate consumes the memory it needs to run,
which is how the kill in M9 happens at all.

M9. A killed kcov and a clean one are the same to the caller, and the report can still say OK.
`bin/coverage/bash.sh:17` ends `|| true`, discarding kcov's exit status, so a SIGKILL from the
OOM killer reads as success. The gate's fail-closed rule for missing data is per FILE and not
per line: `bin/coverage/gate.sh:368-373` counts a changed file absent from the coverage data
as wholly uncovered, but a partial run that touched the file at all passes. Both outcomes were
observed in this one task at the same digest - round 6's killed run reported `FAIL ... absent
from coverage data`, and two killed runs in round 7 reported `gate: OK ... Uncovered changed
lines: none`. The only difference is whether kcov got as far as the file before it died.

Smallest fix for M9, in `bin/coverage/bash.sh` where the `|| true` is. The discriminator is
exact, because a signalled status is never a red suite:

    rc=$?; [ "$rc" -ge 128 ] && { echo "bash adapter: kcov was killed - cannot measure" >&2; exit 4; }

Why this reaches past one task. `cannot measure` / exit 4 is the honest answer the repo's
tier-B coverage story rests on, and today the gate cannot tell a partial run from a clean
pass. A coverage receipt produced on a memory-pressured machine is not evidence until M9 is
closed. Two reviews in this task declined to re-run the gate and substituted their own
measurement for precisely this reason - one of them instrumented a `/tmp` copy of the changed
file with a marker appended on the same physical line, so numbering was untouched, and counted
153 executions of the line in question from three shipped cells.

Tier: project. The files, the line numbers and the tmpfs behaviour are this repo's own
surfaces, and the fix lands here.
