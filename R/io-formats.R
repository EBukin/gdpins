#' I/O format detection and geospatial encoding
#'
#' Functions for converting between R objects and storage formats, with special
#' handling for `sf` geospatial objects using a WKT + column-name CRS encoding.
#'
#' @section WKT engine:
#' The geometry <-> WKT text conversion can be performed by one of two engines,
#' selected with the `engine` argument (or, package-wide, the
#' `gdpins.wkt_engine` option):
#'
#' * `"wk"` (default) — uses [wk::as_wkt()] to write and routes reads through
#'   [wk::wkt()] into [sf::st_as_sfc()]. About 20x faster to write than `"sf"`
#'   and always full-precision.
#' * `"sf"` — uses [sf::st_as_text()] (with `digits = 15`, so it is
#'   full-precision) to write and [sf::st_as_sfc()] to read. Kept as a fallback
#'   so encoding never depends on a single engine.
#'
#' Both engines are read-compatible: WKT written by one reads back correctly with
#' the other. The default can be changed globally with
#' `options(gdpins.wkt_engine = "sf")`.
#'
#' Note: `sf::st_as_text()` defaults to `getOption("digits")` (7 significant
#' figures), which silently rounds projected coordinates (e.g. UTM metres) by up
#' to ~0.5 m. gdpins always pins `digits = 15` for the `"sf"` engine to avoid
#' this; the `"wk"` engine is full-precision by construction.
#'
#' @name io-formats
NULL

#' Resolve and validate the WKT engine
#'
#' @param engine Character scalar `"wk"` or `"sf"`, or `NULL` to fall back to the
#'   `gdpins.wkt_engine` option (default `"wk"`).
#' @return `"wk"` or `"sf"`.
#' @keywords internal
.gdpins_wkt_engine <- function(engine = NULL) {
  if (is.null(engine)) {
    engine <- getOption("gdpins.wkt_engine", "wk")
  }
  engine <- tryCatch(
    match.arg(engine, c("wk", "sf")),
    error = function(e) {
      cli::cli_abort(c(
        "Invalid WKT {.arg engine}: {.val {engine}}.",
        i = "Must be one of {.val wk} or {.val sf}."
      ))
    }
  )
  if (identical(engine, "wk") && !requireNamespace("wk", quietly = TRUE)) {
    cli::cli_abort(c(
      "WKT engine {.val wk} requested but the {.pkg wk} package is not installed.",
      i = "Install it, or use {.code engine = \"sf\"} / {.code options(gdpins.wkt_engine = \"sf\")}."
    ))
  }
  engine
}

# sfc -> character WKT (one column), full precision, chosen engine
.gdpins_sfc_to_wkt <- function(sfc, engine) {
  if (identical(engine, "wk")) {
    as.character(wk::as_wkt(sfc))
  } else {
    # digits = 15: st_as_text() otherwise rounds to getOption("digits") == 7,
    # silently losing sub-metre precision on projected coordinates.
    sf::st_as_text(sfc, digits = 15)
  }
}

# character WKT -> sfc (one column), chosen engine
.gdpins_wkt_to_sfc <- function(x, epsg, engine) {
  if (identical(engine, "wk")) {
    # Marking the character vector as wk_wkt makes st_as_sfc() dispatch through
    # wk's C handler instead of sf's own WKT parser. The `crs` argument is NOT
    # honoured by the wk_wkt method (it silently yields an empty CRS), so assign
    # it explicitly afterwards — no reprojection, just a label.
    sfc <- sf::st_as_sfc(wk::wkt(x))
    sf::st_crs(sfc) <- epsg
    sfc
  } else {
    sf::st_as_sfc(x, crs = epsg)
  }
}

#' Convert an sf object to a plain tibble suitable for parquet storage
#'
#' Converts all `sfc` geometry columns to WKT text and encodes the per-column
#' CRS (EPSG integer) into the column name using the pattern
#' `"<name>__<epsg>__"` (double-underscore both sides). The result is a plain
#' tibble with no `sf` class.
#'
#' No coordinate transformation is performed. Each geometry is converted to WKT
#' text (never WKB) by the selected `engine` (see [io-formats]). Per-column CRS
#' is supported.
#'
#' @param x An `sf` data frame with one or more geometry columns.
#' @param engine Character scalar, the WKT engine: `"wk"` (default) or `"sf"`.
#'   `NULL` uses the `gdpins.wkt_engine` option (default `"wk"`). See the
#'   [io-formats] "WKT engine" section.
#'
#' @return A [tibble::tibble()] with geometry columns replaced by WKT character
#'   columns named `"<original_name>__<epsg>__"`.
#' @examples
#' library(sf)
#' pts <- st_sf(
#'   id = 1:2,
#'   geometry = st_sfc(st_point(c(71, 51)), st_point(c(76, 43)), crs = 4326)
#' )
#' gdpins_sf_to_parquet(pts)                 # default "wk" engine
#' gdpins_sf_to_parquet(pts, engine = "sf")  # sf fallback (full precision)
#' @export
gdpins_sf_to_parquet <- function(x, engine = NULL) {
  engine <- .gdpins_wkt_engine(engine)

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
    result[[col]]                       <- .gdpins_sfc_to_wkt(sfc, engine)
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
#' @param engine Character scalar, the WKT engine: `"wk"` (default) or `"sf"`.
#'   `NULL` uses the `gdpins.wkt_engine` option (default `"wk"`). Reads are
#'   engine-agnostic — WKT written by either engine parses with either — so this
#'   only affects parsing speed. See the [io-formats] "WKT engine" section.
#'
#' @return An `sf` object. Column names are restored to their original form
#'   (suffix stripped). CRS is set from the EPSG code embedded in the name.
#' @examples
#' library(sf)
#' pts <- st_sf(
#'   id = 1:2,
#'   geometry = st_sfc(st_point(c(71, 51)), st_point(c(76, 43)), crs = 4326)
#' )
#' encoded <- gdpins_sf_to_parquet(pts)
#' gdpins_parquet_to_sf(encoded)                 # default "wk" engine
#' gdpins_parquet_to_sf(encoded, engine = "sf")  # sf fallback
#' @export
gdpins_parquet_to_sf <- function(x, engine = NULL) {
  engine <- .gdpins_wkt_engine(engine)

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
      .gdpins_wkt_to_sfc(result[[col]], epsg, engine),
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
#' Returns `"parquet"` for data frames, tibbles (including `sf` objects), and
#' other tabular objects. Returns `"rds"` for lists, nested tibbles with
#' list-columns, and any non-tabular object.
#'
#' Decision rules (in order):
#' 1. Not a data frame -> `"rds"`.
#' 2. Data frame with any non-`sfc` list-column -> `"rds"`.
#' 3. Plain df/tibble or `sf` (all list-cols are `sfc`) -> `"parquet"`.
#'
#' @param x An R object.
#'
#' @return Character scalar: `"parquet"` or `"rds"`.
#' @export
gdpins_detect_format <- function(x) {
  # Bare list (not data frame) -> rds
  if (!is.data.frame(x)) {
    return("rds")
  }

  # Data frame: check for non-sfc list-columns (sfc cols are fine for parquet)
  has_non_sfc_list_col <- any(vapply(
    x,
    function(col) is.list(col) && !inherits(col, "sfc"),
    logical(1)
  ))

  if (has_non_sfc_list_col) {
    return("rds")
  }

  "parquet"
}
