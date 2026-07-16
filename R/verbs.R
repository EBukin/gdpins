#' Read/write verbs for gdpins boards
#'
#' Core verbs for writing R objects to a board and reading them back. Writes
#' fan out to all non-NULL board components (Drive, cache, local). Reads are
#' local-first: local → cache → Drive.
#'
#' @name verbs
NULL

# ── Internal helpers ──────────────────────────────────────────────────────────

#' Write x to a single pins board with appropriate type
#'
#' @param pins_board A pins board object.
#' @param x The R object to write.
#' @param name Pin name.
#' @param fmt Character scalar: `"parquet"` or `"rds"`.
#' @param versioned Logical. Whether this write creates a version.
#'
#' @keywords internal
.write_to_board <- function(pins_board, x, name, fmt, versioned) {
  type <- switch(fmt,
    parquet = "parquet",
    rds     = "rds",
    cli::cli_abort("Unknown format {.val {fmt}}.")
  )
  pins::pin_write(
    pins_board,
    x,
    name      = name,
    type      = type,
    versioned = versioned
  )
  invisible(NULL)
}

#' Read from a single pins board
#'
#' @param pins_board A pins board object.
#' @param name Pin name.
#' @param version Character scalar or `NULL`.
#'
#' @keywords internal
.read_from_board <- function(pins_board, name, version) {
  if (is.null(version)) {
    pins::pin_read(pins_board, name)
  } else {
    pins::pin_read(pins_board, name, version = version)
  }
}

# ── Exported verbs ────────────────────────────────────────────────────────────

#' Write a pin to a gdpins board
#'
#' Serialises `x` and writes it to every non-NULL component of `board`
#' (Drive board, cache board, local board). Format auto-detection calls
#' [gdpins_detect_format()] unless `format` is supplied explicitly.
#'
#' If `x` is an `sf` object, it is encoded with [gdpins_sf_to_parquet()]
#' before writing (type `"parquet"`).
#'
#' @param board A `gdpins_board` object.
#' @param x An R object to pin.
#' @param name Character scalar. Pin name (bare snake_case, e.g. `"parcels"`).
#' @param version Character scalar or `NULL`. Version label; `NULL` uses the
#'   board default.
#' @param format Character scalar or `NULL`. One of `"parquet"` or `"rds"`;
#'   `NULL` auto-detects via [gdpins_detect_format()].
#' @param wkt_engine Character scalar or `NULL`. WKT engine used to encode `sf`
#'   geometry: `"wk"` (default, fast, full precision) or `"sf"` (fallback).
#'   `NULL` uses the `gdpins.wkt_engine` option. See [gdpins_sf_to_parquet()].
#'
#' @return Invisibly `NULL`. Called for its side effect.
#' @seealso [gdpins_real_drive()], [gdpins_init_board()], [gdpins_pin_read()],
#'   [gdpins_pin_remove()].
#' @examples
#' adapter <- gdpins_fake_drive()
#' board <- gdpins_init_board(
#'   name       = "data_raw",
#'   drive_path = "my-project/data-raw",
#'   cache_dir  = tempfile("cache_"),
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#'
#' gdpins_pin_write(board, mtcars, "cars")
#'
#' \dontrun{
#' adapter <- gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")
#' board <- gdpins_init_board(
#'   name       = "data_raw",
#'   drive_path = "my-project/data-raw",
#'   cache_dir  = "~/.cache/gdpins/data-raw",
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#' gdpins_pin_write(board, mtcars, "cars")
#' }
#' @export
gdpins_pin_write <- function(board, x, name, version = NULL, format = NULL,
                             wkt_engine = NULL) {
  if (!inherits(board, "gdpins_board")) {
    cli::cli_abort(c(
      "{.arg board} must be a {.cls gdpins_board}.",
      x = "Got {.cls {class(board)}}."
    ))
  }
  if (!is.character(name) || length(name) != 1L || !nzchar(name)) {
    cli::cli_abort("{.arg name} must be a non-empty character scalar.")
  }

  # Block writes when offline (Drive present = network needed)
  if (!is.null(board$drive_board)) {
    is_online <- tryCatch(gdpins_is_online(), error = function(e) FALSE)
    if (!is_online) {
      cli::cli_abort(c(
        "Cannot write pin {.val {name}}: no internet connection.",
        i = "Writes to Drive boards are blocked offline.",
        i = "Use a {.val local_only} board for offline writes."
      ))
    }
  }

  # Resolve versioned for this write
  versioned_write <- if (!is.null(version)) {
    # version supplied: honour board$versioned; version label passed to pins
    board$versioned
  } else {
    board$versioned
  }

  # Detect format
  fmt <- if (!is.null(format)) {
    match.arg(format, c("parquet", "rds"))
  } else {
    gdpins_detect_format(x)
  }

  # sf pre-processing: encode geometry before writing as parquet
  x_to_write <- if (inherits(x, "sf") || .is_sf_like(x)) {
    gdpins_sf_to_parquet(x, engine = wkt_engine)
  } else {
    x
  }

  # Fan-out write to every non-NULL component
  boards_to_write <- list(
    drive = board$drive_board,
    cache = board$cache_board,
    local = board$local_board
  )

  for (component in boards_to_write) {
    if (!is.null(component)) {
      .write_to_board(component, x_to_write, name, fmt, versioned_write)
    }
  }

  invisible(NULL)
}

