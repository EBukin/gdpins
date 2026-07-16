# Lazy board connection

A board created with `gdpins_init_board(lazy = TRUE)` (the default) does
no network work at init. It records the arguments it was given and
connects on first use: the online probe, the Drive existence/create
check, folder-ID resolution, `pins` board construction, and the
`on_discrepancy` sync check all run the first time something reads one
of the board's components (`drive_board`, `cache_board`, `local_board`).

The point is scripts that set up several boards but only touch some of
them. Initialising three Drive boards costs three round-trips plus three
sync checks; if the script only ever reads one, lazy init pays for one.

## What forces a connection

Any verb that touches board contents —
[`gdpins_pin_read()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_read.md),
[`gdpins_pin_write()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_write.md),
[`gdpins_pin_path()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_path.md),
[`gdpins_pin_remove()`](https://ebukin.github.io/gdpins/reference/gdpins_pin_remove.md),
[`gdpins_list_pins()`](https://ebukin.github.io/gdpins/reference/gdpins_list_pins.md),
[`gdpins_board_status()`](https://ebukin.github.io/gdpins/reference/gdpins_board_status.md),
[`gdpins_sync()`](https://ebukin.github.io/gdpins/reference/gdpins_sync.md),
[`gdpins_go_offline()`](https://ebukin.github.io/gdpins/reference/offline-mode.md),
the prune verbs — plus
[`gdpins_board_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_board_connect.md),
which exists to force it deliberately.

[`print()`](https://rdrr.io/r/base/print.html),
[`format()`](https://rdrr.io/r/base/format.html), and
[`summary()`](https://rdrr.io/r/base/summary.html) do **not** force:
they describe the board from its declared config. Nor do the plain
metadata fields (`name`, `config`, `versioned`, `drive_path`,
`cache_dir`, `local_dir`, `adapter`).

## Consequences

Errors move. A mistyped `drive_path`, a missing folder with
`create = FALSE`, or the `create = NA` interactive prompt used to fire
at
[`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md);
they now fire at first use. Call
[`gdpins_board_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_board_connect.md)
right after init to get the old timing back, or pass `lazy = FALSE`.

Connection state is shared, not copied. `b2 <- board` gives two handles
onto one connection: forcing either resolves both. This is deliberate —
it stops a board passed to a function from reconnecting inside it.

If
[`.build_board()`](https://ebukin.github.io/gdpins/reference/dot-build_board.md)
fails, the board stays unresolved and the next access retries. A
transient network failure does not permanently poison the board.

## Disabling

Set `options(gdpins.lazy_boards = FALSE)` to make every
[`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md)
call eager, or pass `lazy = FALSE` per board. An explicit `lazy`
argument always beats the option.

## See also

[`gdpins_init_board()`](https://ebukin.github.io/gdpins/reference/gdpins_init_board.md),
[`gdpins_board_connect()`](https://ebukin.github.io/gdpins/reference/gdpins_board_connect.md),
[`gdpins_board_is_connected()`](https://ebukin.github.io/gdpins/reference/gdpins_board_is_connected.md).
