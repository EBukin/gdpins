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

  Character scalar, `TRUE`, `FALSE`, or `NULL` (default). Path of the
  board's one local copy. `NULL`/`TRUE` use the default path under
  `getOption("gdpins.cache_dir")`; `FALSE` means no local copy
  (`"drive_only"`); a path uses that directory. For boards without
  `drive_path` (`"local_only"`), `cache_dir` must be a non-empty
  character path — the local board's directory; `NULL`/`TRUE`/`FALSE`
  error ("Supply `drive_path`, or `cache_dir` as a path for a local-only
  board.").

- local_dir:

  Character scalar. Deprecated as of 0.0.1.9025; superseded by
  `cache_dir`. If supplied while `cache_dir` is `NULL`, it is used as
  `cache_dir`; otherwise it is ignored (with a deprecation warning).

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
