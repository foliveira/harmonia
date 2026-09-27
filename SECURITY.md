# Security

Harmonia runs shell scripts and agent instructions against a repository you point
it at. Some files in that repository are treated as code, and some are treated as
evidence that a gate ran.

## What Harmonia executes from a repository

Three routes. These are the ones we can name here; this is not an inventory of
every way a payload can reach them.

**`.harmonia/project.yaml`.** No script reads this file.
`core/charters/scoper.md` and `/harmonia:onboard` copy its `test`, `lint`,
`typecheck` and `build` values verbatim into the `- run:` criteria of a scope
declaration you then author, and those execute at review. A repository is meant
to commit this file - that is what `/harmonia:onboard` produces - so a
repository you clone can supply one. The provenance check below cannot see
these values: by the time they run they are inside a file you wrote.

**`.harmonia/tasks/<id>/scope.md`.** The criteria gate executes the scope
declaration's `- run:` lines when `/harmonia:review` invokes it with `--run`.
Task workspaces are gitignored, so this file is normally one you wrote. A scope
declaration a repository carries is refused.

**`.git/config`.** Not narrowed at all, and named here because it is not obvious.
Git config supplies commands git itself runs: `core.fsmonitor` on `git ls-files`,
and `diff.external` or a `textconv` filter on `git diff`. Harmonia runs both
against the repository you point it at, so a delivery that carries a `.git`
directory carries these too. A clone does not - `git clone` writes its own config
- but an archive, a tarball, an rsync or a mounted directory does.

Running Harmonia against a repository you did not write runs the `- run:`
criteria of every scope declaration you author there, from the repository root,
at review. Read a criterion copied from that repository's `project.yaml` the way
you would read a `Makefile` target or a `package.json` script.

## What this version guards

Two independent properties. Containment says where bytes land; provenance says
who put them there. Neither implies the other: a file a repository committed sits
exactly where it belongs and passes every containment test there is.

### Containment

Every workspace write, and every workspace read whose result is a verdict,
refuses a path that is not a real path inside a `.harmonia/tasks/<id>` directory.

The writes: the receipts, the acceptance and rejection markers,
the `done` and `abandoned` markers, the test-immutability manifest, the violations
record, and the mint markers.

The reads: each individual receipt in the audit - not merely the directory holding
them - the `base-ref` file, the test-hash manifest, and the acceptance and
rejection markers.

Symlink positions are not all treated alike, and the difference is deliberate:

- At `.harmonia`, at `tasks`, or at the task directory, the test is a **prefix**
  one. A redirect whose target stays inside the tree the command was pointed at
  is contained and is accepted. Containment says a write did not leave that tree.
  It does not say the tree is yours.
- At a directory **inside** the workspace, or at the artifact file itself, the
  refusal is **unconditional**. A symlink there is refused whether or not its
  target stays in the tree.

The anchor comes from the workspace path itself, not from `--repo`, so the two
differ when they name different trees.

### Provenance

The scope declaration, the base ref, the acceptance marker, the test-hash manifest
and each receipt are refused when the repository carries them. The base ref is on
that list for a reason worth stating: it selects the tree every gate checks, so
a repository that supplies it chooses what gets looked at. Task workspaces are
gitignored, so a carried one is not one you wrote. Without this, a repository
could ship its own `accepted` marker and its own receipts carrying the digest of
an untouched tree, and a fresh clone would report `acceptance verified` and
`receipts verified` with nothing having run.

"Carries" means one of exactly two things: the path is in that repository's
**index**, or it is in the tree of the commit that repository has **checked out**.
Two lookups, both cheap. Nothing else is consulted.

Every repository from the workspace upwards is asked, not just the nearest. A
repository nested inside a delivered tree would otherwise shadow the one that
actually carries the file: the nested one answers "not carried" perfectly
truthfully, because the file is carried by the repository above it.

A level is only a repository if git opens one there. An empty `.git` directory, a
`.git` symlink pointing nowhere, and a gitfile naming a missing directory are not
repositories, and the walk continues past them.

This fails **closed** where git opens a repository and then cannot be trusted to
answer about it: a corrupt or unreadable index, a `core.bare` or `core.worktree`
setting that makes git answer about a different tree, and `GIT_DIR`,
`GIT_WORK_TREE`, `GIT_INDEX_FILE` or `GIT_CEILING_DIRECTORIES` in the environment.
That refusal applies wherever the repository sits in the walk.

