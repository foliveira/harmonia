---
title: A reviewer subagent's untracked stray at the repo root flips the live coverage gate to cannot-measure
date: 2026-07-13
tags: [bash,harmonia,coverage,review,gates]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

Found at review of 2026-07-13-multi-harness-install (audit A1, routed and closed as
REQ-4). The task workspace is gitignored, so this entry is the durable carrier.

What happened. A review subagent wrote a 23-byte untracked file `pre-flight` (content
"NO - will not guard it") at the repo root during the review. The live coverage gate then
returned exit 4, "cannot measure - unsupported language", until the file was deleted.
Moving it to scratch and re-running gave OK exit 0; restoring it reproduced exit 4. It was
the sole cause, and it was never part of the diff.

Why the live gate trips on it. bin/coverage/gate.sh:100 collects untracked files with
`git ls-files --others --exclude-standard` and merges them into the changed set (line 101).
A file with no recognized extension classifies as `unsupported` (line 111); with no project
coverage command configured, unsupported files route to the advisory cannot-measure branch
and the gate exits 4 (line 328). So any untracked, unrecognized-extension file sitting where
the gate scans trips it, whatever its content.

The asymmetry worth remembering. `git diff <base>` - the diff digest formula - excludes
untracked files (see 2026-07-04-the-diff-digest-excludes-untracked-files), so the recorded
gate-report.md status was 0 and accurate for the diff, and the stray could never ship (the
staged-source test stages from `git ls-files`). But the LIVE gate re-run reads the working
tree via `ls-files --others`, so the same file is invisible to the receipt yet breaks the
live re-run. Untracked cuts both ways depending on which git command the consumer uses: the
receipt cannot see the stray, the live gate cannot ignore it.

Operational tell. If a live coverage-gate re-run returns exit 4 cannot-measure while the
recorded receipt says status 0, look for an untracked stray at the repo root before
suspecting the diff or the tools.

The class it widens. This is the second reviewer-side filesystem side-effect to break the
repo. The first was a review subagent running `rm -rf .git` (2026-07-02, no material loss),
which set the standing rule: keep reviewer subagents read-only, and commit or clean
artifacts early. That rule grew out of a destructive deletion; this instance shows a benign
untracked stray is enough to break a live gate. A reviewer that must scribble should write
under the scratch dir, never the repo root.

Ladder: not mechanized. The cheapest defense is the read-only discipline above, which is
hard to enforce mechanically on a subagent. This entry is the reproduction record and the
widened discipline.

Tier: project - the coverage gate, the review orchestration, and the read-only rule are all
Harmonia's own; no client work.
