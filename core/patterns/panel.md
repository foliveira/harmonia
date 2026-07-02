# Panel — model-diverse fan-out with synthesis (R29)

A reusable orchestration pattern. The v1 consumer is the review lead; wider roster uses are future work.

## Shape

1. **Brief once.** One task brief, written before any dispatch: the question, the inputs (workspace paths, never prose recaps), and the exact output contract expected back.
2. **Fan out N seats.** Dispatch N subagents with the same brief. Deliberately vary the model per seat when decorrelation helps — a fast cheap model for breadth, a strong model for depth — using the spawn tool's per-invocation model parameter. Seats never see each other's output.
3. **Synthesis step (mandatory).** One synthesizer — the dispatching agent itself, unless the panel is large — collects all returns and produces a single arbitrated result: deduplicate overlapping findings, resolve contradictions by evidence quality (never by seat seniority), and **attribute** every surviving item to its originating seat so the panel's value stays measurable.

## Rules

- A panel without a synthesis step is just noise multiplied; never skip step 3.
- Seat count follows the question: two seats for a fork, three to five for open review. More seats than distinct perspectives is waste (Simplicity First).
- Disagreement between seats is signal — surface it in the synthesis with both positions and the evidence, rather than averaging it away.
- The synthesis result is written to the task workspace; seat transcripts are not (files over conversation, R8).
