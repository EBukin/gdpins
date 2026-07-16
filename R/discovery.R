#' Pin discovery and metadata
#'
#' Functions for listing pins and retrieving detailed metadata about a single
#' pin. Output is compact (≤80-col) and programmatic-first (tibbles).
#'
#' @name discovery
NULL

# ── Internal helpers ─────────────────────────────────────────────────────────

# Resolve the local-first read source: local_board > cache_board > drive_board
.read_source <- function(board) {
  if (!is.null(board$local_board)) return(board$local_board)
  if (!is.null(board$cache_board)) return(board$cache_board)
  board$drive_board
}

# Detect sf CRS from geometry__<epsg>__ column names; NA_integer_ if none found.
.detect_sf_crs <- function(src, name) {
  tryCatch({
    dat <- pins::pin_read(src, name)
    if (!is.data.frame(dat)) return(NA_integer_)
    # Look for __<epsg>__ pattern (4–5 digit EPSG)
    geo_cols <- grep("^.*__\\d{4,5}__$", names(dat), value = TRUE)
    if (length(geo_cols) == 0L) return(NA_integer_)
    # Extract EPSG from the first geometry column
    epsg_str <- regmatches(
      geo_cols[[1L]],
      regexpr("\\d{4,5}(?=__$)", geo_cols[[1L]], perl = TRUE)
    )
    as.integer(epsg_str)
  }, error = function(e) NA_integer_)
}

# ── Listing class ─────────────────────────────────────────────────────────────

# Tag a pin listing tibble. The class goes *ahead* of the tibble classes so the
# print method wins while every tibble/dplyr operation still works and
# inherits(x, "tbl_df") stays TRUE. Mirrors gdpins_raw_listing.
.new_pin_listing <- function(x) {
  class(x) <- unique(c("gdpins_pin_listing", class(x)))
  x
}

#' @export
print.gdpins_pin_listing <- function(x, ...) {
  n <- nrow(x)
  if (n == 0L) {
    cli::cli_alert_info("No matching pins.")
    return(invisible(x))
  }
  cli::cli_text("{.strong {n} pin{?s}}")
  # Names only: a listing answers "what is there", not "what is in it".
  cli::cli_ul(gsub("}", "}}", gsub("{", "{{", x$name, fixed = TRUE), fixed = TRUE))
  invisible(x)
}

# ── Exported functions ───────────────────────────────────────────────────────

#' List all pins in a board
#'
#' Returns a programmatic tibble with one row per pin. Compact output fits
#' ≤80 columns. Reads from the board's local-first component
#' (`local_board` > `cache_board` > `drive_board`).
#'
#' @param board A `gdpins_board` object.
#'
#' @return A [tibble::tibble()] with columns `name` (chr), `type` (chr),
#'   `n_versions` (int), `size` (dbl, bytes), `modified` (POSIXct).
#'   Returns a zero-row tibble for an empty board.
#' @export
gdpins_list_pins <- function(board) {
  if (!inherits(board, "gdpins_board")) {
    cli::cli_abort(c(
      "{.arg board} must be a {.cls gdpins_board} object.",
      x = "Got {.cls {class(board)}}."
    ))
  }

  src   <- .read_source(board)
  names <- pins::pin_list(src)

  if (length(names) == 0L) {
    return(.new_pin_listing(tibble::tibble(
      name       = character(0),
      type       = character(0),
      n_versions = integer(0),
      size       = double(0),
      modified   = structure(numeric(0), class = c("POSIXct", "POSIXt"))
    )))
  }

  rows <- purrr::map(names, function(nm) {
    meta       <- pins::pin_meta(src, nm)
    n_versions <- nrow(pins::pin_versions(src, nm))
    # A pin may hold several files (pins::pin_upload()), making meta$file_size a
    # vector. Left as-is it recycles `name` and yields one row *per file*, so a
    # two-file pin was listed twice. One pin is one row; size is the total.
    size <- if (is.null(meta$file_size)) {
      NA_real_
    } else {
      as.double(sum(meta$file_size))
    }
    tibble::tibble(
      name       = nm,
      type       = if (is.null(meta$type)) NA_character_ else meta$type[[1L]],
      n_versions = as.integer(n_versions),
      size       = size,
      modified   = meta$created[[1L]]
    )
  })

  .new_pin_listing(purrr::list_rbind(rows))
}

#' Retrieve detailed metadata for a single pin
#'
#' Returns a structured list with format, sf/CRS details (if applicable),
#' version count, and the pin's lineage name. The print form is compact
#' (≤80 cols) and uses `cli` styling.
#'
#' @param board A `gdpins_board` object.
#' @param name Character scalar. Pin name.
#'
#' @return An S3 object of class `gdpins_pin_info` — a named list with
#'   elements: `name` (chr), `type` (chr), `n_versions` (int), `size`
#'   (dbl, bytes), `modified` (POSIXct), `is_sf` (lgl), `crs_epsg`
#'   (int or NA), `lineage_name` (chr), `versions` (tibble from
#'   [pins::pin_versions()]).
#' @export
gdpins_pin_info <- function(board, name) {
  if (!inherits(board, "gdpins_board")) {
    cli::cli_abort(c(
      "{.arg board} must be a {.cls gdpins_board} object.",
      x = "Got {.cls {class(board)}}."
    ))
  }
  if (!is.character(name) || length(name) != 1L || !nzchar(name)) {
    cli::cli_abort("{.arg name} must be a non-empty character scalar.")
  }

  src      <- .read_source(board)
  all_pins <- pins::pin_list(src)

  if (!name %in% all_pins) {
    cli::cli_abort(c(
      "Pin {.val {name}} not found in board {.val {board$name}}.",
      i = "Available pins: {.val {all_pins}}."
    ))
  }

  meta      <- pins::pin_meta(src, name)
  versions  <- pins::pin_versions(src, name)
  crs_epsg  <- .detect_sf_crs(src, name)
  is_sf     <- !is.na(crs_epsg)

  structure(
    list(
      name         = name,
      type         = if (is.null(meta$type)) NA_character_ else meta$type,
      n_versions   = as.integer(nrow(versions)),
      size         = as.double(meta$file_size),
      modified     = meta$created,
      is_sf        = is_sf,
      crs_epsg     = crs_epsg,
      lineage_name = name,
      versions     = versions
    ),
    class = "gdpins_pin_info"
  )
}

#' Print method for gdpins_pin_info
#'
#' Compact ≤80-col output using `cli` styling. One key-value pair per line.
#'
#' @param x A `gdpins_pin_info` object.
#' @param ... Unused.
#' @return Invisibly `x`.
#' @exportS3Method print gdpins_pin_info
print.gdpins_pin_info <- function(x, ...) {
  cli::cli_text("{.strong Pin}: {.val {x$name}}")
  gd_cli_kv(
    type     = x$type,
    versions = x$n_versions,
    size     = gd_fmt_bytes(x$size),
    modified = gd_fmt_mtime(x$modified)
  )
  if (x$is_sf) {
    gd_cli_kv(sf = "yes", crs_epsg = x$crs_epsg)
  } else {
    gd_cli_kv(sf = "no")
  }
  gd_cli_kv(lineage = x$lineage_name)
  invisible(x)
}
