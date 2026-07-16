#' Lazy board connection
#'
#' @description
#' A board created with `gdpins_init_board(lazy = TRUE)` (the default) does no
#' network work at init. It records the arguments it was given and connects on
#' first use: the online probe, the Drive existence/create check, folder-ID
#' resolution, `pins` board construction, and the `on_discrepancy` sync check
#' all run the first time something reads one of the board's components
#' (`drive_board`, `cache_board`, `local_board`).
#'
#' The point is scripts that set up several boards but only touch some of them.
#' Initialising three Drive boards costs three round-trips plus three sync
#' checks; if the script only ever reads one, lazy init pays for one.
#'
#' @section What forces a connection:
#' Any verb that touches board contents — [gdpins_pin_read()],
#' [gdpins_pin_write()], [gdpins_pin_path()], [gdpins_pin_remove()],
#' [gdpins_list_pins()], [gdpins_board_status()], [gdpins_sync()],
#' [gdpins_go_offline()], the prune verbs — plus
#' [gdpins_board_connect()], which exists to force it deliberately.
#'
#' [print()], [format()], and [summary()] do **not** force: they describe the
#' board from its declared config. Nor do the plain metadata fields (`name`,
#' `config`, `versioned`, `drive_path`, `cache_dir`, `local_dir`, `adapter`).
#'
#' @section Consequences:
#' Errors move. A mistyped `drive_path`, a missing folder with `create =
#' FALSE`, or the `create = NA` interactive prompt used to fire at
#' `gdpins_init_board()`; they now fire at first use. Call
#' [gdpins_board_connect()] right after init to get the old timing back, or
#' pass `lazy = FALSE`.
#'
#' Connection state is shared, not copied. `b2 <- board` gives two handles onto
#' one connection: forcing either resolves both. This is deliberate — it stops
#' a board passed to a function from reconnecting inside it.
#'
#' If `.build_board()` fails, the board stays unresolved and the next access
#' retries. A transient network failure does not permanently poison the board.
#'
#' @section Disabling:
#' Set `options(gdpins.lazy_boards = FALSE)` to make every
#' `gdpins_init_board()` call eager, or pass `lazy = FALSE` per board. An
#' explicit `lazy` argument always beats the option.
#'
#' @name lazy-boards
#' @seealso [gdpins_init_board()], [gdpins_board_connect()],
#'   [gdpins_board_is_connected()].
NULL

# Fields that force a connection when read. Everything else in the frozen
# layout is known from the arguments alone.
.LAZY_FIELDS <- c("drive_board", "cache_board", "local_board")

# Attribute holding the state environment. Absent on eager boards, which keeps
# `$`/`[[` on them a plain .subset2() call.
.GDPINS_LAZY_ATTR <- "gdpins_lazy"

#' Construct an unresolved `gdpins_board` (internal)
#'
#' Mirrors [new_gdpins_board()]'s frozen field layout so `$` sees the same
#' names either way. Components are `NULL` in the underlying list and are only
#' ever served through `$`/`[[`, which force first.
#'
#' @param spec A list from [.board_spec()].
#' @return An unresolved `gdpins_board`.
#' @keywords internal
new_gdpins_board_lazy <- function(spec) {
  state <- new.env(parent = emptyenv())
  state$spec     <- spec
  state$resolved <- FALSE
  state$forcing  <- FALSE
  state$fields   <- NULL

  # Declared fields — what we can answer without connecting. Components stay
  # NULL here; `$` never reads them from this list while unresolved.
  board <- new_gdpins_board(
    config     = spec$config,
    name       = spec$name,
    cache_dir  = spec$cache_dir,
    local_dir  = spec$local_dir,
    drive_path = spec$drive_path,
    adapter    = spec$adapter,
    versioned  = spec$versioned
  )
  attr(board, .GDPINS_LAZY_ATTR) <- state
  board
}

#' Get the lazy state environment, or NULL for an eager board
#' @keywords internal
.board_lazy_state <- function(x) attr(x, .GDPINS_LAZY_ATTR, exact = TRUE)

#' Connect an unresolved board and cache the result
#'
#' Marks the board resolved **before** running the sync check, so
#' `.handle_init_sync()` — which reads `x$drive_board` via
#' [gdpins_board_status()] — reads the cache instead of recursing.
#'
#' @param state A lazy state environment.
#' @return Invisibly `NULL`. Called for its effect on `state`.
#' @keywords internal
.board_force <- function(state) {
  if (isTRUE(state$forcing)) {
    cli::cli_abort(
      "Recursive board resolution.",
      .internal = TRUE
    )
  }
  state$forcing <- TRUE
  on.exit(state$forcing <- FALSE, add = TRUE)

  # On failure `resolved` stays FALSE and the next access retries.
  board <- .build_board(state$spec)

  state$fields   <- unclass(board)
  state$resolved <- TRUE

  .handle_init_sync(board, state$spec$on_discrepancy)
  invisible(NULL)
}

