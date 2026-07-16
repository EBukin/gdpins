# Changelog

## gdpins 0.0.1.9022

### Bug fixes

- **Fixed pin type drift when copying pins between boards.**
  [`gdpins_sync()`](https://ebukin.github.io/gdpins/reference/gdpins_sync.md)
  and `on_discrepancy = "sync_from_drive"`/`"sync_to_drive"` copy pins
  via an internal helper that used to write with `pins`’ default type
  (`"rds"`) regardless of how the source pin was stored. A parquet pin
  synced between boards silently became an rds pin — on either side,
  including Drive itself for `to_drive` syncs — and lost the
  tibble-normalisation that
  [`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md)
  applies to parquet reads. The copy now preserves the source pin’s
  [`pins::pin_meta()`](https://pins.rstudio.com/reference/pin_meta.html)
  type.

## gdpins 0.0.1.9021

### New features

- **Boards are now lazy.**
  [`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md)
  no longer touches Drive: it records its arguments and connects on
  first use. Setting up three boards in a script used to cost three
  Drive round-trips plus three sync checks even if you only ever read
  one of them — now you pay only for the boards you touch. The deferred
  work is the same work as before (online probe, Drive existence/create
  check, folder-ID resolution, `pins` board construction, and the
  `on_discrepancy` sync check); it just happens the first time something
  reads the board’s `drive_board`, `cache_board`, or `local_board`. In
  practice that means the first
  [`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md)/[`gdpins_pin_write()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_write.md)/
  [`gdpins_board_status()`](https://ebukin.github.io/gdpins/reference/gdpins_board_status.md)/[`gdpins_sync()`](https://ebukin.github.io/gdpins/reference/gdpins_sync.md).
  See
  [`?"lazy-boards"`](https://ebukin.github.io/gdpins/reference/lazy-boards.md).
  - [`gdpins_board_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_board_connect.md)
    forces a lazy board to connect on demand, so you can choose when to
    pay. It accepts an `on_discrepancy` override for that connection.
  - [`gdpins_board_is_connected()`](https://ebukin.github.io/gdpins/reference/gdpins_board_is_connected.md)
    reports whether a board has connected yet, without connecting it.
  - [`print()`](https://rdrr.io/r/base/print.html),
    [`format()`](https://rdrr.io/r/base/format.html) and
    [`summary()`](https://rdrr.io/r/base/summary.html) never connect a
    board — they describe it from its declared config and report
    `connected: FALSE`.
  - Connection state is shared across copies: passing a board to a
    function and using it there connects the caller’s board too, rather
    than reconnecting.

### Breaking changes

- **Board init errors and sync warnings now surface at first use, not at
  [`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md).**
  A mistyped `drive_path`, a missing folder with `create = FALSE`, the
  `create = NA` interactive prompt, and the `on_discrepancy` sync
  warning all move from the init call to the first board access. To get
  the old timing back, call
  [`gdpins_board_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_board_connect.md)
  right after init, pass `gdpins_init_board(lazy = FALSE)`, or set
  `options(gdpins.lazy_boards = FALSE)` globally. An explicit `lazy`
  argument always beats the option.
- `$` and `[[` on a `gdpins_board` no longer partial-match field names:
  `board$drive` is `NULL` rather than an ambiguous match against
  `drive_board` and `drive_path`. Spell fields in full.

## gdpins 0.0.1.9015

### Bug fixes

- **[`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md)
  no longer reports a sync discrepancy when there is none.** The
  init-time check ran its `on_discrepancy` action for *any* status it
  managed to compute, without ever inspecting the result: only an
  outright error in
  [`gdpins_board_status()`](https://ebukin.github.io/gdpins/reference/gdpins_board_status.md)
  suppressed it. Every board therefore warned
  `"<board>": sync discrepancy detected` on every call — including
  brand-new empty boards and boards that were fully in sync — and
  `on_discrepancy = "sync_from_drive"` / `"sync_to_drive"` re-synced
  boards that needed nothing. The status is now inspected, and the
  action fires only when a row genuinely needs reconciling. Real drift
  still warns and still syncs.

  - An **empty** status (nothing on either side) is not a discrepancy.
  - **`"offline"`** rows are not a discrepancy:
    [`gdpins_board_status()`](https://ebukin.github.io/gdpins/reference/gdpins_board_status.md)
    has already warned about connectivity and cannot know the Drive
    side.

- **[`gdpins_sync()`](https://ebukin.github.io/gdpins/reference/gdpins_sync.md)
  is no longer silent when there is nothing to do.** Both the board and
  raw-connection paths skipped every in-sync item and returned without
  printing anything, which was indistinguishable from a no-op failure.
  They now report
  `everything in sync, nothing to reconcile (N pin/file(s) checked)`.

- **[`gdpins_sync()`](https://ebukin.github.io/gdpins/reference/gdpins_sync.md)
  board messages now name the board**, e.g.
  `Board "data_raw": synced "cars" Drive -> local.`, so sync output is
  unambiguous when several boards are reconciled in one session.
  Conflict resolutions and interactive choices are now reported too,
  rather than only the directional copies.

## gdpins 0.0.1.9012

### New features

- **Names now resolve instead of just failing.**
  [`gdpins_raw_path()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_path.md),
  [`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md)
  and
  [`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md)
  match the name you pass against what actually exists, stopping at the
  first hit: exact path → unique basename → case-insensitive exact →
  same-stem-different-extension → edit-distance neighbours → “nothing
  close”. A name is auto-resolved **only** when the match is exact *and*
  unique; every looser rung merely suggests, so gdpins never silently
  reads a different file than you asked for. `"cars.csv"` now finds
  `"sub/cars.csv"`; a typo gets a “did you mean” listing the nearest
  candidates. See
  [`?"raw-connection"`](https://ebukin.github.io/gdpins/reference/raw-connection.md)
  for the full ladder.

  - [`gdpins_raw_remove()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_remove.md)
    deliberately uses **only** the exact-path rung. It hard-deletes the
    local copy, so it never guesses; missing targets remain an
    idempotent no-op.
  - The case-insensitive rung also settles a real platform difference:
    [`file.exists()`](https://rdrr.io/r/base/files.html) is
    case-insensitive on Windows and case-sensitive elsewhere, so gdpins
    now does the case-folding itself and returns the on-disk spelling on
    every platform.

- **Glob / listing mode.** A `name` containing `*` or `?` switches
  [`gdpins_raw_path()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_path.md),
  [`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md),
  [`gdpins_raw_remove()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_remove.md),
  [`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md)
  and
  [`gdpins_pin_path()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_path.md)
  into listing mode: they return what matches rather than acting on one
  item. Listing mode never bulk-reads and never bulk-deletes. `"*"`
  lists everything; `"*.csv"` matches at **any** depth (unlike
  [`gdpins_raw_ls()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_ls.md),
  whose `depth = 2` default hides `sub/sub/folder/file.rds`). Matching
  is case-sensitive on every platform.

- **[`gdpins_pin_path()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_path.md)**
  — the path counterpart of
  [`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md),
  completing the `*_get`/`*_read` return **objects**, `*_path` returns
  **paths** rule on the pins side. Same board, same name, same
  local-first resolution (local → cache → Drive), but returns where the
  pin’s file(s) live. The pin is materialised when Drive holds the only
  copy, as
  [`gdpins_raw_path()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_path.md)
  already does. Returns a character vector: length 1 for an ordinary
  pin, longer for a multi-file pin written with
  [`pins::pin_upload()`](https://pins.rstudio.com/reference/pin_download.html).

- **Listings are classed and print compactly.**
  [`gdpins_raw_ls()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_ls.md)
  gains class `gdpins_raw_listing` and
  [`gdpins_list_pins()`](https://ebukin.github.io/gdpins/reference/gdpins_list_pins.md)
  gains `gdpins_pin_listing`, each ahead of the tibble classes. Both
  keep their existing columns and remain ordinary tibbles
  (`inherits(x, "tbl_df")` is still `TRUE`); the new `print` methods
  show names only.

### Bug fixes

- **A multi-file pin is no longer listed once per file.**
  [`gdpins_list_pins()`](https://ebukin.github.io/gdpins/reference/gdpins_list_pins.md)
  built its row from `pins::pin_meta()$file_size`, which is a *vector*
  for a pin written with
  [`pins::pin_upload()`](https://pins.rstudio.com/reference/pin_download.html).
  That recycled `name` and produced one row per file, so a two-file pin
  appeared twice. One pin is now one row, with the total size.

### Breaking changes

- [`gdpins_raw_put_file()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_put_file.md)
  now requires `name` to carry a file extension (any extension — it
  uploads bytes verbatim, so `.gpkg`/`.tif`/`.xlsx` are all fine).
  Previously an extensionless name was accepted and produced a file that
  could not be identified on Drive.
- [`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md)
  on an extension it cannot deserialise now errors naming the four
  readable formats (`.rds`, `.parquet`, `.geojson`, `.csv`) and pointing
  at
  [`gdpins_raw_path()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_path.md),
  which returns a path for *any* extension. The previous message named
  only the offending extension.
- [`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md)
  on a name that matches nothing now reports that the name is unknown
  (with suggestions) instead of blaming the local mirror for a file that
  exists nowhere. A name that exists on Drive but is not mirrored
  locally still reports `Local file not found` and points at
  `force_refresh`.

### Internal

- `tools` and `utils` added to `Imports`. Both were already used on
  always-run code paths
  ([`tools::md5sum()`](https://rdrr.io/r/tools/md5sum.html),
  [`tools::file_ext()`](https://rdrr.io/r/tools/fileutils.html));
  [`utils::adist()`](https://rdrr.io/r/utils/adist.html) powers the
  edit-distance rung. This also clears a pre-existing
  `R CMD check --as-cran` NOTE.

## gdpins 0.0.1.9010

### New features

- **Keep geometry as raw WKT text on read.**
  [`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md)
  now accepts `wkt_engine = "none"`, which skips `sf` restoration and
  returns the geometry columns as WKT character vectors (names keep
  their `__<epsg>__` suffix). The `"none"` value is read-only — it is
  not a valid `gdpins.wkt_engine` option and never applies to writes.
- **[`gdpins_as_sf()`](https://ebukin.github.io/gdpins/reference/gdpins_as_sf.md)**
  — a user-facing, autodetecting WKT → `sf` converter.
  - Autodetects the geometry column (character column named like
    `geom__4326__`, `geom`, or `wkt`). Returns the input unchanged with
    a warning when none is found (plain, non-spatial data passes
    through); errors asking for `column` only when several candidates
    match.
  - Infers the CRS from the column name: the standard `__<epsg>__`
    pattern is trusted silently, a non-standard digit run
    (e.g. `geom_1111`) is used with a message, and a name with no digits
    falls back to `default_epsg` (4326) with a warning. Pass `epsg`
    explicitly to silence inference.
  - Uses the same swappable WKT engine (`"wk"` default / `"sf"`) as the
    rest of the package. Pairs with
    `gdpins_pin_read(wkt_engine = "none")`.

## gdpins 0.0.1.0

### New features

- The `sf` ⇄ parquet geometry encoding gained a **swappable WKT
  engine**, selectable per call or session-wide (#12).
  - `"wk"` (new **default**) uses the wk package: ~20× faster geometry
    writes than `sf` and full-precision.
  - `"sf"` remains available as a dependency-light fallback.
  - Choose it with the `engine` argument on
    [`gdpins_sf_to_parquet()`](https://ebukin.github.io/gdpins/reference/gdpins_sf_to_parquet.md)
    /
    [`gdpins_parquet_to_sf()`](https://ebukin.github.io/gdpins/reference/gdpins_parquet_to_sf.md),
    the `wkt_engine` argument on
    [`gdpins_pin_write()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_write.md),
    [`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md),
    [`gdpins_raw_put_object()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_put_object.md)
    and
    [`gdpins_raw_get()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_get.md),
    or the `gdpins.wkt_engine` option
    (`options(gdpins.wkt_engine = "sf")`).
  - The two engines are read-compatible: WKT written by one reads back
    correctly with the other, so switching never requires re-encoding
    stored data.
- `wk` is now an `Imports` dependency (it backs the default engine).

### Bug fixes

- **Geometry precision.** The previous encoder called
  [`sf::st_as_text()`](https://r-spatial.github.io/sf/reference/st_as_text.html)
  at its default `getOption("digits")` (7 significant figures), which
  silently rounded projected coordinates (e.g. UTM 32643 metres) by up
  to ~0.5 m on write. Both engines are now full-precision — the `"wk"`
  engine by construction and the `"sf"` engine via `digits = 15`.

### Internal

- Added `tests/testthat/test-benchmark-wkt.R`, a skip-by-default
  benchmark (`GDPINS_BENCH_WKT=true`) comparing the sf / wk / lwgeom WKT
  engines across polygon and multipolygon workloads.