#' Check if an object is sf-like (has any sfc column)
#'
#' @keywords internal
.is_sf_like <- function(x) {
  if (!is.data.frame(x)) return(FALSE)
  any(vapply(x, inherits, logical(1L), "sfc"))
}

# ── Pin name resolution ───────────────────────────────────────────────────────

# The board components a read may come from, in local-first order.
#
# Deliberately NOT filtered by gdpins_is_online(). Resolution only answers "does
# this name exist anywhere on this board"; gdpins_pin_read() owns the offline
# semantics and warns + returns NULL for a pin that lives only on Drive.
# Dropping the Drive component here would turn that warning into a "pin not
# found" abort. When Drive is genuinely unreachable, pin_list() below fails and
# contributes nothing, which is the same answer by a slower route.
.pin_sources <- function(board) {
  srcs <- list(
    local = board$local_board,
    cache = board$cache_board,
    drive = board$drive_board
  )
  srcs[!vapply(srcs, is.null, logical(1L))]
}

# Every pin name reachable from the board, deduped across components.
.pin_candidates <- function(board) {
  out <- character()
  for (src in .pin_sources(board)) {
    out <- c(out, tryCatch(pins::pin_list(src), error = function(e) character()))
  }
  unique(out)
}

# Listing mode for pins: the gdpins_list_pins() tibble, filtered by glob.
.pin_glob_listing <- function(board, pattern) {
  listing <- gdpins_list_pins(board)
  matched <- fs::path_filter(listing$name, glob = pattern)
  .new_pin_listing(listing[listing$name %in% matched, , drop = FALSE])
}

