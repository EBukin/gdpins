#' Raw-exogenous connection
#'
#' Plain-file interface for data as received from external APIs or sources.
#' No pins metadata layer — files are stored verbatim or serialised from R
#' objects. Drive path is the truth; a local directory mirrors it.
#'
#' @name raw-connection
NULL

# ── Legal values ──────────────────────────────────────────────────────────────

.ON_DISCREPANCY_VALUES <- c("prompt", "warn", "sync_from_drive",
                             "sync_to_drive", "ignore")

# ── Mockable shims (WS4-internal) ─────────────────────────────────────────────

# Thin wrappers around base functions.
# - GDPINS_RAW_INTERACTIVE env var overrides interactive() for testing.
# - GDPINS_RAW_READLINE    env var overrides readline() for testing.
.raw_is_interactive <- function() {
  override <- Sys.getenv("GDPINS_RAW_INTERACTIVE", unset = "")
  if (nzchar(override)) return(override == "TRUE")
  interactive()
}

.raw_readline <- function(prompt) {
  override <- Sys.getenv("GDPINS_RAW_READLINE", unset = "")
  if (nzchar(override)) return(override)
  readline(prompt)
}

# ── Internal helpers ──────────────────────────────────────────────────────────

# Resolve on_discrepancy to a concrete value (never NULL at runtime)
.resolve_on_discrepancy <- function(on_discrepancy) {
  if (!is.null(on_discrepancy)) {
    legal <- .ON_DISCREPANCY_VALUES
    if (!on_discrepancy %in% legal) {
      cli::cli_abort(c(
        "{.arg on_discrepancy} must be one of {.val {(legal)}}.",
        x = "Got {.val {on_discrepancy}}."
      ))
    }
    return(on_discrepancy)
  }
  if (.raw_is_interactive()) "prompt" else "warn"
}

# Derive the extension from a name (lowercase, with dot)
.raw_ext <- function(name) {
  ext <- tolower(tools::file_ext(name))
  if (!nzchar(ext)) return("")
  paste0(".", ext)
}

# Validate that extension is supported (abort on unknown)
.check_ext <- function(name) {
  ext <- .raw_ext(name)
  supported <- c(".rds", ".parquet", ".geojson", ".csv")
  if (!ext %in% supported) {
    cli::cli_abort(c(
      "Unsupported file extension {.val {ext}} in {.val {name}}.",
      i = "Supported extensions: {.val {supported}}."
    ))
  }
  ext
}

# Serialise x to a temp file using the writer for ext; return temp path
.raw_write_tmp <- function(x, name) {
  ext  <- .check_ext(name)
  tmp  <- tempfile(fileext = ext)

  switch(
    ext,
    ".rds"     = saveRDS(x, tmp),
    ".parquet" = {
      if (inherits(x, "sf")) {
        encoded <- gdpins_sf_to_parquet(x)
        arrow::write_parquet(encoded, tmp)
      } else {
        arrow::write_parquet(x, tmp)
      }
    },
    ".geojson" = sf::st_write(x, tmp, quiet = TRUE),
    ".csv"     = readr::write_csv(x, tmp)
  )

  tmp
}

# Read from a local file path using the reader for the extension
.raw_read_local <- function(local_file) {
  ext <- .raw_ext(local_file)
  .check_ext(local_file)  # errors on unknown

  switch(
    ext,
    ".rds"     = readRDS(local_file),
    ".parquet" = {
      tbl <- arrow::read_parquet(local_file)
      # Route through gdpins_parquet_to_sf if encoded geometry columns present
      gdpins_parquet_to_sf(tbl)
    },
    ".geojson" = sf::st_read(local_file, quiet = TRUE),
    ".csv"     = readr::read_csv(local_file, show_col_types = FALSE)
  )
}

# Build the full Drive path for a name relative to conn$drive_path
.drive_full_path <- function(conn, name) {
  paste0(conn$drive_path, "/", name)
}

# Build the full local path for a name relative to conn$local_path
.local_full_path <- function(conn, name) {
  file.path(conn$local_path, gsub("/", .Platform$file.sep, name, fixed = TRUE))
}

