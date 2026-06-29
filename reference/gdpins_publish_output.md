# Publish local output to Google Drive

Copies local output (tables board and/or figures directory) to their
corresponding Drive destinations. This is a deliberate, user-triggered
action — local output is never auto-published.

## Usage

``` r
gdpins_publish_output(
  tables_board = NULL,
  figures_dir = NULL,
  drive_tables = "output-tables",
  drive_figures = "output-figures",
  adapter = NULL,
  dry_run = FALSE
)
```

## Arguments

- tables_board:

  A `gdpins_board` or `NULL`. Source board for output tables. The
  read-authoritative local pins board inside `tables_board` is mirrored
  to Drive (local-first: local \> cache \> drive board).

- figures_dir:

  Character scalar or `NULL`. Local directory containing PNG/SVG figures
  to publish.

- drive_tables:

  Character scalar. Drive destination folder name for tables. Default
  `"output-tables"`.

- drive_figures:

  Character scalar. Drive destination folder name for figures. Default
  `"output-figures"`.

- adapter:

  A `gdpins_drive_adapter` or `NULL`. If `NULL`, uses the adapter from
  `tables_board`.

- dry_run:

  Logical. If `TRUE`, show what would be published without uploading.
  Default `FALSE`.

## Value

Invisibly `NULL`. Called for its side effect.

## Details

`dry_run = TRUE` prints what would be published without uploading
anything. Blocked when offline.

## See also

[`gdpins_real_drive()`](https://ebukin.github.io/gdpins/reference/gdpins_real_drive.md)
to create an adapter.

## Examples

``` r
if (FALSE) { # \dontrun{
adapter <- gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")

# Publish via adapter directly
gdpins_publish_output(
  figures_dir   = "output/figures",
  adapter       = adapter,
  drive_figures = "my-project/output-figures"
)

# Or pass a board that already holds the adapter
board <- gdpins_init_board(
  name       = "output",
  drive_path = "my-project/output-tables",
  cache_dir  = tempfile("cache_"),
  adapter    = adapter,
  create     = TRUE
)
gdpins_publish_output(tables_board = board, figures_dir = "output/figures")
} # }
```
