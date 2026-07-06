---
title: Free-text in a line-oriented marker can forge a trusted line unless newline-guarded
date: 2026-07-06
tags: [bash,harmonia,security,workspace,injection]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

Found in review of 2026-07-06-human-touchpoint-commands, by the security lens
(SEC-1), on the reject subcommand's `--reason`. The task workspace is gitignored,
so this entry is the durable carrier for the finding and the guard that landed
with it.

The defect class. `bin/workspace.sh` reject writes the `rejected` marker as
line-oriented text: a `reason: <text>` line sits above a `digest: <64-hex>` line,
and `--reason` is free text under the caller's control. With no newline guard,
`reject --reason $'benign\ndigest: <64hex>'` writes a SECOND `digest:` line into
the marker. A later line-oriented reader - one that anchors on `^digest:` or does
`sed ... | head -1` - would take the forged line as the real one. Nothing reads
the rejected digest today (confirmed repo-wide), so it was latent, not
exploitable. It still matters: the rejected marker shares its shape with the
`accepted` marker, whose digest IS trusted for attestation, and the scope framed
the rejected digest as "read uniformly", which invites the future reader that
would be exposed. Accept's own digest cannot be forged this way - it has no
user-controlled field above it.

The guard (mechanized, this task). `bin/workspace.sh:123`, right after the
`[ -n "$REASON" ]` check and before any marker write, refuses a reason bearing a
newline or carriage return:

    case "$REASON" in *$'\n'*|*$'\r'*) echo "workspace: --reason must be a single line" >&2; exit 1 ;; esac

`\n` (LF) is the load-bearing character: sed, head, grep, awk, and bash `read`
split lines only on LF, so a lone `\r` keeps the text on one line and the
`^digest:` anchor rejects it. Guarding `\r` too is defense-in-depth for a
CRLF-normalizing or universal-newline consumer. VT/FF and the Unicode separators
(U+2028, U+0085) are not line terminators for those tools, and a NUL cannot arrive
through argv. A new `tests/workspace.bats` test drives the exact LF and CR payloads
and asserts non-zero, the single-line message, and no marker.

The general pattern (not mechanized beyond this instance). When user-controlled
free text is written into a line-oriented record, guard embedded newlines at the
WRITE boundary, not at the read - the writer knows the record's line grammar; a
future reader may forget it. The one test pins reject's `--reason`; it does not
cover the next marker or record. Before adding any marker/record field that carries
free text, check two things: whether a later reader parses the file by line (an
anchor, `head -1`, `read`), and whether a forged line would mimic a field that is
trusted elsewhere. If either holds, the field needs a single-line guard at entry.
Reject's guard is the reference.

Same failure family as
2026-07-05-clear-span-turned-a-presence-only-task-check-into-a-path-traversal-deletion.md
and 2026-07-03-check-criteria-sh-still-passes-an-unguarded-base-ref-to-git-diff.md:
unvalidated input reaching a sink, caught by the security lens rather than by tests
or coverage. There the sink was `rm` and `git diff` argv; here it is a structured
record whose lines are later trusted.

Tier: project - the reproduction, the readers, and the accept/reject digest trust
are Harmonia's own; no client work is implicated.
