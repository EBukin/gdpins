# Handle init-time sync check

Calls
[`gdpins_board_status()`](https://ebukin.github.io/gdpins/reference/gdpins_board_status.md)
on the board and acts per `on_discrepancy`. Errors from
`gdpins_board_status` (e.g. WS5 stub) are caught and treated as
offline/unavailable — a warning is emitted and the board is returned
as-is.

## Usage

``` r
.handle_init_sync(board, on_discrepancy)
```
