---
title: Test-immutability locks every file under tests/, not just .bats files
date: 2026-07-06
tags: [bash,harmonia,test-immutability,boundary,ownership]
tier: project
source_repo: git@github.com:foliveira/harmonia.git
---

Found in review of 2026-07-06-rename-brainstorm-to-discuss, a pure token
rename. One of the nine touched files was tests/e2e-walkthrough.md, a markdown
walkthrough rather than a .bats test.

Current behavior, verified. record-test-hashes / verify-test-hashes select the
immutable set at bin/workspace.sh:146 with:

  grep -E '(^tests?/|\.bats$|[._]test\.|[._]spec\.)'

The first alternative, ^tests?/, matches any path under test/ or tests/ by
location, whatever the extension. So tests/e2e-walkthrough.md is hashed and
frozen the same as a .bats file. KTD12 bars the implementer from editing
anything in that set, which makes this doc the test-engineer's to change.

Why it matters at boundary time. When a change touches a non-test file that
happens to live under tests/, the scoper and planner must put that file on the
test-engineer turn, and the test-engineer flips it in the red round. If the
implementer edits it, verify-test-hashes writes a violation the review lead then
sees. The gate punishes a mis-assignment after the fact; it does not draw the
ownership line for you. A file is locked by where it sits (under tests/) even
when its extension is .md, and "it's only a doc" is the trap.

This task drew the line correctly: boundary.md assigned tests/e2e-walkthrough.md
to the test-engineer, that turn edited it in round 1, the implementer left it
alone, and verify-test-hashes verified with no violation.

Cheap forward defense, liftable into scoping. Run the same selector over the
planned blast radius before splitting ownership, e.g.
`printf '%s\n' <files> | grep -E '(^tests?/|\.bats$|[._]test\.|[._]spec\.)'`,
and hand every hit to the test-engineer. This turns the after-the-fact hash
violation into a boundary-time assignment.

Project tier: KTD12 and this hashing are Harmonia's own mechanism
(bin/workspace.sh); the fact is specific to this repo's test-immutability and
does not port to a project without it.
