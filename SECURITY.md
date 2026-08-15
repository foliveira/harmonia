# Security

Harmonia runs shell scripts and agent instructions against a repository you point
it at. Some files in that repository are treated as code, and some are treated as
evidence that a gate ran.

## What Harmonia executes from a repository

Five routes. These are the ones we can name here; this is not an inventory of
every way a payload can reach them.

**`.harmonia/project.yaml`.** The coverage gate runs the `coverage:` value as a
shell command from the repository root, at every implement round, at review, and
in the quick lane. A repository is meant to commit this file - that is what
`/harmonia:onboard` produces - so a repository you clone can supply one. There is
no provenance check on it, because a tracked `project.yaml` is the legitimate
case. What that value now needs instead is consent: it runs only when a record
under `${HARMONIA_HOME:-$HOME/.harmonia}`, written by `/harmonia:trust`, is keyed
to this tree's physically resolved path and carries the digest of this exact
command. A cloned `project.yaml` has no record here and is refused; an edited
command no longer matches and is refused. A value whose shape the recorder cannot
show you honestly - which is most of them, including `make cov`,
`npx vitest --coverage` and `pytest --cov` - **cannot be recorded at all**, and
the remedy is to put it in a script of your own and record that. Consent covers
the string and no file, so a script the value names runs with whatever it
contains at that moment; see **Consent** below.

That file's reach is wider than the one `coverage:` value. `core/charters/scoper.md`
and `/harmonia:onboard` copy its `test`, `lint`, `typecheck` and `build` values
verbatim into the `- run:` criteria of a scope declaration you then author, and
those execute at review. The provenance check below cannot see them, and neither
does the consent record - it covers the `coverage:` value only, because that is
the one a code path executes. By the time the other four run they are inside a
file you wrote.

**The coverage adapters.** `bin/coverage/bash.sh` runs the repository's own
`tests/*.bats` under kcov; its `ts.sh` and `go.sh` siblings run the repository's
vitest and `go test ./...`. That is a clone's own code, executed by us, and after
the consent record above it is the cheapest remaining route. Closing it means not
measuring coverage, so it is not closed. Note the inversion the record creates:
the committed-filename route below fires only when there is no `coverage:` value
to run, so refusing an unattested one pushes an attacker towards it.

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

**A committed filename.** The coverage gate detects a language by substituting a
changed file's name into a shell script (`xargs -I{} bash -c 'f="{}"' ...`), so a
repository that commits a file whose NAME contains `$( )` executes it. This needs
no config file and no `.git` delivery - a plain `git clone` carries it, and the
gate reaches the branch on any repository with no `.harmonia/project.yaml`. Worse
than it first looks: the command runs with the cwd of whoever invoked the gate,
not of the repository being measured, so the payload lands in *your* tree rather
than in the clone. Reproduced against this repository by accident while checking
the claim - the file appeared at this repo's root. Not closed in this version.

Running Harmonia against a repository you did not write still runs that
repository's test suite through an adapter, and runs its `coverage:` command once
you have agreed to it. Read that command the way you would read a `Makefile`
target or a `package.json` script - `/harmonia:trust` prints it to you, byte for
byte, before it records anything, and that reading is the control. It is the
whole of the control: the command is what you read, and the code the command
reaches is not.

## What this version guards

Three independent properties. Containment says where bytes land; provenance says
who put them there; consent says whether anyone here agreed to run a string. No
one implies another: a file a repository committed sits exactly where it belongs
and passes every containment test there is.

### Containment

Every workspace write, and every workspace read whose result is a verdict,
refuses a path that is not a real path inside a `.harmonia/tasks/<id>` directory.

The writes: the gate report, the receipts, the acceptance and rejection markers,
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
that list for a reason worth stating: it selects the tree every gate measures, so
a repository that supplies it chooses what gets looked at, which is how a clone
reached the filename route above on a fresh checkout with no `--base` given. Task workspaces are
gitignored, so a carried one is not one you wrote. Without this, a repository
could ship its own `accepted` marker and its own receipts carrying the digest of
an untouched tree, and a fresh clone would report `acceptance verified` and
`receipts verified` with nothing having been measured.

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

### Consent

