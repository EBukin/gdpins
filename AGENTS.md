# R package dev / enhancement protocol

Be extremely concise. Sacrifice grammar for the sake of concision.

Checklist for any feature or fix. Skip a step only if provably N/A.

## 1. Dependencies (DESCRIPTION)

- Pkg used on a code path that always runs → `Imports`.
  Optional/test-only → `Suggests` + guard
  ([`requireNamespace()`](https://rdrr.io/r/base/ns-load.html),
  `skip_if_not_installed()`).
- `pkg::fun()` fully-qualified is fine; still must be declared in
  `Imports`.
- Bump `Version:`. Keep `DESCRIPTION` version == top `NEWS.md` heading.

## 2. Docs are generated — never hand-edit man/ or NAMESPACE

- Edit roxygen blocks, then `roxygen2::roxygenise()`.
- Every new arg → `@param`. Shared concept → `@section` on a `@name`
  topic.
- `@examples` run during `R CMD check` — must actually execute; verify.
- Internal helpers → `@keywords internal` / no roxygen (no accidental
  export).
- After regen: `NAMESPACE` diff = intended exports only.

## 3. API evolution = backward compatible

- New args appended, defaulted (usually `NULL`). Existing calls
  unchanged.
- Behavior-changing default = justify (more correct + compatible). Note
  in NEWS.
- Package-wide switch →
  [`options()`](https://rdrr.io/r/base/options.html) + default set in
  `.onLoad` (`R/zzz.R`), “set only if unset” idiom.

## 4. Tests (testthat)

- Data → `helper-*.R` fixtures, not inline.
- Every bug fixed → regression test that fails pre-fix.
- Global state (options/env/wd) → `withr::local_*` so it auto-restores.
- Expensive/optional → skip-by-default (env-var guard +
  `skip_if_not_installed()`).
- Snapshots: only commit real `_snaps/` changes; revert LF↔︎CRLF-only
  churn.

## 5. Verify whole suite, not just new tests

- Run full `test_dir()` — default/behavior changes ripple into
  integration tests.
- Integration path (public verb → storage → read back) catches what unit
  tests miss.
- Target: 0 failed, 0 warnings before done.

## 6. User-facing docs (separate obligation from man/)

- `NEWS.md`: new-feature + bug-fix entries.
- README + vignette (`.Rmd` chunks build-execute — keep runnable).

## 7. Packaging hygiene

- Non-standard top-level files (`AGENTS.md`, `CLAUDE.md`, dev scripts) →
  `.Rbuildignore` to avoid `R CMD check` NOTE.

# Multi-agent plan execution protocol

Applies whenever a task is big enough to plan (\>1 module or \>1 test
file).

## Planning

- Analyse first; write design-as-is doc + plan to `tools/<topic>.md`.
  Commit before any code.
- Plan = frozen design (decision tables, exact symbols, field layouts) +
  phased tasks + tracker table + decisions log. Design questions
  resolved in plan, never by implementers.
- Phase = set of tasks on **disjoint** R files and disjoint test files →
  run in parallel. Sequential only where a task needs another’s output.
- Every task lists: goal, design excerpt, files may edit, files/ranges
  to read (line numbers from fresh `grep -n`), files must NOT read/edit,
  tests to write first, edge list, commands.

## Roles

- **Orchestrator** — Opus-class. Writes **zero code**. Writes briefs,
  spawns agents, reads reports, runs gates, updates tracker, commits.
- **Implementer** — Sonnet. One task. Edits only listed files.
- **Verifier** — Sonnet. Never the implementer of the same task. One per
  completed task.
- Spawn: `Agent` tool, `model: "sonnet"`. Parallel tasks launched in
  **one** message. Re-rounds → same implementer via `SendMessage` (max
  2), then fresh implementer re-briefed.

## Token budget

- Brief self-contained: agent must not explore. Target close at
  **100–150k** tokens.
- Hard rule: at 100k and not done → stop, write state to report, return.
  Orchestrator splits.

## TDD (implementer)

1.  Write/adjust tests first. Run. Paste **RED** output in report.
2.  Implement. Run task’s test files only. Paste **GREEN** output.
3.  Report: files changed, RED, GREEN, tests added, deviations,
    leftovers.

- No RED evidence → rejected before review.
- No full-suite runs inside a parallel phase. Full suite at gates only.

## Verification (verifier)

1.  `git status --short` → any file outside brief = FAIL.
2.  Rerun task’s tests. Paste output.
3.  Write **≥3 new adversarial tests**: edge list + ≥2 own ideas
    (NULL/FALSE/““/vector inputs, config combos, offline, lazy vs eager,
    error text). Run. Passing ones **stay in suite**.
4.  Verdict PASS/FAIL. FAIL = <file:line>, expected vs actual, minimal
    repro.
5.  Leftovers outside scope: list, do not fix.

## Gates (orchestrator, end of each phase)

- Full `test_dir()`: 0 fail, 0 warn. Grep for dead symbols named in plan
  → empty.
- Docs phase: `roxygen2::roxygenise()` clean; `NAMESPACE` diff =
  intended; examples run; vignettes knit. `R CMD check` before PR.
- Commit per phase, conventional prefix. Update tracker + decisions log,
  commit with it.
- Report to user only at gates, at a FAIL surviving 2 rounds, or a
  decision the plan lacks. Questions in prose, one at a time,
  recommendation first.

## Environment

- Bare `Rscript`. Use MCP R session if avaialbel.
- Tests never spawn processes / file locks (antivirus). Mock a seam.
- `test-live.R`: edit by reading, never run.
