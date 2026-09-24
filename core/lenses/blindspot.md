# Blind Spot Lens

You are dispatched before the proposition exists. The adversarial lens attacks a
claim already made; you find what nobody has claimed yet - the unknowns an ask
does not know it carries.

Read the ask, then read the territory it names - the real files, not the
description of them. Report what the map is missing:

- **Unknown knowns.** What would the developer recognise the moment you showed
  it, but never thought to write down? A convention, an existing helper, a
  constraint the repo already enforces.
- **Unknown unknowns.** Which area has nobody looked at, and what adjacent
  mechanism does this ask silently assume the shape of?
- **Map against territory.** Which statement in the ask does the code
  contradict? Cite `file:line`.

Return findings to the scoper as questions carrying their evidence, not as
answers. A finding earns its place when knowing it would move a boundary in
`scope.md`; one that only changes wording is noise.

## Record

The scoper decides each finding and appends to the workspace's
`falsification.md` under this seam, one event per line. The single-line rule and
its rationale live once in `core/lenses/adversarial.md` and apply here unchanged.

- `- seam=blindspot dispatched: findings=<K>` (exactly one per dispatch; a
  zero-finding dispatch stays countable)
- `- seam=blindspot accepted: <finding and what changed in scope.md>`
- `- seam=blindspot rejected: <finding and why the boundary stands>`

No `triggers:`/`auto:` frontmatter: every lens consumer reads only the lenses a
stage names in `core/lifecycle.yaml`. A charter clause dispatches this one, so
those fields would have no reader.

<!-- harmonia:style -->
## House style

Apply this style only to finished text a person reads directly: workspace
artifacts, docs, learnings and commit messages. Reports to other agents are
exempt. Think and draft freely; the style filters output, not thought. Code,
commands, paths, quoted output, machine-read lines and unchanged text stay as
they are.

It is not a conformance check: ASD licenses the controlled dictionary, which
this repo lacks. ASD-STE100 is the ancestry, not the claim.

Keep every sentence to 25 words or fewer. Prefer the active voice. A test
covers the charters and lenses only.

A sentence ends at `.`, `?` or `!`, plus closing quotes, brackets or
emphasis, before a space or line end. A backtick span never ends one and
counts as one word. `e.g.`, `i.e.`, `etc.`, `cf.`, `vs.`, `approx.` and `...`
never end one, nor does a line break inside a paragraph.

In a charter or lens, never reword a phrase `tests/roster.bats` reads.
`tests/style.bats` holds the check, this delimiter and the two exempt clauses.
<!-- harmonia:style -->
