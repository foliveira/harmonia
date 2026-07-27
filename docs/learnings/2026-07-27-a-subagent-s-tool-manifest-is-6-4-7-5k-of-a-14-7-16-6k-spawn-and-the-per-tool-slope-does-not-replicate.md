---
title: A subagent's tool manifest is 6.4-7.5k of a 14.7-16.6k spawn, and the per-tool slope does not replicate
date: 2026-07-27
tags: [harmonia,context,agents,measurement,process]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

Measured at discuss for 2026-07-26-claude5-prompt-adaptation, then re-run independently
by the scope attack, which found two method defects. The corrected numbers:

- **The tool manifest is 6.4-7.5k tokens of every spawn.** Model-matched deltas between
  an all-tools agent and a two-tool agent: 7,468 (haiku-matched) and 6,422
  (inherit-matched), against 7,312 from the first uncontrolled pass. This is the saving
  available to a seat that drops to two tools, and it is the load-bearing claim - it
  replicated.
- **A full-manifest seat costs 14.7-16.6k before doing any work**, depending on model.
  Corroborates the ~18.5k in 2026-07-11-standing-context-is-descriptions-plus-hook-output.
- **Roughly 7-9k is the harness's own base prompt** and no change in this repo can reach
  it.

Method, which matters as much as the number. Spawn agent *types* whose tool sets the
harness already fixes - the Agent tool has no per-invocation tools parameter, so nothing
has to be defined anywhere - give each an identical trivial prompt ("reply with the
single word DONE, use no tools"), make zero tool calls, and read the harness's own
`subagent_tokens`.

Two defects in the first pass, both of which change what the numbers mean:

- `subagent_tokens` **includes generated output**, so every absolute figure is an upper
  bound on injected context rather than a clean read of it. An earlier "body variance
  +/-300" bound was measuring reply length.
- **Model is a confound larger than the signal.** The same agent type on the same prompt
  measured 7,264 on haiku against 9,159 on inherit - 1,895 tokens from the model alone,
  1.6x the quantity being divided in the projection below. Run-to-run noise on
  byte-identical configuration is ~400; five all-tools probes span 714.

**Withdrawn, and it should not re-enter the record: ~586 tokens per tool.** Recomputed
model-matched it is 1,680/tool (haiku) or 733/tool (inherit), a 2.9x spread; the two
anchor probes were not a superset pair, so the quantity being halved was never a
per-tool cost; and per-tool cost is not constant anyway. Some spawn context is
tool-*gated* rather than schema-sized - the agent-type roster arrives with `Agent`, the
skills listing with `Skill` - so the four seats that must keep `Agent` re-import a
roster that grows with every unrelated agent the user installs. Solving the linear model
for the implied manifest size gives 6-15 tools against the ~24 this harness exposes.
Per-seat saving is not projectable before the build; it is knowable after.

What the spike did settle, and the published docs leave open: declaring `tools:` shrinks
the injected context rather than only gating calls at runtime. A 6.4-7.5k model-matched
gap between two spawns that each called zero tools has no other explanation.

Tier project. The number is what this repo's twelve wrappers are sized against, and it
ages with the harness version and with the count of unrelated agents installed on the
machine, so re-measure rather than quote it elsewhere. It also carries no language tag,
and recall filters global entries by language, so a global entry would never surface
(see 2026-07-02-global-learnings-without-a-language-tag-are-unreachable-by-recall).
