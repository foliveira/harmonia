# Contributing

Harmonia is a personal SDLC that I use on my own work, so it carries strong opinions about how change happens. Issues and pull requests are welcome; the opinions below are not incidental, and a change that works against them is likely to be declined even if the code is good.

## Toolchain

```
bats  jq  yamllint  check-jsonschema  kcov  diff-cover
```

`gocover-cobertura` is needed only if you touch the Go coverage adapter. The engine itself is bash and YAML — there is nothing to build.

## The checks

```bash
bats tests/                                  # the whole suite
bin/validate-core.sh                         # lifecycle YAML, schema conformance, lens resolution
bin/coverage/gate.sh --self --base <ref>     # the coverage gate, dogfooded on this repo
```

CI runs the first two on every push and pull request. It deliberately does **not** run the coverage gate yet: the adapters leak a temp directory per run and a kcov killed mid-run currently reports `gate: OK` rather than failing closed, so a green check would not mean what it appears to mean. Both defects are written up in `docs/learnings/`. Run the gate locally on anything touching `bin/`.

## How change happens here

This repo is built with the tool it ships, and the process is not ceremony — it is where the value is. A change of any size goes through a pinned scope with machine-checkable success criteria, a red-green implement loop, and a review whose verdict is written down. If you have Harmonia installed, `/harmonia:discuss` then `/harmonia:flow` is the path.

Three rules matter most for a contribution:

- **An abstraction needs a current consumer.** Speculative flexibility gets removed in review. Prefer deleting to configuring.
- **Touch only what the change requires.** Adjacent improvements become their own issue, not riders on this one.
- **Done is decided by a gate, not by inspection.** If a property matters, something has to fail when it breaks.

## Tests

Tests lead. Write the failing test first and make sure it fails for the reason you think — a test that errors on a missing helper is broken, not red.

Two things the review checks specifically:

- **No test is weakened.** Assertions are not deleted, loosened or retitled to make a build pass. If a change genuinely retires a behaviour, move that test to the other side so a build still doing the old thing goes red — do not delete it.
- **Cover both directions.** A guard needs cells proving it refuses what it should *and* cells proving it still accepts legitimate input. Reject-side tests alone have shipped real over-refusals here.

Coverage on changed lines is 100%, a soft block. Exemptions are in-code markers carrying a justification (`# harmonia:exempt <why>`) and they are read in review — restructuring so a line is genuinely exercised is almost always the better answer.

## Commits

Single concern per commit, and a message that says what the change does and why. Describe the shipped behaviour rather than the journey: no round numbers, no narration of what was tried and abandoned.

## Security

Do not open a public issue for a vulnerability. `SECURITY.md` carries the trust model, the routes that are deliberately open, and how to report privately.
