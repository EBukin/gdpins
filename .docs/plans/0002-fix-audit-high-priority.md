---
status: pending
issue:
pr:
---

# Fix audit high-priority bugs H1–H8 (TDD, one branch, one PR)

- **Date:** 2026-10-03
- **Author:** Claude (research only, no code run: six read-only Sonnet investigators, four Opus verifiers); requested by Eduard Bukin
- **Status:** draft

## Goal

The eight high-severity findings in `.docs/notes/0001-audit-2026-10-03.md` (H1–H8) are closed on one branch, `fix/audit-high-priority`, developed in a worktree under `.claude/worktrees/` and merged through one pull request. Every bug has a regression test that was written first, confirmed to fail against `main` for the documented root cause, and then made to pass by the smallest fix. The full testthat suite and `R CMD check` are clean. `DESCRIPTION`, `NEWS.md`, roxygen docs, README and the vignette describe the new behaviour.

## Context

- The audit was written against `feat/single-local-copy` at `d59ca3b` plus uncommitted edits. That work is merged into `main` (`0a573d8`, PR #20). Every line number in the audit is stale. Every line number below was re-located in the current working tree by read-only reading and then re-checked by a second reader. Re-`grep -n` once more before editing: the fixes shift lines.
- No R code was run during planning. Claims about pins and googledrive internals were verified against the upstream sources for the installed versions (pins 1.4.2: `R/board_folder.R`, `R/pin-read-write.R`, `R/pin-upload-download.R`, `R/pin_versions.R`, `R/pin-meta.R`; googledrive 2.1.1: `R/drive_ls.R`, `R/drive_find.R`, `R/drive_get.R`). The remaining **UNVERIFIED** items are listed where they matter and are settled by the first red/green run.
- Project rules that bind this work: `CLAUDE.md` (dependency, docs, backward-compatible API, tests, NEWS, README/vignette, `.Rbuildignore`); no `Co-Authored-By`, no "Generated with", no e-mail address in commits or PR text (`.claude/hooks/no-coauthor.sh` blocks `git commit` and `gh pr`, and scans `--body-file` only when the path is unquoted); stage explicit paths; run R through `Rscript` from the worktree root, not the MCP R session; never spawn background lock-holding processes in tests.
- Test harness facts the tests below rely on (`tests/testthat/helper-fakes.R`): `new_fake_board(config, versioned)` and `new_fake_raw_conn(config)` build real objects over `tempfile()` directories **directly inside the session `tempdir()`** with a `gdpins_fake_drive()` adapter; the fake adapter resolves paths through the filesystem (`R/drive-adapter.R:261-264`, `:287-290`) and has no failure injection, so Drive errors are simulated by mocking the package wrappers (`local_mocked_bindings(gd_ls = ..., .package = "gdpins")`, precedent `tests/testthat/test-sync.R:1352-1356`); conflicts are forced by mocking `gdpins_board_status` (`test-sync.R:15-40`) or by two `pins::pin_write()` calls in the same second (`test-integration.R:189-202`); `setup.R` points `gdpins.cache_dir` at a tempdir; `mock_status_row()` asserts the status schema (`helper-fakes.R:155`), so the status tibble keeps its columns; `gdpins_pin_write()`, `gdpins_board_status()` and `gdpins_sync()` call the real DNS probe `gdpins_is_online()` (`R/verbs.R:149-157`, `R/sync.R:209`, `:356`, `:556`, `:774`), so every new test that touches a Drive-backed object mocks `gdpins_is_online = function() TRUE` (precedent `test-verbs.R:9`).
- pins facts that shape H5, H6 and H8 (pins 1.4.2 sources): `pins:::check_pin_name()` rejects only `/` and `\` (class `pins_check_name`); `pin_exists.pins_board_folder` is `fs::dir_exists(fs::path(board$path, name))`; `pin_delete.pins_board_folder` is `fs::dir_delete(fs::path(board$path, name))`; `pin_list.pins_board_folder` is `fs::path_file(fs::dir_ls(board$path, type = "directory"))` with `all = FALSE`, so loose files and dot-named directories are invisible to pins; version ids are `format(created, "%Y%m%dT%H%M%SZ")` + `-` + the **first 5 characters** of `pin_hash` (`version_name()`), and `pin_versions()$hash` is that 5-character prefix parsed from the directory name (`NA` when the name does not parse); `pin_hash` is xxhash64 of the file bytes; `pin_write()` skips a write whose hash equals the **latest** version's hash unless `force_identical_write = TRUE`, but `pin_upload()` (the path gdpins uses for parquet data frames, `R/verbs.R:34`) never skips; `version_setup()` rejects a new id only when it equals the **oldest** existing id, otherwise a same-second write lands in the existing directory with `file_copy(overwrite = TRUE)` over files that pins made read-only (`file_chmod("u=r")`); "latest" is the last row of `pin_versions()`, so two ids in the same second sort by hash prefix, not by write order.
- googledrive facts that shape H3/H4: `drive_ls()` forwards `pattern` to `drive_find()`, which applies `grep(pattern, res_tbl$name)` **client-side after the API fetch**, so listing without `pattern` costs the same API calls; an empty folder yields a 0-row dribble; `drive_get()` on a missing id raises a gargle API error, it does not return 0 rows.
- testthat: `local_mocked_bindings()` exists since 3.1.7 and is stable since 3.2.0; `.package = "googledrive"` intercepts `googledrive::drive_ls()` calls made from gdpins (precedent `test-auth.R:92-117` and `test-sync.R:1365-1370`, `.package = "pins"`). `DESCRIPTION` declares `testthat (>= 3.0.0)`, already under-declared; bump to `>= 3.2.0`.
- A sibling plan, `.docs/plans/0001-local-dir-eperm-onedrive-cfa.md`, also targets `0.0.1.9027` on its own branch. Whichever branch merges second bumps to `0.0.1.9028` and renames its NEWS heading.

## Branch, worktree, pull request

1. From `main` at `0a573d8`:
   ```
   git worktree prune
   git worktree add .claude/worktrees/fix-audit-high -b fix/audit-high-priority main
   ```
   `git worktree prune` drops the stale `merge-arrow-slc` entry. `.claude/worktrees/` is ignored through `.git/info/exclude` (`**/.claude/worktrees/`, local to this clone) and `.Rbuildignore` (`^\.claude$`), so no `.gitignore` change is needed.
2. The worktree has no renv library (`.Rprofile` sources `renv/activate.R`; `renv/library/` is git-ignored). First command in the worktree:
   ```
   Rscript -e "renv::restore(prompt = FALSE)"
   ```
3. All edits, tests and commits happen inside the worktree. Run R from the Bash tool (PowerShell 5.1 strips the inner quotes of a single-quoted `-e` argument):
   ```
   Rscript -e "devtools::load_all('.'); testthat::test_file('tests/testthat/<file>.R')"
   Rscript -e "devtools::test()"
   Rscript -e "devtools::check(args = '--no-manual')"
   ```
4. One commit per phase, only after that phase is green and the full suite is green. Conventional-commit subject, plain body, no attribution trailer, no e-mail.
5. When all phases are green and `devtools::check()` is clean, write the PR body to a file in the scratchpad and pass its path unquoted so the hook scans it:
   ```
   git push -u origin fix/audit-high-priority
   gh pr create --base main --head fix/audit-high-priority --title "fix: close audit high-priority findings H1-H8" --body-file <path>
   ```
   The body lists the eight findings, the regression test for each, the deliberate behaviour changes (unversioned-board conflict now stops; prune return shape; ambiguous Drive names error; Drive errors surface at init) and the remediation note for duplicate Drive files created by the old H3 bug. Record the PR URL under Outcome and in the front matter.

## TDD protocol (applies to every bug)

1. Add the test(s) to the named test file. Run that file alone. Each test must fail, and fail for the stated root cause (wrong state, a deletion that happened, no error raised), not for a typo, a missing helper, or an unmocked `gdpins_is_online()`. Record the failure message in the commit body.
2. Make the smallest change in `R/` that turns the test green. No refactoring beyond what the fix needs.
3. Re-run the file, then the full suite: `0 failed, 0 warnings`. Fix every test listed under "Tests to flip" for that bug.
4. Update roxygen (`@param`, `@return`, `@section`), run `roxygen2::roxygenise()`, confirm the `NAMESPACE` diff is empty (no new exports are planned).
5. Commit.

## Cross-cutting decisions

- **New file `R/validate.R`** holds `.check_pin_name()`, `.check_rel_name()` and `.check_local_dest()`. All `@keywords internal`, not exported.
- **Condition classes.** Errors use `cli::cli_abort(..., class = c("<specific>", "gdpins_error"), call = call)` with `call = rlang::caller_env()` captured as a default argument of the validator, so the user sees the public verb. The only class in `R/` today is `gdpins_error_unreadable_file` (`R/sync.R:970`); `R/cli.R` has no abort helper, so direct `cli_abort(class = )` is the convention.
  - `gdpins_error_invalid_name` — pin or raw name rejected (H1, H2).
  - `gdpins_warning_invalid_name` — a Drive-listed name was skipped in a bulk loop (H1, H2).
  - `gdpins_error_path_escape` — a joined local path resolves outside `local_path` (H2).
  - `gdpins_error_ambiguous_drive_name` — more than one Drive item shares a name (H3).
  - `gdpins_error_sync_conflict` — the final abort of `on_conflict = "stop"` (today unclassed, `R/sync.R:668-675`); `gdpins_error_unversioned_conflict` is prepended when an unversioned board hit `"version"` (H5).
  - `gdpins_warning_raw_conflict_backup` — the raw backup warning (H7).
- **Test helpers** go in `tests/testthat/helper-fakes.R`: `fake_dribble(name, id, mime, md5, mtime)` for the real-adapter tests (H3/H4) and `new_sandboxed_board(parent)` / `new_sandboxed_raw_conn(parent)` that build objects over sub-directories of a `withr::local_tempdir()` (H1/H2 red tests must **never** use `new_fake_board()` / `new_fake_raw_conn()` with `.` or `..`: on current code those names delete the session `tempdir()` and every later fixture).
- **DESCRIPTION**: `Version: 0.0.1.9027`; `Suggests: testthat (>= 3.2.0)`. No new Imports (`fs`, `tools`, `rlang`, `cli`, `tibble` already present; `rlang` 1.1.6 installed, `rlang::hash()` available).
- **NEWS.md**: new top heading `# gdpins 0.0.1.9027` with "Breaking changes" (prune return shape; unversioned conflict stops; ambiguous Drive names error; Drive errors surface during init), "Bug fixes" (H1–H8, noting that H8 also closes L5), "Security" (H1, H2) and "Known limitations" (see H6).
- **Status tibble schema is unchanged** by H6.
- **Phase order**: H1+H2, H3+H4, H5+H7, H6, H8, docs/check/PR. H5/H7 precede H6 because H6 routes more cases into the conflict branches. H8 does not depend on H6.

---

## H1 — pin name `..` / `.` escapes the board

### Root cause (confirmed by reading; pins facts verified upstream)

- The only check on the pin verbs is "non-empty character scalar": `R/verbs.R:144-146` (`gdpins_pin_write`), `:350-352` (`gdpins_pin_path`), `:431-433` (`gdpins_pin_read`), `:556-558` (`gdpins_pin_remove`).
- `gdpins_prune_pin_versions` (`R/prune.R:172-249`) validates `board` (`:181-186`) and `keep` (`:187-193`) and never checks `name`. `.remove_local_version()` (`:69-74`) is `fs::dir_delete(file.path(board_path, name, version))`; `.trash_drive_version()` (`:56-59`) pastes `drive_path/name/version`. `pins::pin_versions(board, "..")` lists the siblings of `cache_dir` as versions (non-`ts-hash` names get `NA` `created`).
- `gdpins_pin_remove` calls `pins::pin_exists()` then `pins::pin_delete()` per sub-board (`R/verbs.R:569`, `:573`). On `board_folder` that is `fs::dir_delete(<cache_dir>/..)`: the parent of `cache_dir` is deleted. `"."` deletes the board.
- `gdpins_pin_read`/`_path` and `gdpins_sync` are safe on `board_folder` because names must come from `pins::pin_list()` (`.resolve_pin_name()` `R/verbs.R:255`, `.pin_candidates()` `:224-230`, `R/sync.R:220-222`) and a directory listing never contains `.`/`..`. **On a real Drive board** (`pins::board_gdrive`, `R/board.R:519`, `:599`) `pin_list` returns every Drive item name (`googledrive::drive_ls(board$dribble)$name`), so a Drive folder named `..` (created by a collaborator, or by the H2 bug through `.ensure_dir()` `R/drive-adapter.R:95`) reaches `.copy_pin_to_board()` (`R/sync.R:702-745`, writes version dirs into the parent of `cache_dir`), `gdpins_prune_board_versions` (`R/prune.R:301`, deletes siblings) and `.pin_candidates()`.
- A dot-named pin would be written but never listed (`dir_ls(all = FALSE)`), so sync, board prune and name resolution could never see it; it would also collide with the H6 baseline file `.gdpins-sync.rds`. Rejecting a leading dot therefore breaks nothing usable.

### Failing tests (new file `tests/testthat/test-validate.R`)

- `gdpins_pin_remove(board, "..")` on a `local_only` board built with `new_gdpins_board()` (`R/classes.R:45-54`) over `<local_tempdir>/cache`, with `<local_tempdir>/sentinel.txt` beside it: `expect_error(class = "gdpins_error_invalid_name")`, then `expect_true(file.exists(sentinel))`. Today: pins deletes `<local_tempdir>` (acceptable: withr tolerates a missing dir), so the class assertion fails.
- `gdpins_prune_pin_versions(board, "..", keep = 1, dry_run = FALSE, force = TRUE)` with two version-shaped siblings next to `cache` (`20260101T000000Z-aaa`, `20260102T000000Z-bbb`): expect the class error and `aaa` still exists. Today: `pin_versions` returns 3 rows (the two siblings and `cache`, NA `created`), two are removed, `aaa` is deleted whichever way NAs sort. (`keep = 0` must not be used: `keep < 1` aborts at `R/prune.R:188-193` before any deletion.)
- Parametrised rejection across `gdpins_pin_write`, `gdpins_pin_read`, `gdpins_pin_path`, `gdpins_pin_remove`, `gdpins_prune_pin_versions` on a sandboxed board: `".", "..", "a/b", "a\\b", ".hidden", "a\nb", NA_character_, character(0), c("a", "b"), ""`. Every call raises `gdpins_error_invalid_name` before touching storage. Keep the message text "non-empty character scalar" for the scalar branch so `test-verbs.R:306`, `:377`, `:465`, `test-name-resolution.R:307`, `test-raw-connection.R:298-299` keep matching.
- Acceptance: `"my_pin"`, `"pin-2024"`, `"Quarterly.Report"` still write and read.
- Drive-sourced names: `gdpins:::.copy_pin_to_board(src, dst, "..")` raises `gdpins_error_invalid_name`; `.board_status_board()` with `pins::pin_list` mocked (`.package = "pins"`, capture the real function first and dispatch on `board$path`) to return `c("ok", "..")` for the Drive board emits `gdpins_warning_invalid_name` and reports only `ok`.

### Fix

- `R/validate.R`:
  ```r
  .check_pin_name <- function(name, arg = rlang::caller_arg(name), call = rlang::caller_env()) {
    if (!is.character(name) || length(name) != 1L || is.na(name) || !nzchar(name)) {
      cli::cli_abort("{.arg {arg}} must be a non-empty character scalar.",
                     class = c("gdpins_error_invalid_name", "gdpins_error"), call = call)
    }
    if (name %in% c(".", "..") || startsWith(name, ".") ||
        grepl("[/\\\\]", name, useBytes = TRUE) || grepl("[[:cntrl:]]", name, useBytes = TRUE)) {
      cli::cli_abort(c(
        "{.arg {arg}} is not a valid pin name: {.val {name}}.",
        i = "A pin name cannot be {.val .} or {.val ..}, start with a dot, or contain a path separator or control character."
      ), class = c("gdpins_error_invalid_name", "gdpins_error"), call = call)
    }
    invisible(name)
  }
  ```
- Replace the scalar checks at `R/verbs.R:144-146`, `:350-352`, `:431-433`, `:556-558` with `.check_pin_name(name)`. Insert it in `gdpins_prune_pin_versions` after the `board` check (`R/prune.R:186`), at the top of `.copy_pin_to_board()` (`R/sync.R:702`) as a backstop, and in `gdpins_pin_info` (`R/discovery.R:137-138`) for consistency.
- Bulk loops skip and warn instead of aborting: in `.board_status_board()` (after `R/sync.R:222`) and `gdpins_prune_board_versions()` (after `R/prune.R:301`) drop names that fail `.check_pin_name()` and emit one `cli::cli_warn(class = "gdpins_warning_invalid_name")` listing them.
- Roxygen: `@section Pin names:` on the `verbs` topic (`R/verbs.R:1-8`, `@name verbs`), referenced from `gdpins_prune_pin_versions` (`R/prune.R:146`).
- Optional, low exposure (reads only): validate the `version` argument of `gdpins_pin_read`/`gdpins_pin_path` against `/`, `\`, `..`.

### Tests to flip

- None: no existing test, vignette or README uses a dot-leading pin name, a separator, or `..` (grep of `tests/testthat/*.R`, `vignettes/*.Rmd`, `README.md`). `test-prune.R:558-559` (vector name, unclassed `expect_error`) and `test-raw-connection.R:639` (`123L`) stay green.

---

## H2 — raw file names and Drive names escape `local_path`

### Root cause (confirmed by reading)

- `.drive_full_path()` (`R/raw-connection.R:388-390`) and `.local_full_path()` (`:393-395`) join names with no check. `fs::path_has_parent()`/`fs::path_norm()` appear nowhere in `R/`.
- User-supplied names: `gdpins_raw_put_object` (`:712-728`, `.check_ext()` only, joins at `:718`, `:723`), `gdpins_raw_put_file` (`:745-773`, extension presence only, `:763`, `:768`), `gdpins_raw_remove` (`:800-845`, scalar check `:807-808`), `gdpins_raw_get` (`:1037-1068`, `:1044-1045`), `gdpins_raw_path` relative branch (`:982-1009`; scalar check on `name_or_id` at `:932-933`).
- A vector `name` on the put verbs fails at `:125` (`if (!nzchar(ext))` in `.raw_ext`) with base R's `the condition has length > 1`.
- Drive-sourced names: Drive-ID download in `gdpins_raw_path` (`:973-978`, `# nocov`, real adapter only; `file.path(conn$local_path, filename)` at `:974` does **not** go through `.local_full_path`), `gdpins_raw_connect` discrepancy loops (`:645-650`, `:663-669`, build paths by hand from `local_path`), `gdpins_refresh_disconnect` (`:1222-1236`, uses `.local_full_path` at `:1229`), `.raw_copy_to_local` (`R/sync.R:978-987`, by hand at `:980-983`) and `.raw_copy_to_drive` (`:955-975`, by hand at `:956-959`). Ladder-resolved names (`.resolve_raw_name`, used at `:991`, `:1056`) come from the Drive listing, so on the real adapter a Drive folder `..` yields `../x.csv` into `.local_full_path` — the guard must live inside `.local_full_path` itself.
- On the real adapter `put_object(conn, x, "../x.csv")` makes `.ensure_dir()` (`R/drive-adapter.R:85-101`) create a Drive folder literally named `..` (`:95`). On the fake adapter the escape really happens on disk (`:261-264`).
- Subfolder names with `/` are documented (`:702-703`), so the raw validator allows `/` and rejects only `..`/`.` segments, absolute paths, drive letters, backslashes, control characters, and Windows-stripped segments (trailing dot or space; `"a/.. /x.csv"` would bypass both the regex and `fs::path_norm`).

### Failing tests (`tests/testthat/test-validate.R`, raw cases also in `test-raw-connection.R`)

- `gdpins_raw_put_object(conn, mtcars, "../sentinel.csv")` on a `local_only` raw conn built with `new_gdpins_raw_conn()` (`R/classes.R:101-106`) over `<local_tempdir>/mirror`, sentinel at `<local_tempdir>/sentinel.csv`: `expect_error(class = "gdpins_error_invalid_name")`, sentinel bytes unchanged. Today: the sentinel is overwritten.
- Parametrised over `gdpins_raw_put_object`, `gdpins_raw_put_file`, `gdpins_raw_remove`, `gdpins_raw_get`, `gdpins_raw_path`: `"..", "a\\b", "a\nb", NA_character_, character(0), c("a.csv", "b.csv"), "", "C:/x.csv", "/x.csv", "../x.csv", "sub/../../x.csv", "./a.csv", "a/.. /x.csv", "a/... /x.csv"`. Vector input gives the gdpins class, not `the condition has length > 1`.
- Acceptance: `"sub/a.csv"`, `"a..b.csv"`, `"my data (2024).csv"`, `"report - final v2.csv"`, `"a{bad}.csv"` (all used by existing tests) are accepted.
- Drive-sourced, direct helper calls (the fake adapter's recursive listing cannot yield a parent-escaping path): with `conn <- new_sandboxed_raw_conn(parent)` (`drive_local`), seed `<fake_root>/gdpins-fake/sentinel.csv` on the fake Drive with bytes B and `<parent>/sentinel.csv` with bytes A; `expect_error(.raw_copy_to_local(conn, "../sentinel.csv"), class = "gdpins_error_path_escape")`; `<parent>/sentinel.csv` still holds A. Today: `gd_download` overwrites it. Add `"a\\..\\..\\x.csv"` (Windows separator) as a second case. For `.raw_copy_to_drive(conn, "../x.csv")`: seed `<dirname(local_path)>/x.csv`, expect `gdpins_error_invalid_name`, and assert `<fake_root>/gdpins-fake/x.csv` does not exist. Today: it is created there (`R/drive-adapter.R:261-264`, `:298-303`).

### Fix

- `R/validate.R`:
  ```r
  .check_rel_name <- function(name, arg = rlang::caller_arg(name), call = rlang::caller_env()) {
    if (!is.character(name) || length(name) != 1L || is.na(name) || !nzchar(name)) {
      cli::cli_abort("{.arg {arg}} must be a non-empty character scalar.",
                     class = c("gdpins_error_invalid_name", "gdpins_error"), call = call)
    }
    bad <- grepl("\\\\", name, useBytes = TRUE) ||            # backslash
      grepl("^/", name) || grepl("^[A-Za-z]:", name) ||        # absolute / drive letter
      grepl("(^|/)\\.\\.(/|$)", name) ||                        # ".." segment
      grepl("(^|/)\\.(/|$)", name) ||                           # "." segment
      grepl("(^|/)[. ]+(/|$)", name) || grepl("[. ](/|$)", name) || # dot/space-only or trailing dot/space segment (Win32 strips them)
      grepl("[[:cntrl:]]", name, useBytes = TRUE)
    if (bad) {
      cli::cli_abort(c(
        "{.arg {arg}} is not a valid relative file name: {.val {name}}.",
        i = "Use a relative path with {.val /} separators; no {.val ..} or {.val .} segments, no absolute path, no backslash, no segment ending in a dot or space, no control characters."
      ), class = c("gdpins_error_invalid_name", "gdpins_error"), call = call)
    }
    invisible(name)
  }

  .check_local_dest <- function(local_dest, local_path, call = rlang::caller_env()) {
    dest <- fs::path_norm(fs::path_abs(local_dest))
    root <- fs::path_norm(fs::path_abs(local_path))
    if (!fs::path_has_parent(dest, root)) {
      cli::cli_abort("Refusing to write {.path {local_dest}}: it resolves outside {.path {local_path}}.",
                     class = c("gdpins_error_path_escape", "gdpins_error"), call = call)
    }
    invisible(dest)
  }
  ```
  Optionally also reject `:` inside a segment (NTFS alternate data streams).
- `.check_rel_name(name)` first thing in `gdpins_raw_put_object` (`:712`), `gdpins_raw_put_file` (`:745`), `gdpins_raw_remove` (replace `:807-808`), `gdpins_raw_get` (replace `:1044-1045`), `gdpins_raw_path` relative branch (`:982`; keep the scalar check at `:932-933` before the glob/Drive-ID tests), and at the top of `.raw_copy_to_drive` (`R/sync.R:955`).
- `.local_full_path()` (`:393-395`) calls `.check_local_dest()` on its result (covers `:205`, `:718`, `:763`, `:837`, `:986`, `:992`, `:1062`, `:1229` and every ladder-resolved name). Explicit `.check_local_dest()` calls after the hand-built joins at `:646-647`, `:665-666` (local variable `local_path`, no conn yet), `:974`, and `R/sync.R:980-983`; `.check_local_dest()` on the source path at `R/sync.R:956-959`.
- Bulk Drive-sourced loops (connect `:645-669`, `gdpins_refresh_disconnect` `:1228-1232`, `.sync_raw` via `attempt()`) **skip** the offending file with a `gdpins_warning_invalid_name` warning so one hostile name does not leave a partial mirror; single-file verbs abort.
- Roxygen: `@param name` on `gdpins_raw_put_object` (`:702-703`), `gdpins_raw_put_file` (`:739`), `gdpins_raw_remove` (`:782`), `gdpins_raw_get`, `gdpins_raw_path` gains one sentence on the rules.

### Tests to flip

- None expected; re-grep `test-raw-connection.R`, `test-sync.R`, `test-name-resolution.R` for raw names with `\\`, a leading `/`, or a trailing dot/space before landing. The Drive-ID branch (`:973-978`) stays `# nocov` (the fake adapter aborts on IDs at `:952-958`); its `.check_local_dest()` call is not test-covered and is noted in the PR.

---

## H3 — Drive name lookups use the name as an unescaped regex

### Root cause (confirmed by reading; googledrive facts verified upstream)

- `googledrive::drive_ls(current, pattern = paste0("^", part, "$"))` at `R/drive-adapter.R:91` (`.ensure_dir`), `:147` (`upload`, `name_part`), `:585` (`.resolve_real_path`, used by `get_id`, `get_url`, `exists`, `download`, `trash`, `md5`, `mtime`, `ls`). First-row picks at `:97`, `:151` (`drive_update(existing[1L, ])`), `:589`. `trash()` silently no-ops on `NULL` (`:167-173`).
- A name containing `(`, `)`, `+`, `[`, `*`, `?`, `^`, `$`, `|`, `{`, `}` never matches itself: `exists()` is `FALSE`, `download()` says "not found", `trash()` does nothing, `upload()` always takes the `drive_upload()` branch and creates a **duplicate Drive file on every write**. `.` matches any character, so `a.csv` matches `abcsv` and `[1L, ]` can update or trash the wrong file.
- Prefix strip with the connection root as an unescaped regex: `R/raw-connection.R:414-415` (`.gd_ls_to_rel`). The adapter-root strip at `:409-410` is escaped; `.drive_rel()` in `R/sync.R:507-509` already uses `startsWith()` + `substring()`.
- No caller relies on regex semantics: the only `drive_ls(` / `pattern =` uses on names are `:91`, `:147`, `:202`, `:585`, `:632`; glob listing is done locally with `fs::path_filter` (`R/raw-connection.R:230-235`, `R/verbs.R:233-235`); no roxygen in `R/drive-adapter.R` or `R/raw-connection.R` mentions regex. The name ladder (`.resolve_raw_name`, `R/raw-connection.R:271-303`) resolves to the listed spelling before the adapter is called (`:991-1004`), so exact `==` matching does not change case behaviour (`grep` was already case-sensitive).
- Nothing tests this: every real-adapter internal is `# nocov` (`R/drive-adapter.R:61,216,578,592,598,625,631,647`), and the "parenthesised name" tests (`test-drive-adapter.R:448-460`, `test-raw-connection.R:507,661`) run on the fake adapter, which resolves through the filesystem.

### Failing tests (new file `tests/testthat/test-drive-adapter-real.R`)

Every test: `local_mocked_bindings(gdpins_ensure_drive_auth = function(email) invisible(NULL), .package = "gdpins")`; `adapter <- gdpins_real_drive("<25+ char id>")` (an id without `/` or space avoids the `drive_get` path at `:62-68`); `local_mocked_bindings(drive_get = ..., drive_ls = ..., drive_mkdir = ..., drive_upload = ..., drive_update = ..., drive_download = ..., drive_trash = ..., .package = "googledrive")` so no googledrive call reaches the network. `as_id` stays real. The `drive_ls` mock mirrors upstream: `function(path = NULL, ..., recursive = FALSE)` that reads `pattern <- list(...)$pattern` and, when non-NULL, returns `res[grep(pattern, res$name), , drop = FALSE]` — otherwise the red test proves nothing. `fake_dribble()` (in `helper-fakes.R`) returns a plain tibble with `name` (chr), `id` (chr) and `drive_resource` (list of `list(kind = "drive#file", mimeType, md5Checksum, modifiedTime = "2024-01-01T00:00:00.000Z", size = "10")`), the fields the adapter reads at `:111`, `:118`, `:178`, `:185`, `:600-623`.

- Exact match: folder contains `quarterly report (Q1 2024).csv`; `expect_true(adapter$exists("quarterly report (Q1 2024).csv"))`. Today: the regex group `(Q1 2024)` cannot match the literal parentheses, 0 hits, `FALSE`.
- No over-match: folder lists `abcsv` (id_b), `axcsv` (id_x), `a.csv` (id_a) in that order; `expect_identical(adapter$get_id("a.csv"), "id_a")`. Today: `^a.csv$` matches all three and `[1L, ]` returns `id_b`.
- Ambiguity: two rows named `a.csv`; `expect_error(adapter$exists("a.csv"), class = "gdpins_error_ambiguous_drive_name")`. Today: `TRUE`.
- `upload()` into a folder already holding `report (final).csv` must call `drive_update`, not `drive_upload` (mocks record calls). Today: `drive_upload`.
- `gd_mkdir(adapter, "data (raw)")` when a folder `data (raw)` exists must not call `drive_mkdir`. Today: duplicate folder.
- Prefix strip (`test-raw-connection.R`): `gdpins:::.gd_ls_to_rel("data (raw)/a.csv", <fake adapter>, "data (raw)")` → `"a.csv"`. Today: unchanged.

### Fix

- At `:91`, `:147`, `:585`: list the parent without `pattern`, then `hits <- hits[hits$name == part, , drop = FALSE]`. If `nrow(hits) > 1L`, abort with `class = c("gdpins_error_ambiguous_drive_name", "gdpins_error")`, naming the path walked so far (`walked <- c(walked, part)`; `paste(walked, collapse = "/")`) and listing each duplicate's `id` and `modifiedTime` so the user can trash the extras. Keep `[1L, ]` only after that guard. Exact comparison is chosen over a `.regex_escape()` helper: it removes regex semantics entirely, mirrors `.drive_rel()`, and has no escaping edge cases.
- `R/raw-connection.R:413-415`:
  ```r
  prefix <- paste0(drive_path, "/")
  hit    <- startsWith(paths, prefix)
  paths[hit] <- substring(paths[hit], nchar(prefix) + 1L)
  ```
- Remove `# nocov` around `.resolve_real_path`, `.real_hits_to_tbl`, `.real_ls_recursive` and the adapter closures the new tests cover; keep it on the path-string `drive_get` branch `:62-68`. No coverage gate exists (`.github/` empty, no `codecov.yml`/`.covrignore`).
- NEWS "Breaking changes": duplicate-named Drive items now error instead of one being picked. NEWS remediation: the old bug created a duplicate file on every write of a name with regex metacharacters; list them with `googledrive::drive_ls(<folder>)`, keep the newest `modifiedTime`, `drive_trash()` the rest.

---

## H4 — Drive listing/lookup errors are swallowed and read as "absent"

### Root cause (confirmed by reading)

| Site | Wraps | NULL/empty means "absent"? | Consequence |
|---|---|---|---|
| `R/drive-adapter.R:90-93` | `drive_ls` in `.ensure_dir` | yes → `drive_mkdir` | duplicate folder on auth/quota error |
| `:146-149` | `drive_ls` in `upload` | yes → `drive_upload` | duplicate file on every put while the error lasts |
| `:202` | `drive_ls` in `ls` | yes → empty listing | other side looks ahead of an "empty" folder |
| `:584-587` | `drive_ls` in `.resolve_real_path` | yes → `NULL` for every verb | `exists` FALSE, `download` "not found", `trash` no-op (`raw_remove` thinks the file is gone), `md5`/`mtime` NA |
| `:632` | `drive_ls` in `.real_ls_recursive` | yes → subtree dropped | partial listing looks complete |
| `R/sync.R:220-221` | `pins::pin_list(drive_board)` / `(local_board)` | yes → `character()` | every local pin `local_ahead` → sync pushes stale local content over Drive |
| `R/sync.R:291-297` | `pins::pin_versions` in `.latest_version` | yes → pin absent on that side | one pin misreported `*_ahead` |
| `R/sync.R:365-368` | `gd_ls` in `.board_status_raw` | yes → `.empty_gd_ls_tbl()` | every local file `local_ahead` → raw sync uploads stale copies; `test-sync.R:1349-1359` asserts this as correct |
| `R/sync.R:703-740` | `pin_meta`/`pin_download`/`pin_read` in `.copy_pin_to_board` | warns, returns `invisible(NULL)` on success **and** failure | caller cannot tell a skipped copy from a done one (needed by H6) |

Left alone, with reasons: `gdpins_is_online()` probe in `.build_board` (`R/board.R:467`); `.handle_init_sync` (`R/board.R:115-125`, `:172-177`, `:184-190`; roxygen `:94-96` documents "caught, warning, board returned"); Drive-ID `drive_get` wrappers that re-raise (`R/raw-connection.R:961-966`) or abort immediately (`R/board.R:505-508`, `R/raw-connection.R:556-559`; optional improvement: pass `parent = e` so the real cause shows); local-only listings (`R/sync.R:323`, `:574`); `.drive_rel` fallback (`:518-521`); `attempt()` (`:806-816`, collected and reported); readability probe (`:929-935`); cosmetic count in `summary.gdpins_raw_conn` (`R/raw-connection.R:1281-1284`).

### Failing tests

- `test-drive-adapter-real.R`: `drive_ls` mocked to `cli::cli_abort("403", class = "httr2_http_403")`; `expect_error(gd_exists(adapter, "x"), class = "httr2_http_403")`; `expect_error(gd_ls(adapter, ""))` (covers `:202`); `expect_error(gd_ls(adapter, "", recursive = TRUE))` (`:632`); `expect_error(gd_mkdir(adapter, "sub"))` and `drive_mkdir` not called (`:91`); `expect_error(gd_upload(adapter, tmp, "x.csv"))` and neither `drive_upload` nor `drive_update` called (`:147`). Today: `FALSE`, empty tibble, `drive_mkdir` called, `drive_upload` called.
- `test-sync.R` (raw): write a local file first; mock `gdpins_is_online = function() TRUE` and `gd_ls` to abort with class `gdpins_error_drive_listing` (`.package = "gdpins"`); `expect_error(gdpins_board_status(conn), class = ...)`, `expect_error(gdpins_sync(conn), class = ...)`; afterwards the file is absent on the fake Drive (check with the real `adapter$exists`). Today: status has 0 rows and sync uploads the file.
- `test-sync.R` (board): `real <- pins::pin_list`; mock `pin_list = function(board, ...) if (identical(board$path, b$drive_board$path)) stop("403") else real(board, ...)` with `.package = "pins"`; `gdpins_is_online` mocked; `expect_error(gdpins_board_status(b))`, `expect_error(gdpins_sync(b))`, Drive board still has no pin. Today: `p1` reported `local_ahead`, then pushed.
- `.latest_version`: `pins::pin_versions` mocked to `stop()`; `expect_error(gdpins:::.latest_version(b$drive_board, "p"))`. Today: `NULL`.

### Fix

- Delete the `tryCatch(..., error = function(e) NULL)` wrappers at `R/drive-adapter.R:90-93`, `:146-149`, `:202`, `:584-587`, `:632` (same edit as H3 at three of them) and at `R/sync.R:220-221`, `:291-297`, `:365-368`. An empty result still means absent; an exception now propagates. No retry layer in this PR.
- `.copy_pin_to_board()` returns `TRUE` on success and `FALSE` after its warning; `.sync_board()` counts a copy and (H6) records the baseline only on `TRUE`. (Done inside the H5 refactor of that function.)
- `gd_*` wrapper roxygen (`R/drive-adapter.R:433-530`): "Errors from Drive propagate; an empty result means the path is absent."
- NEWS: Drive errors now surface during `gdpins_init_board()` / `gdpins_raw_connect()` (`gd_exists` at `R/board.R:498`, `R/raw-connection.R:551`; `gd_ls` at `:611`) instead of triggering the create-confirm path; transient errors mean "re-run". Note that `gdpins_raw_remove` deletes the local file before trashing on Drive (`R/raw-connection.R:836-841`), so a Drive error now surfaces after the local delete (previously silently ignored).

### Tests to flip

- `test-sync.R:1349-1359` "board_status_raw handles gd_ls error gracefully" → `expect_error(gdpins_board_status(conn))`.
- Unaffected (genuine absence on the fake adapter): `test-sync.R:1361-1373`; `test-board.R:792`; `test-drive-adapter.R:13-14, 199, 278, 290, 437`; `test-discovery.R:67`; `test-board.R:434-449`, `:857-890` (mock status/sync directly, `.handle_init_sync` still warns); `test-verbs.R:487-505`.

---

## H5 — "copy both directions" copies in the wrong order

### Root cause (confirmed by reading; pins facts verified upstream)

- Versioned branch `R/sync.R:595-606`: `.copy_pin_to_board(drive_board, local_board, pin_name)` at `:598`, then `.copy_pin_to_board(local_board, drive_board, pin_name)` at `:599`. Unversioned `"version"` branch `:625-636`: same two calls at `:627-628`.
- `.copy_pin_to_board()` (`:702-745`) always reads the source's **latest**: `pins::pin_download(src_board, pin_name)` (`:713-726`, file pins) and `.read_from_board(src_board, pin_name, NULL)` (`:732-743`) → `pins::pin_read(board, name)` with no `version` (`R/verbs.R:81-85`). It forwards only `type` (`:742`); `title`, `description`, `user` metadata, `tags`, `urls` are dropped (audit M12).
- Trace, versioned, local hL vs Drive hD: step 1 writes hD onto local (local {hL, hD}, latest hD). Step 2 reads local latest = hD and writes it to Drive. For rds pins `pin_write()` skips it as identical to Drive's latest; for parquet pins `pin_upload()` writes a duplicate hD version. Either way **hL never reaches Drive**. Status afterwards compares latest hashes (`:260-261`): hD == hD → `in_sync`. The docstring promise at `:103-105` is false.
- Unversioned: step 1 replaces local's single copy with hD; hL is gone; step 2 is a no-op or a rewrite of hD. Reported `in_sync`.
- "Conflict" is decided in `.compare_board_pin()` (`:242-288`): hashes differ and (either `created` NA, or `created` equal) → `"conflict"` (`:264-276`).
- Two more pins facts constrain the fix: version ids have one-second resolution and same-second ids sort by hash prefix; `version_setup()` aborts only when the new id equals the **oldest** id, otherwise a same-second write lands in the existing directory over read-only files (likely an error on Windows, **UNVERIFIED**). Writing the loser then the winner to the same board within one second is therefore about 50% flaky. Re-serialisation can change a hash: legacy `type = "parquet"` pins are read through arrow and rewritten by nanoparquet (`:732-743`), so only file pins and rds pins are byte-stable across a copy.

### Failing tests (`tests/testthat/test-sync.R`)

- Versioned: `.write_pin(b$drive_board, data.frame(x = 10), "p_vc2")` and `.write_pin(b$local_board, data.frame(x = 20), "p_vc2")` (rds, byte-stable); `h_drive <- substr(pins::pin_meta(b$drive_board, "p_vc2")$pin_hash, 1, 5)`, same for local (`pin_versions()$hash` is the 5-char prefix); run `with_mocked_bindings(gdpins_sync(b, on_conflict = "version"), gdpins_board_status = function(x) .fake_board_status_conflict("p_vc2"), gdpins_is_online = function() TRUE, .package = "gdpins")`. Assert both prefixes are in `pins::pin_versions(b$drive_board, "p_vc2")$hash` **and** in the local list; the unmocked `gdpins_board_status(b)` (online mocked) reports `in_sync`; `pins::pin_read()` of the latest on both sides is the same object. Today: `h_local %in% drive_hashes` fails.
- Metadata survives: write the local side with `title`, `description`, `metadata = list(k = 1)`; after resolution the Drive copy of that version carries the same `title`, `description`, `user$k`. Today: dropped.
- Unversioned: same setup with `versioned = FALSE`; `expect_error(gdpins_sync(b, on_conflict = "version"), class = "gdpins_error_unversioned_conflict")`; `pin_read(b$local_board)$x == 20` and `pin_read(b$drive_board)$x == 10` unchanged. Today: no error, local becomes 10.

### Fix

- Split `.copy_pin_to_board()` into `.snapshot_pin(src_board, pin_name)` (reads the latest version's files or object plus `pin_meta()` fields `type`, `title`, `description`, `user`, `tags`, `urls`, `pin_hash`, `created`; no writes; returns `NULL` after a warning on read failure) and `.write_pin_snapshot(dst_board, snap, pin_name)` (`pin_upload()` for file pins, `pin_write()` otherwise, forwarding `title`, `description`, `metadata = snap$user`, `tags`, `urls`; returns `TRUE`). `.copy_pin_to_board()` becomes the composition and returns `FALSE` when the snapshot is `NULL` (H4 row). The directional branches (`:641-653`) are unchanged.
- New `.await_new_version_second(board, name)`: if the board's latest `created` is in the current UTC second, sleep until the next second (at most about 1 s per write). Called before every write in the conflict resolution so each new id sorts last and never collides.
- Versioned conflict branch (`:595-606`): take both snapshots first. The snapshot with the later `created` (tie → Drive) is the final latest on both sides. Drive newer: write Drive's snapshot to local; write local's snapshot to Drive; write Drive's snapshot to Drive again (it is not identical to Drive's new latest, so `pin_write()` does not skip). Local newer: mirror image. After the writes assert `identical(.latest_version(drive)$hash, .latest_version(local)$hash)` and abort with an internal error otherwise. Then record the H6 baseline. Result: both pre-conflict contents are versions on both boards, both boards have the same latest, status reports `in_sync`.
- Unversioned `"version"` branch (`:625-636`): no loss-free automatic resolution exists on a one-slot board. Treat `"version"` as `"stop"`: collect the name, continue, and abort after the loop. Add a class to the final abort at `:668-675`: `class = c(if (unversioned_hit) "gdpins_error_unversioned_conflict", "gdpins_error_sync_conflict", "gdpins_error")`, reword "Nothing was changed" to "Conflicting pins were not changed." (non-conflicting pins are copied before the abort, audit M14), and add the hint `i = "Use on_conflict = \"prompt\" to choose a side, or write the local data under a new pin name first."`. `x$versioned` is reliable on lazy and offline boards (`R/lazy.R:76-83`, `:128-134`; `R/offline.R:108`, `:212`).
- Roxygen: rewrite "Conflict handling" (`:103-110`) and `@param on_conflict` (`:118-119`). Update `vignettes/gdpins-usage.Rmd:458-460` ("both sides simply become new versions") and `README.md:149-162` in this phase.
- NEWS: an unversioned board with a conflict under `gdpins_init_board(on_discrepancy = "sync_*")` now warns "Sync ... failed" through `.handle_init_sync` (`R/board.R:172-190`) instead of silently overwriting.

### Tests to flip

- `test-sync.R:850-863` → `expect_error(..., class = "gdpins_error_unversioned_conflict")` with unchanged-data assertions, mirroring `:312-335`. Existing `class = "rlang_error"` assertions at `:325-328`, `:379-382` still pass.
- `test-sync.R:286-308` stays green (`expect_gte` on counts). `test-integration.R:189-221` runs the **real** path with same-second seeding (tie → conflict); it was flaky-by-hash before the await guard and must assert per-version **content** on both sides (it seeds `type = "parquet"`, which is re-encoded on copy), not hashes.
- `test-sync.R:866-914` (`"prompt"`) unaffected.

---

## H7 — raw conflict default silently lets Drive overwrite local

### Root cause (confirmed by reading)

- `on_conflict = c("version", "prompt", "stop")` at `R/sync.R:150`, `:161`, `:172`, `:183`; `match.arg` picks `"version"`. Raw conflict branch `:827-847`: `"stop"` collects (`:828-830`), `"prompt"` asks (`:831-837`), else `.raw_copy_to_local(x, fname)` (`:840`) and `cli_inform` (`:842-844`). `.raw_copy_to_local()` (`:978-987`) runs `gd_download()` onto the local file (`:985`): no backup, no diff.
- `attempt()` (`:806-816`) catches only errors, so a warning raised inside it propagates; `cli_warn(class = )` attaches the class (passed to `rlang::warn`).
- The backup file will be listed by `.list_local_files()` (`:440`), `gdpins_raw_ls()` (`R/raw-connection.R:1173`) and the connect scan (`:616`): on the next sync it is `local_ahead` and is uploaded.

### Failing test (`tests/testthat/test-sync.R`)

- Upload `x = 1:3` as `conf.csv` to the fake Drive; place `x = 7:9` as `conf.csv` in `local_path`; record the local bytes; force conflict via `.fake_raw_status_conflict("conf.csv")` with `gdpins_is_online` mocked; `expect_warning(gdpins_sync(conn), class = "gdpins_warning_raw_conflict_backup")`; exactly one file matching `conf.conflict-*.csv` in `local_path` whose bytes equal the recorded local bytes; `conf.csv` now equals the Drive bytes. Today: no backup, info message only.

### Fix (option chosen: back up, then let Drive win)

Rationale: unattended `gdpins_sync()` keeps working, the pre-sync local bytes are preserved, and the conflict is a classed warning. Treating `"version"` as `"stop"` is rejected for raw because raw sync is the path meant to run unattended, and a backup file is raw's equivalent of "both become versions".

- `.raw_conflict_backup_path(conn, rel_name)` → `<dir>/<stem>.conflict-<ts>.<ext>` with `ts <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")` (no `:`, Windows-safe); extensionless names → `<name>.conflict-<ts>`; `fs::file_copy(..., overwrite = FALSE)` so a same-second re-run errors safely inside `attempt()`.
- Branch `:838-846`: inside `attempt(fname, ...)`, `if (file.exists(local_file)) fs::file_copy(local_file, backup)` then `.raw_copy_to_local(x, fname)`; on success, when a backup was made, `cli::cli_warn(c("!" = "File {.val {fname}}: conflict -- Drive version kept, previous local copy saved as {.path {backup}}.", i = "Resolve by reading the backup, or re-run with on_conflict = \"prompt\"."), class = "gdpins_warning_raw_conflict_backup")`; then record the H6 raw baseline.
- Roxygen + NEWS: the backup is a normal file in `local_path` and will be uploaded on the next sync unless deleted.

### Tests to flip

- `test-sync.R:405-423` → wrap in `expect_warning(..., class = "gdpins_warning_raw_conflict_backup")` and assert the backup file.
- `test-sync.R:1322-1347` (NA-mtime conflict, no local file): still downloads, no backup, no warning; assert it does not emit the "failed" warning.

---

## H6 — no last-synced baseline, so "newer wins" hides two-sided edits

### Root cause (confirmed by reading)

- Boards, `.compare_board_pin()` (`R/sync.R:242-288`): hashes equal → `in_sync` (`:260-261`); hashes differ and either `created` NA → `conflict` (`:266-267`); `dc > lc` → `drive_ahead` (`:268-269`); `lc > dc` → `local_ahead` (`:270-271`); equal → `conflict` (`:273-274`). Raw, `.board_status_raw()` (`:350-429`): same shape with md5/mtime at `:402-416`.
- Two sides that both moved on from the last synced content are reported `*_ahead` whenever their timestamps differ, `.effective_direction()` (`:682-699`) turns that into a one-way copy (`:641-653`, `:850-860`) and the `on_conflict` branch is never entered. Unversioned boards lose the losing side in place; versioned boards never push it; raw files are also exposed to clock skew.
- Nothing persists a sync marker. Lazy boards rebuild from `spec` each session (`R/lazy.R:101-119`); `go_offline`/`go_online` stash in attributes (`R/offline.R:95-101`, `:127-131`). The baseline must be on disk.
- `gdpins_pin_write()` writes both sides in one call (`R/verbs.R:182-192`); `gdpins_raw_put_object`/`_put_file` do the same when an adapter is present (`R/raw-connection.R:712-728`, `:745-773`).

### Design

- **Board baseline file**: `<cache_dir>/.gdpins-sync.rds`, a data frame `name, drive_hash, local_hash, synced_at` (POSIXct UTC). The hashes are the 5-character prefixes returned by `.latest_version(board, name)$hash` — the same values status compares — **stored per side**, never `pin_meta()$pin_hash` (full hash) and never one shared value (copies of non-file pins can re-serialise to a different hash, and the two parquet writes of `gdpins_pin_write()` are only assumed identical). Written with `saveRDS()` to a temp file in the same directory then `fs::file_move()`; read with `readRDS()`; missing file → no baseline; unreadable file → one `cli_warn` and no baseline. The file is local-only and gdpins-owned (audit M1 is about rds pulled from Drive). `pin_list.pins_board_folder` lists directories only and nothing in `R/` lists `cache_dir` (all `dir_ls`/`list.files` hits are on `local_path`, the fake root or `figures_dir`), so the file is invisible to pins and gdpins; the H1 leading-dot rule prevents a pin of that name.
- **Raw baseline file**: not inside `local_path` (the user's mirror is fully scanned by `.list_local_files()` `R/sync.R:432-465`, `gdpins_raw_ls()` `R/raw-connection.R:1135-1207` and the connect scan `:610-690`, none of which apply `.is_sync_sidecar()` `R/raw-connection.R:439-443`). Instead `file.path(getOption("gdpins.cache_dir"), ".gdpins-raw-baselines", paste0(key, ".rds"))` (dot-named so it can never be mistaken for a pin if a user points a board at that root), with `key <- rlang::hash(list(root = <adapter$root_id or basename(adapter$root), as .default_cache_dir() uses at R/board.R:50-54>, drive_path = conn$drive_path, local_path = fs::path_norm(fs::path_abs(conn$local_path))))`. Default `gdpins.cache_dir` is set in `R/zzz.R:22`; `setup.R` sandboxes it. Unset option or uncreatable directory → no baseline, one warning. Columns `name, synced_md5, synced_at` (raw copies are byte-exact, one md5 suffices).
- `local_only` boards and connections (no adapter, `helper-fakes.R:104-108`, `R/offline.R:133-136`): no baseline. `drive_only` boards: no `cache_dir`, nothing persistent locally, baseline inapplicable (`R/sync.R:200-206`).
- **Decision table** (after the one-side-only rules and after hash-equal → `in_sync`; `base_drive`/`base_local` from the row for that name, `NA` if none):
  - no row → today's timestamp rule (`:264-276` / `:406-416`) unchanged.
  - `drive_changed <- !identical(drive_hash, base_drive)`; `local_changed <- !identical(local_hash, base_local)`.
  - `local_changed && !drive_changed` → `local_ahead`; `drive_changed && !local_changed` → `drive_ahead`; both → `conflict` regardless of timestamps; neither (hashes differ from each other but each equals its own baseline, the state right after an H5 resolution if the latest ever differed) → `in_sync`.
  - Raw: same with `drv_md5`/`loc_md5` against `synced_md5` (both adapters' `ls` return `md5`: fake `R/drive-adapter.R:349,411-420`, real `:528,611-613`; local via `tools::md5sum()` as `.list_local_files()` already does, `R/sync.R:457-461`).
- **Baseline writes** (`.baseline_set()`, `.baseline_drop()`, raw variants): `gdpins_pin_write()` after a successful fan-out on `drive_cache` (`R/verbs.R:192`); `gdpins_pin_remove()` drops the row; `.sync_board()` after each copy that returned `TRUE` (`:641-653`), after the H5 resolution, **and for every `in_sync` row** (bootstraps pre-existing boards; `.sync_board()` skips those rows today at `:593`); `.sync_raw()` after each successful copy (`:850-860`), after the H7 backup-overwrite, and for `in_sync` rows; `gdpins_raw_put_object`/`_put_file` after both sides are written; `gdpins_raw_remove` drops the row; `gdpins_raw_connect` loops `:645-650`, `:663-669` and the `sync_to_drive` loop `:671-677`; optional: downloads in `gdpins_raw_path` (`:1004`), `gdpins_raw_get` (`:1067`), `gdpins_refresh_disconnect` (`:1231`). Missing a write point only degrades to the timestamp rule.
- **Status output schema unchanged**, so `helper-fakes.R:155` and `expect_named()` at `test-sync.R:49-50, 58-59, 808-809, 817-818` keep passing. `.compare_board_pin()` gains `baseline = NULL` (appended, defaulted; all callers use named arguments: `R/sync.R:229-235`, `test-sync.R:217-228`, `:1271-1277`, `:1296-1302`).
- `go_offline`/`go_online`, lazy boards: no changes; `go_offline` keeps `cache_dir` (`R/offline.R:106-108`) and the baseline is read from disk at status time.

### Failing tests (new file `tests/testthat/test-sync-baseline.R`)

Every test mocks `gdpins_is_online = function() TRUE`. Timestamps use `Sys.sleep(1.1)` (`test-sync.R:771-792`, `test-integration.R:486-490`).

1. Versioned `drive_cache`: `gdpins_pin_write(b, v0, "p")`; sleep; `pins::pin_write(b$local_board, v1, "p")`; sleep; `pins::pin_write(b$drive_board, v2, "p")`. `expect_identical(gdpins_board_status(b)$state, "conflict")`. Today: `drive_ahead` (`:268-269`). Then `expect_error(gdpins_sync(b, on_conflict = "stop"), class = "gdpins_error_sync_conflict")` and both sides' latest unchanged. Today: no error; `auto` pulls v2 into local.
2. Same with `versioned = FALSE`: `conflict`; after `on_conflict = "stop"` local still reads v1. Today: `drive_ahead`, local replaced by v2.
3. Raw with clock skew: `gdpins_raw_put_object(conn, df0, "f.csv")` (baseline recorded); edit local `f.csv`; upload different bytes to the fake Drive as `f.csv` and `Sys.setFileTime()` the Drive copy older than the local edit (fake `ls()` reports `file.mtime`, `R/drive-adapter.R:414`; `.board_status_raw` reads it, `R/sync.R:392`; set it explicitly because `fs::file_copy` may keep the source mtime). `expect_identical(state, "conflict")`; `gdpins_sync(conn, on_conflict = "stop")` errors, bytes on both sides unchanged. Today: `local_ahead` (`:410-411`) and the local file is pushed over Drive.
4. One-sided change: after `gdpins_pin_write`, write only to `b$drive_board` → `drive_ahead`; only to `b$local_board` → `local_ahead` (now independent of timestamp luck).
5. Backward compatibility: write pins to both sides directly (no baseline file); `gdpins_board_status(b)` emits no warning and uses the timestamp rule; after one `gdpins_sync(b)` the file `<cache_dir>/.gdpins-sync.rds` exists with one row per pin (including `in_sync` ones); `pins::pin_list(b$local_board)` does not list it.
6. Hygiene: `gdpins_pin_remove(b, "p")` removes the row; a corrupt baseline file yields one warning and the fallback rule.

### Fix (files)

- `R/sync.R`: `.baseline_path()`, `.baseline_read()`, `.baseline_write()`, `.baseline_set()`, `.baseline_drop()` and raw equivalents; the baseline branch in `.compare_board_pin()` and `.board_status_raw()`; `.board_status_board()` reads the baseline once per call; updates in `.sync_board()` and `.sync_raw()`.
- `R/verbs.R`: set in `gdpins_pin_write()`, drop in `gdpins_pin_remove()`.
- `R/raw-connection.R`: set in the two put verbs and the three connect-time loops; drop in `gdpins_raw_remove()`.
- Roxygen `@section Sync rules:` on the `gdpins_sync` topic; `vignettes/gdpins-usage.Rmd:447-460` paragraph; `README.md:149-162`.

### Tests to flip / check

- `test-sync.R:780`, `:791`, `:1230`, `:1399` already accept `%in% c("drive_ahead", "conflict")`.
- `test-integration.R:486-490`, `:290-330`, `:466-509`, `test-offline.R:211-227` are one-sided → still `*_ahead`. The V7 offline write goes to a `local_only` board; the baseline still says Drive = v1 → `local_ahead`.
- Mocked tests (`test-sync.R:286-497`, `:850-914`; `test-offline.R:187-207` mocks `local_ahead`; `test-board.R:370-416`, `:868-891`, `:1205-1223`) bypass detection → unaffected.

### Known limitations (NEWS)

- Real adapter: `pin_meta.pins_board_gdrive` writes `<cache>/<name>/<drive_version>/data.txt`, and `cache_dir` is also `local_board`'s path (`R/board.R:596-602`, audit M10). Drive versions therefore appear as local versions on the real adapter and can mask the local latest; the fake adapter cannot reproduce this. Out of scope here; coordinate with M10.
- Conflict rows ignore `direction` (`R/sync.R:684`): the H5 resolution writes to Drive even under `direction = "from_drive"` (audit M15).
- `gdpins_raw_connect()`'s connect-time check still compares name sets only (M16); `.list_local_files()` and `gdpins_raw_ls()` do not apply `.is_sync_sidecar()`.

---

## H8 — prune deletes local-only versions, unseen and uncounted

### Root cause (confirmed by reading; pins facts verified upstream)

- `.prune_primary_board()` (`R/prune.R:22-24`): Drive when present. Plan and count come from the primary only: `old_versions <- .versions_to_remove(primary, name, keep)`; `n_remove <- length(old_versions)` (`:199-201`); dry run prints only those (`:211-217`); threshold uses only `n_remove` (`:220-222`, `.prune_check_threshold()` `:105-124`); the board-level pre-flight sums primary counts and only fires when a single pin exceeds the threshold (`:311-323`, audit L5).
- `.versions_to_remove()` (`:39-44`) does not sort; it takes `v$version[seq_len(n - keep)]` in `pins::pin_versions()` row order (directory order of `<ts>-<hash>` names).
- Deletion prunes each side on its own list: Drive (`:229-235`, trash via `.trash_drive_version()`), local (`:236-242`, hard `fs::dir_delete` via `.remove_local_version()` `:69-74`). A never-synced local version is treated like any other and survives only by recency. Example: Drive {v1,v2,v3}, local {v1,v2,v3,v4 unsynced}: `keep = 2` → Drive trashes v1, local deletes v1 and v2, dry run listed v1 only; `keep = 1` → Drive trashes v1,v2, local deletes v1,v2,v3. No data is lost in that example (v3 is on Drive); the loss case is an unsynced version **older** than the synced ones (test 2).
- Messages (L5): `:204-206` prints `"{keep} present"`; `:244-246` reports the Drive count only. Return (`:248`) is the Drive list only; early returns at `:207` (`character(0)`) and `:305` (`list()`).
- Offline boards: `gdpins_go_offline()` rebuilds a `drive_cache` board as `config = "local_only"` with `drive_board = NULL` (`R/offline.R:103-110`), so a rule "no Drive board → prune everything beyond keep" would hard-delete exactly the unsynced offline versions the audit describes. `local_only` boards built as such are consistent (primary = local).
- A pin present on Drive but not locally makes `pins::pin_versions(local_board, nm)` abort (`check_pin_exists()`), already a latent error in `gdpins_prune_board_versions` (`:300-301`).
- Matching local versions to Drive versions: version ids differ between the two boards for the same write (`.write_to_board()` is called once per board, `R/verbs.R:21-47`, `:182-192`; `test-prune.R:470-498`), so match on `pin_versions()$hash` (5-char prefix of xxhash64 over file bytes). rds bytes are deterministic (`saveRDS(version = 2)`, no timestamp). Parquet is written **twice** by arrow (`R/verbs.R:29-34`, `R/io-formats.R:119-127`), so identical bytes are assumed, not guaranteed (**UNVERIFIED**; arrow writes no timestamp in the footer). `R/sync.R:260` already relies on this equality. `NA %in% NA` is `TRUE`, so unparseable ids must be excluded.

### Failing tests (`tests/testthat/test-prune.R`)

All tests that call `gdpins_pin_write()` mock `gdpins_is_online = function() TRUE`. Synced versions via `gdpins_pin_write()` (parquet; also settles the arrow-determinism question) or `seed_versions()` (`test-prune.R:9-19`, rds); unsynced via `pins::pin_write(board$local_board, ...)` with content that differs from every synced version; `Sys.sleep(1.1)` between writes (`:476`).

1. Dry run, Drive {v1,v2,v3}, local {v1,v2,v3,v4 unsynced}, `keep = 2`: the return is a tibble `name, version, side, hash, action` with three `remove` rows (drive v1; local v1, v2) and no row for v4; nothing deleted. Today: a character vector of length 1 (this test is red on shape only; test 2 proves the loss).
2. Unsynced version older than the synced ones: write `v_old` to `board$local_board` first, then v1..v3 through `gdpins_pin_write()`. `keep = 2`, `dry_run = FALSE, force = TRUE`: local candidates beyond keep are {v_old, v1}; v1's hash is on Drive → removed; v_old's is not → kept, `action = "keep_unsynced"`. Assert `pins::pin_read(board$local_board, "p", version = <v_old>)` works; Drive has {v2, v3}; local has {v_old, v2, v3}. Today: `.versions_to_remove()` returns {v_old, v1} and `:238-240` deletes v_old.
3. Threshold: Drive 2 versions, local 6 (4 unsynced), `keep = 1`, `threshold = 1`, `force = FALSE` → `expect_error(regexp = "force")`, local count still 6. Today: `n_remove = 1`, `1 > 1` is FALSE, local deletions proceed.
4. Board-level total: two pins with 6 removals each, `threshold = 10`, `force = FALSE` → abort (today only a single pin above the threshold triggers it).
5. Offline board: `gdpins_pin_write` v1 online, `gdpins_go_offline()`, write v2 offline, `gdpins_prune_pin_versions(keep = 1, dry_run = FALSE, force = TRUE)` → v1 is still present locally (nothing is deleted on an offline board) and the plan marks it `keep_unsynced`. Today: v1 is hard-deleted.
6. `local_only` board built as such: behaviour and counts unchanged (`test-prune.R:348-360`).
7. Message: "No versions to remove" prints the real number present (`expect_message(regexp = "3 present")`).
8. Pin present on Drive only: `gdpins_prune_board_versions()` does not error and reports the pin with zero local rows.

### Fix

- `.local_versions_to_remove(local_board, drive_board, name, keep, offline)`: zero rows when `!pins::pin_exists(local_board, name)`; local versions beyond `keep` split into `remove` (hash present among the Drive versions listed **before** this call's trashing, `!is.na(hash)`) and `keep_unsynced` (hash absent, `NA`, or the board is offline per `attr(board, .GDPINS_OFFLINE_STATE_ATTR)`); `local_only` built as such (no Drive board, not offline): all candidates `remove`. A Drive listing error propagates (H4) and the prune aborts: fail-safe. Comment the 1-in-16^5 prefix collision acceptance.
- `gdpins_prune_pin_versions()`: one plan tibble (`name, version, side, hash, action`) from the Drive list and the local list; dry run prints all rows grouped by side and lists `keep_unsynced` rows ("kept: not on Drive"); threshold count `n_remove <- max(sum(side == "drive" & action == "remove"), sum(side == "local" & action == "remove"))` (a synced version must not count twice, or `test-prune.R:210-221` "exactly at threshold" breaks); deletion loops iterate the plan; "No versions to remove" uses the real count; the final message reports Drive, local and kept-unsynced counts. Early returns (`:207`) return a 0-row plan tibble. Return the plan invisibly.
- `gdpins_prune_board_versions()`: pre-flight compares the **total** `remove` count over all pins with `threshold` (closes L5); returns one tibble with all pins' rows; early return (`:305`) a 0-row tibble (the `@examples` at `:275` hit this path on an empty board, so the example must still run).
- `gdpins_pin_write()` (`R/verbs.R:21-47`): write the parquet file once and `pin_upload()` the same file to both boards, so hash identity across boards holds by construction (small change; removes the arrow-determinism doubt). If the red run of test 2 already shows identical hashes, still make the change; it is cheap and the `[V7]` integration test (`test-integration.R:513-526`, write → sync → prune `keep = 1` leaves 1 local version) checks the end-to-end path.
- Roxygen `@return` (`:156-157`, `:263-264`), `@param dry_run`/`threshold`/`force` (`:149-154`) updated.

### Tests to flip

- Return-shape assertions (`expect_length()` on a tibble checks `ncol`): `test-prune.R:35-36`, `:60`, `:81-94`, `:120`, `:206`, `:219`, `:252`, `:268-276` (named list → one tibble), `:285`, `:291-298`, `:341-342`, `:358`, `:423`, `:464`, `:508`, `:522-523`, `:575-576`, `:581-660` → read `plan$version[plan$side == "drive" & plan$action == "remove"]` or count rows. `:106-109` and `:272-275` assert `pin_versions` counts and stay as they are. `:210-221` stays green with the `max()` threshold.
- `test-integration.R:513` and `test-live.R:377,415` call prune and ignore the result. No `_snaps/prune.md` exists; re-grep `expect_message(regexp = ...)` for the old wording.

### API note

Returning a tibble instead of a character vector (and one tibble instead of a named list) is the one deliberate API break. `CLAUDE.md` §3 permits justified default changes but is literal about compatibility; this plan asks for an exception because the old return value cannot represent local deletions (the bug), tibble returns are the package norm (`gdpins_board_status`, `gdpins_list_pins`), no README or vignette code uses the value (`README.md:188-191`, `vignettes/gdpins-usage.Rmd:356-359`, `:511-516`), the package is `0.0.1.9xxx`, and `NEWS.md` already has a "Breaking changes" section (0.0.1.9025). An `attr(result, "plan")` fallback is not used because `attr()` is only used for internal state in this package (`R/lazy.R:84`, `R/offline.R:110,137`).

---

## Steps

- [x] 0. Worktree: `git worktree prune`; `git worktree add .claude/worktrees/fix-audit-high -b fix/audit-high-priority main`; in the worktree `Rscript -e "renv::restore(prompt = FALSE)"`; `DESCRIPTION` → `Version: 0.0.1.9027`, `testthat (>= 3.2.0)`; `NEWS.md` → new `# gdpins 0.0.1.9027` heading; `Rscript -e "devtools::test()"` once to record the baseline (expect 0 failed). Commit `chore: start 0.0.1.9027`.
- [x] 1. H1 + H2 (red): add `new_sandboxed_board()`/`new_sandboxed_raw_conn()` to `helper-fakes.R`; add `tests/testthat/test-validate.R` and the raw-verb cases in `test-raw-connection.R`; run; confirm each fails for the documented reason (sentinel gone or wrong class).
- [x] 2. H1 + H2 (green): `R/validate.R`; wire every call site listed above, including the `.local_full_path()` guard and the bulk-loop skip-and-warn; roxygen; full suite; commit `fix: validate pin and raw file names against path traversal (H1, H2)`.
- [x] 3. H3 + H4 (red): add `fake_dribble()` to `helper-fakes.R`; add `tests/testthat/test-drive-adapter-real.R`; add the error-propagation tests and the `.latest_version` test in `test-sync.R`; run; confirm failures (`FALSE`, empty tibble, `drive_mkdir`/`drive_upload` called, no error).
- [x] 4. H3 + H4 (green): exact-match lookups and ambiguity abort in `R/drive-adapter.R`; `startsWith` strip in `R/raw-connection.R`; remove the swallowing `tryCatch` sites; flip `test-sync.R:1349-1359`; drop `# nocov` on covered functions (keep `:62-68`); roxygen; full suite; commit `fix: exact Drive name matching and propagate listing errors (H3, H4)`.
- [x] 5. H5 + H7 (red): versioned both-prefixes test, metadata test, unversioned error test, raw backup test in `test-sync.R`; run; confirm failures.
- [x] 6. H5 + H7 (green): `.snapshot_pin()`/`.write_pin_snapshot()` with logical return, `.await_new_version_second()`, ordered conflict writes with the post-check, unversioned → stop with classes, raw backup + warning class; flip `test-sync.R:850-863`, `:405-423`; strengthen `test-integration.R:189-221` (content per version); roxygen; `vignettes/gdpins-usage.Rmd:458-460` and `README.md:149-162`; full suite; commit `fix: lossless conflict resolution for boards and raw connections (H5, H7)`.
- [x] 7. H6 (red): `tests/testthat/test-sync-baseline.R` (six tests); run; confirm `drive_ahead`/`local_ahead` where `conflict` is expected and no baseline file after sync.
- [x] 8. H6 (green): baseline helpers and decision branch in `R/sync.R`; writes in `R/verbs.R` and `R/raw-connection.R`; roxygen `@section Sync rules:`; vignette paragraph; full suite; commit `feat: last-synced baseline for conflict detection (H6)`.
- [x] 9. H8 (red): the eight prune tests in `test-prune.R`; run; confirm (vector return, v_old deleted, threshold not triggered, offline board pruned, Drive-only pin errors).
- [x] 10. H8 (green): `.local_versions_to_remove()`, plan tibble, `max()` threshold, board-level total, messages, 0-row early returns, single parquet write in `gdpins_pin_write()`; flip the listed `test-prune.R` assertions; roxygen; full suite; commit `fix: prune keeps unsynced local versions and reports every deletion (H8)`.
- [x] 11. Docs and hygiene: `NEWS.md` complete (Breaking changes, Bug fixes incl. L5, Security, Known limitations, H3 duplicate remediation); `README.md:97`, `:149-162`, `:188-191` and `vignettes/gdpins-usage.Rmd:186`, `:447-460`, `:540` re-read and corrected (vignette chunks are `eval = FALSE`, `gdpins-usage.Rmd:14`); `roxygen2::roxygenise()` with an empty `NAMESPACE` diff; `Rscript -e "devtools::check(args = '--no-manual')"` → 0 errors, 0 warnings, notes reviewed; commit `docs: NEWS and documentation for audit fixes`.
- [ ] 12. Push and open the PR as described; link the audit note and this plan in the body; record the PR URL here and in the front matter; set `status: review`.

## Open questions

- H8 return shape: accept the §3 exception for the tibble return (recommended), or keep a character vector and lose the local-deletion report. Decide at PR review.
- H3 ambiguity: abort on duplicate Drive names (chosen) versus, for `upload()` only, updating the most recent duplicate with a warning. The abort is safer; the remediation note covers folders polluted by the old bug.
- H7: upload the backup file on the next sync as a normal file (chosen, simplest, visible on every machine) versus excluding it, which needs the sidecar-exclusion work (M16).
- H6 raw baseline location: under `gdpins.cache_dir/.gdpins-raw-baselines/` keyed by `rlang::hash()` (chosen; no listing changes) versus a hidden file inside `local_path` (travels with the mirror; needs sidecar exclusion in three listing functions).
- H5 final-latest rule (newer `created` wins as latest on both sides, tie → Drive) and the fact that conflict resolution ignores `direction` (M15): confirm this matches product intent before step 6.
- Version clash: plan 0001 also targets `0.0.1.9027`; the second branch to merge bumps to `0.0.1.9028` and renames its NEWS heading.
- Real adapter: `cache_dir` is both `local_board` and `board_gdrive`'s cache (M10); H5/H6 cannot be validated against that on the fake adapter. Should M10 be scheduled next?

## Outcome

Filled in when the status becomes done or superseded.