One question, asked once, immediately above the line that would run a
repository's `coverage:` value: has a human on this machine agreed to **this
exact string** for this exact tree. The answer lives in one file outside every
repository, under `${HARMONIA_HOME:-$HOME/.harmonia}/trust/`, written by
`/harmonia:trust` and holding three things - the tree's path, the sha256 of the
command as the gate will run it (after one quote layer is stripped, which is what
`eval` receives), and when it was agreed to. No record, a record naming another
tree, one nothing can read, a value the grammar refuses, or a different digest of
the command: the gate refuses with `cannot measure`, runs nothing, and writes no
report and no receipt.
A truncation refuses when it reaches either of the first two lines; one that eats
only the trailing `recorded:` line leaves the record semantically complete and
still attesting, and nothing reads that line. A receipt written at refusal time
would be fresh by construction, and the audit would then certify a tree nothing
measured. The gate asks the grammar again before it compares the digest, so the
string it parses is whatever the `coverage:` value holds at that moment and not
one a record has already matched: a record whose tree and whose digest both match
still refuses when the value it covers has fallen outside the grammar since it
was written. What that is for is in the migration paragraph below.

**Consent covers the string. It covers no file.** Nothing in the consent path
opens, hashes or stats anything a `coverage:` value names, so the one thing that
withdraws consent is an edit to the command itself. What that means for a value
that names a script - which is nearly all of them - is stated here rather than
left to be worked out: **pointing `coverage:` at a script means trusting that
script for whatever it contains on every future run, including contents that
arrive after you agreed.** A `git pull` that rewrites it, an `npm ci` that
replaces a tool under `node_modules/`, a commit that repoints a symlink, a build
that creates a file the value already named: each runs new code under the old
consent, and none of them touches the line you were told to re-read. A repository
you clone can do all of it.

Earlier versions of this guard digested the named files too, and this file
claimed the stronger promise in the place the code did not deliver it, four times
running. The promise is withdrawn rather than restated, because it could not be
stated honestly at any width: `sh .harmonia/cov.sh` names one file whose whole
job is to run the repository's suite, so the digest stopped the rewrite of that
one file and nothing behind it, and evading it needed no attacker and no skill.
The paragraph that used to argue the other way - that a digest over the string
alone leaves a later commit free to rewrite the script while the line you were
told to re-read stays exactly as you read it - is exactly right, and is now the
statement of what you give up rather than the reason for a mechanism.

What is left is not nothing, and it is the part that never failed: **nothing runs
unread.** The exact bytes were printed and agreed to; the value is short enough
and plain enough to read; the first word of each part is the program that runs; a
word where a file belongs is a file rather than an option; no word reaches
through a `..` path component; and any edit stops the gate until a human agrees
again.

If you onboarded a repository before this shipped, its `coverage:` value stops
running until you invoke `/harmonia:trust`, because no record for it exists here
at all. A record written by any earlier version carries the two lines this reads,
so it still attests and its extra lines are ignored text - but only while the
value it covers is one the grammar admits, because the gate asks the grammar
again above the `eval` rather than trusting the record to have been written by
this recorder. A record covering a value the grammar has since narrowed away
stops attesting, and it says so in those words rather than telling you to record
consent for a value that cannot be recorded. Once is enough only for a value the
grammar admits; for `make cov` or `npx vitest --coverage` - the two this file
uses as examples two sections up - the recorder refuses in turn and the value has
to be rewritten first, so the path is gate refusal, then skill, then recorder
refusal, then one rewrite. The refusal names the file to read and the command to
type at every step, and it fires at every implement round, at review and in the
quick lane, so the discovery path is the refusal itself.

The key is the tree's **physically resolved path** and nothing else. No answer
git gives contributes, and each exclusion is a measured attack rather than a
preference: the remote URL is chosen by the clone, and `coverage:` values are
near-canonical per language, so copying a public `project.yaml` verbatim matches
on both halves; the git common dir is supplied by a delivered `.git` gitfile; the
toplevel is answered by a tree delivered inside an attested repository with no
`.git` of its own, and is redirected by a delivered `core.worktree`. A build
keyed on the toplevel passed every criterion this task had as first drafted and
still executed a payload from that third shape. Lookup is exact equality on the
resolved path - nothing walks upwards - so a tree at `<attested>/vendor/evil`
inherits nothing.

**Only some commands can be recorded at all, and the grammar is the second half
of the promise.** A digest is worth what the string is worth, so the string has
to be one a person can read and be right about: the first word of a part has to
be the program that runs, and a word standing where a file goes has to be that
file. Deciding either over an arbitrary shell command is unbounded - a rule that
read every token called the interpreter the program for `/bin/sh cov.sh` and
found nothing at all in `env`, `exec`, `nohup`, `.`, `VAR=1 ./x.sh`, `sh <x.sh`
and `sh -c '…'` - so the shapes that can be recorded are enumerated, with no
fallback arm, and everything else is refused while you are standing in front of
the refusal.

