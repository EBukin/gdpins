---
status: pending
issue:
pr:
---

# Clear error when a local directory cannot be prepared (OneDrive + Controlled Folder Access)

- **Date:** 2026-10-03
- **Author:** Claude (investigation by two sonnet subagents: codebase map + live repro); requested by Eduard Bukin
- **Status:** draft

## Goal

`gdpins_init_board()` (and `gdpins_raw_connect()`) fail fast with a gdpins error class and an
actionable hint when the local directory cannot be prepared, instead of leaking fs's
`[EPERM] Failed to set permissions for directory 'C:/Users/wb532966/OneDrive - WBG'`.
The regression test for that behaviour fails on `main` and passes on the fix branch. The work
lands on branch `fix/local-dir-eperm` in a worktree under `.claude/worktrees/` and is merged
through a pull request. The environment-side cause (below) is documented for the user, because
no package change can make writes to OneDrive succeed from the MCP R worker.

## Context

### Reported bug

```r
gdpins_init_board(name = "data_raw",
                  local_dir = file.path(Sys.getenv("OneDrive"), "mcp_gdpins_test", "data-raw"),
                  lazy = FALSE)
#> Error: [EPERM] Failed to set permissions for directory 'C:/Users/wb532966/OneDrive - WBG': operation not permitted
```

Fails inside the MCP R sessions (`mcp__r__repl`, `mcp__r2__repl`, `mcp__r3__repl`); works under
`C:/Program Files/R/R-4.6.1/bin/Rscript.exe`. Traceback ends in `fs::dir_create(cache_dir)` at
`R/board.R:447-448` (`local_dir` is a deprecated alias of `cache_dir`, `R/board.R:354-368`).

### Root cause (verified 2026-10-03, live repro)

**Windows Defender Controlled Folder Access (CFA) blocks the MCP R worker binary
`C:\Users\wb532966\.local\bin\mcp-repl.exe` from modifying the OneDrive folder.** R runs
embedded inside that process (`commandArgs()` is `"mcp-repl"`; parent chain
`mcp-repl.exe` -> `claude.exe`). `Rscript.exe` under `C:\Program Files\R` is allowed. Same R
4.6.1, same renv library, same fs 2.1.0 and pins 1.4.2 in both environments.

Evidence:

- Defender operational log, 7 events, all naming the same process:

  ```powershell
  Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Windows Defender/Operational'; Id=1123,1124} -MaxEvents 10
  # C:\Users\wb532966\.local\bin\mcp-repl.exe has been blocked from modifying
  # %userprofile%\OneDrive - WBG by Controlled Folder Access.
  ```

