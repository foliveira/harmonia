---
title: clear-span turned a presence-only --task check into a path-traversal deletion
date: 2026-07-05
tags: [bash,harmonia,security,workspace,path-traversal]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

Found in review of 2026-07-05-flow-runner-hardening, caught by the security lens
(it fired on the "input parsing" trigger), not by tests or coverage. The task
workspace is gitignored, so this entry is the durable carrier for the finding
(S1) and the fix that landed with it.

Verified current behavior. pick() (bin/workspace.sh:45) resolves the `--task`
override for every subcommand that acts on a task. Its `--task` branch now
rejects any id that is not a single path component, before the existence check
(line 47):

    case "$TASK" in */*|*..*) echo "workspace: invalid task id '$TASK'" >&2; exit 1 ;; esac

A legitimate id is one `YYYY-MM-DD-slug` component, so this refuses `..` and `/`
while letting every real id through. Because the guard lives in the shared
resolver, one line hardens all eight pick-based subcommands at once (resolve,
clear-span, accept, verify-acceptance, complete, abandon, record-/verify-test-
hashes), not just the one that exposed the weakness.

What it was before, and why it was latent. The `--task` branch validated only
that the directory existed (`[ -d "$TASKS/$TASK" ]`, still line 48) and then
echoed `$TASK` verbatim as `$ID`. It never rejected `..` or `/`. That was
harmless for as long as every consumer used the resolved `$ID` only to WRITE a
small marker: accept/complete/abandon drop a timestamp file. The new clear-span
arm (lines 91-106) is the first consumer to make `$ID` an `rm` target: it builds
`D="$TASKS/$ID"` and runs `rm -f "$D/$f"` over five span-named files. A
`../`-bearing `--task` therefore resolved outside `$TASKS/$ID/` and pointed those
deletions at an arbitrary directory.

Reproduction (pre-fix). `clear-span --repo <repo> --task '../../../bystander'`
deleted the span-named files present in a directory outside the workspace
(design.md, verdict.md, gate-report.md) and exited 0 with the normal
"cleared span out-artifacts" message: a silent escape. `[ -d ]` passed because
the traversed path resolved to a real directory.

The claim that was false. design.md 1.3 advertised the five-literal-file list as
"the `.git`-deletion-incident guard, now in tested shell" and asserted removal
happens "in `$TASKS/$ID/` only". That confinement was false for a `..`-bearing
`--task`. The referenced incident is real: a review subagent once ran
`rm -rf .git` in this repo (2026-07-02, no material loss). Same class, an
unconfined deletion, which is why the confinement guarantee had to be real and
tested rather than asserted.

Why gates did not catch it, and the lens did. The change shipped 100% coverage on
its changed lines and a green suite, yet carried a Medium security defect, because
the defect was a false safety CLAIM rather than a failing behavior: coverage
proves lines execute, not that inputs are validated. The security lens found it by
reading the design's claim against the code and reproducing the counterexample.
That is the dogfooding value of a review lens over the mechanical gates.

Mechanized, not merely noted. The guard above landed in this task (2026-07-05),
and tests/workspace.bats (the first behavioral test file for workspace.sh) pins
the refusal: it seeds a bystander directory holding span-named files outside the
tasks tree, runs `clear-span --task '../../../bystander'`, and asserts a non-zero
exit with both bystander files surviving. That test is what makes the design's
"incident guard" claim true, and it catches any future reintroduction. The
narrower alternative (guarding only inside the clear-span arm) was rejected in
favor of the shared-resolver guard, which also covers the next rm or write sink.

Related: 2026-07-03-check-criteria-sh-still-passes-an-unguarded-base-ref-to-git-diff.md
is the same failure family, an unvalidated input reaching a dangerous sink in a
Harmonia bash script (there a base ref reaching `git diff` argv; here a `--task`
reaching `rm`), and both surfaced through review rather than through tests.

The general principle: when a shared resolver gains a destructive consumer,
re-audit its input validation. Validation that is adequate for a benign sink (a
marker write) is inadequate for a destructive one (`rm`), and a presence-only
check (`[ -d ]`) admits path traversal. The corollary for reviewers: a safety
claim in a design is a claim to reproduce, not to trust, and green coverage does
not prove input-safety.

Kept at project tier: pick/workspace.sh, the flow runner, and the `.git` incident
are all Harmonia's own; no client work is implicated.