**What this deliberately does not answer, and why.** History that is not checked
out is not consulted, and a repository git cannot open at all is not consulted.
So a delivery is accepted if it carries a `.git` whose refs are damaged, whose
HEAD tree object is missing, or which git cannot open — and one that commits the
payload only on a branch that is not checked out. Each of those is the same
exposure as a delivery carrying **no** `.git`, which is accepted too and is a
declared non-goal: provenance is decided by what arrived with the repository, and
an archive or a mounted directory is not distinguished from work you did yourself.
The vector this is built against is the clone, and a clone always has an index and
a resolvable HEAD.

Earlier versions tried to answer more than this. Each attempt needed a way to tell
a damaged repository from a pristine one, and each way was wrong in one direction
or the other — an empty object database was fooled by a removed pack index, and
counting commits refused an ordinary repository between `git add` and its first
commit. Walking all refs instead of the checked-out one refused a live stash and a
colleague's fetched branch, and cost seconds per audit on a large repository. The
narrower promise above is the one that can actually be kept.

A refusal says which case it is. For a carried file the remedy is a freshly minted
workspace: task workspaces are gitignored, so nothing carries them. Removing the
file from the index does **not** clear it on its own, because the checked-out tree
is looked at too. "Cannot be asked" says plainly that it is not a claim the file is
carried; the remedy there is to repair that repository. There is no flag to bypass
either.

### The base ref

The `base-ref` file's **contents** are repository-suppliable, and every git
command here takes that value in argument position, where a value beginning with
`-` is an option rather than a ref. A committed `ref: --output=<path>` therefore
made `git diff` write that path. Values beginning with `-` are now refused before
git is asked anything, and the base is verified before any diff is taken. Git
refnames cannot begin with `-`, so nothing legitimate is refused.

An unresolvable base is not an error: `mint` writes `ref: none` in a tree that is
not a git repository, so a workspace there carries one by design. It digests as
the empty diff, which is what that shape has always recorded.

## What this version does not guard

- The `.gitignore` that mint writes one directory above the workspace is guarded,
  but by a direct symlink check rather than by the containment predicate, since
  it sits outside the directory that predicate is defined over.
- The check is on symlinks. A hard link is indistinguishable from the file it
  links to, passes containment on both the write and the read side, and writes
  through to the same inode.
- A workspace path with only three components anchors at the filesystem root,
  which makes the containment test vacuous for it. This is about the path you
  pass, not only about `/.harmonia/tasks/<id>`.
- A task directory name supplied by a repository is interpolated into receipt
  JSON without escaping, so a crafted name can forge the `gate` field a later
  audit reads. Refusal messages interpolate the same name, so a crafted one can
  use ANSI escapes to rewrite what a refusal looks like on a terminal.
- `scope.md` is read through whatever path it is handed, and the shape-mode read
  has no provenance check at all: that guard runs only under `--run`, because
  shape mode executes nothing and a refusal there would block work no one can
  run. So a repository CAN hand shape mode a declaration of its choosing through
  a tracked symlink - nothing executes, but it gets a passing `check-criteria`
  receipt and satisfies `/harmonia:flow`'s entry gate. Pre-existing; measured
  identical on the base build.
- Containment is about where bytes land, so it does nothing about any execution
  route. The `scope.md` route is narrowed by provenance; the `project.yaml`
  values and the `.git/config` route are not narrowed at all.
- Opening a session in a repository injects text that repository chose: a
  SessionStart hook reads the titles of its `docs/learnings/*.md` into the
  prompt, before any gate. That is prompt injection rather than code execution,
  and it is not closed.

## Posture

Harmonia assumes one user per machine and no concurrent runs against the same
workspace. The guards check and then write; they are not atomic, so a path that
changes in between is not detected.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting: the "Report a vulnerability" button
on this repository's Security tab. It opens a private thread and carries the
disclosure tooling with it.

Please do not open a public issue for a security problem. A report is most useful
with the command or delivery that triggers it and what you expected to happen
instead; this is a personal project, so expect a human-speed reply rather than a
same-day one.
