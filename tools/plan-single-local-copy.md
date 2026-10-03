# Plan: single local copy per board (drop `cache_board`, deprecate `local_dir`)

Status: PLANNED, not started. Target version 0.0.1.9024. Branch `feat/single-local-copy` off `main`; `fix/raw-sync-locked-files` (0.0.1.9023) merged in at 184a935.
Companion: `tools/design-local-cache.md` (how it works today). Tracker section at bottom.

---

## 1. Operating rules (user requirements — binding)

### Roles
- **Orchestrator** — Opus-class. Writes **zero code**. Writes briefs, spawns agents, reads reports,
  runs gates, commits. Owns this file.
- **Implementer** — Sonnet. One task. TDD. Edits only files listed in its brief.
- **Verifier** — Sonnet. Independent of the implementer (never the same agent). Reviews one task.

### TDD (implementer)
1. Read brief. Read only the files/ranges it lists.
2. Write the new/changed tests first. Run them. **Paste RED output into the report.**
3. Implement. Run the task's test files. **Paste GREEN output.**
4. Report (template §6). No RED evidence → task rejected without review.

### Verification (verifier)
1. Read brief + implementer report + `git diff -- <task files>`.
2. Check `git status --short`: any file outside the brief's list → FAIL.
3. Run the task's test files yourself. Any failure → FAIL.
4. **Write ≥3 new adversarial tests**: take the brief's edge list, add your own. Target
   boundaries, NULL/FALSE/TRUE/"" inputs, config combos, offline paths, lazy vs eager, error
   messages. Run them. Any new failure → FAIL with repro. Passing new tests **stay in the suite**.
