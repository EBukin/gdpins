#' Internal S3 constructors — FROZEN field layout
#'
#' These are the **only** place field names are fixed. WS3/WS4 call these
#' constructors but never redefine the field list. Changing field names or
#' order requires orchestrator sign-off.
#'
#' @name classes
#' @keywords internal
NULL

# ── Legal configuration sets ─────────────────────────────────────────────────

.BOARD_CONFIGS <- c("local_only", "drive_cache", "drive_cache_local")
.RAW_CONN_CONFIGS <- c("drive_local", "local_only")

# ── gdpins_board ─────────────────────────────────────────────────────────────

#' Construct a `gdpins_board` object (internal)
#'
#' Field layout is FROZEN — executors call this constructor and rely on exact
#' field names in exactly this order.
#'
#' Config → components:
#' - `"local_only"`: `local_board` only; `drive_board`/`cache_board`/`adapter`
#'   are `NULL`.
#' - `"drive_cache"`: `drive_board` + `cache_board` (+ `adapter`);
#'   `local_board` is `NULL`.
#' - `"drive_cache_local"` (super): `drive_board` + `cache_board` +
#'   `local_board` (+ `adapter`).
#'
#' @param config Character scalar. One of `"local_only"`, `"drive_cache"`,
#'   `"drive_cache_local"`.
#' @param name Character scalar. Board/layer label (e.g. `"data_raw"`).
#' @param drive_board A `pins` board, or `NULL`.
#' @param cache_board A `pins` `board_folder` over the cache dir, or `NULL`.
#' @param local_board A `pins` `board_folder` for local-only / super config,
#'   or `NULL`.
#' @param cache_dir Character scalar path to the cache directory, or `NULL`.
#' @param local_dir Character scalar path to the standalone local board dir,
#'   or `NULL`.
#' @param drive_path Character scalar Drive path relative to the adapter root,
#'   or `NULL`.
#' @param adapter A `gdpins_drive_adapter`, or `NULL` for `"local_only"`.
#' @param versioned Logical scalar. Whether the board is versioned.
#'
#' @return An object of S3 class `"gdpins_board"`.
#' @keywords internal
new_gdpins_board <- function(
    config,
    name,
    drive_board  = NULL,
    cache_board  = NULL,
    local_board  = NULL,
    cache_dir    = NULL,
    local_dir    = NULL,
    drive_path   = NULL,
    adapter      = NULL,
    versioned    = TRUE
) {
  if (!config %in% .BOARD_CONFIGS) {
    cli::cli_abort(c(
      "{.arg config} must be one of {.val {.BOARD_CONFIGS}}.",
      x = "Got {.val {config}}."
    ))
  }
  if (!is.character(name) || length(name) != 1L || !nzchar(name)) {
    cli::cli_abort("{.arg name} must be a non-empty character scalar.")
  }
  if (!is.logical(versioned) || length(versioned) != 1L) {
    cli::cli_abort("{.arg versioned} must be a logical scalar.")
  }

  structure(
    list(
      config      = config,
      name        = name,
      drive_board = drive_board,
      cache_board = cache_board,
      local_board = local_board,
      cache_dir   = cache_dir,
      local_dir   = local_dir,
      drive_path  = drive_path,
      adapter     = adapter,
      versioned   = versioned
    ),
    class = "gdpins_board"
  )
}

# ── gdpins_raw_conn ───────────────────────────────────────────────────────────

#' Construct a `gdpins_raw_conn` object (internal)
#'
#' Field layout is FROZEN. WS4 calls this constructor and relies on exact
#' field names in exactly this order.
#'
#' Raw paths in verbs are **relative to `drive_path`/`local_path`** (e.g.
#' `"worldbank-api/x.parquet"`).
#'
#' @param config Character scalar. One of `"drive_local"`, `"local_only"`.
#' @param drive_path Character scalar Drive raw-root (relative to the adapter
#'   root), or `NULL` for `"local_only"`.
#' @param local_path Character scalar local mirror directory.
#' @param adapter A `gdpins_drive_adapter`, or `NULL` for `"local_only"`.
#'
#' @return An object of S3 class `"gdpins_raw_conn"`.
#' @keywords internal
new_gdpins_raw_conn <- function(
    config,
    drive_path = NULL,
    local_path,
    adapter    = NULL
) {
  if (!config %in% .RAW_CONN_CONFIGS) {
    cli::cli_abort(c(
      "{.arg config} must be one of {.val {.RAW_CONN_CONFIGS}}.",
      x = "Got {.val {config}}."
    ))
  }
  if (!is.character(local_path) || length(local_path) != 1L || !nzchar(local_path)) {
    cli::cli_abort("{.arg local_path} must be a non-empty character scalar.")
  }

  structure(
    list(
      config     = config,
      drive_path = drive_path,
      local_path = local_path,
      adapter    = adapter
    ),
    class = "gdpins_raw_conn"
  )
}
