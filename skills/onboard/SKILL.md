---
name: onboard
description: Harmonia onboard - capture an existing repo's canonical verify commands and its own coverage command into .harmonia/project.yaml. Use ONLY when explicitly invoked as /harmonia:onboard.
disable-model-invocation: true
---

Your working contract is the 4 rules; their digest is injected at session start - read `${CLAUDE_PLUGIN_ROOT}/core/RULES.md` in full only if that digest is not in your context.

Attach Harmonia to a repository it did not scaffold. You capture the repo's own
verify and coverage commands into `.harmonia/project.yaml` so the scoper authors
success criteria against the repo's real commands and the coverage gate measures
the repo with the repo's own tool instead of falling back to a built-in adapter.

This is not a lifecycle stage: it mints no task workspace and writes no marker or
receipt. It writes exactly one file - `.harmonia/project.yaml` at the repo root -
which the onboarded repo is meant to commit. On a second run it refines that file
in place; see step 5.

The interview, the run-before-record step, the end-to-end coverage certification,
and the refine step are yours to carry out honestly. They are a prose contract, on
the same footing as human acceptance today, not a technical guarantee.

## The file you write

`.harmonia/project.yaml` is flat: one scalar per line, known keys only, no nesting
and no arrays. Its reader is a bash line-reader, not a YAML parser, so each value
sits on a single physical line.

```yaml
# .harmonia/project.yaml - this repo's canonical verify commands and its own
# coverage command. Read by the scoper (the four verify commands) and by the
# coverage gate (the coverage command). Written by /harmonia:onboard; safe to
# hand-edit; commit it.
test: <shell command>
lint: <shell command>
typecheck: <shell command>
build: <shell command>
coverage: <shell command>
```

Each value is a single bare command on one physical line. The reader does not
strip a trailing `# comment`, so leave no `#` on a value line - it would become
part of the command. Typical values: `go test ./...`, `npx vitest run`, or
`bats tests/` for `test`; `golangci-lint run` or `npm run lint` for `lint`;
`tsc --noEmit` or `npm run typecheck` for `typecheck`; `go build ./...` or
`npm run build` for `build`. The `coverage` value runs on the current tree and
prints ONLY a report path; see step 3.

## Steps

1. **Interview for the four verify commands - do not guess them.** Elicit this
   repo's canonical commands in four categories from the developer: `test`, `lint`,
   `typecheck` (or `type-check`), and `build`. Ask; do not infer them from a glance
   at the tree.

2. **Prove each verify command works before recording it.** The discipline is:
   prove it works before recording it. Run each candidate once, from the repo root,
   and record it only when it exits 0. Reject it on ANY non-zero exit - gate on
   non-zero, not on an enumerated code set. Judge it by exit status, never by
   pattern-matching its output. A command that does not run is not written as if it
   did.

3. **Capture the coverage command and CERTIFY it end-to-end before recording it.**
   The coverage command is a full shell command the gate runs on the current tree
   each invocation. It must silence tool chatter and print ONLY the report path on
   stdout; the report must be diff-cover-readable Cobertura XML with repo-relative
   filenames. A canonical shape, for python:

   ```
   pytest --cov --cov-report=xml:cov.xml >/dev/null 2>&1 && echo cov.xml
   ```

   Exit 0 alone is not enough. Before recording the command, read
   `${CLAUDE_PLUGIN_ROOT}/skills/onboard/CERTIFY.md` and apply all five checks it
   defines; record only if every one passes, and reject on the first failure.

4. **Advise, do not scaffold, when no coverage tool is found.** If the repo has no
   coverage tooling for its language, or a candidate cannot be certified because no
   tool exists, be advise-only: name a suitable tool for the detected language and
   how to make it emit a diff-cover-readable, repo-relative report - for example
   pytest-cov (`--cov-report=xml`) for python, SimpleCov with a Cobertura formatter
   for ruby, cargo-llvm-cover emitting Cobertura for rust, or jest with a Cobertura
   reporter for js. The developer sets it up and re-runs onboarding to certify.
   Onboarding writes no config files and touches no CI.

5. **Refine in place on re-run.** One `.harmonia/project.yaml` per repo. If the
   file already exists, read it and update only the keys that changed, preserving
   the rest; never clobber it from scratch. A second run refines the file in place.
