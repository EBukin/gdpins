# Construct a `gdpins_board` object (internal)

Field layout is FROZEN — executors call this constructor and rely on
exact field names in exactly this order.

## Usage

``` r
new_gdpins_board(
  config,
  name,
  drive_board = NULL,
  cache_board = NULL,
  local_board = NULL,
  cache_dir = NULL,
  local_dir = NULL,
  drive_path = NULL,
  adapter = NULL,
  versioned = TRUE
)
```

## Arguments

- config:

  Character scalar. One of `"local_only"`, `"drive_cache"`,
  `"drive_cache_local"`.

- name:

  Character scalar. Board/layer label (e.g. `"data_raw"`).

- drive_board:

  A `pins` board, or `NULL`.

- cache_board:

  A `pins` `board_folder` over the cache dir, or `NULL`.

- local_board:

  A `pins` `board_folder` for local-only / super config, or `NULL`.

- cache_dir:

  Character scalar path to the cache directory, or `NULL`.

- local_dir:

  Character scalar path to the standalone local board dir, or `NULL`.

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

- `"local_only"`: `local_board` only;
  `drive_board`/`cache_board`/`adapter` are `NULL`.

- `"drive_cache"`: `drive_board` + `cache_board` (+ `adapter`);
  `local_board` is `NULL`.

- `"drive_cache_local"` (super): `drive_board` + `cache_board` +
  `local_board` (+ `adapter`).
