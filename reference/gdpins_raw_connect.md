# Connect to a raw-exogenous Drive folder

Creates a `gdpins_raw_conn` object pointing at a Drive raw-root and its
local mirror. On connect, checks for sync discrepancies and whether the
Drive folder exists (controlled by `create` and `on_discrepancy`).

## Usage

``` r
gdpins_raw_connect(
  drive_path,
  local_path,
  create = NA,
  on_discrepancy = NULL,
  adapter = NULL
)
```

## Arguments

- drive_path:

  Character scalar. Drive raw-root path (relative to the adapter root),
  or `NULL` for `"local_only"`.

- local_path:

  Character scalar. Local mirror directory path.

- create:

  Logical or `NA`. Controls Drive folder creation: `TRUE` = create if
  absent; `FALSE` = error if absent; `NA` = interactive prompt.

- on_discrepancy:

  Character scalar or `NULL`. One of
  `c("prompt","warn","sync_from_drive","sync_to_drive","ignore")`.
  `NULL` resolves at runtime.

- adapter:

  A `gdpins_drive_adapter`, or `NULL` for `"local_only"`.

## Value

A `gdpins_raw_conn` object.

## See also

[`gdpins_real_drive()`](https://ebukin.github.io/gdpins/reference/gdpins_real_drive.md)
and
[`gdpins_ensure_drive_auth()`](https://ebukin.github.io/gdpins/reference/gdpins_ensure_drive_auth.md)
for auth and adapter setup,
[`gdpins_raw_remove()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_remove.md),
[`gdpins_go_offline()`](https://ebukin.github.io/gdpins/reference/offline-mode.md)
to temporarily detach an existing connection from Drive and work
locally.

## Examples

``` r
# --- Fake adapter (no network) ---
adapter <- gdpins_fake_drive()
conn <- gdpins_raw_connect(
  drive_path = "worldbank-api",
  local_path = tempfile("raw_"),
  adapter    = adapter,
  create     = TRUE
)
conn
#> <gdpins_raw_conn> [drive+local]
#>   local: /tmp/Rtmp7u8b8x/raw_24f914e6af43
#>   drive: worldbank-api

# --- Real adapter ---
if (FALSE) { # \dontrun{
adapter <- gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")
conn <- gdpins_raw_connect(
  drive_path = "worldbank-api",
  local_path = "data/raw/worldbank-api",
  adapter    = adapter,
  create     = TRUE
)

# Supply a Drive folder ID directly as drive_path
conn2 <- gdpins_raw_connect(
  drive_path = "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms",
  local_path = "data/raw/worldbank-api",
  adapter    = adapter
)
} # }
```