#' Resolve a user-supplied pin name
#'
#' The [raw-connection] name-resolution ladder, minus the basename rungs: pin
#' names are flat, so "exact path" and "exact basename" are the same question.
#' Auto-resolve still happens only on an exact, unique match.
#'
#' @param board A `gdpins_board` object.
#' @param name Character scalar. The name as the user typed it.
#' @param verb Character scalar. Calling verb, used in error text.
#'
#' @return Character scalar. A pin name known to the board.
#' @keywords internal
.resolve_pin_name <- function(board, name, verb = "gdpins_pin_read") {
  cands <- .pin_candidates(board)

  # Rung 1 -- exact name.
  if (name %in% cands) return(name)

  glob_hint <- paste0(verb, '(board, "*")')

  if (length(cands) == 0L) {
    cli::cli_abort(c(
      "Pin {.val {name}} not found in any board component.",
      x = "The board has no pins.",
      i = "Write one with {.fn gdpins_pin_write}."
    ))
  }

  # Rung 4 -- case-insensitive exact, unique.
  ci <- unique(cands[tolower(cands) == tolower(name)])
  if (length(ci) == 1L) return(ci)

  near <- ci

  # Rung 5 -- same stem, different extension. Rarely fires for pins (names are
  # usually extensionless) but catches pin_read(board, "cars.csv") for "cars".
  by_stem <- cands[
    tolower(tools::file_path_sans_ext(cands)) ==
      tolower(tools::file_path_sans_ext(name))
  ]
  near <- unique(c(near, by_stem))

  # Rung 6 -- edit distance on the lowercased name.
  if (length(near) == 0L) {
    d      <- utils::adist(tolower(name), tolower(cands))[1L, ]
    thr    <- max(2L, floor(0.34 * nchar(name)))
    within <- which(d <= thr)
    near   <- utils::head(cands[within[order(d[within])]], 5L)
  }

  # Rung 7 -- nothing close.
  if (length(near) == 0L) {
    cli::cli_abort(c(
      "Pin {.val {name}} not found in any board component.",
      i = "Board: {.val {board$name}}",
      i = "List every pin with {.code {glob_hint}}."
    ))
  }

  cli::cli_abort(c(
    "Pin {.val {name}} not found in any board component.",
    i = "Did you mean:",
    .raw_suggest_bullets(near),
    i = "List every pin with {.code {glob_hint}}."
  ))
}

#' Resolve a pin to its file path(s) on disk
#'
#' The path counterpart of [gdpins_pin_read()]: same board, same name, same
#' local-first resolution, but returns where the pin's file(s) live rather than
#' the object inside them. Use it to hand a pin to a reader gdpins does not
#' know about, or to inspect the stored bytes.
#'
#' Resolution mirrors [gdpins_pin_read()] exactly — local board, then cache
#' board, then Drive — and the pin is materialised (downloaded into the pins
#' cache) when Drive holds the only copy, just as [gdpins_raw_path()] downloads
#' on demand.
#'
#' @param board A `gdpins_board` object.
#' @param name Character scalar. Pin name. A `name` containing `*` or `?`
#'   switches to listing mode; see the Glob section on [raw-connection].
#' @param version Character scalar or `NULL`. Pin version; `NULL` = latest.
#'
#' @return Character vector of absolute paths — length 1 for an ordinary pin,
#'   longer for a multi-file pin written with [pins::pin_upload()]. In listing
#'   mode, a `gdpins_pin_listing` tibble instead.
#' @seealso [gdpins_pin_read()], [gdpins_raw_path()].
#' @examples
#' adapter <- gdpins_fake_drive()
#' board <- gdpins_init_board(
#'   name       = "data_raw",
#'   drive_path = "my-project/data-raw",
#'   cache_dir  = tempfile("cache_"),
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#' gdpins_pin_write(board, mtcars, "cars")
#' p <- gdpins_pin_path(board, "cars")
#' file.exists(p)
#' @inheritSection raw-connection Name resolution
#' @inheritSection raw-connection Glob and listing mode
#' @inheritSection raw-connection Objects vs paths
#' @export
gdpins_pin_path <- function(board, name, version = NULL) {
  if (!inherits(board, "gdpins_board")) {
    cli::cli_abort(c(
      "{.arg board} must be a {.cls gdpins_board}.",
      x = "Got {.cls {class(board)}}."
    ))
  }
  if (!is.character(name) || length(name) != 1L || !nzchar(name)) {
    cli::cli_abort("{.arg name} must be a non-empty character scalar.")
  }

  if (.is_glob(name)) {
    return(.pin_glob_listing(board, name))
  }

  name <- .resolve_pin_name(board, name, verb = "gdpins_pin_path")

  for (src in .pin_sources(board)) {
    found <- tryCatch(pins::pin_exists(src, name), error = function(e) FALSE)
    if (!isTRUE(found)) next
    paths <- tryCatch(
      pins::pin_download(src, name, version = version),
      error = function(e) NULL
    )
    if (!is.null(paths)) return(as.character(paths))
  }

  cli::cli_abort(c(
    "Could not resolve a path for pin {.val {name}}.",
    i = "The pin is known to the board but no component could produce its files.",
    i = "If it lives only on Drive, check your connection."
  ))
}

