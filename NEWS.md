# gdpins 0.0.1.9027

## Breaking changes

* **Duplicate-named Drive items now error (H3).** When a Drive folder holds
  more than one item with the same name, the real Drive adapter stops with an
  error of class `gdpins_error_ambiguous_drive_name` that lists each
  duplicate's id and modified time. Previously it silently picked the first
  one, so a read, overwrite or trash could hit an arbitrary duplicate.
* **Drive errors surface instead of reading as "absent" (H4).** An error from
  Drive while listing or looking up a path (expired token, 403, quota, network)
  now propagates. `gdpins_init_board()` and `gdpins_raw_connect()` stop with
  that error instead of taking the create-confirm path for a folder that
  exists. A transient error means "re-run". `gdpins_raw_remove()` deletes the
  local file before trashing it on Drive, so a Drive error there now surfaces
  after the local delete; before, the Drive failure was silently ignored.
* **A conflict on an unversioned board now stops (H5).** `gdpins_sync(x,
  on_conflict = "version")` (the default) on an unversioned board used to copy
  Drive over local and lose the local content. A one-slot board cannot keep
  both sides, so `"version"` now behaves like `"stop"`: non-conflicting pins
  are still copied, conflicting pins are left unchanged, and sync aborts with
  an error of class `gdpins_error_unversioned_conflict`,
  `gdpins_error_sync_conflict` and `gdpins_error`. Use `on_conflict =
  "prompt"` to choose a side. `gdpins_init_board(on_discrepancy = "sync_*")`
  on such a board now warns "Sync ... failed" instead of silently
  overwriting. The `"stop"` aborts for boards and raw connections now carry
  the classes `gdpins_error_sync_conflict` and `gdpins_error`.
* **Prune functions return a plan tibble (H8).**
  `gdpins_prune_pin_versions()` used to return a character vector of the
  Drive version ids it removed, and `gdpins_prune_board_versions()` a named
  list of such vectors. Both now return, invisibly, one tibble with columns
  `name`, `version`, `side` (`"drive"` or `"local"`), `hash` and `action`
  (`"remove"` or `"keep_unsynced"`): one row per version removed (or, in a dry
  run, to be removed) and per unsynced local version that was kept. The board
  function returns one tibble for all pins instead of a named list. The old
  value could not report local deletions. Read Drive removals with
  `plan$version[plan$side == "drive" & plan$action == "remove"]`.

## Bug fixes

