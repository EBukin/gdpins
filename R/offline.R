#' Temporarily disconnect from Drive, then reconnect and sync later
#'
#' A Drive-backed `gdpins_board` or `gdpins_raw_conn` normally needs Drive to
#' be reachable: `gdpins_pin_write()` blocks offline writes, and
#' `gdpins_sync()`/`gdpins_go_online()` hard-abort without connectivity.
#' `gdpins_go_offline()` and `gdpins_go_online()` give users an explicit,
#' reversible way to work around Drive instability (or work disconnected on
#' purpose) without losing the ability to reconnect and sync afterwards.
#'
#' `gdpins_go_offline(x)` strips the Drive-facing components off `x` and
#' returns a `"local_only"` object backed by whichever local storage `x`
#' already had on disk:
#' - `"drive_cache_local"` boards keep using their standalone `local_board`
#'   / `local_dir` — the same directory the user was already working in.
#' - `"drive_cache"` boards (no standalone local dir) fall back to their
#'   `cache_board` / `cache_dir`, mirroring the automatic offline fallback in
#'   [gdpins_init_board()].
#' - `"drive_local"` raw connections keep using their existing `local_path`.
#'
#' No files are copied, moved, or deleted — the returned object reuses the
#' exact same local `pins` board / directory, so anything already on disk
#' stays reachable, and anything written afterwards lands in the same place.
#' The original Drive configuration (adapter, drive_path, drive/cache boards)
#' is stashed on the returned object as an attribute so
#' `gdpins_go_online()` can restore it later. Calling `gdpins_go_offline()` on
#' an object that is already `"local_only"` is a no-op.
#'
#' `gdpins_go_online(x)` reverses this: it requires `x` to have been produced
#' by `gdpins_go_offline()` (i.e. carry the stashed state), checks
#' [gdpins_is_online()], reattaches the stashed Drive adapter and path (or a
#' freshly supplied `adapter`), and runs the same discrepancy check used by
#' [gdpins_init_board()] / [gdpins_raw_connect()] — governed by
#' `on_discrepancy` — so that anything written while offline is reconciled
#' with Drive.
#'
#' @param x A `gdpins_board` or `gdpins_raw_conn` object.
#' @param ... Passed to methods (currently unused).
#'
#' @return An object of the same class as `x`.
#' @seealso [gdpins_init_board()], [gdpins_raw_connect()], [gdpins_sync()],
#'   [gdpins_board_status()], [gdpins_is_online()].
#' @examples
#' adapter <- gdpins_fake_drive()
#' board <- gdpins_init_board(
#'   name       = "data_raw",
#'   drive_path = "my-project/data-raw",
#'   cache_dir  = tempfile("cache_"),
#'   local_dir  = tempfile("local_"),
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#'
#' # Work disconnected for a while -- writes/reads stay local
#' board_offline <- gdpins_go_offline(board)
#' board_offline$config   # "local_only"
#' gdpins_pin_write(board_offline, mtcars, "cars")
#'
#' # Reconnect and push local changes back up to Drive
#' board_online <- gdpins_go_online(board_offline, on_discrepancy = "sync_to_drive")
#' board_online$config    # "drive_cache_local"
#' @name offline-mode
NULL

.GDPINS_OFFLINE_STATE_ATTR <- "gdpins_offline_state"

# ── gdpins_go_offline ─────────────────────────────────────────────────────────

#' @rdname offline-mode
#' @export
gdpins_go_offline <- function(x, ...) {
  UseMethod("gdpins_go_offline")
}

#' @export
gdpins_go_offline.default <- function(x, ...) {
  cli::cli_abort(c(
    "{.fn gdpins_go_offline} requires a {.cls gdpins_board} or {.cls gdpins_raw_conn}.",
    x = "Got {.cls {class(x)[[1L]]}}."
  ))
}

#' @export
gdpins_go_offline.gdpins_board <- function(x, ...) {
  if (identical(x$config, "local_only")) {
    cli::cli_inform("Board {.val {x$name}} is already local-only.")
    return(x)
  }

  offline_state <- list(
    config      = x$config,
    drive_board = x$drive_board,
    cache_board = x$cache_board,
    cache_dir   = x$cache_dir,
    local_dir   = x$local_dir,
    drive_path  = x$drive_path,
    adapter     = x$adapter
  )

  if (identical(x$config, "drive_cache_local")) {
    local_board <- x$local_board
    local_dir   <- x$local_dir
  } else {
    # "drive_cache": no standalone local dir -- the cache *is* the local copy
    local_board <- x$cache_board
    local_dir   <- x$cache_dir
  }

  board <- new_gdpins_board(
    config      = "local_only",
    name        = x$name,
    local_board = local_board,
    local_dir   = local_dir,
    versioned   = x$versioned
  )
  attr(board, .GDPINS_OFFLINE_STATE_ATTR) <- offline_state

  cli::cli_inform(c(
    "i" = "Board {.val {x$name}} switched to local-only (offline) mode.",
    "i" = "Drive is untouched; call {.fn gdpins_go_online} to reconnect and sync."
  ))

  board
}

