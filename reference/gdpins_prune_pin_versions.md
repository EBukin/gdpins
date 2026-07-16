# Prune old versions of a single pin

Removes old versions of one pin from Drive **and** cache (or local
board), keeping the `keep` most recent. Drive versions are always
**trashed** (recoverable via
[`gd_trash()`](https://ebukin.github.io/gdpins/reference/gd_trash.md)),
never hard-deleted. Cache versions are deleted from the local
filesystem.

## Usage

``` r
gdpins_prune_pin_versions(
  board,
  name,
  keep = 1,
  dry_run = TRUE,
  threshold = 10,
  force = FALSE
)
```

## Arguments

- board:

  A `gdpins_board` object.

- name:

  Character scalar. Pin name.

- keep:

  Integer scalar. Number of most-recent versions to keep. Default `1`.

- dry_run:

  Logical. If `TRUE` (default), show what would be removed without
  actually removing anything.

- threshold:

  Integer scalar. Maximum number of versions to remove without requiring
  `force = TRUE` or interactive confirmation. Default `10`.

- force:

  Logical. If `TRUE`, skip the interactive threshold confirmation.
  Default `FALSE`.

## Value

Invisibly, a character vector of the version labels that were (or would
be) removed (as reported by the primary / Drive board).

## Details

Defaults to `dry_run = TRUE` for safety: the plan is shown but nothing
is removed.

Deleting more than `threshold` versions in a single call requires either
interactive confirmation or `force = TRUE`. The threshold check is
skipped during a dry run.

**Raw files are never auto-deleted by any function** – removal is manual
outside R.

## See also

[`gdpins_real_drive()`](https://ebukin.github.io/gdpins/reference/gdpins_real_drive.md),
[`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md).

## Examples

``` r
adapter <- gdpins_fake_drive()
board <- gdpins_init_board(
  name       = "data_raw",
  drive_path = "my-project/data-raw",
  cache_dir  = tempfile("cache_"),
  adapter    = adapter,
  create     = TRUE
)
if (FALSE) { # \dontrun{
gdpins_prune_pin_versions(board, name = "my-pin", keep = 3L)
} # }
```
