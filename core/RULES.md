# The 4 Rules

Harmonia's working contract, adopted from Andrej Karpathy's guidelines. Every agent charter and every lifecycle command binds to these. When a rule and convenience conflict, the rule wins; when two rules appear to conflict, say so out loud instead of silently picking one.

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

**Binding in Harmonia:** the scoper compiles every task into criteria a command can verify; gates (criteria, tests, coverage) decide done-ness, and receipts prove the gates actually ran. "Looks good" is never a completion signal.
