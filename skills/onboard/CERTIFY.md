# Coverage certification - the five checks

Read by `/harmonia:onboard` step 3 before recording a coverage command into
`.harmonia/project.yaml`: apply all five checks; record only if every one
passes, and reject on the first failure.

   1. **Run it fresh in the repo.** `report="$( cd REPO && eval "CMD" )"`. Resolve a
      relative `report` against the repo root. Require exit 0 AND that `report`
      names a readable file. Exit 0 with no readable report is insufficient -
      reject. This is the run-before-record discipline applied to coverage.
   2. **Confirm it parses (diff-cover-readable).** Confirm `report` is well-formed
      Cobertura XML carrying the elements diff-cover consumes: a `<coverage>` root,
      `<class filename="...">` entries, and `<line number=... hits=.../>` lines. A
      report that fails to parse, or that lacks these elements, is rejected.
   3. **Confirm repo-relative rooting - a tracked file reads as measured.** Derive
      the src-roots the same way the gate does: `.` plus each `<source>` element
      that points under the repo. Take the report's `filename="..."` entries and
      confirm at least one, resolved against a src-root, is a path that
      `git -C REPO ls-files` tracks. That tracked source file is the one that reads
      as measured. The gate marks any changed file NOT in the report's measured set
      as ALL uncovered, so a report whose filenames do not resolve to tracked repo
      paths (absolute, or rooted outside the repo) would make every changed file
      read as absent-from-coverage. Requiring a tracked file to resolve proves the
      rooting is repo-relative and correct.
   4. **Confirm line-completeness - an uncovered line reads as `hits="0"`, not
      omitted.** The gate's diff-cover reasons only about the lines the report
      lists, so a tool that emits partial line data - listing the lines it executed
      and dropping the uncovered ones - false-greens the gate: an omitted uncovered
      changed line is never seen and reads green. Riding the same tracked file
      check 3 resolved, read that file's `<line number=... hits=.../>` entries and
      confirm at least one is `hits="0"` at a source line the run does not exercise
      - an error branch, a defensive guard, or a CLI/`__main__` entry the command
      skips. Seeing that line as `hits="0"` rather than absent from the report is
      the evidence the tool reports uncovered lines instead of omitting them. If the
      resolved file is fully covered (every executable line `hits>0`) there is no
      `hits="0"` to observe, so it cannot witness this; then exercise a known
      uncovered line on purpose - pick a measured file with an unexecuted region, or
      have the developer name one, and confirm the report lists it as `hits="0"`. A
      run in which no measured file yields any `hits="0"` line is inconclusive for
      completeness, not a pass - say so rather than reading "no hits=0 seen" as
      green. Stated honestly: this catches a tool that omits uncovered lines
      whenever an uncovered line is observable in the run, but it cannot prove every
      future gate run is line-complete for every file. It is a sample, not a proof.
   5. **Require any stray byproducts gitignored before recording.** The gate folds
      untracked files into its changed set, and the widened classifier routes an
      untracked non-skip-extension file into the measured set. So a coverage command
      that leaves a data-file byproduct in the repo - outside `.harmonia/`, and not
      the report - is picked up on the NEXT gate run, found absent from the report,
      and false-reds the gate. Because the gate excludes gitignored files,
      gitignoring the byproduct resolves it. Right after check 1's run, inspect
      `git status --porcelain` for the untracked entries the command created: any
      untracked path outside `.harmonia/` that is not the report is a stray
      byproduct, and it must be gitignored (a `.gitignore` entry the repo commits)
      before the command is recorded. Common offenders are coverage data files -
      `.coverage` (coverage.py), `.info` (lcov), `.profraw` (llvm), `.gcda` (gcov).
      The report itself usually ends in `.xml`, a skip extension the classifier
      ignores, so the report is never the problem - only the data-file leftovers.

   Why this intersection and not a live diff-cover dry run: the rooting check is a
   `filename` against `git ls-files` intersection through the gate's own src-root
   derivation, using NO diff. A real diff-cover run would be more faithful but needs
   a non-empty diff over a measured tracked file, which is fragile on repo history
   and risks two failure modes - coverage passing vacuously on an empty or wrong
   diff, and a resolvable-but-wrong base. The intersection predicts the gate's
   measured set deterministically without a diff and sidesteps both. Certify against
   an existing tracked source file the command already measured, never a freshly
   created synthetic one. The reason is measurement, not git tracking status: a fresh
   fixture reads as absent because the coverage tool never executed it, not because
   the gate excludes untracked files - the gate in fact passes diff-cover
   `--include-untracked` and folds untracked files into its changed set. The diff
   digest is untracked-blind (plain `git diff`), but that governs receipt staleness,
   not this rooting check, so it is not the reason to prefer a tracked file here.