#' Read one field, forcing the connection only when the field demands it
#' @keywords internal
.board_field <- function(x, name) {
  state <- .board_lazy_state(x)
  if (is.null(state)) {
    return(.subset2(x, name))
  }
  if (state$resolved) {
    # .build_board() may have downgraded config/local_dir/adapter on an offline
    # fallback, so every field comes from the resolved set, not just components.
    return(state$fields[[name]])
  }
  if (!name %in% .LAZY_FIELDS) {
    return(.subset2(x, name))
  }
  .board_force(state)
  state$fields[[name]]
}

#' Extract a field from a gdpins_board
#'
#' Connects a lazy board on first read of `drive_board`, `cache_board`, or
#' `local_board`; every other field is answered without connecting. See
#' [lazy-boards].
#'
#' Unlike `$` on a plain list, these do **not** partial-match: `board$drive`
#' is `NULL`, not `board$drive_board`.
#'
#' @param x A `gdpins_board` object.
#' @param name,i Character scalar. Field name.
#' @param ... Unused.
#'
#' @return The field value, or `NULL` if there is no such field.
#' @name board-extract
#' @export
`$.gdpins_board` <- function(x, name) {
  .board_field(x, name)
}

#' @rdname board-extract
#' @export
`[[.gdpins_board` <- function(x, i, ...) {
  if (!is.character(i) || length(i) != 1L) {
    cli::cli_abort(c(
      "A {.cls gdpins_board} can only be indexed by a single field name.",
      i = "Got {.cls {class(i)[[1L]]}} of length {length(i)}."
    ))
  }
  .board_field(x, i)
}

# ── Exported connection verbs ────────────────────────────────────────────────

#' Connect a lazy board now
#'
#' Forces a board created with `lazy = TRUE` (the default) to do its deferred
#' init: resolve the Drive folder, build the `pins` boards, and run the
#' `on_discrepancy` sync check. This is exactly the work
#' [gdpins_init_board()] used to do at init.
#'
#' Use it to control *when* you pay: call it right after init to restore
#' eager-style timing and surface a bad `drive_path` immediately, or call it at
#' a natural pause before a long stretch of reads.
#'
#' Already-connected boards and eager boards are a no-op, so it is safe to call
#' repeatedly. To only run the sync check on a board that may already be
#' connected, use [gdpins_board_status()] — it connects too, and returns the
#' per-pin comparison rather than applying a policy.
#'
#' @param board A `gdpins_board` object.
#' @param on_discrepancy Character scalar or `NULL`. Overrides the value given
#'   at [gdpins_init_board()] for this connection only. See
#'   [gdpins_init_board()] for the legal values.
#'
#' @return Invisibly `board`, now connected.
#' @seealso [lazy-boards] for what else forces a connection,
#'   [gdpins_board_is_connected()], [gdpins_board_status()], [gdpins_sync()].
#' @examples
#' adapter <- gdpins_fake_drive()
#' board <- gdpins_init_board(
#'   name       = "data_raw",
#'   drive_path = "my-project/data-raw",
#'   cache_dir  = tempfile("cache_"),
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#' gdpins_board_is_connected(board)
#'
#' gdpins_board_connect(board, on_discrepancy = "ignore")
#' gdpins_board_is_connected(board)
#' @export
gdpins_board_connect <- function(board, on_discrepancy = NULL) {
  if (!inherits(board, "gdpins_board")) {
    cli::cli_abort(c(
      "{.arg board} must be a {.cls gdpins_board}.",
      x = "Got {.cls {class(board)[[1L]]}}."
    ))
  }

  state <- .board_lazy_state(board)
  if (is.null(state) || isTRUE(state$resolved)) {
    return(invisible(board))
  }

  if (!is.null(on_discrepancy)) {
    state$spec$on_discrepancy <- .resolve_on_discrepancy(on_discrepancy)
  }
  .board_force(state)
  invisible(board)
}

#' Has a board connected yet?
#'
#' Reports whether `board` has done its deferred init. Eager boards
#' (`lazy = FALSE`) are connected by construction and always return `TRUE`.
#' Never forces a connection itself.
#'
#' @param board A `gdpins_board` object.
#'
#' @return `TRUE` if the board has connected, `FALSE` if it is still lazy.
#' @seealso [gdpins_board_connect()], [lazy-boards].
#' @examples
#' adapter <- gdpins_fake_drive()
#' board <- gdpins_init_board(
#'   name       = "data_raw",
#'   drive_path = "my-project/data-raw",
#'   cache_dir  = tempfile("cache_"),
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#' gdpins_board_is_connected(board)   # FALSE — nothing has touched it
#'
#' gdpins_pin_write(board, mtcars, "cars")
#' gdpins_board_is_connected(board)   # TRUE — the write connected it
#' @export
gdpins_board_is_connected <- function(board) {
  if (!inherits(board, "gdpins_board")) {
    cli::cli_abort(c(
      "{.arg board} must be a {.cls gdpins_board}.",
      x = "Got {.cls {class(board)[[1L]]}}."
    ))
  }
  state <- .board_lazy_state(board)
  is.null(state) || isTRUE(state$resolved)
}