#' Read a pin from a gdpins board
#'
#' Reads from the local-first source: local board if present, else cache board,
#' else Drive board. Hits the network only if the pin is absent locally.
#'
#' If the stored object contains `__<epsg>__`-suffixed geometry columns (WKT
#' encoding), the geometry is automatically restored via [gdpins_parquet_to_sf()].
#'
#' @param board A `gdpins_board` object.
#' @param name Character scalar. Pin name.
#' @param version Character scalar or `NULL`. Pin version; `NULL` = latest.
#' @param wkt_engine Character scalar or `NULL`. Controls how WKT-encoded `sf`
#'   geometry is restored: `"wk"` (default) or `"sf"` decode to an `sf` object
#'   (reads are engine-agnostic; the choice only affects parse speed), while
#'   `"none"` skips restoration and returns the geometry columns as raw WKT text
#'   (names keep their `__<epsg>__` suffix, so the result can be fed to
#'   [gdpins_as_sf()] later). `NULL` uses the `gdpins.wkt_engine` option (never
#'   `"none"`). See [gdpins_parquet_to_sf()].
#'
#' @return The pinned R object.
#' @seealso [gdpins_real_drive()], [gdpins_init_board()], [gdpins_pin_write()],
#'   [gdpins_pin_remove()].
#' @examples
#' adapter <- gdpins_fake_drive()
#' board <- gdpins_init_board(
#'   name       = "data_raw",
#'   drive_path = "my-project/data-raw",
#'   cache_dir  = tempfile("cache_"),
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#' gdpins_pin_write(board, mtcars, "cars")
#' gdpins_pin_read(board, "cars")
#'
#' \dontrun{
#' adapter <- gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")
#' board <- gdpins_init_board(
#'   name       = "data_raw",
#'   drive_path = "my-project/data-raw",
#'   cache_dir  = "~/.cache/gdpins/data-raw",
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#' gdpins_pin_read(board, "cars")
#' }
#' @inheritSection raw-connection Name resolution
#' @inheritSection raw-connection Glob and listing mode
#' @export
gdpins_pin_read <- function(board, name, version = NULL, wkt_engine = NULL) {
  if (!inherits(board, "gdpins_board")) {
    cli::cli_abort(c(
      "{.arg board} must be a {.cls gdpins_board}.",
      x = "Got {.cls {class(board)}}."
    ))
  }
  if (!is.character(name) || length(name) != 1L || !nzchar(name)) {
    cli::cli_abort("{.arg name} must be a non-empty character scalar.")
  }

  # Listing mode. Never bulk-reads: a glob asks which pins exist.
  if (.is_glob(name)) {
    return(.pin_glob_listing(board, name))
  }

  name <- .resolve_pin_name(board, name, verb = "gdpins_pin_read")
  if (!is.null(wkt_engine) &&
      !(is.character(wkt_engine) && length(wkt_engine) == 1L &&
        wkt_engine %in% c("wk", "sf", "none"))) {
    cli::cli_abort(c(
      "Invalid {.arg wkt_engine}: {.val {wkt_engine}}.",
      i = "Must be one of {.val wk}, {.val sf}, {.val none}, or {.code NULL}."
    ))
  }

  # Local-first read order: local → cache → drive
  read_sources <- list(
    local = board$local_board,
    cache = board$cache_board,
    drive = board$drive_board
  )

  result      <- NULL
  result_type <- NA_character_
  read_from_drive <- FALSE

  for (src_name in names(read_sources)) {
    src <- read_sources[[src_name]]
    if (is.null(src)) next

    # Check if pin exists in this source
    pin_found <- tryCatch(
      pins::pin_exists(src, name),
      error = function(e) FALSE
    )

    if (!pin_found) next

    if (src_name == "drive") {
      # Only hit Drive if offline fallback check passes
      is_online <- tryCatch(gdpins_is_online(), error = function(e) FALSE)
      if (!is_online) {
        cli::cli_warn(c(
          "!" = paste0(
            "Pin {.val {name}} is only available on Drive but no internet ",
            "connection detected."
          ),
          "i" = "Returning NULL."
        ))
        return(NULL)
      }
      read_from_drive <- TRUE
    }

    result <- tryCatch(
      .read_from_board(src, name, version),
      error = function(e) {
        cli::cli_warn(
          "Failed to read pin {.val {name}} from {src_name}: {conditionMessage(e)}"
        )
        NULL
      }
    )

    if (!is.null(result)) {
      result_type <- tryCatch(
        pins::pin_meta(src, name, version = version)$type,
        error = function(e) NA_character_
      )
      break
    }
  }

  if (is.null(result)) {
    cli::cli_abort(c(
      "Pin {.val {name}} not found in any board component.",
      i = "Check that the pin was written before reading."
    ))
  }

  if (is.data.frame(result)) {
    # nanoparquet::read_parquet() (used by pins type "parquet") returns plain
    # data frames rather than tibbles; normalise so parquet reads are still
    # tibbles like before. Leave "rds" reads untouched so arbitrary
    # data-frame subclasses (e.g. base data.frame with row names) round-trip
    # byte-for-byte, as saveRDS()/readRDS() already guarantee.
    if (identical(result_type, "parquet") && !inherits(result, "tbl_df")) {
      result <- tibble::as_tibble(result)
    }

    # Auto-decode sf: if any column matches the __epsg__ pattern, restore sf.
    # wkt_engine = "none" opts out: geometry stays as raw WKT text columns.
    has_geo_cols <- any(grepl("^.*__\\d{4,5}__$", names(result)))
    if (has_geo_cols && !identical(wkt_engine, "none")) {
      result <- gdpins_parquet_to_sf(result, engine = wkt_engine)
    }
  }

  result
}