#' @export
gdpins_go_offline.gdpins_raw_conn <- function(x, ...) {
  if (identical(x$config, "local_only")) {
    cli::cli_inform("Raw connection is already local-only.")
    return(x)
  }

  offline_state <- list(
    config     = x$config,
    drive_path = x$drive_path,
    adapter    = x$adapter
  )

  conn <- new_gdpins_raw_conn(
    config     = "local_only",
    local_path = x$local_path
  )
  attr(conn, .GDPINS_OFFLINE_STATE_ATTR) <- offline_state

  cli::cli_inform(c(
    "i" = "Raw connection switched to local-only (offline) mode.",
    "i" = "Drive is untouched; call {.fn gdpins_go_online} to reconnect and sync."
  ))

  conn
}

# ── gdpins_go_online ──────────────────────────────────────────────────────────

#' @rdname offline-mode
#' @param adapter A `gdpins_drive_adapter` to reconnect with, or `NULL`
#'   (default) to reuse the adapter stashed by `gdpins_go_offline()` — pass a
#'   freshly authenticated [gdpins_real_drive()] here if the stashed
#'   adapter's credentials have expired.
#' @param on_discrepancy Character scalar or `NULL`. Same semantics as
#'   [gdpins_init_board()]/[gdpins_raw_connect()]: one of
#'   `c("prompt","warn","sync_from_drive","sync_to_drive","ignore")`. `NULL`
#'   resolves to `"prompt"` interactively or `"warn"` non-interactively.
#' @export
gdpins_go_online <- function(x, adapter = NULL, on_discrepancy = NULL, ...) {
  UseMethod("gdpins_go_online")
}

#' @export
gdpins_go_online.default <- function(x, adapter = NULL, on_discrepancy = NULL, ...) {
  cli::cli_abort(c(
    "{.fn gdpins_go_online} requires a {.cls gdpins_board} or {.cls gdpins_raw_conn}.",
    x = "Got {.cls {class(x)[[1L]]}}."
  ))
}

#' @keywords internal
.require_offline_state <- function(x) {
  state <- attr(x, .GDPINS_OFFLINE_STATE_ATTR, exact = TRUE)
  if (is.null(state)) {
    cli::cli_abort(c(
      "{.arg x} has no stored Drive configuration to reconnect to.",
      i = "{.fn gdpins_go_online} only works on objects produced by {.fn gdpins_go_offline}.",
      i = "Build a fresh Drive-backed object with {.fn gdpins_init_board} or {.fn gdpins_raw_connect} instead."
    ))
  }
  state
}

#' @keywords internal
.check_online_or_abort <- function() {
  is_online <- tryCatch(gdpins_is_online(), error = function(e) FALSE)
  if (!is_online) {
    cli::cli_abort(c(
      "Cannot go online: no internet connection detected.",
      i = "Try again once connectivity is restored."
    ))
  }
  invisible(TRUE)
}

#' @export
gdpins_go_online.gdpins_board <- function(x, adapter = NULL, on_discrepancy = NULL, ...) {
  state <- .require_offline_state(x)
  .check_online_or_abort()

  on_discrepancy <- .resolve_on_discrepancy(on_discrepancy)
  drive_adapter  <- if (!is.null(adapter)) adapter else state$adapter

  is_super <- identical(state$config, "drive_cache_local")
  local_board <- if (is_super) x$local_board else NULL
  local_dir   <- if (is_super) state$local_dir else NULL

  # Offline writes for "drive_cache_local" landed on local_board only (the
  # cache_board was frozen while offline). The status/sync engine always
  # compares cache_board (not local_board) when both are present, so catch
  # the cache up first or offline-only writes would look "in sync" and never
  # reach Drive.
  if (is_super && !is.null(state$cache_board)) {
    local_pins <- tryCatch(pins::pin_list(x$local_board), error = function(e) character())
    for (pin_name in local_pins) {
      .copy_pin_to_board(x$local_board, state$cache_board, pin_name)
    }
  }

  board <- new_gdpins_board(
    config      = state$config,
    name        = x$name,
    drive_board = state$drive_board,
    cache_board = state$cache_board,
    local_board = local_board,
    cache_dir   = state$cache_dir,
    local_dir   = local_dir,
    drive_path  = state$drive_path,
    adapter     = drive_adapter,
    versioned   = x$versioned
  )

  .handle_init_sync(board, on_discrepancy, label = x$name)

  cli::cli_inform(c(
    "v" = "Board {.val {x$name}} reconnected to Drive ({.val {state$config}})."
  ))

  board
}

#' @export
gdpins_go_online.gdpins_raw_conn <- function(x, adapter = NULL, on_discrepancy = NULL, ...) {
  state <- .require_offline_state(x)
  .check_online_or_abort()

  on_discrepancy <- .resolve_on_discrepancy(on_discrepancy)
  drive_adapter  <- if (!is.null(adapter)) adapter else state$adapter

  conn <- new_gdpins_raw_conn(
    config     = state$config,
    drive_path = state$drive_path,
    local_path = x$local_path,
    adapter    = drive_adapter
  )

  .handle_init_sync(conn, on_discrepancy, label = "raw connection")

  cli::cli_inform(c(
    "v" = "Raw connection reconnected to Drive ({.val {state$drive_path}})."
  ))

  conn
}