# Normalise paths returned by gd_ls (may be absolute on Windows fake adapter)
# Strips the adapter root prefix + drive_path prefix to get names relative to
# drive_path. Returns a character vector of "/" separated relative names.
.gd_ls_to_rel <- function(paths, adapter, drive_path) {
  if (length(paths) == 0L) return(character(0L))

  # Strip adapter root if present (fake adapter on Windows returns abs paths)
  adapter_root <- if (!is.null(adapter$root)) adapter$root else ""
  if (nzchar(adapter_root)) {
    # Normalise separators
    adapter_root_norm <- gsub("\\\\", "/", normalizePath(adapter_root, mustWork = FALSE))
    paths <- gsub("\\\\", "/", paths)
    paths <- sub(paste0("^", gsub("([.^$|?*+(){}\\[\\]\\\\])", "\\\\\\1",
                                  adapter_root_norm), "/?"), "", paths)
  }

  # Now strip drive_path prefix if present
  prefix <- paste0(drive_path, "/")
  paths  <- sub(paste0("^", prefix), "", paths)

  paths
}

# ── gdpins_raw_connect ────────────────────────────────────────────────────────

#' Connect to a raw-exogenous Drive folder
#'
#' Creates a `gdpins_raw_conn` object pointing at a Drive raw-root and its
#' local mirror. On connect, checks for sync discrepancies and whether the
#' Drive folder exists (controlled by `create` and `on_discrepancy`).
#'
#' @param drive_path Character scalar. Drive raw-root path (relative to the
#'   adapter root), or `NULL` for `"local_only"`.
#' @param local_path Character scalar. Local mirror directory path.
#' @param create Logical or `NA`. Controls Drive folder creation: `TRUE` =
#'   create if absent; `FALSE` = error if absent; `NA` = interactive prompt.
#' @param on_discrepancy Character scalar or `NULL`. One of
#'   `c("prompt","warn","sync_from_drive","sync_to_drive","ignore")`. `NULL`
#'   resolves at runtime.
#' @param adapter A `gdpins_drive_adapter`, or `NULL` for `"local_only"`.
#'
#' @return A `gdpins_raw_conn` object.
#' @export
gdpins_raw_connect <- function(
    drive_path,
    local_path,
    create         = NA,
    on_discrepancy = NULL,
    adapter        = NULL
) {
  # Validate local_path
  if (!is.character(local_path) || length(local_path) != 1L || !nzchar(local_path)) {
    cli::cli_abort("{.arg local_path} must be a non-empty character scalar.")
  }

  # Resolve on_discrepancy
  disc <- .resolve_on_discrepancy(on_discrepancy)

  # Determine config
  if (is.null(adapter)) {
    # local_only: no Drive interaction
    fs::dir_create(local_path)
    return(new_gdpins_raw_conn(
      config     = "local_only",
      local_path = local_path
    ))
  }

  # drive_local: validate drive_path
  if (is.null(drive_path) || !is.character(drive_path) ||
      length(drive_path) != 1L || !nzchar(drive_path)) {
    cli::cli_abort(
      "{.arg drive_path} must be a non-empty character scalar when {.arg adapter} is provided."
    )
  }

  # Create-confirm logic for Drive folder
  drive_exists <- gd_exists(adapter, drive_path)

  if (!drive_exists) {
    if (isTRUE(create)) {
      gd_mkdir(adapter, drive_path)
    } else if (isFALSE(create)) {
      cli::cli_abort(c(
        "Drive path {.val {drive_path}} does not exist.",
        i = "Set {.code create = TRUE} to create it."
      ))
    } else {
      # create = NA: prompt if interactive, else error
      if (.raw_is_interactive()) {
        answer <- .raw_readline(
          paste0("Drive path '", drive_path, "' not found. Create? [y/N] ")
        )
        if (tolower(trimws(answer)) == "y") {
          gd_mkdir(adapter, drive_path)
        } else {
          cli::cli_abort(
            "Drive path {.val {drive_path}} does not exist and creation was declined."
          )
        }
      } else {
        cli::cli_abort(c(
          "Drive path {.val {drive_path}} does not exist.",
          i = "Set {.code create = TRUE} to create it, or run interactively to be prompted."
        ))
      }
    }
  }

  # Ensure local mirror exists
  fs::dir_create(local_path)

  # Init-time sync check: compare Drive vs local
  drive_listing <- gd_ls(adapter, drive_path, recursive = TRUE)
  drive_all_rel <- .gd_ls_to_rel(drive_listing$path, adapter, drive_path)
  drive_files   <- drive_all_rel[!drive_listing$is_dir]

  # Local files (relative to local_path, "/" separated)
  local_abs <- fs::dir_ls(local_path, recurse = TRUE, type = "file", all = FALSE)
  local_rel <- if (length(local_abs) == 0L) {
    character(0L)
  } else {
    root_norm <- gsub("\\\\", "/",
                      normalizePath(local_path, mustWork = FALSE))
    vapply(as.character(local_abs), function(p) {
      p_norm <- gsub("\\\\", "/", normalizePath(p, mustWork = FALSE))
      rel    <- sub(paste0("^", gsub("([.^$|?*+(){}\\[\\]\\\\])", "\\\\\\1",
                                     root_norm), "/?"), "", p_norm)
      rel
    }, character(1L), USE.NAMES = FALSE)
  }

  has_discrepancy <- !setequal(drive_files, local_rel)

  if (has_discrepancy) {
    switch(
      disc,
      "prompt" = {
        if (.raw_is_interactive()) {
          cli::cli_alert_warning(
            "Drive and local mirror differ for {.val {drive_path}}."
          )
          answer <- .raw_readline("Sync from Drive? [y/N] ")
          if (tolower(trimws(answer)) == "y") {
            for (f in drive_files) {
              local_dest <- file.path(local_path,
                                      gsub("/", .Platform$file.sep, f, fixed = TRUE))
              fs::dir_create(dirname(local_dest))
              gd_download(adapter, paste0(drive_path, "/", f), local_dest)
            }
          }
        } else {
          cli::cli_warn(
            "Drive and local mirror differ for {.val {drive_path}}. Run interactively to sync."
          )
        }
      },
      "warn" = {
        cli::cli_warn(
          "Drive and local mirror differ for {.val {drive_path}}."
        )
      },
      "sync_from_drive" = {
        for (f in drive_files) {
          local_dest <- file.path(local_path,
                                  gsub("/", .Platform$file.sep, f, fixed = TRUE))
          fs::dir_create(dirname(local_dest))
          gd_download(adapter, paste0(drive_path, "/", f), local_dest)
        }
      },
      "sync_to_drive" = {
        for (f in local_rel) {
          local_src  <- file.path(local_path,
                                  gsub("/", .Platform$file.sep, f, fixed = TRUE))
          drive_dest <- paste0(drive_path, "/", f)
          gd_upload(adapter, local_src, drive_dest)
        }
      },
      "ignore" = {
        # do nothing
      }
    )
  }

  new_gdpins_raw_conn(
    config     = "drive_local",
    drive_path = drive_path,
    local_path = local_path,
    adapter    = adapter
  )
}