#' Remove a pin from a gdpins board
#'
#' Deletes `name` from every non-NULL board component (Drive, cache, local).
#' Missing pins are ignored (idempotent no-op).
#'
#' @param board A `gdpins_board` object.
#' @param name Character scalar. Pin name.
#'
#' @return Invisibly `NULL`.
#' @seealso [gdpins_pin_write()], [gdpins_pin_read()], [gdpins_init_board()].
#' @examples
#' adapter <- gdpins_fake_drive()
#' board <- gdpins_init_board(
#'   name       = "data_raw",
#'   drive_path = "my-project/data-raw",
#'   cache_dir  = tempfile("cache_"),
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#' gdpins_pin_write(board, mtcars, "cars")
#' gdpins_pin_remove(board, "cars")
#' @export
gdpins_pin_remove <- function(board, name) {
  if (!inherits(board, "gdpins_board")) {
    cli::cli_abort(c(
      "{.arg board} must be a {.cls gdpins_board}.",
      x = "Got {.cls {class(board)}}."
    ))
  }
  if (!is.character(name) || length(name) != 1L || !nzchar(name)) {
    cli::cli_abort("{.arg name} must be a non-empty character scalar.")
  }

  boards_to_remove <- list(
    drive = board$drive_board,
    cache = board$cache_board,
    local = board$local_board
  )

  for (component in boards_to_remove) {
    if (is.null(component)) next

    exists <- tryCatch(
      pins::pin_exists(component, name),
      error = function(e) FALSE
    )
    if (exists) {
      pins::pin_delete(component, name)
    }
  }

  invisible(NULL)
}
