# Common rules for every gdpins single-local-copy brief (read this + your brief only)

Repo: `C:\Users\wb532966\eb-local-private\gdpins` (R package). Branch `feat/single-local-copy`.
Do NOT commit. Do NOT `git add`/`stash`/`checkout`/`reset`. The orchestrator commits.
Do NOT read `tools/plan-single-local-copy.md` or `tools/design-local-cache.md` — your brief has what you need.

## Environment
- R: `"/c/Program Files/R/R-4.5.3/bin/x64/Rscript" --no-init-file` (Bash tool). Never bare `Rscript`,
  never the MCP R session, never drop `--no-init-file` (renv lib lacks pkgload).
- Run one test file:
  ```
  "/c/Program Files/R/R-4.5.3/bin/x64/Rscript" --no-init-file -e 'pkgload::load_all(".", quiet=TRUE); testthat::test_file("tests/testthat/test-board.R", reporter="summary")'
  ```
- One test only: `testthat::test_file("<file>", desc = "<exact test_that name>")` (testthat 3.3.2).
  Otherwise run the whole file and read failures for your sections.
- Tests must never spawn background processes or file-lock helpers (antivirus). Mock seams with
  `testthat::local_mocked_bindings(..., .package = "gdpins")`.
- Never run `tests/testthat/test-live.R`.
- Never write to the real user cache: tests rely on `tests/testthat/setup.R` setting option
  `gdpins.cache_dir` to a tempdir; examples always pass `cache_dir = tempfile("cache_")`.
- Global state in tests (options/env/wd) → `withr::local_*`.
- Never hand-edit `man/` or `NAMESPACE`.
- Snapshots (`tests/testthat/_snaps/`): only T3 may touch; revert LF↔CRLF-only churn.

## Frozen design (all tasks)
- One local copy per Drive board, or none. Local copy = `pins::board_folder` in `board$local_board`;
  its path = `board$cache_dir`. `pins::board_gdrive(cache=)` points at the same dir.
- Configs: `.BOARD_CONFIGS <- c("local_only", "drive_cache", "drive_only")`. `"drive_cache_local"` is gone.
- Object fields, exact order: `config, name, drive_board, local_board, cache_dir, drive_path, adapter, versioned`.
  Fields `cache_board` and `local_dir` are REMOVED (`board$cache_board` / `board$local_dir` now return NULL).
- Components per config: `local_only` → `local_board`; `drive_cache` → `drive_board` + `local_board`;
  `drive_only` → `drive_board` only (`local_board = NULL`, `cache_dir = NULL`).
- Test fixture: `new_fake_board(config = c("drive_cache", "local_only", "drive_only"), versioned = TRUE, name = "test")`.
  `drive_cache`: fake drive `board_folder` + `local_board` over fresh tempdir `cache_dir`.
  `drive_only`: fake drive board only. `local_only`: `local_board` over fresh tempdir, `cache_dir` = that dir.
- Mechanical test rewrites everywhere: `board$cache_board` → `board$local_board`; `board$local_dir` →
  `board$cache_dir`; `gdpins_init_board(local_dir = X)` → `gdpins_init_board(cache_dir = X)`;
  `new_fake_board("drive_cache_local")` → `"drive_cache"` (or `"drive_only"` if the test is about
  having no local copy). Tests asserting "three copies"/"local and cache both" collapse to one local copy.

## TDD
1. Write/adjust tests first. Run. Paste RED output (failures expected) in report.
2. Implement. Run your task's test files only. Paste GREEN output.
3. Budget: close at 100–150k tokens. At 100k and not done → stop, write state into report, return.

## Report template (final message)
```
Task: Tn / Vn        Tokens used (approx):        Verdict (verifier only): PASS|FAIL
Files changed:
RED output (pre-impl):      <paste, trimmed to failure summary lines>
GREEN output (post-impl):   <paste summary>
Tests added:                <names>
Deviations from brief:      <none | list>
Leftovers / risks:          <list>
```

## Verifier addendum (verifiers only)
You are verifying Tn. You did not write it. Assume it is wrong until proven otherwise.
1. `git status --short` + `git diff --stat` → any modified file outside the brief's "may edit" list
   = FAIL (ignore `tools/working-on-raw-sync-locked-files.md`, `tools/briefs/`, `tools/plan-single-local-copy.md`).
   Note: other phase-2 tasks run in parallel and edit their own files — only flag files that are in
   NO task's list for this phase; list other-task files as "parallel, ignored".
2. Run the task's test files. Paste output.
3. Add ≥3 new tests named `test_that("[Vn] …")` in the task's test files: from the edge list AND ≥2 of
   your own (NULL/FALSE/TRUE/""/vector inputs, config combos, offline, lazy vs eager, error text). Run. Paste.
   Passing new tests stay in the suite. Do not edit R/ source.
4. Verdict PASS/FAIL. FAIL: file:line, expected vs actual, minimal repro.
5. Leftovers outside scope: list, do not fix.
