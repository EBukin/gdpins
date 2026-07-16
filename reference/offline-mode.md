# Temporarily disconnect from Drive, then reconnect and sync later

A Drive-backed `gdpins_board` or `gdpins_raw_conn` normally needs Drive
to be reachable:
[`gdpins_pin_write()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_write.md)
blocks offline writes, and
[`gdpins_sync()`](https://ebukin.github.io/gdpins/reference/gdpins_sync.md)/`gdpins_go_online()`
hard-abort without connectivity. `gdpins_go_offline()` and
`gdpins_go_online()` give users an explicit, reversible way to work
around Drive instability (or work disconnected on purpose) without
losing the ability to reconnect and sync afterwards.

## Usage

``` r
gdpins_go_offline(x, ...)

gdpins_go_online(x, adapter = NULL, on_discrepancy = NULL, ...)
```

## Arguments

- x:

  A `gdpins_board` or `gdpins_raw_conn` object.

- ...:

  Passed to methods (currently unused).

- adapter:

  A `gdpins_drive_adapter` to reconnect with, or `NULL` (default) to
  reuse the adapter stashed by `gdpins_go_offline()` — pass a freshly
  authenticated
  [`gdpins_real_drive()`](https://ebukin.github.io/gdpins/reference/gdpins_real_drive.md)
  here if the stashed adapter's credentials have expired.

- on_discrepancy:

  Character scalar or `NULL`. Same semantics as
  [`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md)/[`gdpins_raw_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_connect.md):
  one of
  `c("prompt","warn","sync_from_drive","sync_to_drive","ignore")`.
  `NULL` resolves to `"prompt"` interactively or `"warn"`
  non-interactively.

## Value

An object of the same class as `x`.

## Details

`gdpins_go_offline(x)` strips the Drive-facing components off `x` and
returns a `"local_only"` object backed by whichever local storage `x`
already had on disk:

- `"drive_cache_local"` boards keep using their standalone `local_board`
  / `local_dir` — the same directory the user was already working in.

- `"drive_cache"` boards (no standalone local dir) fall back to their
  `cache_board` / `cache_dir`, mirroring the automatic offline fallback
  in
  [`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md).

- `"drive_local"` raw connections keep using their existing
  `local_path`.

No files are copied, moved, or deleted — the returned object reuses the
exact same local `pins` board / directory, so anything already on disk
stays reachable, and anything written afterwards lands in the same
place. The original Drive configuration (adapter, drive_path,
drive/cache boards) is stashed on the returned object as an attribute so
`gdpins_go_online()` can restore it later. Calling `gdpins_go_offline()`
on an object that is already `"local_only"` is a no-op.

`gdpins_go_online(x)` reverses this: it requires `x` to have been
produced by `gdpins_go_offline()` (i.e. carry the stashed state), checks
[`gdpins_is_online()`](https://ebukin.github.io/gdpins/reference/gdpins_is_online.md),
reattaches the stashed Drive adapter and path (or a freshly supplied
`adapter`), and runs the same discrepancy check used by
[`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md)
/
[`gdpins_raw_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_connect.md)
— governed by `on_discrepancy` — so that anything written while offline
is reconciled with Drive.

## See also

[`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md),
[`gdpins_raw_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_connect.md),
[`gdpins_sync()`](https://ebukin.github.io/gdpins/reference/gdpins_sync.md),
[`gdpins_board_status()`](https://ebukin.github.io/gdpins/reference/gdpins_board_status.md),
[`gdpins_is_online()`](https://ebukin.github.io/gdpins/reference/gdpins_is_online.md).

## Examples

``` r
adapter <- gdpins_fake_drive()
board <- gdpins_init_board(
  name       = "data_raw",
  drive_path = "my-project/data-raw",
  cache_dir  = tempfile("cache_"),
  local_dir  = tempfile("local_"),
  adapter    = adapter,
  create     = TRUE
)

# Work disconnected for a while -- writes/reads stay local
board_offline <- gdpins_go_offline(board)
#> ℹ Board "data_raw" switched to local-only (offline) mode.
#> ℹ Drive is untouched; call `gdpins_go_online()` to reconnect and sync.
board_offline$config   # "local_only"
#> [1] "local_only"
gdpins_pin_write(board_offline, mtcars, "cars")
#> Creating new version '20260716T190826Z-c0340'
#> Writing to pin 'cars'

# Reconnect and push local changes back up to Drive
board_online <- gdpins_go_online(board_offline, on_discrepancy = "sync_to_drive")
#> Syncing "data_raw" to Drive (on_discrepancy = "sync_to_drive").
#> ✔ Board "data_raw": synced "cars" local -> Drive.
#> ✔ Board "data_raw" reconnected to Drive ("drive_cache_local").
board_online$config    # "drive_cache_local"
#> [1] "drive_cache_local"
```