# ── gdpins_raw_put_object ─────────────────────────────────────────────────────

#' Write an R object to a raw connection
#'
#' Serialises `x` to a temp file using the appropriate writer for the extension
#' in `name`, then deposits it to Drive and mirrors locally.
#'
#' @param conn A `gdpins_raw_conn` object.
#' @param x An R object.
#' @param name Character scalar. Relative path within the raw-root, including
#'   extension (e.g. `"worldbank-api/gdp_2024.parquet"`).
#'
#' @return Invisibly `NULL`.
#' @export
gdpins_raw_put_object <- function(conn, x, name) {
  .check_ext(name)

  tmp        <- .raw_write_tmp(x, name)
  on.exit(unlink(tmp), add = TRUE)

  local_dest <- .local_full_path(conn, name)
  fs::dir_create(dirname(local_dest))
  fs::file_copy(tmp, local_dest, overwrite = TRUE)

  if (!is.null(conn$adapter)) {
    drive_dest <- .drive_full_path(conn, name)
    gd_upload(conn$adapter, local_dest, drive_dest)
  }

  invisible(NULL)
}

# ── gdpins_raw_put_file ───────────────────────────────────────────────────────

#' Upload a file verbatim to a raw connection
#'
#' Copies a local file byte-for-byte to Drive and mirrors locally. No R
#' round-trip, no coercion — byte-faithful upload.
#'
#' @param conn A `gdpins_raw_conn` object.
#' @param path Character scalar. Path to the local source file.
#' @param name Character scalar. Relative destination path within the raw-root.
#'
#' @return Invisibly `NULL`.
#' @export
gdpins_raw_put_file <- function(conn, path, name) {
  if (!file.exists(path)) {
    cli::cli_abort("Source file not found: {.path {path}}")
  }

  local_dest <- .local_full_path(conn, name)
  fs::dir_create(dirname(local_dest))
  fs::file_copy(path, local_dest, overwrite = TRUE)

  if (!is.null(conn$adapter)) {
    drive_dest <- .drive_full_path(conn, name)
    gd_upload(conn$adapter, local_dest, drive_dest)
  }

  invisible(NULL)
}

