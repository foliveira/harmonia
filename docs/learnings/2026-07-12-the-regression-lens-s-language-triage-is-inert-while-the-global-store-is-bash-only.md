---
title: The regression lens's language triage is inert while the global store is bash-only
date: 2026-07-12
tags: [harmonia,memory,review,process]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

From review of 2026-07-12-capability-gaps (adversarial F3, downgraded to a
capture note after its factual substrate verified).

The lens triages global entries by language tag (core/lenses/regression.md:
tags sharing no language with the diff go straight to not-applicable without a
deep read). Verified at capture: `bash` is the only language token across all
13 global entries, so on this repo's diffs the screen passes everything and
discriminates nothing. The first dispatch still triaged sanely - its nine
not-applicable calls (9 of 13 global entries) came from reading topics, not
from the stated language key. The triage that worked was judgment; the
mechanism as written is inert.

Adjacent verified fact: repo_langs (bin/memory/store-lib.sh) derives a repo's
languages from every file extension in it, so tests/fixtures/sandbox/main.go
makes this repo count as go alongside bash and yaml. A fixture can add a
phantom language to recall's filter and to any consumer keying on repo_langs.

Design-rationale correction, for the record: the design claimed the triage
"reuses recall's own relevance rule". It does not - recall keys repo_langs
(repo-wide extensions) against index tags; the lens keys the diff's languages
against entry tags. Two different keys; no shipped surface claims otherwise.

The queued improvement: when the store grows past bash-heavy, or the
whole-store read starts to weigh on review (the adversarial seat flagged a
store-scale ceiling; its threshold estimate was labeled SPECULATION and was
not preserved outside the panel exchange), give the triage a real key - the
topic tokens already in every entry's tags, matched against the diff's touched
surfaces. Until then the language screen costs nothing and catches nothing
here.

Tier: project - the lens, recall.sh, and store-lib.sh are this repo's own.
