#' Compact CLI formatters for gdpins console output
#'
#' Internal helpers for formatting values in compact, <=80-col `cli`-styled
#' output. Every public-facing print/summary method in the package uses these
#' to stay consistent.
#'
#' @name cli-helpers
#' @keywords internal
NULL

#' Format a byte count as a human-readable string
#'
#' Converts a numeric byte count to a compact string with appropriate unit
#' suffix (B, KB, MB, GB). Fits within <=80-col output.
#'
#' @param n Numeric scalar. Number of bytes.
#'
#' @return Character scalar, e.g. `"1.2 MB"` or `"456 B"`.
#' @keywords internal
gd_fmt_bytes <- function(n) {
  if (!is.numeric(n) || length(n) != 1L) {
    cli::cli_abort("{.arg n} must be a numeric scalar.")
  }
  if (is.na(n)) {
    return("NA")
  }
  if (n < 0) {
    return(paste0(round(n), " B"))
  }
  if (n < 1e3) {
    return(paste0(round(n), " B"))
  }
  if (n < 1e6) {
    return(paste0(round(n / 1e3, 1L), " KB"))
  }
  if (n < 1e9) {
    return(paste0(round(n / 1e6, 1L), " MB"))
  }
  paste0(round(n / 1e9, 2L), " GB")
}

#' Format a POSIXct timestamp compactly
#'
#' Produces a short ISO-8601-like string (`"YYYY-MM-DD HH:MM"`) suitable for
#' narrow console output. Returns `"\u2014"` (em-dash) for `NA` values.
#'
#' @param t A `POSIXct` scalar (or something coercible via [as.POSIXct()]).
#'
#' @return Character scalar.
#' @keywords internal
gd_fmt_mtime <- function(t) {
  if (!inherits(t, "POSIXct") && !inherits(t, "POSIXlt")) {
    t <- tryCatch(as.POSIXct(t), error = function(e) as.POSIXct(NA))
  }
  if (is.na(t)) {
    return("\u2014")
  } # em-dash
  format(t, "%Y-%m-%d %H:%M")
}

#' Emit a compact key-value line via cli
#'
#' Formats each `name = value` pair as a `cli`-styled bullet:
#' `  {.field name}: {.val value}`. Truncates long values to keep lines <=80
#' characters. Passes `...` as named arguments where names become keys and
#' values become the displayed values.
#'
#' @param ... Named arguments. Names are the keys; values are coerced to
#'   character for display.
#'
#' @return Invisibly `NULL`. Called for its side effect of printing.
#' @keywords internal
gd_cli_kv <- function(...) {
  args <- list(...)
  keys <- names(args)
  if (is.null(keys) || any(!nzchar(keys))) {
    cli::cli_abort("All arguments to {.fn gd_cli_kv} must be named.")
  }
  for (i in seq_along(args)) {
    key <- keys[[i]]
    val <- as.character(args[[i]])
    # Truncate to keep within 80 cols: key + ": " + val
    max_val <- 80L - nchar(key) - 4L # 4 = "  " prefix + ": "
    if (nchar(val) > max_val && max_val > 3L) {
      val <- paste0(substr(val, 1L, max_val - 3L), "...")
    }
    cli::cli_text("  {.field {key}}: {.val {val}}")
  }
  invisible(NULL)
}
