# Report sync status of a board or raw connection

Returns a per-pin/per-file tibble describing drift between Drive and
local. Dispatches on the class of `x`:

## Usage

``` r
gdpins_board_status(x)
```

## Arguments

- x:

  A `gdpins_board` or `gdpins_raw_conn` object.

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
with at least columns:

- `name` – pin/file name (character).

- `state` – one of `"in_sync"`, `"local_ahead"`, `"drive_ahead"`,
  `"conflict"`, `"offline"` (character).

- Additional signal columns differ by object type (see Details).

## Details

- **`gdpins_board`**: compares pins version id/timestamp between the
  Drive board and the local side (cache board if present, else local
  board).

- **`gdpins_raw_conn`**: compares MD5 checksums between the Drive folder
  and the local mirror directory; mtime is used as a tiebreaker.

If `!gdpins_is_online()`, all rows are set to `state = "offline"` and a
warning is emitted. No Drive calls are made offline.

**Board signal columns**: `drive_version`, `local_version`,
`drive_created`, `local_created`, `drive_hash`, `local_hash`.

**Raw connection signal columns**: `drive_md5`, `local_md5`,
`drive_mtime`, `local_mtime`.

## See also

[`gdpins_real_drive()`](https://ebukin.github.io/gdpins/reference/gdpins_real_drive.md)
to create an adapter,
[`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md)
and
[`gdpins_raw_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_connect.md)
to create boards/connections,
[`gdpins_go_offline()`](https://ebukin.github.io/gdpins/reference/offline-mode.md)/[`gdpins_go_online()`](https://ebukin.github.io/gdpins/reference/offline-mode.md)
to temporarily detach a board or connection from Drive and reconcile it
later.

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
gdpins_board_status(board)
#> # A tibble: 0 × 8
#> # ℹ 8 variables: name <chr>, state <chr>, drive_version <chr>,
#> #   local_version <chr>, drive_created <list>, local_created <list>,
#> #   drive_hash <chr>, local_hash <chr>

# --- Real adapter ---
if (FALSE) { # \dontrun{
adapter <- gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")
board   <- gdpins_init_board(
  name       = "data_raw",
  drive_path = "my-project/data-raw",
  cache_dir  = "~/.cache/gdpins/data-raw",
  adapter    = adapter,
  create     = TRUE
)
gdpins_board_status(board)
} # }
```
