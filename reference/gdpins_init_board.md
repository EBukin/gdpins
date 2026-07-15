# Initialise a gdpins board

Builds a board in one of three legal configurations depending on the
combination of arguments supplied:

## Usage

``` r
gdpins_init_board(
  name,
  drive_path = NULL,
  cache_dir = NULL,
  local_dir = NULL,
  versioned = TRUE,
  create = NA,
  on_discrepancy = NULL,
  adapter = NULL
)
```

## Arguments

- name:

  Character scalar. Board/layer label (e.g. `"data_raw"`).

- drive_path:

  Character scalar. Drive path for the board (relative to the adapter
  root), or `NULL` for `"local_only"`.

- cache_dir:

  Character scalar. Local cache directory path, or `NULL`.

- local_dir:

  Character scalar. Standalone local board directory path, or `NULL`.

- versioned:

  Logical. Whether the board stores pin versions. Default `TRUE`.

- create:

  Logical or `NA`. `TRUE` = create Drive board if absent; `FALSE` =
  error if absent; `NA` (default) = interactive CLI prompt or error.

- on_discrepancy:

  Character scalar or `NULL`. One of
  `c("prompt","warn","sync_from_drive","sync_to_drive","ignore")`.
  `NULL` resolves to `"prompt"` interactively or `"warn"`
  non-interactively.

- adapter:

  A `gdpins_drive_adapter`, or `NULL` for `"local_only"`.

## Value

A `gdpins_board` object.

## Details

- **`"local_only"`** — `local_dir` provided, no `drive_path`/`adapter`.

- **`"drive_cache"`** — `drive_path` + `adapter` + `cache_dir`, no
  `local_dir`.

- **`"drive_cache_local"`** — all three: `drive_path`, `cache_dir`, and
  `local_dir`.

On init the board checks for sync discrepancies between Drive and local
(governed by `on_discrepancy`). Non-existent Drive boards are never
auto-created unless `create = TRUE`.

## See also

[`gdpins_real_drive()`](https://ebukin.github.io/gdpins/reference/gdpins_real_drive.md)
to create an adapter,
[`gdpins_go_offline()`](https://ebukin.github.io/gdpins/reference/offline-mode.md)
to temporarily detach an existing board from Drive and work locally.

## Examples

``` r
# --- Fake adapter (no network) ---
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
board
#> <gdpins_board> [DC-] v+ cfg=drive_cache name=data_raw path=my-project/data-raw
#> config: "drive_cache"
#> name: "data_raw"
#> versioned: "TRUE"
#> drive: "my-project/data-raw"
#> cache: "/tmp/Rtmp7u8b8x/cache_24f967e50144"

# --- Real adapter (requires Google Drive auth) ---
if (FALSE) { # \dontrun{
adapter <- gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")
board <- gdpins_init_board(
  name       = "data_raw",
  drive_path = "my-project/data-raw",
  cache_dir  = "~/.cache/gdpins/data-raw",
  adapter    = adapter,
  create     = TRUE
)

# Supply a Drive folder ID directly as drive_path
board2 <- gdpins_init_board(
  name       = "data_raw",
  drive_path = "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms",
  cache_dir  = "~/.cache/gdpins/data-raw",
  adapter    = adapter,
  create     = TRUE
)
} # }
```
