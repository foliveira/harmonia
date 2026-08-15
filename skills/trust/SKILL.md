---
name: trust
description: Harmonia trust - record your consent, on this machine, to run a repository's .harmonia/project.yaml coverage command. Use ONLY when explicitly invoked as /harmonia:trust.
disable-model-invocation: true
---

This is a human-invoked setup command. Agreeing to run a repository's shell command is a human act: no other skill or agent - flow explicitly, and `/harmonia:onboard` in particular - runs it or `bash ${CLAUDE_PLUGIN_ROOT}/bin/trust.sh record` on the developer's behalf. Onboarding proposes a `coverage:` value; this command is what makes it runnable, and only the developer types it.

Run the recorder against the repository the developer is in and surface its output verbatim:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/trust.sh record --repo .
```

It prints the exact command it is about to make executable, on its own line and byte for byte, before writing. **Read that line and decide.** It is a shell command the coverage gate will run from the repository root at every implement round, at review and in the quick lane, so read it the way you would read a `Makefile` target or a `package.json` script.

**Consent covers that string, and no file.** The record holds the tree's path, the sha256 of the command exactly as the gate will run it, and the date. Change one byte of the command and the gate refuses until a human agrees again. Change anything else and it does not.

**So pointing `coverage:` at a script means trusting that script's contents on every future run**, including contents that arrive after you agreed. `sh .harmonia/cov.sh && echo cov.xml` is consent to run whatever `.harmonia/cov.sh` holds at the moment the gate runs it - and **a repository you clone can change that script** with an ordinary commit, with the `coverage:` line you read left exactly as you read it. A `git pull`, an `npm ci` and a rebuilt virtualenv all do the same thing without a commit. Nothing in the gate looks at any file's contents; only the string is watched.

Earlier versions of this file promised more: that the record covered the contents of the scripts the command ran, so a rewritten script refused. The promise could not be kept and is withdrawn rather than restated. `.harmonia/cov.sh`'s whole job is to run the repository's test suite - hundreds of files no record ever covered - so the digest stopped a rewrite of one file and nothing behind it, and getting past it took no attacker and no skill.

**What you do get is that nothing runs unread.** The exact string was printed and agreed to; it is short enough and plain enough to read; its first word per part is the program; a word where a file belongs is a file rather than an option; no word reaches through a `..` path component; and any edit to it stops the gate until a human agrees again.

**Most commands cannot be recorded, and that is the point.** The recorder **refuses the value** outright, with the offending word and the remedy, while you are there to read it: a value nobody can read honestly is worse than one nobody can run.

<!-- harmonia:grammar-card -->
```
interpreters: sh bash dash python python3 node
inert: echo true
bytes: 1024
words-per-part: 64
byte-class: 0x20-0x7e
```
<!-- harmonia:grammar-card -->

That card is one block carried identically by this file, `SECURITY.md`, `skills/onboard/SKILL.md`, `skills/onboard/CERTIFY.md` and `bin/trust.sh`, and checked against what the recorder admits. Around it: a recordable value is bytes from the card's byte class, up to the byte cap, split by `;`, `&&`, `||` and `|` into parts of at most the word cap, every word made of letters, digits and `_ . , : = + @ / -` (or that inside one matching pair of quotes) and none of them carrying a `..` path **component** - `--out=../x` and `a..b` are ordinary words and are fine; `../x` and `src/../lib` are not. Every part starts with one of:

- an interpreter from the card, bare and exact - `sh`, not `/bin/sh` and not `./sh`. Its next word is the script it runs, must carry a `/`, must not begin with `-` or `+`, and must not sit under `/dev/` or `/proc/` (`sh /dev/stdin` hands the interpreter the pipe beside it instead of a file). Later words go to that script.
- `cd <dir>` - first part only, one operand, followed by `&&`, `<dir>` relative. An absolute one is refused because it is the one `cd` shape decidable from the string alone and costs a single rule; where a relative name leads is a fact about your tree, and nothing here asks the tree anything.
- an inert word from the card.

**A path is not a program**: a first word carrying a `/` is refused, whatever its basename and whatever it points at - `/bin/sh`, `./sh`, `./scripts/cov.sh`, `./gradlew`, `./node_modules/.bin/vitest`, `/usr/bin/env`. That spelling had its own class until the class was measured running the repository's own `fakebin/sh` through `/usr/bin/env PATH=fakebin sh ./cov.sh`. The remedy is one word of typing and it is below.

`make cov`, `npm run cov`, `npx vitest --coverage`, `pytest --cov=src`, `go test ./...`, `sh -e cov.sh`, `sh +x ./cov.sh`, `sh ./cov.sh > out`, `sh *.sh`, `sh ../tools/cov.sh`, `sh cov.sh`, `sh /dev/stdin`, `cd -P`, `cd /etc`, `cd a/../b`, `python3.12 ./cov.py`, `V=1 sh ./cov.sh`, `V+=1 sh ./cov.sh`, `zsh ./cov.sh`, `perl ./cov.pl` and a trailing `# comment` are all refused, and no flag or config key clears the refusal. A bare word not on the card is refused because `PATH` decides what it names and `PATH` is not in the value; `sh cov.sh` is refused one word over for the same reason, and `sh ./cov.sh` is the fix.