Admission is a **pure function of the string**. Nothing in it asks the filesystem
anything, which is what makes "the same value gets the same verdict" a property
with a test rather than a hope.

The grammar is one block, carried identically by this file,
`skills/trust/SKILL.md`, `skills/onboard/SKILL.md`, `skills/onboard/CERTIFY.md`
and `bin/trust.sh`, and checked against the set the recorder actually admits -
five prose copies of one list drifted twice before it existed:

<!-- harmonia:grammar-card -->
```
interpreters: sh bash dash python python3 node
inert: echo true
bytes: 1024
words-per-part: 64
byte-class: 0x20-0x7e
```
<!-- harmonia:grammar-card -->

A recordable value is bytes from the card's byte class within the byte cap, split
by `;`, `&&`, `||` and `|` into parts within the word cap, where every word is
`[A-Za-z0-9_.,:=+@/-]+` or that inside one matching pair of quotes and carries no
`..` path component - `--out=../x` and `a..b` are ordinary words and are fine,
`../x` and `src/../lib` are not - and every part begins with one of exactly nine
words:

| the part begins with | and the rule that goes with it |
| --- | --- |
| an interpreter from the card, spelled bare and exact | the next word is the script it runs, has to carry a `/`, may not begin with `-` or `+`, and may not sit under `/dev/` or `/proc/`. Later words go to that script |
| `cd <dir>` | first part only, one operand, followed by `&&`, and `<dir>` spelled relative. Everything after it is read from where it lands |
| an inert word from the card | nothing follows from it |

**A path is not a program.** A first word carrying a `/` is refused - whatever
its basename, whatever it points at, and in every part of the value. `/bin/sh ./cov.sh`, `./sh ./cov.sh`,
`/usr/bin/env sh ./cov.sh`, `./scripts/cov.sh`, `./gradlew jacoco` and
`./node_modules/.bin/vitest run --coverage` are all outside the grammar. That is
the sharpest cost this file describes and it is deliberate: rounds 3, 4 and 5
each gave a `/`-carrying first word a class of its own and each left a way in one
spelling over, the last of them by leaving a launcher's later words unconstrained
so that `/usr/bin/env PATH=fakebin sh ./cov.sh` recorded and ran the repository's
own `fakebin/sh`. There is nothing left to constrain once the class is gone.

Nothing in that table is a claim about a file's contents, and no row digests one.

Anything else is refused: `make cov`, `npm run cov`, `npx vitest --coverage`,
`pytest --cov=src`, `go test ./...`, an assignment in front of the program
(`V=1 sh ./cov.sh`, and `V+=1 sh ./cov.sh`, which is the spelling that made an
earlier rule call the assignment the program while bash preloaded a file through
it), an option where a script or a directory belongs, `cd -P`, `cd /etc`, a `..`
path component, a slash-less script operand (`sh cov.sh`, which searches `PATH`
and runs a file the value does not name), a redirection, a glob, a `$(...)`, a
variable, a trailing `# comment` (`bin/coverage/config-lib.sh` is not a YAML
parser and does not strip one), a name that is a near miss on the card such as
`python3.12`, and an interpreter the card dropped such as `zsh` or `perl`. There
is no allow-list, no `--force` and no opt-out: a refusal a tool can clear is not
consent.

Two rewrites get a repository back inside the grammar, and between them they
cover everything the list above refuses.

**Put a card interpreter in front of the file.** `./gradlew jacoco` becomes
`sh ./gradlew jacoco`, `./mvnw verify` becomes `sh ./mvnw verify`,
`npx jest --coverage` becomes `node ./node_modules/.bin/jest --coverage`, and
`./tools/cov.py` becomes `python3 ./tools/cov.py`. **Which interpreter is a fact
about the file, so read its first line.** The three shapes that ship under
`node_modules/.bin` need three different answers: an npm-style shim is a
JavaScript file and runs under `node`, a pnpm or yarn shim starts `#!/bin/sh` and
runs under `sh`, and a native binary (`esbuild`, `swc`, `biome`, `turbo`) runs
under neither.

**Or put the command in a script of your own** and record
`sh ./<script> && echo <report>`, which always terminates. This is the only
rewrite for anything that is not a script in one of the card's six languages: a
compiled test or coverage binary, the native tools above, and scripts in perl,
ruby, php, zsh, deno or bun. A launcher belongs here too - `env`, `nice`,
`timeout`, `stdbuf`, `nohup`, `setsid` and `xargs` have no in-grammar spelling at
all - and so does anything that needs `NODE_OPTIONS` or `PYTHONPATH` set, since
the seam clears both.

