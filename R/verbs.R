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
gdpins_pin_write <- function(board, x, name, version = NULL, format = NULL) {
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
    gdpins_sf_to_parquet(x)
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
#' @export
gdpins_pin_read <- function(board, name, version = NULL) {
  if (!inherits(board, "gdpins_board")) {
    cli::cli_abort(c(
      "{.arg board} must be a {.cls gdpins_board}.",
      x = "Got {.cls {class(board)}}."
    ))
  }
  if (!is.character(name) || length(name) != 1L || !nzchar(name)) {
    cli::cli_abort("{.arg name} must be a non-empty character scalar.")
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

    # Auto-decode sf: if any column matches the __epsg__ pattern, restore sf
    has_geo_cols <- any(grepl("^.*__\\d{4,5}__$", names(result)))
    if (has_geo_cols) {
      result <- gdpins_parquet_to_sf(result)
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
