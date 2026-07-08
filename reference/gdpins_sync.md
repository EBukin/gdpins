# Synchronise a board or raw connection with Drive

Reconciles Drive and local copies bidirectionally. Direction defaults to
`"auto"` (newer wins). Conflict handling is controlled by `on_conflict`.

## Usage

``` r
gdpins_sync(
  x,
  direction = c("auto", "to_drive", "from_drive"),
  on_conflict = c("version", "prompt", "stop")
)
```

## Arguments

- x:

  A `gdpins_board` or `gdpins_raw_conn` object.

- direction:

  Character scalar. One of `c("auto", "to_drive", "from_drive")`.
  Default `"auto"`.

- on_conflict:

  Character scalar. One of `c("version", "prompt", "stop")`. Default
  `"version"`.

## Value

Invisibly `x`. Called for its side effect.

## Details

"Newer" decision (strongest signal per layer):

- Boards: compare pins version id/timestamp.

- Raw files: compare MD5 (`drive`'s `md5Checksum`).

- mtime only as tiebreaker.

**Conflict handling:**

- Versioned boards: both writes simply become versions (`pins` handles
  it, zero loss). `on_conflict` is effectively `"version"` regardless.

- Raw / unversioned boards with `on_conflict = "stop"`: abort with a
  report of the conflicting items; change nothing.

- Raw / unversioned boards with `on_conflict = "prompt"`: ask the user
  interactively per conflict.

- **Never silent overwrite.**

Writes and syncs are blocked when offline
([`gdpins_is_online()`](https://ebukin.github.io/gdpins/reference/gdpins_is_online.md)
is `FALSE`). An informative error is raised.

## See also

[`gdpins_real_drive()`](https://ebukin.github.io/gdpins/reference/gdpins_real_drive.md),
[`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md),
[`gdpins_raw_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_connect.md),
[`gdpins_go_offline()`](https://ebukin.github.io/gdpins/reference/offline-mode.md)/[`gdpins_go_online()`](https://ebukin.github.io/gdpins/reference/offline-mode.md).

## Examples

``` r
# --- Fake adapter board ---
adapter <- gdpins_fake_drive()
board <- gdpins_init_board(
  name       = "data_raw",
  drive_path = "my-project/data-raw",
  cache_dir  = tempfile("cache_"),
  adapter    = adapter,
  create     = TRUE
)
#> Warning: ! "data_raw": sync discrepancy detected between Drive and local. Run
#>   `gdpins_sync()` to reconcile.
gdpins_sync(board)
#> ℹ Nothing to sync for board "data_raw".

if (FALSE) { # \dontrun{
adapter <- gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")
board   <- gdpins_init_board(
  name       = "data_raw",
  drive_path = "my-project/data-raw",
  cache_dir  = "~/.cache/gdpins/data-raw",
  adapter    = adapter,
  create     = TRUE
)
gdpins_sync(board, direction = "from_drive")
} # }
```