# ── gdpins_raw_get ────────────────────────────────────────────────────────────

#' Read a file from a raw connection
#'
#' Reads a file from the local mirror by default. Set `force_refresh = TRUE` to
#' re-pull from Drive first.
#'
#' @param conn A `gdpins_raw_conn` object.
#' @param name Character scalar. Relative path within the raw-root.
#' @param force_refresh Logical. `TRUE` re-pulls from Drive before reading.
#'   Default `FALSE`.
#'
#' @return The deserialised R object.
#' @export
gdpins_raw_get <- function(conn, name, force_refresh = FALSE) {
  local_file <- .local_full_path(conn, name)

  if (isTRUE(force_refresh) && !is.null(conn$adapter)) {
    drive_src  <- .drive_full_path(conn, name)
    fs::dir_create(dirname(local_file))
    gd_download(conn$adapter, drive_src, local_file)
  }

  if (!file.exists(local_file)) {
    cli::cli_abort(c(
      "Local file not found: {.path {local_file}}",
      i = "Use {.code force_refresh = TRUE} to pull from Drive first."
    ))
  }

  .raw_read_local(local_file)
}

# ── gdpins_raw_ls ─────────────────────────────────────────────────────────────

#' List contents of a raw connection
#'
#' Returns a compact folder tree for the raw connection, defaulting to 2 levels
#' of depth.
#'
#' @param conn A `gdpins_raw_conn` object.
#' @param depth Integer scalar. Maximum directory depth to display. Default `2`.
#'
#' @return A [tibble::tibble()] describing the folder tree.
#' @export
gdpins_raw_ls <- function(conn, depth = 2) {
  empty <- tibble::tibble(
    name   = character(),
    is_dir = logical(),
    size   = double(),
    mtime  = as.POSIXct(character()),
    depth  = integer()
  )

  if (!is.null(conn$adapter)) {
    # Drive-backed: use gd_ls with recursive = TRUE then filter by depth
    listing <- gd_ls(conn$adapter, conn$drive_path, recursive = TRUE)
    if (nrow(listing) == 0L) return(empty)

    # Normalise absolute paths returned by the fake adapter
    rel_path <- .gd_ls_to_rel(listing$path, conn$adapter, conn$drive_path)

    # Compute depth (number of path components)
    entry_depth <- vapply(rel_path, function(p) {
      length(strsplit(p, "/", fixed = TRUE)[[1L]])
    }, integer(1L), USE.NAMES = FALSE)

    # Filter by depth
    keep        <- entry_depth <= depth
    rel_path    <- rel_path[keep]
    entry_depth <- entry_depth[keep]
    listing     <- listing[keep, , drop = FALSE]

    tibble::tibble(
      name   = rel_path,
      is_dir = listing$is_dir,
      size   = listing$size,
      mtime  = listing$mtime,
      depth  = entry_depth
    )
  } else {
    # local_only
    abs_paths <- fs::dir_ls(conn$local_path, recurse = TRUE, all = FALSE)

    if (length(abs_paths) == 0L) return(empty)

    root_norm <- gsub("\\\\", "/",
                      normalizePath(conn$local_path, mustWork = FALSE))
    rel_paths <- vapply(as.character(abs_paths), function(p) {
      p_norm <- gsub("\\\\", "/", normalizePath(p, mustWork = FALSE))
      rel    <- sub(paste0("^", gsub("([.^$|?*+(){}\\[\\]\\\\])", "\\\\\\1",
                                     root_norm), "/?"), "", p_norm)
      rel
    }, character(1L), USE.NAMES = FALSE)

    entry_depth <- vapply(rel_paths, function(p) {
      length(strsplit(p, "/", fixed = TRUE)[[1L]])
    }, integer(1L), USE.NAMES = FALSE)

    keep     <- entry_depth <= depth
    abs_keep <- as.character(abs_paths)[keep]
    rel_keep <- rel_paths[keep]
    dep_keep <- entry_depth[keep]

    tibble::tibble(
      name   = rel_keep,
      is_dir = fs::is_dir(abs_keep),
      size   = vapply(abs_keep, function(p) {
        if (fs::is_dir(p)) 0 else as.double(file.size(p))
      }, double(1L), USE.NAMES = FALSE),
      mtime  = file.mtime(abs_keep),
      depth  = dep_keep
    )
  }
}