* **Pin names are validated (H1).** `gdpins_pin_write()`, `gdpins_pin_read()`,
  `gdpins_pin_path()`, `gdpins_pin_remove()`, `gdpins_pin_info()` and
  `gdpins_prune_pin_versions()` reject `"."`, `".."`, names starting with a
  dot, and names containing `/`, `\` or a control character, with an error of
  class `gdpins_error_invalid_name`. Previously `gdpins_pin_remove(board, "..")`
  deleted the parent directory of the board's local copy, and
  `gdpins_prune_pin_versions(board, "..")` deleted its siblings.
  `gdpins_prune_pin_versions()` checked no name at all, and `NA` passed every
  verb's check. Pin names that arrive from a Drive listing and break these
  rules are skipped with a `gdpins_warning_invalid_name` warning by
  `gdpins_board_status()`, `gdpins_sync()` and
  `gdpins_prune_board_versions()`. See the "Pin names" section of `?verbs`.
* **Raw file names are validated (H2).** `gdpins_raw_put_object()`,
  `gdpins_raw_put_file()`, `gdpins_raw_remove()`, `gdpins_raw_get()` and
  `gdpins_raw_path()` reject names with a `..` or `.` segment, an absolute path
  or drive letter, a backslash, a segment ending in a dot or space, or a control
  character (`gdpins_error_invalid_name`). `gdpins_raw_put_object(conn, x,
  "../x.csv")` used to overwrite a file next to `local_path`, and on a real
  Drive created a folder literally named `..`. A vector `name` given to the put
  verbs now fails with that class instead of base R's "the condition has
  length > 1".
* Every local path built from a raw name, including names read from a Drive
  listing, is checked to stay inside `local_path` (`gdpins_error_path_escape`).
  `gdpins_raw_connect(on_discrepancy = "sync_from_drive")` and
  `gdpins_refresh_disconnect()` skip an unsafe Drive name with a
  `gdpins_warning_invalid_name` warning; `gdpins_sync()` reports it as a failed
  file.
* **Drive names are matched literally (H3).** The real Drive adapter compared
  names as unescaped regular expressions. A name containing `(`, `)`, `+`,
  `[`, `*`, `?`, `^`, `$`, `|`, `{` or `}` never matched itself: `exists()`
  returned `FALSE`, downloads said "not found", trash did nothing, and every
  upload created a new duplicate file. `.` matched any character, so `a.csv`
  could resolve to `abcsv`. Names are now compared with `==`. The raw
  connection's Drive-prefix strip had the same bug and now uses `startsWith()`.
* **Remediation for duplicates left by the old H3 bug.** Each write of a name
  with regex metacharacters created another Drive file of the same name; such
  folders now raise `gdpins_error_ambiguous_drive_name`. List them with
  `googledrive::drive_ls(<folder>)`, keep the file with the newest
  `modifiedTime`, and `googledrive::drive_trash()` the rest.
* **Drive listing and lookup errors are no longer swallowed (H4).** The real
  adapter's `exists`, `get_id`, `download`, `trash`, `md5`, `mtime`, `ls`,
  `mkdir` and `upload`, and `gdpins_board_status()` / `gdpins_sync()` for
  boards (`pins::pin_list()`, `pins::pin_versions()`) and raw connections
  (`gd_ls()`), caught every error and treated it as "nothing there". During
  an outage that created duplicate folders and files, and made sync report
  every local item `local_ahead` and push stale local copies over Drive.
* **Versioned conflicts keep both sides on both boards (H5).** Conflict
  resolution copied Drive to local and then local's *new* latest (Drive's
  content) back to Drive, so the local content never reached Drive and the pin
  was reported in sync. Now both pre-conflict contents become versions on both
  boards; the one with the later `created` time (tie: Drive) is the latest on
  both. Writes wait for the next second when needed, because pins version ids
  have one-second resolution and same-second ids sort by hash, not by write
  order. Copies between boards (conflicts and normal sync) now keep `title`,
  `description`, user `metadata`, `tags` and `urls`, not only `type`. A copy
  whose source cannot be read is no longer counted or reported as synced.
* **Edits on both sides are detected as conflicts (H6).** Status used
  "newer timestamp wins" whenever the two sides differed, so a pin or raw file
  edited on both sides since the last sync was reported `drive_ahead` or
  `local_ahead`, and `gdpins_sync()` replaced one edit with the other without
  entering conflict handling (raw files were also exposed to clock skew).
  gdpins now keeps a local **last-synced baseline**: each side's latest pin
  hash in `<cache_dir>/.gdpins-sync.rds` for a board, the file MD5 under
  `getOption("gdpins.cache_dir")/.gdpins-raw-baselines/` for a raw connection.
  It is recorded by `gdpins_pin_write()`, `gdpins_raw_put_object()`,
  `gdpins_raw_put_file()`, the connect-time sync of `gdpins_raw_connect()`,
  and by `gdpins_sync()` for every item it copies, resolves or finds in sync;
  `gdpins_pin_remove()` and `gdpins_raw_remove()` drop the entry. One side
  changed since the baseline: that side is ahead. Both changed: `"conflict"`,
  whatever the timestamps say. Items without a baseline entry keep the
  timestamp rule until the first sync records one. An unreadable baseline file
  raises one warning of class `gdpins_warning_baseline_unreadable` and is
  ignored. The status tibble's columns are unchanged.
* **Raw conflicts back up the local file (H7).** With the default
  `on_conflict = "version"`, a raw file that changed on both sides was
  overwritten by Drive's copy with only an info message. The local file is
  now first copied to `<stem>.conflict-<UTC timestamp>.<ext>` in the same
  folder, then Drive's copy replaces it, with a warning of class
  `gdpins_warning_raw_conflict_backup`. The backup is a normal file in
  `local_path`, so the next `gdpins_sync()` uploads it to Drive unless you
  delete it.
* **Pruning no longer deletes unsynced local versions, and reports every
  deletion (H8).** The plan, the dry-run listing, the threshold count and the
  return value came from Drive only, while the local copy was pruned on its
  own list: a local version that never reached Drive was hard-deleted when it
  was older than the newest `keep`, and local deletions were never shown or
  counted. Now a local version beyond `keep` is deleted only when its content
  hash is also on Drive; otherwise it is kept and reported as
  `"keep_unsynced"`. The dry run lists Drive removals, local removals and kept
  versions. The threshold counts the larger of the Drive and local removal
  counts, so local-only deletions can trigger it. "No versions to remove"
  reports the real number of versions present.
* **Board-level prune threshold uses the total (H8, closes audit L5).**
  `gdpins_prune_board_versions()` asked for confirmation (or `force = TRUE`)
  only when a single pin exceeded `threshold`; many pins just under it were
  pruned without a check. The total removal count over all pins is now
  compared with `threshold`.
* **Offline boards never delete unsynced versions (H8).** On a board switched
  with `gdpins_go_offline()`, Drive cannot be checked, so pruning keeps every
  local version (`"keep_unsynced"`) instead of deleting the offline writes.
  A board built as `local_only` prunes as before.
* **Pins present on Drive only no longer break board pruning (H8).**
  `gdpins_prune_board_versions()` errored with "Can't find pin" for a pin
  that was on Drive but not in the local copy; such a pin is now pruned on
  Drive with no local rows.
* **Parquet is written once per `gdpins_pin_write()` (H8).** The same file is
  uploaded to Drive and to the local copy, so both versions carry the same
  content hash by construction; prune and sync match versions on that hash.

## Security

* Pin names and raw file names can no longer escape the board or the raw
  connection's `local_path`. A crafted name -- typed by a user, or a Drive item
  named `..` created by a collaborator -- could previously write, overwrite or
  delete files outside the gdpins directories (H1, H2).

## Known limitations

* Real Drive adapter: `pins::board_gdrive()` caches Drive versions under
  `cache_dir`, which is also the local board's path (audit M10). Drive
  versions can therefore appear as local versions and mask the local latest,
  which can confuse status and the sync baseline. The fake adapter cannot
  reproduce this; a fix is planned with M10.
* Conflict resolution ignores `direction` (audit M15): a versioned-board
  conflict is resolved by writing to both sides even under
  `direction = "from_drive"` or `"to_drive"`.
* `gdpins_raw_connect()`'s connect-time check still compares file-name sets
  only, not content (audit M16), and the local listings used by status and
  `gdpins_raw_ls()` do not skip sync sidecar files.

# gdpins 0.0.1.9026

## New features

* **Parquet is now read and written with arrow by default.** A new
  `gdpins.parquet_engine` option selects the parquet engine — `"arrow"`
  (default) or `"nanoparquet"`. Set `options(gdpins.parquet_engine =
  "nanoparquet")` to restore the previous behaviour. Both engines write
  standard parquet that either can read, so the choice is transparent apart
  from memory use. See `?"io-formats"`.

## Bug fixes

* **Fixed a memory explosion when reading pins with large geometry columns.**
  `gdpins_pin_read()` (and the internal copy used by `gdpins_sync()`) read
  parquet through `pins`, which is hardwired to `nanoparquet`. On a pin whose
  WKT geometry column holds a few large (multi-MB) string cells — e.g. one row
  per administrative region — `nanoparquet::read_parquet()` allocates tens of
  gigabytes and crashes the R session, even though the file is only ~15 MB on
  disk. gdpins now reads parquet with arrow by default, which reads the same
  bytes in bounded memory. Existing pins are read unchanged; no re-write is
  needed. New parquet pins are written by arrow (stored as a `pins` `"file"`
  pin) so they never carry the nanoparquet-authored payload that triggers the
  blow-up. The upstream `nanoparquet` bug is tracked separately.

# gdpins 0.0.1.9025

## Breaking changes

* **A Drive board now keeps at most one local copy.** The old
  `"drive_cache_local"` configuration — a standalone `local_board`/`local_dir`
  *and* a separate `cache_board`/`cache_dir` on the same board — is gone.
  `gdpins_board` objects no longer have `cache_board` or `local_dir` fields;
  `board$cache_board` and `board$local_dir` now return `NULL`. The legal
  configs are `"local_only"`, `"drive_cache"` (one local copy), and the new
  `"drive_only"` (no local copy at all).
* **`cache_dir` is now the single argument that controls a board's local
  copy**, on `gdpins_init_board()`:
  - `NULL` (the default) or `TRUE` — use the default path,
    `getOption("gdpins.cache_dir")/<adapter root>/<drive_path>` (option
    default `~/.gdpins/cache`, via `fs::path_home()`).
  - A path — use that directory as the local copy.
  - `FALSE` — no local copy (`"drive_only"`); Drive downloads go to a session
    temp dir instead, and the board cannot go offline.
  - For a board without `drive_path` (`"local_only"`), `cache_dir` is the
    local board's own path.
* **`local_dir` is deprecated.** If supplied while `cache_dir` is `NULL`, it
  is used as `cache_dir` (with a deprecation warning); if `cache_dir` is also
  supplied, `local_dir` is ignored (with a warning that both were given).
* **`gdpins_go_online()` no longer copies local → cache.** With only one
  local copy per board, there is nothing left to reconcile between a
  standalone local directory and a cache directory on reconnect.

See `vignette("gdpins-usage")` ("Board initialisation", "Offline behaviour")
and `?gdpins_init_board` for the full config/`cache_dir` reference.

# gdpins 0.0.1.9023

## Bug fixes

* **`gdpins_sync()` on a raw connection no longer aborts the whole run when one
  file cannot be read.** A file held open by another program (Word, Excel, a
  sync client) passes `file.exists()`, so the upload started and only failed
  once `curl` streamed the bytes — surfacing as an opaque
  `"read error getting mime data"` from `curl::curl_fetch_memory()`, with every
  remaining file left unsynced. Raw sync now checks that each local file can
  actually be opened *and read* before uploading (a Windows byte-range lock,
  as held by Office, lets the open succeed but returns no bytes), and isolates
  per-file failures — uploads and downloads alike — so the rest of the folder
  still syncs. A single end-of-run warning reports how many files synced and
  which failed, with each error message; the "close the program" hint appears
  only for unreadable local files.

* **Raw sync no longer reports a missing local file as synced.** It used to
  warn and then print "Synced … local -> Drive" anyway; it is now counted as a
  failure in the end-of-run summary.

# gdpins 0.0.1.9022

## Bug fixes

* **Fixed pin type drift when copying pins between boards.** `gdpins_sync()`
  and `on_discrepancy = "sync_from_drive"`/`"sync_to_drive"` copy pins via an
  internal helper that used to write with `pins`' default type (`"rds"`)
  regardless of how the source pin was stored. A parquet pin synced between
  boards silently became an rds pin — on either side, including Drive itself
  for `to_drive` syncs — and lost the tibble-normalisation that
  `gdpins_pin_read()` applies to parquet reads. The copy now preserves the
  source pin's `pins::pin_meta()` type.

# gdpins 0.0.1.9021

## New features

* **Boards are now lazy.** `gdpins_init_board()` no longer touches Drive: it
  records its arguments and connects on first use. Setting up three boards in a
  script used to cost three Drive round-trips plus three sync checks even if you
  only ever read one of them — now you pay only for the boards you touch. The
  deferred work is the same work as before (online probe, Drive
  existence/create check, folder-ID resolution, `pins` board construction, and
  the `on_discrepancy` sync check); it just happens the first time something
  reads the board's `drive_board`, `cache_board`, or `local_board`. In practice
  that means the first `gdpins_pin_read()`/`gdpins_pin_write()`/
  `gdpins_board_status()`/`gdpins_sync()`. See `?"lazy-boards"`.
  - `gdpins_board_connect()` forces a lazy board to connect on demand, so you
    can choose when to pay. It accepts an `on_discrepancy` override for that
    connection.
  - `gdpins_board_is_connected()` reports whether a board has connected yet,
    without connecting it.
  - `print()`, `format()` and `summary()` never connect a board — they describe
    it from its declared config and report `connected: FALSE`.
  - Connection state is shared across copies: passing a board to a function and
    using it there connects the caller's board too, rather than reconnecting.

## Breaking changes

* **Board init errors and sync warnings now surface at first use, not at
  `gdpins_init_board()`.** A mistyped `drive_path`, a missing folder with
  `create = FALSE`, the `create = NA` interactive prompt, and the
  `on_discrepancy` sync warning all move from the init call to the first board
  access. To get the old timing back, call `gdpins_board_connect()` right after
  init, pass `gdpins_init_board(lazy = FALSE)`, or set
  `options(gdpins.lazy_boards = FALSE)` globally. An explicit `lazy` argument
  always beats the option.
* `$` and `[[` on a `gdpins_board` no longer partial-match field names:
  `board$drive` is `NULL` rather than an ambiguous match against `drive_board`
  and `drive_path`. Spell fields in full.

# gdpins 0.0.1.9015

## Bug fixes

* **`gdpins_init_board()` no longer reports a sync discrepancy when there is
  none.** The init-time check ran its `on_discrepancy` action for *any* status
  it managed to compute, without ever inspecting the result: only an outright
  error in `gdpins_board_status()` suppressed it. Every board therefore warned
  `"<board>": sync discrepancy detected` on every call — including brand-new
  empty boards and boards that were fully in sync — and
  `on_discrepancy = "sync_from_drive"` / `"sync_to_drive"` re-synced boards that
  needed nothing. The status is now inspected, and the action fires only when a
  row genuinely needs reconciling. Real drift still warns and still syncs.
  - An **empty** status (nothing on either side) is not a discrepancy.
  - **`"offline"`** rows are not a discrepancy: `gdpins_board_status()` has
    already warned about connectivity and cannot know the Drive side.

* **`gdpins_sync()` is no longer silent when there is nothing to do.** Both the
  board and raw-connection paths skipped every in-sync item and returned without
  printing anything, which was indistinguishable from a no-op failure. They now
  report `everything in sync, nothing to reconcile (N pin/file(s) checked)`.

* **`gdpins_sync()` board messages now name the board**, e.g.
  `Board "data_raw": synced "cars" Drive -> local.`, so sync output is
  unambiguous when several boards are reconciled in one session. Conflict
  resolutions and interactive choices are now reported too, rather than only
  the directional copies.

# gdpins 0.0.1.9012

## New features

* **Names now resolve instead of just failing.** `gdpins_raw_path()`,
  `gdpins_raw_get()` and `gdpins_pin_read()` match the name you pass against
  what actually exists, stopping at the first hit: exact path → unique basename
  → case-insensitive exact → same-stem-different-extension → edit-distance
  neighbours → "nothing close". A name is auto-resolved **only** when the match
  is exact *and* unique; every looser rung merely suggests, so gdpins never
  silently reads a different file than you asked for. `"cars.csv"` now finds
  `"sub/cars.csv"`; a typo gets a "did you mean" listing the nearest candidates.
  See `?"raw-connection"` for the full ladder.
  - `gdpins_raw_remove()` deliberately uses **only** the exact-path rung. It
    hard-deletes the local copy, so it never guesses; missing targets remain an
    idempotent no-op.
  - The case-insensitive rung also settles a real platform difference:
    `file.exists()` is case-insensitive on Windows and case-sensitive elsewhere,
    so gdpins now does the case-folding itself and returns the on-disk spelling
    on every platform.

* **Glob / listing mode.** A `name` containing `*` or `?` switches
  `gdpins_raw_path()`, `gdpins_raw_get()`, `gdpins_raw_remove()`,
  `gdpins_pin_read()` and `gdpins_pin_path()` into listing mode: they return
  what matches rather than acting on one item. Listing mode never bulk-reads and
  never bulk-deletes. `"*"` lists everything; `"*.csv"` matches at **any** depth
  (unlike `gdpins_raw_ls()`, whose `depth = 2` default hides
  `sub/sub/folder/file.rds`). Matching is case-sensitive on every platform.

* **`gdpins_pin_path()`** — the path counterpart of `gdpins_pin_read()`,
  completing the `*_get`/`*_read` return **objects**, `*_path` returns **paths**
  rule on the pins side. Same board, same name, same local-first resolution
  (local → cache → Drive), but returns where the pin's file(s) live. The pin is
  materialised when Drive holds the only copy, as `gdpins_raw_path()` already
  does. Returns a character vector: length 1 for an ordinary pin, longer for a
  multi-file pin written with `pins::pin_upload()`.

* **Listings are classed and print compactly.** `gdpins_raw_ls()` gains class
  `gdpins_raw_listing` and `gdpins_list_pins()` gains `gdpins_pin_listing`,
  each ahead of the tibble classes. Both keep their existing columns and remain
  ordinary tibbles (`inherits(x, "tbl_df")` is still `TRUE`); the new `print`
  methods show names only.

## Bug fixes

* **A multi-file pin is no longer listed once per file.** `gdpins_list_pins()`
  built its row from `pins::pin_meta()$file_size`, which is a *vector* for a pin
  written with `pins::pin_upload()`. That recycled `name` and produced one row
  per file, so a two-file pin appeared twice. One pin is now one row, with the
  total size.

## Breaking changes

* `gdpins_raw_put_file()` now requires `name` to carry a file extension (any
  extension — it uploads bytes verbatim, so `.gpkg`/`.tif`/`.xlsx` are all fine).
  Previously an extensionless name was accepted and produced a file that could
  not be identified on Drive.
* `gdpins_raw_get()` on an extension it cannot deserialise now errors naming the
  four readable formats (`.rds`, `.parquet`, `.geojson`, `.csv`) and pointing at
  `gdpins_raw_path()`, which returns a path for *any* extension. The previous
  message named only the offending extension.
* `gdpins_raw_get()` on a name that matches nothing now reports that the name is
  unknown (with suggestions) instead of blaming the local mirror for a file that
  exists nowhere. A name that exists on Drive but is not mirrored locally still
  reports `Local file not found` and points at `force_refresh`.

## Internal

* `tools` and `utils` added to `Imports`. Both were already used on always-run
  code paths (`tools::md5sum()`, `tools::file_ext()`); `utils::adist()` powers
  the edit-distance rung. This also clears a pre-existing
  `R CMD check --as-cran` NOTE.

# gdpins 0.0.1.9010

## New features

* **Keep geometry as raw WKT text on read.** `gdpins_pin_read()` now accepts
  `wkt_engine = "none"`, which skips `sf` restoration and returns the geometry
  columns as WKT character vectors (names keep their `__<epsg>__` suffix). The
  `"none"` value is read-only — it is not a valid `gdpins.wkt_engine` option and
  never applies to writes.
* **`gdpins_as_sf()`** — a user-facing, autodetecting WKT → `sf` converter.
  - Autodetects the geometry column (character column named like `geom__4326__`,
    `geom`, or `wkt`). Returns the input unchanged with a warning when none is
    found (plain, non-spatial data passes through); errors asking for `column`
    only when several candidates match.
  - Infers the CRS from the column name: the standard `__<epsg>__` pattern is
    trusted silently, a non-standard digit run (e.g. `geom_1111`) is used with a
    message, and a name with no digits falls back to `default_epsg` (4326) with a
    warning. Pass `epsg` explicitly to silence inference.
  - Uses the same swappable WKT engine (`"wk"` default / `"sf"`) as the rest of
    the package. Pairs with `gdpins_pin_read(wkt_engine = "none")`.

# gdpins 0.0.1.0

## New features

* The `sf` ⇄ parquet geometry encoding gained a **swappable WKT engine**,
  selectable per call or session-wide (#12).
  - `"wk"` (new **default**) uses the wk package: ~20× faster geometry writes
    than `sf` and full-precision.
  - `"sf"` remains available as a dependency-light fallback.
  - Choose it with the `engine` argument on `gdpins_sf_to_parquet()` /
    `gdpins_parquet_to_sf()`, the `wkt_engine` argument on `gdpins_pin_write()`,
    `gdpins_pin_read()`, `gdpins_raw_put_object()` and `gdpins_raw_get()`, or
    the `gdpins.wkt_engine` option (`options(gdpins.wkt_engine = "sf")`).
  - The two engines are read-compatible: WKT written by one reads back correctly
    with the other, so switching never requires re-encoding stored data.
* `wk` is now an `Imports` dependency (it backs the default engine).

## Bug fixes

* **Geometry precision.** The previous encoder called `sf::st_as_text()` at its
  default `getOption("digits")` (7 significant figures), which silently rounded
  projected coordinates (e.g. UTM 32643 metres) by up to ~0.5 m on write. Both
  engines are now full-precision — the `"wk"` engine by construction and the
  `"sf"` engine via `digits = 15`.

## Internal

* Added `tests/testthat/test-benchmark-wkt.R`, a skip-by-default benchmark
  (`GDPINS_BENCH_WKT=true`) comparing the sf / wk / lwgeom WKT engines across
  polygon and multipolygon workloads.
