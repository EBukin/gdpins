# Handle init-time (or reconnect-time) sync check

Calls
[`gdpins_board_status()`](https://ebukin.github.io/gdpins/reference/gdpins_board_status.md)
on `x` and acts per `on_discrepancy`. Errors from `gdpins_board_status`
(e.g. WS5 stub) are caught and treated as offline/unavailable — a
warning is emitted and `x` is returned as-is.

## Usage

``` r
.handle_init_sync(x, on_discrepancy, label = NULL)
```

## Arguments

- x:

  A `gdpins_board` or `gdpins_raw_conn` object.

- on_discrepancy:

  Resolved on_discrepancy value (never `NULL`).

- label:

  Character scalar used in messages. Defaults to `x$name` (set on
  `gdpins_board`) or `"connection"` when unavailable (e.g. raw
  connections, which have no `name` field).

## Details

Shared by
[`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md)/[`gdpins_raw_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_raw_connect.md)
(init-time) and
[`gdpins_go_online()`](https://ebukin.github.io/gdpins/reference/offline-mode.md)
(reconnect-time) — `x` may be a `gdpins_board` or a `gdpins_raw_conn`,
since
[`gdpins_board_status()`](https://ebukin.github.io/gdpins/reference/gdpins_board_status.md)/[`gdpins_sync()`](https://ebukin.github.io/gdpins/reference/gdpins_sync.md)
dispatch on both.
