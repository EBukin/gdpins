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
#' @section Parquet engine:
#' The parquet files behind pins are read and written by one of two engines,
#' controlled package-wide by the `gdpins.parquet_engine` option:
#'
#' * `"arrow"` (default) — uses [arrow::read_parquet()] / [arrow::write_parquet()].
#' * `"nanoparquet"` — uses [nanoparquet::read_parquet()] /
#'   [nanoparquet::write_parquet()].
#'
#' arrow is the default because nanoparquet's reader can allocate tens of
#' gigabytes and crash the session on files that hold a few large (multi-MB)
#' string cells — for example a WKT geometry column with one row per region.
#' arrow reads the identical bytes in bounded memory. Both engines write
#' standard parquet that either can read, so the choice is transparent apart
#' from the memory behaviour. Switch with
#' `options(gdpins.parquet_engine = "nanoparquet")`.
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

#' Resolve the parquet (de)serialisation engine
#'
#' @param engine Character scalar `"arrow"` or `"nanoparquet"`, or `NULL` to
#'   fall back to the `gdpins.parquet_engine` option (default `"arrow"`).
#' @return `"arrow"` or `"nanoparquet"`.
#' @keywords internal
.gdpins_parquet_engine <- function(engine = NULL) {
  if (is.null(engine)) {
    engine <- getOption("gdpins.parquet_engine", "arrow")
  }
  engine <- tryCatch(
    match.arg(engine, c("arrow", "nanoparquet")),
    error = function(e) {
      cli::cli_abort(c(
        "Invalid parquet {.arg engine}: {.val {engine}}.",
        i = "Must be one of {.val arrow} or {.val nanoparquet}."
      ))
    }
  )
  if (!requireNamespace(engine, quietly = TRUE)) {
    cli::cli_abort(c(
      "Parquet engine {.val {engine}} requested but the {.pkg {engine}} package is not installed.",
      i = "Install it, or select the other engine via {.code options(gdpins.parquet_engine = ...)}."
    ))
  }
  engine
}

# Read a parquet file into a tibble using the selected engine. arrow is the
# default: nanoparquet's reader can allocate tens of GB on files holding a few
# large (~MB) string cells (e.g. WKT geometry), whereas arrow reads the same
# bytes in bounded memory. mmap = FALSE because memory-mapping a file on a
# cloud-sync mount (OneDrive/SharePoint) segfaults when the backing pages are
# invalidated mid-read.
.read_parquet_file <- function(path, engine = NULL) {
  engine <- .gdpins_parquet_engine(engine)
  tbl <- if (identical(engine, "arrow")) {
    arrow::read_parquet(path, mmap = FALSE)
  } else {
    nanoparquet::read_parquet(path)
  }
  tibble::as_tibble(tbl)
}