- `Get-MpPreference`: `EnableControlledFolderAccess = 1`; protected folders include
  `%userprofile%\OneDrive - WBG`. The allow-list is admin-only ("Must be an administrator to
  view exclusions"), so it is centrally managed.

| Probe (same wall-clock time) | mcp-repl worker | Rscript 4.6.1 |
|---|---|---|
| `fs::dir_create(Sys.getenv("OneDrive"))` (exists) | EPERM (r: first 4 calls passed, then 100 % EPERM; r2/r3: EPERM from first call) | OK |
| `fs::dir_create(<existing OneDrive subdir>/new_child)` | EPERM on the OneDrive root | OK, created |
| `fs::file_chmod(<OneDrive subdir>, "u=rwx,go=rx")` | EPERM | OK |
| base `dir.create(<new subdir under OneDrive>, recursive = TRUE)` | `FALSE`, warning `reason 'No such file or directory'` | OK, created |
| `fs::dir_create(Sys.getenv("USERPROFILE"))` | OK | OK |
| `pins::board_folder(<OneDrive subdir>)` | EPERM (it calls `fs::dir_create(path)` unconditionally) | OK; `pin_write`/`pin_read` round trip OK |
| `gdpins_init_board(local_dir = <OneDrive>, lazy = FALSE)` via `pkgload::load_all()` | exact reported error | OK, `local_only` board |

Why fs names the OneDrive *root*: `fs::dir_create(recurse = TRUE)` passes every ancestor to
`fs_mkdir_`. On a healthy system an existing ancestor returns `EEXIST` and is skipped. Under
the CFA block the existing root does not come back as `EEXIST`, so fs reaches its chmod step and
CFA refuses it.

### Consequences for the fix

- The in-package change proposed in the report (skip `fs::dir_create` when the folder exists,
  or use base `dir.create()`) **does not resolve the reported scenario**: base `dir.create()`
  also fails from the blocked process, and `pins::board_folder()` calls `fs::dir_create()`
  unconditionally right after gdpins, so the same EPERM surfaces one frame later.
- What gdpins *can* do: detect the failure at the first touch of the directory, before pins, and
  raise a classed, explained error. Today the raw fs error gives no clue that the process, not
  the path, is the problem; that cost several debugging sessions.
- The default cache root `~/.gdpins/cache` (`R/zzz.R:20-22`) is outside the protected folders,
  so default boards keep working in MCP sessions.

### Existing code and tests

- `R/board.R:446-448` (local_only), `:485` (drive_cache offline fallback), `:620` (drive_cache),
  `:518`/`:597` (scratch dir for `pins::board_gdrive(cache =)`) all call `fs::dir_create` on
  `cache_dir`; `R/raw-connection.R:535`, `:567`, `:608` do the same on `local_path`;
  `R/output.R:50` on a user-supplied `dir`. 25 `fs::dir_create` sites in total, 21 unguarded;
  no shared helper exists. `fs` stays in Imports (9 other fs functions in use).
- Tests: testthat edition 3, `local_mocked_bindings()` is the house idiom (16 files). Closest
  tests: `tests/testthat/test-board.R:13-50` (existing dir; missing leaf under tempdir) and
  `tests/testthat/test-integration.R:592-634` (`local_dir` deprecation round trip). Nothing
  simulates a directory that cannot be prepared. Only `test-live.R` has an opt-in gate
  (`GDRIVE_TEST_FOLDER`).
- Repo: `origin` = `https://github.com/EBukin/gdpins.git`, default branch `main`, `gh` logged in
  as `EBukin`, no CI workflows. Prior worktree convention: `.claude/worktrees/<name>`
  (`.claude` is in `.Rbuildignore`; `.gitignore` has no worktree entry). renv project library is
  keyed by project path, so a new worktree needs `renv::restore()`.
- DESCRIPTION `Version: 0.0.1.9026` == top `NEWS.md` heading. `man/` is gitignored; roxygen
  output is regenerated, not committed.

### Constraints

- Run R through Rscript, not the MCP session (memory: MCP session may be rooted elsewhere; and
  here the MCP worker is the blocked process). Use the `run-r` skill's Rscript fallback with the
  worktree as working directory.
- Never spawn background processes or file-lock tests (antivirus trips).
- Commits and PR text: no email, no AI attribution (`.claude/hooks/no-coauthor.sh`).
  Stage explicit paths. Commit only when asked.
- Keep OneDrive clean: any manual probe under OneDrive is deleted afterwards with
  `Remove-Item -Recurse -Force` (pins marks data files read-only).

## Key Files

- `R/board.R:446-448` — `.build_board()` local_only branch, the reported failure site.
- `R/board.R:485, 518, 597, 620` — other `cache_dir` / scratch creation sites.
- `R/raw-connection.R:535, 567, 608` — `local_path` creation in `gdpins_raw_connect()`.
- `R/output.R:50` — user-supplied `dir` creation.
- `R/utils-dir.R` (new) — `.prepare_local_dir()` helper and its abort function.
- `tests/testthat/test-local-dir.R` (new) — regression + opt-in protected-folder test.
- `DESCRIPTION`, `NEWS.md`, `README.md` — version bump, entry, troubleshooting note.

## Steps

Order matters in steps 1-5: the test must be seen failing before the code changes.

### 1. Branch and worktree

- [ ] From the main checkout (`C:/Users/wb532966/eb-local-private/gdpins`, clean `main`):
      `git worktree prune` (drops the stale `merge-arrow-slc` entry), then
      `git worktree add .claude/worktrees/fix-local-dir-eperm -b fix/local-dir-eperm main`.
- [ ] If `git status` in the main checkout now lists `.claude/worktrees/`, add the line
      `.claude/worktrees/` to `.gitignore` inside the worktree (part of this PR).
- [ ] In the worktree: `Rscript -e "renv::restore(prompt = FALSE)"` (links from the renv cache).
      If that is slow, set `RENV_PATHS_LIBRARY` to the main checkout's `.libPaths()[1]` instead.
- [ ] Sanity: `Rscript -e "devtools::test()"` in the worktree runs green before any change.

### 2. Regression test first (must fail on the unfixed branch)

- [ ] Create `tests/testthat/test-local-dir.R`. Core regression test:

  ```r
  test_that("init_board turns an fs error on cache_dir into a gdpins error with a hint", {
    cache_dir <- withr::local_tempdir()
    testthat::local_mocked_bindings(
      dir_create = function(path, ...) {
        rlang::abort(
          "[EPERM] Failed to set permissions for directory 'C:/x': operation not permitted",
          class = c("EPERM", "fs_error")
        )
      },
      .package = "fs"
    )
    err <- expect_error(
      gdpins_init_board(name = "t", cache_dir = cache_dir, lazy = FALSE),
      class = "gdpins_error_local_dir"
    )
    expect_s3_class(err$parent, "fs_error")
    expect_match(conditionMessage(err), "Controlled Folder Access")
    expect_match(conditionMessage(err), basename(cache_dir), fixed = TRUE)
  })
  ```

  Add sibling cases: `lazy = TRUE` (error surfaces on first field access, same class);
  `gdpins_raw_connect(local_path = <existing tempdir>)` local_only path; healthy paths
  (existing dir returns silently; missing nested dir is created).
- [ ] Before touching `R/`, run only this file: `Rscript -e "devtools::test(filter = 'local-dir')"`.
      Expected: the regression cases fail because the error class is fs's `EPERM`, not
      `gdpins_error_local_dir`. Record the failing output in the Decision Log.
- [ ] Verify that the `.package = "fs"` mock is really intercepted (the error message in the
      failure must be the mocked `C:/x` text). If testthat refuses to mock `fs::dir_create`
      this way, fall back to a package seam: route every call through `.fs_dir_create()` in
      `R/utils-dir.R` and mock that binding instead; note the change in the Decision Log.

### 3. Fix

- [ ] New `R/utils-dir.R` (internal, `@keywords internal`, `@noRd`):

  ```r
  .prepare_local_dir <- function(path, arg = "cache_dir", call = rlang::caller_env()) {
    withCallingHandlers(
      fs::dir_create(path),
      fs_error = function(e) .abort_local_dir(path, e, arg, call)
    )
    invisible(path)
  }

  .abort_local_dir <- function(path, parent, arg, call) {
    cli::cli_abort(
      c(
        "Cannot prepare local directory {.path {path}} for {.arg {arg}}.",
        "i" = "On Windows, Defender {.strong Controlled Folder Access} can block the current
               R process from writing to OneDrive and other protected folders, even when the
               folder already exists.",
        "i" = "Check the Defender log (event IDs 1123/1124) for the blocked executable, allow
               it, run gdpins from an allowed R such as {.path Rscript.exe}, or choose a
               directory outside protected folders (default: {.path {getOption('gdpins.cache_dir')}})."
      ),
      parent = parent, class = "gdpins_error_local_dir", call = call
    )
  }
  ```

  `fs::dir_create()` on an existing directory is a no-op on healthy systems and is exactly the
  operation pins performs next, so it doubles as the write probe. Confirm the fs condition class
  vector first (`class(tryCatch(fs::file_chmod("<missing>", "u=r"), error = identity))`); if
  `fs_error` is absent in fs 2.1.0, handle `error` and test `inherits(e, c("EPERM", "EACCES", "ENOENT"))`.
  The hint is unconditional (text says "On Windows") so the test is OS-independent.
- [ ] Replace with `.prepare_local_dir()`: `R/board.R:446-448`, `:485`, `:620` (arg `cache_dir`,
      `call` = the public caller's frame, which `.build_board()` must receive or default to the
      `gdpins_init_board()` call); `R/board.R:518`, `:597` (scratch); `R/raw-connection.R:535`,
      `:567`, `:608` (arg `local_path`); `R/output.R:50` (arg `dir`). Drop the now redundant
      `if (!dir.exists(...))` guards. Leave the fake adapter, per-file `dirname()` sites and the
      `tempfile()` sites unchanged.
- [ ] `Rscript -e "devtools::test(filter = 'local-dir')"` green.

### 4. Docs, version, packaging

- [ ] `DESCRIPTION` `Version: 0.0.1.9027`; `NEWS.md` new top heading `# gdpins 0.0.1.9027`
      with a "Bug fixes" entry: classed error `gdpins_error_local_dir` with a Controlled Folder
      Access hint replaces the raw fs EPERM; note that the failure itself is environmental.
- [ ] Roxygen `@section Local directories on OneDrive and protected folders:` on
      `gdpins_init_board()` (and `gdpins_raw_connect()`): what CFA does, how to recognise it,
      the three remedies above. Run `Rscript -e "roxygen2::roxygenise()"`; `NAMESPACE` diff must
      be empty (helper is internal).
- [ ] README: one troubleshooting bullet under the Boards section pointing at the new section.
      Vignettes untouched (no `local_dir`/OneDrive content there).
- [ ] `.Rbuildignore` already covers `.claude`, `.docs`, `CLAUDE.md`; nothing to add unless step 1
      created a new top-level file.

### 5. Verify

- [ ] Full suite in the worktree: `Rscript -e "devtools::test()"`: 0 failed, 0 warnings.
      Pay attention to `test-board.R`, `test-integration.R` (`local_dir` round trip),
      `test-raw-connection.R`, `test-output.R`, which share the changed call sites.
- [ ] `Rscript -e "devtools::check(args = '--no-manual')"` or at least `R CMD build` + examples run.
- [ ] Opt-in real check (both environments, same script), using
      `GDPINS_TEST_PROTECTED_DIR=<OneDrive>/gdpins_cfa_check`:
      - via Rscript: board created, pin written and read back, directory removed with
        `unlink(dir, recursive = TRUE, force = TRUE)` (`force` handles pins' read-only files);
      - via `mcp__r__repl` (a subagent runs it): fails with `gdpins_error_local_dir` and the
        hint. Record both outputs in the Decision Log. Confirm nothing is left in OneDrive.
      Encode this as a `skip_if(!nzchar(Sys.getenv("GDPINS_TEST_PROTECTED_DIR")))` test in
      `test-local-dir.R` so it is repeatable but off by default.

### 6. Pull request

- [ ] Commit on `fix/local-dir-eperm` with explicit paths (`R/utils-dir.R`, `R/board.R`,
      `R/raw-connection.R`, `R/output.R`, `tests/testthat/test-local-dir.R`, `DESCRIPTION`,
      `NEWS.md`, `README.md`, `.gitignore` if changed). Message in plain prose, no trailer.
- [ ] `git push -u origin fix/local-dir-eperm`, then
      `gh pr create --base main --head fix/local-dir-eperm --title "Clear error when a local directory cannot be prepared" --body-file <file>`.
      Body: root cause with the Defender event text, what changed, what deliberately did not
      change (no attempt to bypass CFA; base `dir.create` rejected and why), how it was tested
      (regression test failing on main, full suite, opt-in OneDrive run in both environments).
      No email address, no AI attribution.
- [ ] Update this plan: `pr:` link in the front matter, `status: review`, tick the boxes.
- [ ] After merge: `git worktree remove .claude/worktrees/fix-local-dir-eperm`, delete the
      branch, set this plan to `status: done` and fill in Outcome.

### 7. Environment remediation (outside the PR, for the user)

This part is a security decision and is written in full sentences on purpose. The blocked binary
lives in a user-writable folder (`%USERPROFILE%\.local\bin`). Allowing it through Controlled
Folder Access means any file later placed at that path inherits the permission. Prefer the first
two options; take the third only with IT's agreement.

1. Keep using the default cache root (`~/.gdpins/cache`) or any folder outside OneDrive and the
   other protected folders for boards used from MCP sessions. This already works.
2. Run OneDrive-targeting gdpins work through the full-path `Rscript.exe` (current workaround).
3. Ask IT (admin rights required, and the list looks centrally managed) to allow the worker:
   `Add-MpPreference -ControlledFolderAccessAllowedApplications "C:\Users\wb532966\.local\bin\mcp-repl.exe"`.
   Confirm afterwards with the `Get-WinEvent` query above: no new 1123/1124 events.

## Open questions

- Should `.prepare_local_dir()` also wrap the per-file `fs::dir_create(dirname(...))` sites in
  `R/raw-connection.R` and `R/sync.R`? They sit under an already prepared `local_path`, so the
  plan leaves them; revisit if a CFA block appears mid-sync.
- Plan numbering: `.docs/plans/` was empty, so this file is `0001` (per-folder series). If the
  series is meant to be shared with `.docs/notes/`, rename is not allowed; leave as is.
- Upstream: `pins::board_folder()` and `pins:::pin_store.pins_board_folder()` call
  `fs::dir_create` and `fs::file_chmod` unconditionally; an issue to r-lib/fs or rstudio/pins
  about CFA-friendly behaviour is optional and not part of this plan.

## Side findings (not in scope)

- `identical(pin_read(...), mtcars)` is `FALSE` because the parquet format drops row names
  (`rownames` come back as `"1" "2" "3"`); `all.equal(..., check.attributes = FALSE)` is `TRUE`.
  Already recorded as M18 in `.docs/notes/0001-audit-2026-10-03.md:187-189`.
- pins writes pinned files read-only (`pin_store.pins_board_folder` runs
  `fs::file_chmod(out_paths, "u=r")`). Use `unlink(..., recursive = TRUE, force = TRUE)` to
  remove test boards.

## Decision Log

### 2026-10-03 — Root cause is Controlled Folder Access, not gdpins or fs
**Decision:** Treat the bug as environmental; scope the package change to diagnostics.
**Rationale:** Defender events 1123/1124 name `mcp-repl.exe` as blocked from modifying
`%userprofile%\OneDrive - WBG`; three independent MCP worker processes fail, `Rscript.exe`
never does, with identical R, fs and pins versions and library.

### 2026-10-03 — Rejected: swap `fs::dir_create` for base `dir.create` / skip when existing
**Decision:** Do not change the creation primitive.
**Rationale:** From the blocked process base `dir.create()` also fails (`'No such file or
directory'`), and `pins::board_folder()` calls `fs::dir_create()` unconditionally on the same
path immediately afterwards. The swap would move the error one frame later and make it less
clear (a warning plus `FALSE` instead of a classed condition).

### 2026-10-03 — Regression test mocks `fs::dir_create` via `.package = "fs"`
**Decision:** First choice is mocking fs's binding so the test fails on `main` with the raw fs
class and passes with the gdpins class; fallback is an internal `.fs_dir_create()` seam.
**Rationale:** Mocking the real callee is the only way the pre-fix failure matches the reported
symptom. The seam fallback follows the project memory "mock a seam instead".

## Outcome

Filled in when the status becomes done or superseded.