Both rewrites need the value to end in `&& echo <report>` with nothing else on
stdout, because the gate reads the whole of stdout as the report path. What
cannot be rewritten at all is a script or report path carrying a space or a byte
outside the card's class; that file has to be renamed.

The recorder prints the command, byte for byte, on its own line, then one
sentence saying what consent does not cover, and then writes. There is no list of
files, because there is no set of files for a list to be about - and the two
defects the old list produced went with it: a repository chose the annotation on
the one line these documents call the control, and a resolved path was labelled
as sitting outside the repository while sitting one directory up inside the same
one.

**What a repository still decides, with consent intact.** The repository picks
which files the command reaches. A committed symlink can point `cov.sh` or a `cd`
operand anywhere on the machine, and the words you agreed to stay the same. A
script named by the value can be absent when you agree and appear before the
first gate run. `python3 ./pkg` runs `./pkg/__main__.py` and `node ./pkg` runs
`./pkg/index.js`; what an interpreter does with an operand is not modelled.
`echo <report>` with a checked-in report attests, because nothing executes, and
coverage integrity against a repository's own report is a different property this
file does not claim. ASCII homoglyphs (`tools/l.sh` against `tools/I.sh`) are not
addressed. Read all of it as a control against a repository that changes **the
command**, and nothing wider: a repository already hostile when consent was
recorded wins by putting its payload one step along, and one that turns hostile
afterwards does it by rewriting a file the command names.

The seam that runs the value - the subshell at `bin/coverage/gate.sh` - clears a
list rather than the environment, and the list cannot be completed. What it
clears, and why each name is on it:

- `CDPATH`, because POSIX `cd` searches it before the current directory and an
  ordinary `CDPATH=$HOME/src` in a `.bashrc` sends the one `cd` the grammar
  admits into a sibling tree - no attacker required.
- `PATH`, down to the entries that are absolute and land outside the repository,
  because the card's list is a claim about the machine's interpreters:
  `PATH_add node_modules/.bin` in an `.envrc` is repository content that makes a
  bare `sh` mean the repository's own. Relative entries go too - the gate's own
  `cd "$REPO"` is what would move them inside - and entries are compared as
  directories rather than as strings, so `//repo/bin` and a symlinked parent go
  with the plain spelling. When that leaves nothing, `PATH` becomes
  `/usr/bin:/bin` and not the empty string: an empty `PATH` makes bash search the
  current directory, which after the `cd` is the repository.
- `BASH_ENV`, `ENV`, `LD_PRELOAD`, `PYTHONSTARTUP`, `NODE_OPTIONS` and
  `PYTHONPATH`, because three of the six card interpreters take code from the
  environment: `BASH_ENV` runs a file before bash reads the script it was given,
  `NODE_OPTIONS=--require` does the same for node, and `PYTHONPATH` plus a
  `sitecustomize.py` does it for python3. An `.envrc` exports arbitrary names,
  not only `PATH_add`. A repository that legitimately needs `NODE_OPTIONS` or
  `PYTHONPATH` sets them inside its own wrapper script, which is committed and
  readable.

What it does **not** clear, said here because a denylist that hides its edge is
worth less than one that shows it. `SHELLOPTS` and `BASHOPTS` are readonly in
bash and cannot be unset at all; `BASHOPTS=nocasematch` reaches the seam.
`LD_LIBRARY_PATH` stays inherited on purpose - it is a toolchain input for nix
and conda, not a way into a card interpreter - and no list of names is complete.
All of this sits inside one declared class: an actor who can write an absolute
`PATH` entry outside the repository, set the gate's environment, or replace
`/bin/sh` itself has already won and is outside this model.

A `coverage:` value carrying a byte outside the card's class is refused when
consent is recorded, and nothing is written. Two refusals share the rule because
a reader needs different things told. For a **control byte** - anything below
`0x20`, TAB included, or `0x7f` - the reason says so: `bin/coverage/config-lib.sh`
strips only surrounding blanks, so an interior carriage return or `ESC[2K`
survives into the printed line, the digest and the `eval`, and the shell stops at
a `#` while the terminal returns to column zero or erases the line and is left
showing a benign tail. TAB is in that class because the byte cap is a reading
bound: 1024 TABs is 8192 columns, 83 wrapped lines, with the payload scrolled off
the top of the terminal. For any other refused byte the reason names the byte and
its offset, because the common instance is invisible: a pasted U+00A0, a smart
quote, U+200B, and U+202E, which is CVE-2021-42574 and reorders the rendered line
in any renderer implementing the bidi algorithm. Every one of those is `>= 0x80`
in UTF-8 and dies on the same rule as an accented letter, which is what keeps
this from being a list of codepoints somebody has to maintain; the declared cost
is that a `coverage:` value carrying `é` can no longer be recorded. It is refused
rather than escaped on the way out, because an escaped display form is a second
string to keep honest against the one that executes, and this file names the
printed line as the control.