# ── gdpins_refresh_disconnect ─────────────────────────────────────────────────

#' Force-refresh a raw connection and disconnect
#'
#' Pulls all files from Drive to the local mirror, then invalidates the
#' connection object.
#'
#' @param conn A `gdpins_raw_conn` object.
#'
#' @return Invisibly `NULL`.
#' @export
gdpins_refresh_disconnect <- function(conn) {
  if (!is.null(conn$adapter)) {
    listing     <- gd_ls(conn$adapter, conn$drive_path, recursive = TRUE)
    all_rel     <- .gd_ls_to_rel(listing$path, conn$adapter, conn$drive_path)
    drive_files <- all_rel[!listing$is_dir]

    for (rel in drive_files) {
      local_dest <- .local_full_path(conn, rel)
      fs::dir_create(dirname(local_dest))
      gd_download(conn$adapter, paste0(conn$drive_path, "/", rel), local_dest)
    }
  }

  invisible(NULL)
}

# ── S3 methods ────────────────────────────────────────────────────────────────

# Truncate a path string to fit within max_width characters
.truncate_path <- function(path, max_width = 60L) {
  if (nchar(path) <= max_width) return(path)
  paste0("...", substr(path, nchar(path) - max_width + 4L, nchar(path)))
}

#' @export
#' @exportS3Method format gdpins_raw_conn
format.gdpins_raw_conn <- function(x, ...) {
  config_lbl <- if (x$config == "drive_local") "drive+local" else "local only"
  local_disp <- .truncate_path(x$local_path, 55L)
  lines <- c(
    paste0("<gdpins_raw_conn> [", config_lbl, "]"),
    paste0("  local: ", local_disp)
  )
  if (!is.null(x$drive_path)) {
    drive_disp <- .truncate_path(x$drive_path, 55L)
    lines <- c(lines, paste0("  drive: ", drive_disp))
  }
  paste(lines, collapse = "\n")
}

#' @export
#' @exportS3Method print gdpins_raw_conn
print.gdpins_raw_conn <- function(x, ...) {
  cat(format(x, ...), "\n", sep = "")
  invisible(x)
}

#' @export
#' @exportS3Method summary gdpins_raw_conn
summary.gdpins_raw_conn <- function(object, ...) {
  config_lbl <- if (object$config == "drive_local") "drive+local" else "local only"
  cli::cli_text("<gdpins_raw_conn> [{config_lbl}]")
  gd_cli_kv(local = object$local_path)
  if (!is.null(object$drive_path)) {
    gd_cli_kv(drive = object$drive_path)
  }
  gd_cli_kv(config = object$config)

  # Count local files
  local_files <- tryCatch(
    length(fs::dir_ls(object$local_path, recurse = TRUE, type = "file")),
    error = function(e) NA_integer_
  )
  gd_cli_kv(files = if (is.na(local_files)) "?" else as.character(local_files))

  invisible(object)
}