**What to do with a command it will not record.** One rewrite, and it always terminates: **put it in a script** the repository commits and record `sh ./.harmonia/cov.sh && echo cov.xml`. Both halves matter - the value ends in `&& echo <report>`, and the script prints **nothing else to stdout**, because the gate captures the whole of stdout as the report path and does not take the last line. Two things about that script were each measured breaking a repository that followed this advice: `sh` is `dash` on Debian, so a wrapper using `[[ ]]`, an array or `set -o pipefail` is recorded as `bash ./<script>`, which is equally recordable; and a chatty tool is quietened by a redirect **inside** the script, since a pipe into `tail` cannot be spelled here at all.

**The shorter rewrite, when the program is itself a script: put a card interpreter in front of it.** `gradle` becomes `sh ./gradlew jacoco`, `mvn` becomes `sh ./mvnw verify`, `npx jest --coverage` becomes `node ./node_modules/.bin/jest --coverage` - no new file, same two conditions. **Which interpreter is a fact about the file, so read its first line.** The three shapes under `node_modules/.bin` need three answers: an npm shim is JavaScript and needs `node`; a pnpm or yarn shim starts `#!/bin/sh` and needs `sh`; a native binary (`esbuild`, `swc`, `biome`) is neither and needs the wrapper above - as does a compiled harness, a perl or ruby script, a launcher (`env`, `nice`, `timeout`, `nohup`, `xargs` have no spelling here at all), `python -m pytest` (the `-m` form puts the cwd on `sys.path` where `python3 ./tools/x.py` does not) and `node --test`, and anything needing `NODE_OPTIONS` or `PYTHONPATH`, which the gate clears. Whether the file behind the name is real, a link out of the tree, or not there yet does not matter: consent covers the name you read.

A script or report path carrying a space or a byte outside the card's byte class cannot be spelled here at all, and has to be renamed.

A `coverage:` value carrying a byte outside the card's class is refused outright with nothing recorded: a **control byte** (including TAB, whose eight columns are how a payload is scrolled off the top of a terminal), because it can leave your terminal showing a command other than the one that would run; and any other byte because the recorder cannot show it to you honestly - a pasted non-breaking space, a smart quote, a zero-width space or a bidi override all read on screen like something they are not.

Read this as a control against a repository that CHANGES ITS COMMAND, and nothing more. You read the command, never the code the command reaches, so a repository that was hostile when you recorded consent already won by putting its payload one step along - and one that becomes hostile afterwards can do it by rewriting a file the command names, which is a commit the gate does not see.

The record is one file kept under `${HARMONIA_HOME:-$HOME/.harmonia}/trust/`, which is outside every repository as long as `HARMONIA_HOME` is unset or absolute: a relative one is resolved against the cwd of whoever runs the gate, so `HARMONIA_HOME=.hh` from a repository root keeps the store inside the tree being measured. Deleting the file withdraws consent, which is why there is no revoke subcommand.

**Consent is keyed by the tree's resolved path.** A repository that moves or is renamed is a tree nobody has agreed to yet and is recorded again - and the other side of that is the sharpest thing to know before relying on any of this: `rm -rf ~/src/foo && git clone <a fork> ~/src/foo`, with a byte-identical `coverage:` line, runs the fork's script under the consent you recorded for the original. Nothing here notices, because nothing here reads a file. If a tree at a path you have recorded consent for is replaced, record again.

The script is the single source of truth - it resolves the tree, reads the command through the same reader the gate uses, and writes the record. Do not fork or reinterpret its logic; report what it prints (the command, the recorded path, or its refusal and exit code).

`disable-model-invocation: true` stops this skill being auto-invoked. It does not stop the script being run, the same way `skills/accept/SKILL.md` treats `workspace.sh accept`: the contract that a human records consent is prose, and what the recorder buys is that executing a repository's command is a named, printed act rather than a silent one.
