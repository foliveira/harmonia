---
title: Standing context is descriptions plus hook output - new skills ship hidden and budgeted
date: 2026-07-11
tags: [process,plugin,context]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

A session starts at ~32k tokens; harmonia's standing share was ~1.6k (hook 601t + 15 skill descriptions ~660t + 13 agent descriptions 366t), and because the plugin is installed user-scoped from the live repo directory that cost lands in EVERY project. Skill bodies cost nothing until invoked - descriptions and hook output are the standing spend - and subagent spawns dominate flow-run cost (~18.5k context each, 82% of a flow's fresh tokens; the platform's agent baseline, not harmonia prose). Conventions pinned by tests/context-budget.bats: new skills ship disable-model-invocation: true unless Skill-tool-chained (allowlist: flow quick plan implement review); descriptions stay one lean line; the unconditional RULES.md read stays dead (the session hook injects the digest at startup/resume/compact, so main-thread reads are conditional on its absence; agents still read in full); flow-chained stages never re-read lifecycle.yaml; SKILL.md bodies stay under 10,000 bytes, with reference material in a sibling file read on demand (skills/onboard/CERTIFY.md is the pattern).
