---
title: A dispatched subagent cannot message its dispatcher by agent-type name
date: 2026-07-13
tags: [harmonia,process,orchestration,agents]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

Found across 2026-07-13-multi-harness-install, at the discuss seam and again at review. It
appears in no workspace artifact - it is an orchestration-layer fact - so this entry is its
carrier.

The fact. A subagent dispatched by a seat cannot reach that dispatcher with SendMessage
addressed by agent-TYPE name: `harmonia:scoper` and `harmonia:reviewer` are not reachable
that way. Agents are addressable by their agentId, not by their type. Two live instances
this task: the discuss-seam falsifier tried to send its report to `harmonia:scoper` and
could not; and when the review lead died on an API limit after dispatching its six seats,
the seats' reports surfaced to the MAIN conversation, not to the dead lead.

Consequence. A reply channel built on "message the dispatcher by name" fails quietly - the
message lands in main, or nowhere the dispatcher reads. Both recoveries this task were
file-based: the falsifier's report reached the scoper by its output-file path, and the
orchestrator consolidated the dead lead's six seat reports from the files they had written.

Why the repo already survives this. Harmonia's inter-agent reply channels are file-based by
design, not SendMessage. The adversarial lens returns findings by appending to the
workspace's `falsification.md` (core/lenses/adversarial.md:31-32); dispatched seats write
workspace out-artifacts the dispatcher reads. The charters name the channel as output back
to the dispatcher, so nothing depends on a live name-addressed message.

The rule for future work. Do not design an inter-agent send-back channel around
SendMessage-by-type. Name it as a final output the dispatcher consumes (a workspace file or
artifact). That also survives the dispatcher dying mid-run, which a live message does not.

Ladder: the defense is already in place (file-based channels); this entry is the pointer
and the harness rationale, so a future charter author does not reintroduce a name-addressed
message channel.

Tier: project. Global-tier recall filters by language tag and this fact carries none (see
2026-07-02-global-learnings-without-a-language-tag-are-unreachable-by-recall), so a global
entry would never surface. Every consumer - the charters, the lenses, the flow runner -
lives in this repo, so project tier reaches it where it is used.
