# Construct a `gdpins_board` object (internal)

Field layout is FROZEN — executors call this constructor and rely on
exact field names in exactly this order.

## Usage

``` r
new_gdpins_board(
  config,
  name,
  drive_board = NULL,
  local_board = NULL,
  cache_dir = NULL,
  drive_path = NULL,
  adapter = NULL,
  versioned = TRUE
)
```

## Arguments

- config:

  Character scalar. One of `"local_only"`, `"drive_cache"`,
  `"drive_only"`.

- name:

  Character scalar. Board/layer label (e.g. `"data_raw"`).

- drive_board:

  A `pins` board, or `NULL`.

- local_board:

  A `pins` `board_folder` over `cache_dir` — the one local copy — or
  `NULL` for `"drive_only"`.

- cache_dir:

  Character scalar path of the local copy, or `NULL` for `"drive_only"`.

- drive_path:

  Character scalar Drive path relative to the adapter root, or `NULL`.

- adapter:

  A `gdpins_drive_adapter`, or `NULL` for `"local_only"`.

- versioned:

  Logical scalar. Whether the board is versioned.

## Value

An object of S3 class `"gdpins_board"`.

## Details

Config → components:

- `"local_only"`: `local_board` only; `drive_board`/`adapter` are
  `NULL`.

- `"drive_cache"`: `drive_board` + `local_board` (+ `adapter`); the one
  local copy lives at `cache_dir`, which is also the
  [`pins::board_gdrive()`](https://pins.rstudio.com/reference/board_gdrive.html)
  `cache=` path.

- `"drive_only"`: `drive_board` only; `local_board`/`cache_dir` are
  `NULL`.
