#' I/O format detection and geospatial encoding
#'
#' Functions for converting between R objects and storage formats, with special
#' handling for `sf` geospatial objects using a WKT + column-name CRS encoding.
#'
#' @name io-formats
NULL

#' Convert an sf object to a plain tibble suitable for parquet storage
#'
#' Converts all `sfc` geometry columns to WKT text and encodes the per-column
#' CRS (EPSG integer) into the column name using the pattern
#' `"<name>__<epsg>__"` (double-underscore both sides). The result is a plain
#' tibble with no `sf` class.
#'
#' No coordinate transformation is performed. Each geometry is converted via
#' [sf::st_as_text()] (WKT, never WKB). Per-column CRS is supported.
#'
#' @param x An `sf` data frame with one or more geometry columns.
#'
#' @return A [tibble::tibble()] with geometry columns replaced by WKT character
#'   columns named `"<original_name>__<epsg>__"`.
#' @export
gdpins_sf_to_parquet <- function(x) {
  # Detect all sfc columns by class (not by name — catches geom/geometry/centroid)
  is_sfc <- vapply(x, inherits, logical(1), "sfc")
  sfc_cols <- names(x)[is_sfc]

  if (length(sfc_cols) == 0L) {
    return(tibble::as_tibble(x))
  }

  # Start with a plain tibble (drops sf class)
  result <- tibble::as_tibble(x)

  for (col in sfc_cols) {
    sfc  <- x[[col]]
    epsg <- sf::st_crs(sfc)$epsg
    if (is.na(epsg)) {
      cli::cli_abort(c(
        "Cannot encode geometry column {.val {col}} without an EPSG code.",
        x = "CRS has no EPSG integer.",
        i = "Set a CRS with {.fn sf::st_set_crs} before converting."
      ))
    }
    new_name                            <- paste0(col, "__", epsg, "__")
    result[[col]]                       <- sf::st_as_text(sfc)
    names(result)[names(result) == col] <- new_name
  }

  result
}

#' Restore an sf object from a parquet-encoded tibble
#'
#' Inverse of [gdpins_sf_to_parquet()]. Detects columns whose names match the
#' pattern `^.*__\\d{4,5}__$` and attempts to parse them as WKT geometry. Only
#' columns where the WKT actually parses are converted; others are left as plain
#' strings (column name is NOT changed).
#'
#' @param x A [tibble::tibble()] previously produced by [gdpins_sf_to_parquet()].
#'
#' @return An `sf` object. Column names are restored to their original form
#'   (suffix stripped). CRS is set from the EPSG code embedded in the name.
#' @export
gdpins_parquet_to_sf <- function(x) {
  # Detect candidate columns by anchored name pattern
  candidate_mask <- grepl("^.*__\\d{4,5}__$", names(x))
  candidate_cols <- names(x)[candidate_mask]

  if (length(candidate_cols) == 0L) {
    return(x)
  }

  result    <- x
  sfc_added <- character(0)

  for (col in candidate_cols) {
    # Extract EPSG from column name suffix
    epsg_str  <- regmatches(col, regexpr("\\d{4,5}(?=__$)", col, perl = TRUE))
    epsg      <- as.integer(epsg_str)
    base_name <- sub("__\\d{4,5}__$", "", col)

    # Guard: only treat as geometry if WKT actually parses
    sfc <- tryCatch(
      sf::st_as_sfc(result[[col]], crs = epsg),
      error   = function(e) NULL,
      warning = function(w) NULL
    )

    if (is.null(sfc)) {
      # WKT did not parse — leave column AS-IS (do NOT rename)
      next
    }

    # Replace chr column with sfc, rename to base name
    result[[col]]                       <- sfc
    names(result)[names(result) == col] <- base_name
    sfc_added                           <- c(sfc_added, base_name)
  }

  if (length(sfc_added) == 0L) {
    return(result)
  }

  # Promote to sf using first restored sfc column as active geometry
  sf::st_sf(result)
}

#' Detect the appropriate storage format for an R object
#'
#' Returns `"arrow"` for data frames, tibbles (including `sf` objects), and
#' other tabular objects. Returns `"rds"` for lists, nested tibbles with
#' list-columns, and any non-tabular object.
#'
#' Decision rules (in order):
#' 1. Not a data frame -> `"rds"`.
#' 2. Data frame with any non-`sfc` list-column -> `"rds"`.
#' 3. Plain df/tibble or `sf` (all list-cols are `sfc`) -> `"arrow"`.
#'
#' @param x An R object.
#'
#' @return Character scalar: `"arrow"` or `"rds"`.
#' @export
gdpins_detect_format <- function(x) {
  # Bare list (not data frame) -> rds
  if (!is.data.frame(x)) {
    return("rds")
  }

  # Data frame: check for non-sfc list-columns (sfc cols are fine for arrow)
  has_non_sfc_list_col <- any(vapply(
    x,
    function(col) is.list(col) && !inherits(col, "sfc"),
    logical(1)
  ))

  if (has_non_sfc_list_col) {
    return("rds")
  }

  "arrow"
}
