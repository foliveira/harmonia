---
title: State the anti-forgery guard once and pin behavior, not phrasing
date: 2026-07-12
tags: [harmonia,testing,process,prose-contracts]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

Found in review of 2026-07-12-capability-gaps (simplifier, test-engineer F3, and
adversarial F7, merged as verdict V3). The workspace is gitignored, so this entry
is the durable carrier.

The state shipped: the single-line / anchored-prefix anti-forgery rationale for
countable records is hand-authored in two lens bodies - core/lenses/regression.md:37-39
("every line single-line, never an embedded newline - the tally counts these
anchored at line start... free text must not be able to forge one") and
core/lenses/adversarial.md's upstream section ("free text single-line only - an
embedded newline could forge a countable line", plus its own per-seam
anchored-count sentences). The design treated it as one decision; the diff states
it twice; no test pins it anywhere.

Why three findings were one item: one seat wanted the guard test-pinned, another
flagged the duplication, and adopting the pin as-is (a literal grep on each
file's sentence) would have hardened the exact duplication. Deduping without a
pin leaves the guard prose free to drift instead. The order matters: dedupe to a
single authority first, then pin at the authority.

The repo norm that sharpens it: roster.bats already pins some grammar as literal
phrasing (tests/roster.bats:120, `grep -qF 'discuss|plan-entry|design'`), so
rewording prose costs test churn even when behavior is unchanged. Prefer pinning
the behavior a consumer counts - the anchored `- regression:hit ` /
`- regression:clean ` prefixes (tests/roster.bats:99-100) - over pinning
rationale sentences. The V1 fix pass in the same task honored this carve-out
deliberately: it pinned the two grammar prefixes and left the guard-rationale
sentences unpinned, so the dedupe stays cheap.

Future shape, liftable into a scope: state the guard once (single authority, as
the charters already do for the record grammar), pin it there, keep rationale
prose unpinned.

Related: the guard itself descends from
2026-07-06-free-text-in-a-line-oriented-marker-can-forge-a-trusted-line-unless-newline-guarded.md,
which is about guarding at the write boundary. This entry is about where the
guard's prose lives and what a test should pin.

Tier: project - the duplicated files, the pin norms, and the tests are this
repo's own surfaces.
