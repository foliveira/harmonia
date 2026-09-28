# The Rules

Harmonia's working contract. Rules 1 to 4 are adopted from Andrej Karpathy's guidelines. Rules 5 to 9 condense Rob Pike's rules of programming, in his order. Every agent charter and every lifecycle command binds to these. When a rule and convenience conflict, the rule wins; when two rules appear to conflict, say so out loud instead of silently picking one.

## 1. Think Before Coding

Don't guess silently: state assumptions, surface tradeoffs, and ask when genuinely unclear.

**Binding in Harmonia:** no implementation starts without a scope declaration whose success criteria are machine-checkable (`check-criteria` gate). Agents write their assumptions into the task workspace, not into thin air.

## 2. Simplicity First

Write the minimum code the ask requires. No speculative abstractions, no flexibility nobody asked for.

**Binding in Harmonia:** an abstraction needs a current consumer to exist. The simplifier and the review lead are charged with challenging anything that doesn't earn its keep. Prefer deleting to configuring.

## 3. Surgical Changes

Touch only what the task requires. No drive-by refactors, no "improving" adjacent code.

**Binding in Harmonia:** the task boundary recorded in the workspace defines what this task touches; the reviewer audits the diff against it. Adjacent improvements become captured ideas for a future task, not riders on this one.

## 4. Goal-Driven Execution

Turn tasks into verifiable success criteria so progress can be checked, not felt.

**Binding in Harmonia:** the scoper compiles every task into criteria a command can verify; gates (criteria, tests) decide done-ness, and receipts prove the gates actually ran. "Looks good" is never a completion signal.

## 5. Prove the Bottleneck

Bottlenecks occur in surprising places, so don't put in a speed hack until you've proven one is there.

**Binding in Harmonia:** a change made for speed records, in the task workspace, the measurement that found its bottleneck. The review lead treats a speed hack with no such record as a finding.

## 6. Measure

Don't tune for speed until you've measured, and even then only if one part overwhelms the rest.

**Binding in Harmonia:** the scoper compiles a speed goal into a `- run:` criterion that takes the measurement, so the criteria gate repeats it at review. Tuning is in scope only for the part the measurement shows overwhelming the rest.

## 7. Don't Get Fancy

Fancy algorithms are slow when n is small, and n is usually small.

**Binding in Harmonia:** a design that reaches for a fancy algorithm names the n it expects and where that number comes from. Even a big n goes through Measure first.

## 8. Use Simple Algorithms

Fancy algorithms are buggier and much harder to implement. Keep the data structures simple too.

**Binding in Harmonia:** the simplifier challenges a fancy algorithm or data structure the way it challenges an abstraction. The fancy one stays only for a named case the simple version cannot handle.

## 9. Data Dominates

Get the data structures right and the algorithms will almost always be self-evident.

**Binding in Harmonia:** the planner chooses the data structures first, and `design.md` names them before the algorithms that use them.