# Write a data frame to a parquet file using the selected engine.
.write_parquet_file <- function(x, path, engine = NULL) {
  engine <- .gdpins_parquet_engine(engine)
  if (identical(engine, "arrow")) {
    arrow::write_parquet(x, path)
  } else {
    nanoparquet::write_parquet(x, path)
  }
  invisible(path)
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

# Detect candidate WKT geometry columns by name + type. A candidate is a
# character column whose name looks geometric: the standard __<epsg>__ suffix,
# or containing "geom"/"wkt" (case-insensitive). The character-type filter keeps
# non-geometry columns like an integer `geom_id` out of the running.
.gdpins_wkt_columns <- function(x) {
  nm     <- names(x)
  is_chr <- vapply(x, is.character, logical(1))
  looks  <- grepl("__\\d{4,5}__$|geom|wkt", nm, ignore.case = TRUE)
  nm[is_chr & looks]
}

# Infer an EPSG code from a column name. Returns list(epsg, source) where
# source is "standard" (the __<epsg>__ pattern, trust it silently),
# "nonstandard" (some digit run present, e.g. geom_1111 — usable but worth a
# heads-up), or "default" (no digits — fall back to default_epsg).
.gdpins_epsg_from_name <- function(col, default_epsg) {
  std <- regmatches(col, regexpr("(?<=__)\\d{4,5}(?=__$)", col, perl = TRUE))
  if (length(std) == 1L && nzchar(std)) {
    return(list(epsg = as.integer(std), source = "standard"))
  }
  digits <- regmatches(col, regexpr("\\d+", col))
  if (length(digits) == 1L && nzchar(digits)) {
    return(list(epsg = as.integer(digits), source = "nonstandard"))
  }
  list(epsg = as.integer(default_epsg), source = "default")
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
#' @seealso [gdpins_as_sf()] for a single-column decoder that autodetects the
#'   geometry column and infers the CRS from messier column names.
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

#' Convert a data frame with a WKT text column to an sf object (autodetecting)
#'
#' A friendly, single-column decoder for data whose geometry lives in a WKT
#' character column. Unlike [gdpins_parquet_to_sf()] — which strictly decodes
#' every `"<name>__<epsg>__"` column and reads the CRS from the name — this
#' function autodetects the geometry column and infers the CRS, so it also
#' handles hand-made or externally-produced columns (`geom`, `geom_1111`, ...)
#' whose name does not carry a clean EPSG code.
#'
#' **Column detection.** When `column` is `NULL`, character columns whose name
#' matches the standard `__<epsg>__` suffix or contains `"geom"`/`"wkt"` are
#' candidates. Exactly one candidate is used automatically. If none is found,
#' `x` is returned unchanged with a warning (so plain, non-spatial data passes
#' through safely). If several match, an error asks you to pass `column`. An
#' explicitly supplied `column` that is absent is always an error.
#'
#' **CRS inference.** When `epsg` is `NULL`, the EPSG code is taken from the
#' column name: the standard `__<epsg>__` pattern is trusted silently; a
#' non-standard digit run (e.g. `geom_1111`) is used but emits a message; a name
#' with no digits falls back to `default_epsg` with a warning. In the latter two
#' cases you are firmly encouraged to pass `epsg` explicitly. An explicit `epsg`
#' argument always wins and silences inference.
#'
#' No coordinate transformation is performed; the EPSG code only labels the CRS.
#'
#' @param x A data frame with a WKT geometry column.
#' @param column Character scalar or `NULL`. Name of the WKT column. `NULL`
#'   autodetects (see Details).
#' @param epsg Integer scalar or `NULL`. EPSG code for the geometry CRS. `NULL`
#'   infers it from `column`'s name (see Details).
#' @param engine Character scalar, the WKT engine: `"wk"` (default) or `"sf"`.
#'   `NULL` uses the `gdpins.wkt_engine` option. See the [io-formats] "WKT
#'   engine" section.
#' @param default_epsg Integer scalar. CRS assumed when `epsg` is `NULL` and the
#'   column name carries no digits. Default `4326` (WGS 84).
#'
#' @return An `sf` object, or — when autodetection finds no geometry column —
#'   the input `x` unchanged (with a warning). A standard `__<epsg>__` suffix is
#'   stripped from the converted column name; other names are kept as-is.
#' @seealso [gdpins_parquet_to_sf()] for strict multi-geometry decoding,
#'   [gdpins_sf_to_parquet()] for the inverse, and [gdpins_pin_read()] whose
#'   `wkt_engine = "none"` returns WKT text ready for this function.
#' @examples
#' library(sf)
#' pts <- st_sf(
#'   id = 1:2,
#'   geometry = st_sfc(st_point(c(71, 51)), st_point(c(76, 43)), crs = 4326)
#' )
#' encoded <- gdpins_sf_to_parquet(pts)   # a "geometry__4326__" WKT column
#' gdpins_as_sf(encoded)                  # autodetect column + EPSG, silent
#'
#' # Non-standard name: EPSG inferred from the digits (with a message)
#' df <- data.frame(geom_3857 = "POINT (0 0)")
#' gdpins_as_sf(df)
#'
#' # No CRS in the name: pass epsg explicitly to avoid the default + warning
#' df2 <- data.frame(geom = "POINT (0 0)")
#' gdpins_as_sf(df2, epsg = 4326)
#' @export
gdpins_as_sf <- function(x,
                         column       = NULL,
                         epsg         = NULL,
                         engine       = NULL,
                         default_epsg = 4326L) {
  if (!is.data.frame(x)) {
    cli::cli_abort("{.arg x} must be a data frame.")
  }
  engine <- .gdpins_wkt_engine(engine)

  # 1. Resolve the geometry column
  if (is.null(column)) {
    candidates <- .gdpins_wkt_columns(x)
    if (length(candidates) == 0L) {
      # Nothing to convert: don't break — the caller asked for a conversion, so
      # warn, but hand the data back untouched (plain, non-spatial data passes
      # through). An explicitly named `column` that is absent is still an error.
      cli::cli_warn(c(
        "!" = "No WKT geometry column detected in {.arg x}; returning it unchanged.",
        "i" = "Expected a character column named like {.val geom__4326__}, {.val geom}, or {.val wkt}.",
        "i" = "Pass {.arg column} to name the geometry column explicitly."
      ))
      return(x)
    }
    if (length(candidates) > 1L) {
      cli::cli_abort(c(
        "Multiple candidate geometry columns detected: {.val {candidates}}.",
        i = "Pass {.arg column} to choose which one to convert."
      ))
    }
    column <- candidates
  } else {
    if (!is.character(column) || length(column) != 1L || !nzchar(column)) {
      cli::cli_abort("{.arg column} must be a non-empty character scalar.")
    }
    if (!column %in% names(x)) {
      cli::cli_abort(c(
        "Column {.val {column}} not found in {.arg x}.",
        i = "Available columns: {.val {names(x)}}."
      ))
    }
  }

  # Already an sfc column: nothing to parse, just promote.
  if (inherits(x[[column]], "sfc")) {
    return(sf::st_sf(x))
  }
  if (!is.character(x[[column]])) {
    cli::cli_abort(c(
      "Geometry column {.val {column}} must be character WKT.",
      x = "Got {.cls {class(x[[column]])}}."
    ))
  }

  # 2. Resolve the EPSG code
  if (is.null(epsg)) {
    det  <- .gdpins_epsg_from_name(column, default_epsg)
    epsg <- det$epsg
    if (identical(det$source, "nonstandard")) {
      cli::cli_inform(c(
        "i" = "Inferred EPSG {.val {epsg}} from non-standard column name {.val {column}}.",
        "i" = "Pass {.arg epsg} explicitly if this is not the intended CRS."
      ))
    } else if (identical(det$source, "default")) {
      cli::cli_warn(c(
        "!" = "Could not infer a CRS from column name {.val {column}}; assuming EPSG {.val {epsg}}.",
        "i" = "Pass {.arg epsg} explicitly to set the correct CRS."
      ))
    }
  } else {
    epsg_int <- suppressWarnings(as.integer(epsg))
    if (length(epsg) != 1L || is.na(epsg_int)) {
      cli::cli_abort("{.arg epsg} must be a single EPSG integer.")
    }
    epsg <- epsg_int
  }

  # 3. Parse WKT -> sfc (guard: a non-WKT column is a hard error here)
  sfc <- tryCatch(
    .gdpins_wkt_to_sfc(x[[column]], epsg, engine),
    error = function(e) {
      cli::cli_abort(c(
        "Column {.val {column}} does not contain valid WKT.",
        x = conditionMessage(e)
      ))
    },
    warning = function(w) {
      cli::cli_abort(c(
        "Column {.val {column}} does not contain valid WKT.",
        x = conditionMessage(w)
      ))
    }
  )

  # 4. Replace column, strip a standard suffix, promote to sf
  result           <- x
  result[[column]] <- sfc
  base_name        <- sub("__\\d{4,5}__$", "", column)
  if (!identical(base_name, column)) {
    names(result)[names(result) == column] <- base_name
  }
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
