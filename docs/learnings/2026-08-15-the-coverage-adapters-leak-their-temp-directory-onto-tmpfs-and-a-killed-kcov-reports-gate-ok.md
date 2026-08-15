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

The rate is one directory per REAL gate run, and the first version of this entry got that
badly wrong - it claimed the suite was the multiplier and that one `bats tests/` run leaked
"on the order of a thousand" directories. Measured twice since, independently, with `TMPDIR`
pointed at a scratch: `bats tests/coverage.bats` leaves **0**. Its ~100 gate invocations
supply `--report`, hide the toolchain so the adapter exits before `mktemp`, or route through
a project coverage command, and none of them reaches an adapter's `mktemp` at all. The whole
suite leaves **4** - 1 kcov, 2 tscov, 1 gocov - every one of them from `tests/adapters.bats`
invoking the adapters standalone.

So the 1,677 counted at the close of that review did not come from running the suite. They
accumulated one at a time across a long session of repeated real gate runs, and the observed
breakdown (1,108 tscov, 554 gocov, 4 kcov) does not match the 1:2:1 the code produces per
suite run, which is the tell that the suite was never the source. The correction matters
beyond the arithmetic: a gate-side fix removes none of the 4 the suite leaves, because their
caller is a test, so `tests/adapters.bats` has to isolate its own `TMPDIR`.

The lesson about the number is its own lesson. Both wrong figures came from counting what was
in `/tmp` after a session and attributing it to the loudest nearby loop, rather than measuring
one run against an isolated `TMPDIR`. A leak rate is a controlled measurement, not a total
divided by a guess.

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

Both are now fixed, in task `2026-08-15-coverage-temp-lifetime`. M9: `bash.sh` and `ts.sh`
capture the status and refuse at `>= 128` with their own message, while a plain non-zero still
measures - that is the red suite the discarded status existed to tolerate. `go.sh` is left
unguarded on evidence rather than oversight: a killed `go test` short-circuits to exit 4, and a
converter killed mid-write leaves XML too truncated for diff-cover to attribute, so every file
reads as absent and the gate fails closed. M8: the gate mints the directory, hands it over as
`--out`, and removes it on a trap - the adapters keep `mktemp` as the standalone fallback, since
their bare invocations in `tests/adapters.bats` are part of the contract. A real gate run now
leaves zero.

Tier: project. The files, the line numbers and the tmpfs behaviour are this repo's own
surfaces, and the fix lands here.