5. Verdict `PASS` / `FAIL` + list of tests added + leftovers noticed outside scope (report, don't fix).
6. FAIL → orchestrator sends it back to the **same implementer** via SendMessage (context intact).
   Max 2 rounds, then orchestrator re-briefs a fresh implementer.

### Parallelism
- Tasks in one phase touch **disjoint** R files and disjoint test files.
- **No full-suite runs inside Phase 2** — other streams are mid-change. Run only your own files.
- Only T3 may touch `tests/testthat/_snaps/`.
- Full suite only at phase gates (orchestrator).

### Token budget
- Brief must carry everything: decision table, exact symbols, line ranges, "do not read" list,
  exact commands. Agent should not need to explore.
- Target: close at **100–150k** tokens. **Hard rule: at 100k and not done → stop, write state
  into report, return.** Orchestrator splits the task.
- Estimates below assume ~12 tokens/line for R source.

### Environment
- R binary: `"/c/Program Files/R/R-4.5.3/bin/x64/Rscript"`. Bare `Rscript` is R 4.6.1 with an
  empty library — never use it. Always pass `--no-init-file`: `.Rprofile` activates renv, whose
  library lacks `pkgload`/`testthat` (`there is no package called 'pkgload'`).
- Test one file:
  ```
  "/c/Program Files/R/R-4.5.3/bin/x64/Rscript" --no-init-file -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-board.R")'
  ```
- Full suite (gates only):
  ```
  "/c/Program Files/R/R-4.5.3/bin/x64/Rscript" --no-init-file -e 'pkgload::load_all("."); testthat::test_dir("tests/testthat")'
  ```
- Never spawn background processes or file-lock helpers in tests (antivirus trips). Mock a seam.
- `test-live.R` needs real Drive; skipped by default. Edit by reading only; never run.
- Snapshots: only commit real `_snaps/` changes; revert LF↔CRLF-only churn.

### Package hygiene (AGENTS.md)
- New dep `lifecycle` → `Imports`. Bump `Version:` → `0.0.1.9024`; top `NEWS.md` heading matches.
- Never hand-edit `man/` or `NAMESPACE`; roxygen then `roxygen2::roxygenise()`.
- Every arg → `@param`. Internal helpers `@keywords internal`.
- `@examples` must run (they do during check). Examples must **never** write to the real user
  cache: always pass `cache_dir = tempfile("cache_")` or set the option to a tempdir.

---

## 2. Frozen design

### Principle
One local copy per Drive board, or none. The local copy is a `pins::board_folder` stored in
`board$local_board`; its path is `board$cache_dir`. `pins::board_gdrive(cache=)` points at the
**same** directory, so Drive downloads land in the local copy (same `<pin>/<version>/` layout).

### Public API — `gdpins_init_board()`
Signature **unchanged** (positional callers keep working):
`name, drive_path = NULL, cache_dir = NULL, local_dir = NULL, versioned = TRUE, create = NA,
on_discrepancy = NULL, adapter = NULL, lazy = NULL`.

`cache_dir` accepts: `NULL` (default), `TRUE`, `FALSE`, non-empty `character(1)`. Else abort.

`local_dir` is **deprecated**:
- non-NULL → `lifecycle::deprecate_warn(when = "0.0.1.9024",
  what = "gdpins_init_board(local_dir)", with = "gdpins_init_board(cache_dir)")`.
- `cache_dir` NULL → `cache_dir <- local_dir`.
- `cache_dir` non-NULL → `local_dir` ignored; say so in `details =`.

### Decision table (`.board_spec()`, pure — no FS, no network)

| `drive_path` | effective `cache_dir` | config | `local_board` over | `board_gdrive(cache=)` |
|---|---|---|---|---|
| NULL | character | `local_only` | that path | – |
| NULL | NULL / TRUE / FALSE | **abort** "Supply `drive_path`, or `cache_dir` as a path for a local-only board." | | |
| path | NULL / TRUE | `drive_cache` | `.default_cache_dir(adapter, drive_path)` | same path |
| path | character | `drive_cache` | that path | same path |
| path | FALSE | `drive_only` | none (`local_board = NULL`) | `tempfile("gdpins_scratch_")` |

`drive_path` non-NULL still requires `adapter` (abort as today).

### Default cache path
`.default_cache_dir(adapter, drive_path)`:
- root = `getOption("gdpins.cache_dir")`.
- key = `adapter$root_id` if `adapter$kind == "real"`, else `basename(adapter$root)` (fake).
- components = `strsplit(drive_path, "/")[[1]]`, each `gsub("[^A-Za-z0-9._-]+", "_", x)`.
- result = `do.call(file.path, c(list(root, key), components))`, as character.
- Computed inside `.board_spec()` so a **lazy** board reports `board$cache_dir` without connecting.

Option registered in `.onLoad()` (set-only-if-unset idiom):
`gdpins.cache_dir = as.character(fs::path_home(".gdpins", "cache"))`.
Rationale: `fs::path_home()` uses `USERPROFILE` on Windows; base `~` may resolve to a
OneDrive-synced `Documents` folder.

### Object (`R/classes.R`) — FROZEN layout, new
`new_gdpins_board(config, name, drive_board = NULL, local_board = NULL, cache_dir = NULL,
drive_path = NULL, adapter = NULL, versioned = TRUE)`.
Field order: `config, name, drive_board, local_board, cache_dir, drive_path, adapter, versioned`.
**Removed fields**: `cache_board`, `local_dir`.
`.BOARD_CONFIGS <- c("local_only", "drive_cache", "drive_only")`.

### Per-module behaviour
- `.config_components()`: `local_only → "local_board"`; `drive_cache → c("drive_board","local_board")`;
  `drive_only → "drive_board"`.
- `format()` flags `[DCL]`: D = drive_board in components; C = config `drive_cache`; L = config
  `local_only`. (`--L`, `DC-`, `D--`.)
- `print()`/`summary()`: `drive =` line when `drive_path`; path line labelled `local =` for
  `local_only`, `cache =` otherwise; omitted for `drive_only`.
- `.LAZY_FIELDS <- c("drive_board", "local_board")`.
- `.build_board()`:
  - `local_only`: `fs::dir_create(cache_dir)`; `local_board <- board_folder(cache_dir)`.
  - Drive configs offline: `drive_cache` → warn + downgrade to `local_only` over `cache_dir`
    (as today); `drive_only` → **abort** "Drive board {drive_path} is unreachable offline and has
    no local copy (`cache_dir = FALSE`)."
  - Drive configs online: existence/create dance unchanged. gdrive scratch = `cache_dir`
    (`drive_cache`) or fresh `tempfile("gdpins_scratch_")` (`drive_only`), `dir_create`d. Real
    adapter → `board_gdrive(as_id(id), cache = scratch)`; fake → `board_folder(<root>/<drive_path>)`.
    `local_board` = `board_folder(cache_dir)` for `drive_cache`, `NULL` for `drive_only`.
  - Drive-ID fast path (`nocov`): same rules.
- Verbs: write fan-out = `drive_board`, then `local_board` (non-NULL ones). Read / `.pin_sources()`
  order = `local_board`, `drive_board`. Remove = both.
- `.read_source()` / `.resolve_read_board()` = `local_board` else `drive_board`.
- Sync: `.board_local_side(x) <- x$local_board`. `.board_status_board()` with NULL local side
  (`drive_only`) → `cli_inform` "no local copy; nothing to compare" + `.empty_board_status_tbl()`.
  `.sync_board()`: after the `local_only` early return add `drive_only` early return with inform.
  Message "New-computer setup detected: local cache is empty." → "…: local copy is empty."
- Offline: `go_offline`: `local_only` no-op (as today); `drive_only` → abort "no local copy";
  `drive_cache` → `local_only` over `x$local_board`/`x$cache_dir`; stash
  `config, drive_board, cache_dir, drive_path, adapter`. `go_online`: **delete** the
  local→cache catch-up loop; rebuild with `local_board = x$local_board, cache_dir = state$cache_dir`.
- Prune: config-agnostic — if `drive_board` non-NULL trash Drive versions; if `local_board`
  non-NULL `.remove_local_version(board$local_board$path, …)`.
- Tests: `tests/testthat/setup.R` sets
  `withr::local_options(gdpins.cache_dir = file.path(tempdir(), "gdpins-test-cache"), .local_envir = teardown_env())`.
- `new_fake_board(config = c("drive_cache", "local_only", "drive_only"))`.

### Out of scope / known limitations (do not fix here)
- `pins:::pin_meta.pins_board_gdrive()` writes `data.txt` into the scratch dir on metadata
  queries; can leave a version dir without data files. Pre-existing with `cache_dir`; unchanged.
- Raw connections (`gdpins_raw_connect`) untouched.
- `attr(x, "sync_failures")` idea from the raw-sync branch — unrelated.

---

## 3. Phases and tasks

Dependency: Phase 1 (sequential) → Phase 2 (4 parallel) → Phase 3 (2 parallel) → Gate.

### Phase 0 — orchestrator only
- `git switch main && git pull && git switch -c feat/single-local-copy`.
  Do **not** carry over `.Rprofile` / `renv/.gitignore` working-tree changes (unrelated).
- Commit `tools/plan-single-local-copy.md` + `tools/design-local-cache.md`.
- Write briefs T1–T8 from §4 (fill in line numbers fresh with `grep -n` at brief time).

### Phase 1 — foundation (sequential: T1 → V1 → T2 → V2)

**T1 — object, option, spec, fixtures.** ~70k tokens.
Files: `R/classes.R`, `R/zzz.R`, `R/board.R` (only `.board_spec`, `.config_components`, new
`.default_cache_dir`; nothing else), `DESCRIPTION` (add `lifecycle` to Imports; bump version),
`tests/testthat/setup.R` (new), `tests/testthat/helper-fakes.R` (`new_fake_board` only),
`tests/testthat/test-classes.R`, `tests/testthat/test-board.R` sections 1–3 and 8
(`Config: local_only`, `Config: drive_cache`, `Config: drive_cache_local` → rewrite as
`drive_only`, `Validation errors`), `tests/testthat/test-helpers.R` "Fake board harness" block.
Read: `R/classes.R` whole; `R/board.R` lines of `.board_spec`/`.config_components`; `R/zzz.R`;
`helper-fakes.R` whole; the listed test sections. Do not read `.build_board`, `R/lazy.R`,
`R/sync.R`, raw files.
Edge list for V1: `cache_dir = ""`, `cache_dir = NA`, `cache_dir = c("a","b")`, `cache_dir = TRUE`
with no `drive_path`, `local_dir` + `cache_dir` both set (warning text names both), default path
honours a changed option, default path sanitises `drive_path` with spaces and `..`, fake vs real
adapter key, `new_fake_board("drive_only")$local_board` is NULL, frozen field order exact,
`new_gdpins_board(config = "drive_cache_local")` aborts.
Note: after T1, `.build_board`/lazy/verbs tests are expected RED — V1 runs only T1's files.

**T2 — build, lazy, print.** ~90k tokens.
Files: `R/board.R` (`.build_board`, `format`/`print`/`summary`, `gdpins_init_board` roxygen
config bullets only), `R/lazy.R`, `tests/testthat/test-board.R` sections 4–7, 9, 10, and the
`.has_discrepancy/.handle_init_sync` block, `tests/testthat/test-lazy.R`.
Read: `R/board.R` whole (needed), `R/lazy.R` whole, both test files. Do not read `R/sync.R`
beyond `.handle_init_sync` call sites, nor verbs/offline/prune.
Edge list for V2: eager `drive_only` offline aborts with the `cache_dir = FALSE` hint; lazy
`drive_only` offline aborts at first access and retries on next; lazy `drive_cache` reports
default `cache_dir` before connecting; `format()` strings `--L`/`DC-`/`D--` ≤80 chars;
`print()` on `drive_only` has no `cache` line; offline fallback on `drive_cache` leaves
`board$cache_dir` unchanged and `config == "local_only"`; `$cache_board` and `$local_dir` return
NULL (field gone) on eager and lazy boards; `gdpins_board_connect()` on `drive_only` runs the
sync check without error (status empty).

### Phase 2 — modules (parallel streams, each implementer → verifier)

**T3 — verbs, discovery, output.** ~80k.
Files: `R/verbs.R`, `R/discovery.R`, `R/output.R`, `tests/testthat/test-verbs.R`,
`tests/testthat/test-discovery.R` (+ `_snaps/discovery.md` if output changes),
`tests/testthat/test-output.R`, `tests/testthat/test-name-resolution.R`.
Read: the three R files' helper blocks and the four `*_board`/`cache` hit sites
(`grep -n "cache_board\|local_board" R/verbs.R R/discovery.R R/output.R`); test files.
Do not read `R/board.R`, `R/sync.R`, `R/io-formats.R`.
Edge list for V3: `drive_only` write lands on Drive only; `drive_only` read offline warns +
returns NULL; `drive_cache` read after Drive-only seed is served from Drive then present in
`local_board`; `gdpins_pin_path()` on `drive_only` returns a path under the scratch dir;
`gdpins_pin_remove()` with pin only on local; glob listing dedupes across local/drive;
`gdpins_list_pins()` on `drive_only` lists Drive pins.

**T4 — sync / status.** ~90k.
Files: `R/sync.R` (board paths only: `.board_local_side`, `.board_status_board`,
`.offline_board_status_tbl`, `.sync_board`, message text), `tests/testthat/test-sync.R` board
sections only (`gdpins_board_status dispatch` … `Versioned/Unversioned board conflict`,
`New-computer case`, `drive_cache_local (super) board` → rewrite as `drive_only`,
`Empty boards`, `Offline board status with no local pins`, `drive_ahead via newer timestamp`,
board tests inside `Additional coverage`). **Do not touch** raw sections or
`Unreadable / locked local files`.
Read: `R/sync.R` lines 1–346 and 537–730 (post-merge; re-grep at brief time); listed test sections. Do not read raw-sync code.
Edge list for V4: `gdpins_board_status(drive_only)` returns 0-row tibble with the exact schema
of `.empty_board_status_tbl()` and informs once; `gdpins_sync(drive_only)` is a no-op and
returns `x` invisibly; `.handle_init_sync(drive_only)` never warns; `drive_cache` with empty
local and 3 Drive pins → "local copy is empty" message + 3 pulls; from_drive copy preserves
pin type (parquet stays parquet); offline status lists local pins as `"offline"`.

**T5 — offline mode.** ~60k.
Files: `R/offline.R`, `tests/testthat/test-offline.R`.
Read: `R/offline.R` whole; test file whole. Do not read `R/sync.R` (only know
`.copy_pin_to_board` exists and is no longer needed here).
Edge list for V5: `go_offline(drive_only)` aborts naming `cache_dir = FALSE`; `go_offline` →
write → `go_online(on_discrepancy = "sync_to_drive")` pushes the pin for `drive_cache`;
stashed state has no `cache_board`/`local_dir` names; `go_online` restores `config ==
"drive_cache"` and the same `cache_dir`; override adapter still works; double `go_offline` is a
no-op; raw-conn tests unchanged and green.

**T6 — prune.** ~60k.
Files: `R/prune.R`, `tests/testthat/test-prune.R`.
Read: `R/prune.R` whole; test file whole.
Edge list for V6: prune on `drive_only` trashes Drive versions and touches no local dir; prune
on `drive_cache` removes from both; prune on `local_only` unchanged; threshold/force paths still
guard; version-label skew between Drive and local (write with 1s gap) prunes correctly per board.

### Phase 3 — integration and docs (2 parallel streams)

**T7 — integration tests + full suite.** ~100k.
Files: `tests/testthat/test-integration.R`, `tests/testthat/test-pipeline.R`,
`tests/testthat/test-helpers.R` (remaining), `tests/testthat/test-live.R` (edit only, never run).
Mechanical: `board$cache_board` → `board$local_board`; `new_fake_board("drive_cache_local")` →
`"drive_cache"` or `"drive_only"` per intent; `board$local_dir` → `board$cache_dir`.
Then run the **full suite**. Leftover failures in other files: fix if ≤10 lines and clearly
mechanical; otherwise report with file:line to the orchestrator.
Gate greps (must be empty, excluding deprecation code/docs):
`grep -rn "cache_board\|drive_cache_local" R/ tests/ vignettes/ README.md`;
`grep -rn "local_dir" R/ tests/` → only `.board_spec()` deprecation lines and its tests.
V7: rerun full suite; add ≥3 cross-module tests (e.g. write → go_offline → read → go_online →
sync → prune on one `drive_cache` board; lazy `drive_only` end-to-end; default cache path
end-to-end under the test option).

**T8 — documentation.** ~90k.
Files: roxygen in `R/board.R` (`gdpins_init_board` params/description/examples), `R/lazy.R`
(`lazy-boards` topic components list), `R/offline.R` (`offline-mode` topic + example: drop
`local_dir = tempfile("local_")`), `R/sync.R`/`R/prune.R`/`R/verbs.R` doc strings mentioning
"cache board"; `README.md`; `vignettes/gdpins-usage.Rmd` (board init section: three configs;
offline table); `vignettes/google-drive-adapter.Rmd` (go_offline paragraph); `NEWS.md`;
`DESCRIPTION` version check; run `roxygen2::roxygenise()`; run `tools/check-pkgdown-index.R`.
Coordinate: T8 edits only roxygen comment lines in R files that T7 does not touch (T7 touches
tests only) — safe in parallel.
NEWS entry (Breaking-ish): one local copy; `cache_dir` semantics (`NULL` default path,
`FALSE` none, path explicit); `local_dir` deprecated; `cache_board` field removed; default
`~/.gdpins/cache/<root>/<drive_path>`; option `gdpins.cache_dir`.
V8: `roxygenise()` produces no further diff; `NAMESPACE` diff = intended (no new exports;
`importFrom` none needed since `lifecycle::` is qualified); examples run via
`devtools::run_examples()`; vignettes knit (`rmarkdown::render` each, chunks `eval=FALSE` for
real Drive stay so); pkgdown index script passes; no `cache_dir = NULL` example writes to home.

### Gate (orchestrator)
1. Full suite: 0 failed, 0 warnings, 0 skipped-unexpected.
2. `roxygen2::roxygenise()` → clean `git diff man/ NAMESPACE`.
3. `rcmdcheck::rcmdcheck(args = "--no-manual")` or `devtools::check()` → 0 errors/warnings;
   NOTEs only pre-existing.
4. Greps from T7 empty.
5. Snapshot churn check in `_snaps/`.
6. Commit per phase (`feat: …`, `test: …`, `docs: …`). Co-author trailer: follow user's standing
   preference recorded in the raw-sync notes (none) unless told otherwise.
7. PR to `main`; body lists the decision table and NEWS entry.

---

## 4. Brief template (orchestrator fills; one file per task under `tools/briefs/`)

```
# Brief Tn — <title>
Role: implementer | verifier        Model: sonnet        Budget: close ≤150k; stop+report at 100k
Branch: feat/single-local-copy      Do NOT run full suite (Phase 2) / MAY run full suite (Phase 3)

## Goal (2–3 sentences)
## Design excerpt (paste only the §2 rows this task needs)
## Files you may edit
## Files/ranges to read (with line numbers from grep at brief time)
## Files you must NOT read or edit
## Tests to write first (bullet list, one line each, RED expected)
## Implementation notes (symbol-level)
## Edge list (for the verifier; implementer should pre-empt)
## Commands
## Report format → §6
```

## 5. Verifier brief addendum
```
You are verifying Tn. You did not write it. Assume it is wrong until proven otherwise.
1. git status --short → anything outside the allowed list = FAIL.
2. Run the task's test files. Paste output.
3. Add ≥3 new tests (name them `test_that("[Vn] …")`). Draw from the edge list AND invent two
   of your own. Run. Paste output.
4. Verdict PASS/FAIL. For FAIL: file:line, expected vs actual, minimal repro.
5. Leftovers outside scope: list, do not fix.
```

## 6. Report template (implementer and verifier)
```
Task: Tn / Vn        Tokens used (approx):        Verdict (verifier only): PASS|FAIL
Files changed:
RED output (pre-impl):      <paste>
GREEN output (post-impl):   <paste>
Tests added:                <names>
Deviations from brief:      <none | list>
Leftovers / risks:          <list>
```

---

## 7. Tracker (orchestrator updates)

| Task | Agent | State | Verifier | State | Notes |
|---|---|---|---|---|---|
| P0 | orchestrator | done | – | – | branch + plan committed; raw-sync fix merged (184a935); briefs in `tools/briefs/` |
| T1 | sonnet | in progress | V1 | todo | |
| T2 | | todo | V2 | todo | after V1 PASS |
| T3 | | todo | V3 | todo | Phase 2 |
| T4 | | todo | V4 | todo | Phase 2 |
| T5 | | todo | V5 | todo | Phase 2 |
| T6 | | todo | V6 | todo | Phase 2 |
| T7 | | todo | V7 | todo | Phase 3, after all V3–V6 PASS |
| T8 | | todo | V8 | todo | Phase 3 |
| Gate | orchestrator | todo | – | – | |

Decisions log
- 2026-10-03: default cache root `fs::path_home(".gdpins","cache")`, not `tools::R_user_dir()` (user).
- 2026-10-03: `local_dir` deprecated via lifecycle; `cache_dir` wins when both given (user).
- 2026-10-03: `cache_board` + `local_dir` fields removed outright; configs = `local_only`,
  `drive_cache`, `drive_only` (orchestrator, accepted).
- 2026-10-03: merged `fix/raw-sync-locked-files` into this branch before Phase 1; T4 must leave
  raw-sync code and `Unreadable / locked local files` tests untouched (user).
- 2026-10-03: test-board.R sections 1–3 moved T1 → T2 (they go through `.build_board`; T1 cannot
  make them GREEN). T1 keeps section 8 + pure `.board_spec()` tests (orchestrator).
- 2026-10-03: spec list drops `local_dir`; names `name, drive_path, cache_dir, versioned, create,
  on_discrepancy, adapter, config`; `cache_dir` NULL for `drive_only` (orchestrator).
- 2026-10-03: `.default_cache_dir()` also drops empty components and maps `.`/`..` to `_`
  (traversal guard) (orchestrator).
- 2026-10-03: print/summary path label `local` for `local_only`, `cache` otherwise (orchestrator).
- 2026-10-03: T1 adds placeholder `# gdpins 0.0.1.9024` NEWS heading to keep DESCRIPTION == NEWS;
  T8 writes the entry (orchestrator).
