---
title: The coverage gate is a report-consumer; projects own coverage via a command, not new adapters
date: 2026-07-08
tags: [bash,harmonia,coverage,architecture]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

Instance: 2026-07-07-onboard-existing-project. Records how new-language coverage attaches
to bin/coverage/gate.sh, so a future task reaches for the command seam instead of writing
a fourth adapter.

The architecture. The gate is fundamentally a report-consumer: it has a report seam
(gate.sh, the `if [ -z "$REPORT" ]` branch) where a provided report skips adapter
production and diff-cover intersects it with the changed lines. The three built-in
adapters (ts, bash, go) are just the DEFAULT report-producers for their languages. So a
project owns its coverage by supplying a `coverage:` command in `.harmonia/project.yaml`;
the gate RUNS that command each invocation (never reads a report lying around - a stale
out-of-band report is the acceptance-attests-a-diff-it-never-saw failure class) and
consumes what it prints. When a command is present, the changed-file classifier also
widens: files whose extension the adapters route to "unsupported" (.py/.rb/.rs/...)
become measurable through the command's report instead of dropping to the advisory
cannot-measure path. The captured command takes precedence over the adapter; with no
command present, the classifier and the adapter fallback are byte-identical to before,
which is what keeps the engine's own self-gate (the bash adapter) green.

The durable decision (why this shape). New-language coverage flows through the project's
own command, NOT through new built-in adapters. The adapters stay zero-config defaults
and are not made project-configurable - an earlier direction to add source_root/test_root
knobs to the bash adapter was reversed as R2 (no knob without a live need; a non-standard
repo supplies its own kcov command instead). A future task tempted to add a python/ruby
adapter should route through the command seam instead, and the store holds only the
command - do not add adapter-config knobs.

Tier: project - this is Harmonia's own gate.sh architecture and every consumer is
in-repo. The task workspace that first recorded it (`.harmonia/tasks/`) is gitignored, so
this entry is the durable carrier. No client content.