**Consent is bound to a path, not to a repository, and this is the sharpest thing
to know before relying on it.** Delete an attested repository, clone a fork to
the same path - `rm -rf ~/src/foo && git clone <fork> ~/src/foo` - and if the new
`coverage:` line reads back identically, the old record still attests it and the
fork's script runs. Reproduced. Equality is on the value
`bin/coverage/config-lib.sh` returns, not on the file's bytes: surrounding blanks
and one layer of quotes are stripped first, so `coverage:   "echo cov.xml"   `
inherits a record written for `coverage: echo cov.xml`. Digesting the named files
used to narrow this and no longer does. There is no fix inside this key: a
witness that could tell two repositories apart at one path is either git-derived,
and so repository-suppliable, or metadata that does not survive ordinary
handling. Both were measured - mtimes are set by whatever wrote the files, and
the root directory's inode changes on a delete-and-re-clone while staying put
under `git pull`, so keying on it would refuse every move, restore and container
rebuild without refusing this. What is offered instead is that the record is one
file you can delete, and that the recorder prints the path and the command before
it writes. If a tree at a path you have recorded consent for is replaced, record
again.

The record is out of a repository's directory, not out of its reach. A delivery
carrying `.git` supplies `core.fsmonitor`, which git runs at
`bin/coverage/gate.sh:169` - before the consent question is asked, and it is the
route `.git/config` above describes - so code from that delivery can write a
well-formed record for its own tree. It gains an attacker nothing they do not
already have at that point, which is why it is a disclosure rather than a guard:
store integrity beyond readability is a declared non-goal below.

The price of a key a repository cannot choose is that a moved, renamed or
re-cloned repository is a tree nobody has agreed to yet, and is recorded again.
Each git worktree records separately: `bin/memory/store-lib.sh:3,10` calls its
own identity worktree-safe on purpose, and this one is deliberately not, so two
stores under one root answer opposite questions. A throwaway worktree that gets
attested leaves a record nothing prunes.

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

- `gate.sh --record-override` appends to `.harmonia/coverage-exemptions.yaml`,
  which is not a task workspace and is not guarded. Through a symlinked
  `.harmonia` it still appends outside the repository.
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
  route. The `scope.md` route is narrowed by provenance, the `project.yaml`
  `coverage:` value by consent; the `.git/config` route is not narrowed at all.
- `bash bin/trust.sh record` can be run by an agent exactly as
  `bash bin/workspace.sh accept` can. `disable-model-invocation: true` stops the
  skill being auto-invoked, not the script being executed. What the record buys
  is that running a repository's command is a named, printed act instead of a
  silent one - not that only a human can record it.
- `HARMONIA_HOME` is trusted, and taken exactly as given. The store's location is
  environmental - `$HOME` is an environment variable too - so
  fail-closed-on-the-environment, which the `GIT_*` names get, is not available to
  a home-directory store. Anyone who can set the gate's environment can run the
  command directly, so the record is not built against them. One consequence is
  worth naming, because "outside every repository" is said without qualification
  elsewhere: a RELATIVE value is resolved against the cwd of whoever runs the
  gate, so `HARMONIA_HOME=.hh` from a repository root keeps the store inside the
  tree being measured.
- Store integrity beyond readability is out: no ownership check, no permission
  check, and nothing about a `~/.harmonia` that is a git repository or a synced
  dotfiles directory. Anyone who can write there can write `~/.bashrc`. A home
  directory synced between machines carries attestations to a machine where the
  same path may name a different repository.
- There is no revocation command and no expiry. Deleting the record is the
  remedy, which is why `/harmonia:trust` prints the path it wrote.
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
on this repository's Security tab. That is the preferred route - it opens a
private thread and carries the disclosure tooling with it.

If you cannot use it - no GitHub account, or the button is not there - mail
fabio.an.oliveira@gmail.com instead, with `harmonia security` in the subject.

Either way, please do not open a public issue for a security problem. A report is
most useful with the command or delivery that triggers it and what you expected
to happen instead; this is a personal project, so expect a human-speed reply
rather than a same-day one.
