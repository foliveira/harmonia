---
title: The test-immutability violation record cannot tell an implementer edit from a verify-before-record inversion
date: 2026-07-27
tags: [bash,harmonia,gates,process,test-immutability]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

Produced live at the review stage of 2026-07-26-claude5-prompt-adaptation, by the
orchestrator, not by any implementer.

What happened. `bin/workspace.sh verify-test-hashes` ran against a tree the
test-engineer had just changed under review orders, before the hashes were re-recorded.
`skills/implement/SKILL.md:13` records hashes after every test-engineer turn and `:15`
verifies before accepting the round; run in the other order a mismatch is guaranteed
regardless of who touched the file or why. A `violations` record landed in the
workspace naming `tests/roster.bats` with one checksum mismatch. Re-recording and
re-verifying returned exit 0.

Why it cost a full adjudication. `core/charters/reviewer.md` and
`skills/review/SKILL.md:14` make a violations record review-failing. The record carries
a timestamp, a filename and a checksum message, and nothing else - it cannot distinguish
"an implementer edited a test" from "verify ran before record". Every fact the review
lead used came from outside it: that only that one test file had changed since the first
verdict, that no product line changed in the window so there was nothing for a test to
be bent toward, that the edit made the test strictly stricter (the direction opposite to
what the control guards against), and that the seat that made it was the test-engineer.

Two rulings worth keeping as precedent. Read the record rather than treat its existence
as a verdict - the script's own failure message says it is recorded "for the review
lead", which is evidence addressed to a reader, not a self-executing verdict - but set
the bar the other way round so this cannot become an escape hatch: the record stands as
a violation unless the evidence positively establishes that no implementer edited a
test. And leave it in place. Deleting it destroys the evidence needed to adjudicate, and
self-exoneration by marker deletion is precisely what the control exists to prevent;
`clear-span` clears it at the next span reset.

Proposed mechanical defense, liftable into a scope declaration - either is cheap:

- have `verify-test-hashes` note when the recorded manifest predates the newest
  test-file mtime, so the ordering inversion is visible in the record itself; or
- have the implement loop refuse to verify when no implementer turn has occurred since
  the last record.

The mechanism itself is sound - `tests/workspace.bats:190` already pins that it records
a violation correctly. The ordering around it is what bit. Registered as FU-9.

Second-order note worth keeping: this was the first live production of the `violations`
artifact, which the same task had just declared in `core/lifecycle.yaml`, and the
reviewer `consumes:` entry the same task added is what routed it to the lead. The
contract slice was exercised end to end by an accident on its first day, which is
better evidence than the tests in its own diff.

Tier project - the record, the loop ordering, the charter obligation and the fix are all
Harmonia's. The general form, for anyone who builds an alarm: if a guard record names
only what tripped it and not the ordering that produced it, every firing costs a manual
investigation from outside evidence.
