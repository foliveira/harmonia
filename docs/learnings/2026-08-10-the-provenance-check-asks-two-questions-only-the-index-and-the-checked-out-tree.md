---
title: The provenance check asks two questions only: the index and the checked-out tree
date: 2026-08-10
tags: [bash,git,harmonia,security,provenance,gates]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

What shipped in bin/base-ref-lib.sh (`ws_tracked` and `_repo_claims`) after round 9 of
2026-08-01-public-release. Recorded because the visible record disagrees with the code: the
task's diff-summary.md is round 7 and verdict.md is round 8, and both describe a mechanism
this build deleted.

The property, and it is the whole property:

> A workspace artifact is refused when a repository at or above it has that path in its
> INDEX (`git ls-files --error-unmatch`), or in the tree of the commit that repository has
> CHECKED OUT (`git rev-parse --verify HEAD:<path>`).

Nothing else is consulted. There is no `log --all`, no `rev-list --all`, no object-database
scan, no pristine-versus-damaged discriminator and no `nearest` position flag. All of those
existed through round 8 and were removed, each having produced a blocker or a false refusal.

So these deliveries are ACCEPTED deliberately, and a patch that starts refusing them again is
a regression, not a hardening:

- refs damaged so HEAD cannot resolve, and a missing HEAD tree object
- a dangling or looping `.git` symlink, and a gitfile pointing nowhere
- an unreadable `.git`, and an unknown `core.repositoryformatversion`
- a payload committed only on a branch that is not checked out
- an unusable `.git` in an unrelated ancestor directory

Six of those are asserted on the ACCEPT side of the criteria and print
`RETIRED-SHAPE-REFUSED` when a build refuses them: C12 (unknown repository format, dangling
gitfile, unreadable `.git`), C16 (dangling and looping `.git` symlink), C17 (missing HEAD
tree object, damaged refs). The branch-that-is-not-checked-out row has no cell on either side,
so that one is held by prose alone.

What still refuses, at every level of the walk and with no position rule: a repository git
DOES open but whose index it cannot read (missing, corrupt or unreadable), `core.bare`, a
redirected `core.worktree`, and `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE` or
`GIT_CEILING_DIRECTORIES` in the environment. A level counts as a repository only when
`git rev-parse --git-dir` succeeds there; the walk passes anything else by.

Why the narrower promise is defensible here rather than everywhere. The measured vector is
`git clone`, and clone always writes an index and a resolvable HEAD, so the clone class stays
closed. Every retired shape needs delivery by archive, tarball, rsync or mount, and that
delivery class is already a declared non-goal in the scope declaration: a tree carrying no
`.git` at all is not distinguished from work you did yourself, which is a strictly larger
hole than any row above.

The repo fact that drives the design, and the one to check any future candidate against:
`mint` writes `*` into `.harmonia/tasks/.gitignore`, so every legitimate workspace artifact is
gitignored and a provenance question about an honest artifact always takes the not-found path.
A check that is cheap on the hit and expensive on the miss is expensive on every honest run;
that is exactly how a 13.2s receipt audit shipped in round 7 (see the global entry on
`git log --all` and absence).

Reading order for anyone picking this up: SECURITY.md's Provenance section is the shipped
public statement and is current. scope.md's "Round 9" section supersedes earlier sections of
that same file. diff-summary.md and verdict.md describe the deleted mechanism.
