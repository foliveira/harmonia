---
title: Global learnings without a language tag are unreachable by recall
date: 2026-07-02
tags: [bash,harmonia,memory,process]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

Found during the capture stage of 2026-07-02-adlc-adoptions, first-hand.

Reproduction:
- command: bash bin/memory/capture.sh --title "..." --tier global --tags process,scoping,harmonia
- observed: exit 0, "captured: global/...". Then bash bin/memory/recall.sh --repo .
  (repo languages: bash, go, yaml) omits the new entry while the three older
  global entries - each tagged bash - all surface.

Mechanism, verified at the line: recall.sh keeps a global index line only when at
least one of its tags appears in repo_langs' output, and repo_langs
(bin/memory/store-lib.sh:22-35) recognizes only file-extension languages: go,
typescript, javascript, bash, python, ruby, yaml. capture.sh accepts any tags, so
a global entry tagged topic-only is written successfully and is then unreachable
by recall in every repo, silently. Project-tier entries are unaffected (always
relevant to their own repo, no tag filter).

Interim rule for curators, now that the trap is known: every global-tier entry
carries at least one recognized language tag alongside its topic tags - the
knowledge-curator charter already says "tag with language and topic".

Proposed mechanical defense, liftable into a scope declaration:
- cheapest floor: capture.sh refuses (or loudly warns on) --tier global when no
  tag is in the recognized language list, mirroring its existing R21 refusal
  shape; keep the list in one place in store-lib.sh so capture and recall cannot
  drift; plus a bats case asserting the refusal.
- design alternative for the developer: an always-relevant topic class in
  recall's filter (for genuinely language-agnostic process learnings), which is a
  product decision about what recall means, not just a lint.

Ladder status: mechanized. Superseded: the capture-side check landed in
2ed6806 - capture.sh refuses a global-tier capture with no recognized
language tag (exit 2) unless --unreachable-ok records the trade-off,
bats-pinned. The entry stays as the reproduction record.
