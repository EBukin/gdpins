# Validate init arguments and derive the declared board spec

Pure argument inspection — no network, no filesystem. Everything a lazy
board must know before it connects. `config` here is the *declared*
config;
[`.build_board()`](https://ebukin.github.io/gdpins/reference/dot-build_board.md)
may downgrade it to `"local_only"` when Drive turns out to be
unreachable.

## Usage

``` r
.board_spec(
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

A named list: the
[`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md)
arguments plus `config`.
