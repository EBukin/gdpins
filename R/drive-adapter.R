#' Drive adapter — thin seam over googledrive
#'
#' @description
#' All `googledrive`-specific operations are isolated behind this adapter so
#' tests can inject a fake. Every Drive-touching function in the package takes
#' the adapter from the board or connection object and calls the wrappers below
#' — **never** `googledrive::*` directly outside this file.
#'
#' S3 class `gdpins_drive_adapter`: a named list of closures plus `kind`
#' (`"real"` | `"fake"`). Paths are **relative to the adapter's drive root**,
#' "/"-separated (e.g. `"kazLandEconImpact-data/data-raw/parcels.parquet"`).
#'
#' @name drive-adapter
#' @keywords internal
NULL

# ── Constructors ─────────────────────────────────────────────────────────────

#' Create a real Google Drive adapter
#'
#' Wraps `googledrive` functions via Drive-ID-based navigation. Only exercised
#' in the live tier. The root folder is identified by its Drive file ID so the
#' adapter works regardless of the folder's location in My Drive.
#'
#' @param root_id Character scalar. Drive file ID of the project root folder
#'   (e.g. from the folder URL or `googledrive::drive_get("name")$id`).
#'
#' @return An object of class `gdpins_drive_adapter`.
#' @keywords internal
gdpins_real_drive <- function(root_id) {
  stopifnot(is.character(root_id), length(root_id) == 1L)

  # nocov start
  # Lazy root dribble — fetched from Drive on first operation.
  state <- new.env(parent = emptyenv())
  state$root_dribble <- NULL

  .root <- function() {
    if (is.null(state$root_dribble)) {
      d <- googledrive::drive_get(googledrive::as_id(root_id))
      if (nrow(d) == 0L) {
        cli::cli_abort("Drive folder not found for ID: {.val {root_id}}")
      }
      state$root_dribble <- d
    }
    state$root_dribble
  }

  adapter <- list(
    kind      = "real",
    root_id   = root_id,
    root_path = root_id,   # kept for compat; value is the Drive folder ID

    get_id = function(path) {
      drib <- .resolve_real_path(.root(), path)
      if (is.null(drib)) return(NA_character_)
      drib$id[[1L]]
    },

    exists = function(path) {
      !is.null(.resolve_real_path(.root(), path))
    },

    mkdir = function(path) {
      parts <- strsplit(path, "/", fixed = TRUE)[[1L]]
      parts <- parts[nzchar(parts)]
      current <- .root()
      for (part in parts) {
        hits <- tryCatch(
          googledrive::drive_ls(current, pattern = paste0("^", part, "$")),
          error = function(e) NULL
        )
        if (is.null(hits) || nrow(hits) == 0L) {
          current <- googledrive::drive_mkdir(part, path = current)
        } else {
          current <- hits[1L, ]
        }
      }
      invisible(NULL)
    },

    upload = function(local_path, path) {
      dir_part <- dirname(path)
      if (identical(dir_part, ".")) dir_part <- ""
      name_part <- basename(path)
      parent <- if (nzchar(dir_part)) {
        .resolve_real_path(.root(), dir_part)
      } else {
        .root()
      }
      if (is.null(parent)) {
        cli::cli_abort("Drive parent directory not found: {.path {dir_part}}")
      }
      existing <- tryCatch(
        googledrive::drive_ls(parent, pattern = paste0("^", name_part, "$")),
        error = function(e) NULL
      )
      if (!is.null(existing) && nrow(existing) > 0L) {
        googledrive::drive_update(existing[1L, ], media = local_path)
      } else {
        googledrive::drive_upload(local_path, path = parent, name = name_part)
      }
      invisible(NULL)
    },

    download = function(path, local_path) {
      drib <- .resolve_real_path(.root(), path)
      if (is.null(drib)) {
        cli::cli_abort("Drive path not found: {.path {path}}")
      }
      googledrive::drive_download(drib, path = local_path, overwrite = TRUE)
      invisible(local_path)
    },

    trash = function(path) {
      drib <- .resolve_real_path(.root(), path)
      if (!is.null(drib)) {
        googledrive::drive_trash(drib)
      }
      invisible(NULL)
    },

    md5 = function(path) {
      drib <- .resolve_real_path(.root(), path)
      if (is.null(drib)) return(NA_character_)
      m <- drib$drive_resource[[1L]]$md5Checksum
      if (is.null(m)) NA_character_ else as.character(m)
    },

    mtime = function(path) {
      drib <- .resolve_real_path(.root(), path)
      if (is.null(drib)) return(as.POSIXct(NA))
      mt <- drib$drive_resource[[1L]]$modifiedTime
      if (is.null(mt)) as.POSIXct(NA) else as.POSIXct(mt, format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC")
    },

    ls = function(path = "", recursive = FALSE) {
      target <- if (nzchar(path)) .resolve_real_path(.root(), path) else .root()
      if (is.null(target)) {
        return(tibble::tibble(
          path  = character(), is_dir = logical(), size = double(),
          md5   = character(), mtime  = as.POSIXct(character())
        ))
      }
      prefix <- if (nzchar(path)) paste0(path, "/") else ""
      if (recursive) {
        .real_ls_recursive(target, prefix)
      } else {
        hits <- tryCatch(googledrive::drive_ls(target), error = function(e) NULL)
        if (is.null(hits) || nrow(hits) == 0L) {
          return(tibble::tibble(
            path  = character(), is_dir = logical(), size = double(),
            md5   = character(), mtime  = as.POSIXct(character())
          ))
        }
        .real_hits_to_tbl(hits, prefix)
      }
    }
  )

  structure(adapter, class = "gdpins_drive_adapter")
  # nocov end
}

#' Create a fake (tempdir-backed) Drive adapter
#'
#' Simulates Google Drive using the local filesystem. State (including a trash
#' store) is held in a mutable environment so all closures share it. Used as
#' the default test seam — **never hits the network**.
#'
#' `gd_trash()` moves entries to an internal trash store (recoverable). It
#' never calls `unlink()`. `gd_md5()` uses `tools::md5sum()`. `gd_ls()`
#' excludes trashed entries.
#'
#' @param root Character scalar. Root directory for the fake drive. Defaults to
#'   a fresh `tempfile()` path (created on first use).
#'
#' @return An object of class `gdpins_drive_adapter`.
#' @keywords internal
gdpins_fake_drive <- function(root = tempfile("gdpins_fake_drive_")) {
  stopifnot(is.character(root), length(root) == 1L)

  # Mutable state environment shared by all closures
  state <- new.env(parent = emptyenv())
  state$root  <- root
  state$trash <- list()  # list of named elements: key = rel path, val = trash dir entry

  # Ensure root exists
  fs::dir_create(root)

  # Helpers (not exported; live in the closure scope)
  .abs <- function(path) {
    if (!nzchar(path)) return(root)
    file.path(root, gsub("/", .Platform$file.sep, path, fixed = TRUE))
  }

  .rel <- function(abs_path) { # nocov start
    rel <- sub(
      paste0("^", gsub("\\\\", "\\\\\\\\", gsub("/", "[\\\\/]", root, fixed = TRUE)), "[\\\\/]?"),
      "",
      abs_path
    )
    gsub("\\\\", "/", rel)
  } # nocov end

  adapter <- list(
    kind = "fake",
    root = root,
    state = state,  # exposed for test inspection

    exists = function(path) {
      abs <- .abs(path)
      file.exists(abs) && !.is_trashed(state, path)
    },

    mkdir = function(path) {
      abs <- .abs(path)
      fs::dir_create(abs)
      invisible(NULL)
    },

    upload = function(local_path, path) {
      abs <- .abs(path)
      # Ensure parent exists
      fs::dir_create(dirname(abs))
      fs::file_copy(local_path, abs, overwrite = TRUE)
      invisible(NULL)
    },

    download = function(path, local_path) {
      abs <- .abs(path)
      if (!file.exists(abs)) {
        cli::cli_abort("Fake Drive path not found: {.path {path}}")
      }
      if (.is_trashed(state, path)) { # nocov start
        cli::cli_abort("Fake Drive path is in trash: {.path {path}}")
      } # nocov end
      fs::dir_create(dirname(local_path))
      fs::file_copy(abs, local_path, overwrite = TRUE)
      invisible(local_path)
    },

    trash = function(path) {
      abs <- .abs(path)
      if (!file.exists(abs)) {
        return(invisible(NULL))
      }
      # Move to a trash holding area (recoverable)
      trash_key <- path
      trash_dir <- file.path(root, ".gdpins_trash", gsub("[/\\\\]", "_", path))
      fs::dir_create(dirname(trash_dir))
      fs::file_move(abs, trash_dir)
      state$trash[[trash_key]] <- trash_dir
      invisible(NULL)
    },

    md5 = function(path) {
      abs <- .abs(path)
      if (!file.exists(abs) || .is_trashed(state, path) || fs::is_dir(abs)) {
        return(NA_character_)
      }
      unname(tools::md5sum(abs))
    },

    mtime = function(path) {
      abs <- .abs(path)
      if (!file.exists(abs) || .is_trashed(state, path)) {
        return(as.POSIXct(NA))
      }
      file.mtime(abs)
    },

    ls = function(path = "", recursive = FALSE) {
      abs <- .abs(path)
      if (!file.exists(abs)) {
        return(tibble::tibble(
          path  = character(),
          is_dir = logical(),
          size  = double(),
          md5   = character(),
          mtime = as.POSIXct(character())
        ))
      }

      if (recursive) {
        all_paths <- fs::dir_ls(abs, recurse = TRUE, all = FALSE)
      } else {
        all_paths <- fs::dir_ls(abs, recurse = FALSE, all = FALSE)
      }

      # Exclude .gdpins_trash directory entries
      all_paths <- all_paths[!grepl(".gdpins_trash", all_paths, fixed = TRUE)]

      if (length(all_paths) == 0L) {
        return(tibble::tibble(
          path  = character(),
          is_dir = logical(),
          size  = double(),
          md5   = character(),
          mtime = as.POSIXct(character())
        ))
      }

      rel_paths <- vapply(all_paths, function(p) {
        r <- sub(paste0("^", gsub("([\\^$.|?*+(){}\\[\\]\\\\])", "\\\\\\1", root), "[\\\\/]?"), "", p)
        gsub("\\\\", "/", r)
      }, character(1L), USE.NAMES = FALSE)

      # Exclude trashed paths
      trashed_keys <- names(state$trash)
      keep <- vapply(rel_paths, function(rp) {
        !any(vapply(trashed_keys, function(tk) startsWith(rp, tk), logical(1L)))
      }, logical(1L))

      rel_paths <- rel_paths[keep]
      abs_paths  <- as.character(all_paths)[keep]

      if (length(rel_paths) == 0L) { # nocov start
        return(tibble::tibble(
          path  = character(),
          is_dir = logical(),
          size  = double(),
          md5   = character(),
          mtime = as.POSIXct(character())
        ))
      } # nocov end

      is_dir <- fs::is_dir(abs_paths)
      size   <- vapply(abs_paths, function(p) {
        if (fs::is_dir(p)) 0 else as.double(file.size(p))
      }, double(1L), USE.NAMES = FALSE)
      md5 <- vapply(abs_paths, function(p) {
        if (fs::is_dir(p)) NA_character_ else unname(tools::md5sum(p))
      }, character(1L), USE.NAMES = FALSE)
      mtime <- file.mtime(abs_paths)

      tibble::tibble(
        path  = rel_paths,
        is_dir = is_dir,
        size  = size,
        md5   = md5,
        mtime = mtime
      )
    }
  )

  structure(adapter, class = "gdpins_drive_adapter")
}

# ── Wrapper functions ─────────────────────────────────────────────────────────
# These are the ONLY way the rest of the package talks to Drive.

#' Check if a path exists on Drive
#'
#' @param adapter A `gdpins_drive_adapter` object.
#' @param path Character scalar. Path relative to the adapter root.
#'
#' @return Logical scalar.
#' @keywords internal
gd_exists <- function(adapter, path) {
  adapter$exists(path)
}

#' Create a directory (and parents) on Drive, idempotent
#'
#' @param adapter A `gdpins_drive_adapter` object.
#' @param path Character scalar. Path relative to the adapter root.
#'
#' @return `invisible(adapter)`.
#' @keywords internal
gd_mkdir <- function(adapter, path) {
  adapter$mkdir(path)
  invisible(adapter)
}

#' Upload a local file to Drive
#'
#' @param adapter A `gdpins_drive_adapter` object.
#' @param local_path Character scalar. Path to the local source file.
#' @param path Character scalar. Destination path relative to the adapter root.
#'
#' @return `invisible(adapter)`.
#' @keywords internal
gd_upload <- function(adapter, local_path, path) {
  adapter$upload(local_path, path)
  invisible(adapter)
}

#' Download a Drive file to a local path
#'
#' @param adapter A `gdpins_drive_adapter` object.
#' @param path Character scalar. Source path relative to the adapter root.
#' @param local_path Character scalar. Destination local path.
#'
#' @return `invisible(local_path)`.
#' @keywords internal
gd_download <- function(adapter, path, local_path) {
  adapter$download(path, local_path)
  invisible(local_path)
}

#' Trash a Drive path (recoverable, never hard-deletes)
#'
#' @param adapter A `gdpins_drive_adapter` object.
#' @param path Character scalar. Path relative to the adapter root.
#'
#' @return `invisible(adapter)`.
#' @keywords internal
gd_trash <- function(adapter, path) {
  adapter$trash(path)
  invisible(adapter)
}

#' Return MD5 checksum of a Drive file
#'
#' @param adapter A `gdpins_drive_adapter` object.
#' @param path Character scalar. Path relative to the adapter root.
#'
#' @return Character scalar MD5, or `NA_character_` if absent or a directory.
#' @keywords internal
gd_md5 <- function(adapter, path) {
  adapter$md5(path)
}

#' Return modification time of a Drive path
#'
#' @param adapter A `gdpins_drive_adapter` object.
#' @param path Character scalar. Path relative to the adapter root.
#'
#' @return `POSIXct` scalar, or `NA` if absent.
#' @keywords internal
gd_mtime <- function(adapter, path) {
  adapter$mtime(path)
}

#' List contents of a Drive directory
#'
#' @param adapter A `gdpins_drive_adapter` object.
#' @param path Character scalar. Path relative to the adapter root. Default
#'   `""` lists the root.
#' @param recursive Logical. Recurse into sub-directories? Default `FALSE`.
#'
#' @return A [tibble::tibble()] with columns `path` (chr, relative),
#'   `is_dir` (lgl), `size` (dbl, bytes), `md5` (chr), `mtime` (POSIXct).
#'   Trashed entries are excluded.
#' @keywords internal
gd_ls <- function(adapter, path = "", recursive = FALSE) {
  adapter$ls(path, recursive)
}

# ── Internal helpers ──────────────────────────────────────────────────────────

#' Walk path segments from root_dribble; return the final dribble or NULL
#' @keywords internal
.resolve_real_path <- function(root_dribble, path) {
  # nocov start
  parts <- strsplit(path, "/", fixed = TRUE)[[1L]]
  parts <- parts[nzchar(parts)]
  if (length(parts) == 0L) return(root_dribble)
  current <- root_dribble
  for (part in parts) {
    hits <- tryCatch(
      googledrive::drive_ls(current, pattern = paste0("^", part, "$")),
      error = function(e) NULL
    )
    if (is.null(hits) || nrow(hits) == 0L) return(NULL)
    current <- hits[1L, ]
  }
  current
  # nocov end
}

#' Convert a drive_ls dribble to the standard adapter tibble with a path prefix
#' @keywords internal
.real_hits_to_tbl <- function(hits, prefix = "") {
  # nocov start
  tibble::tibble(
    path  = paste0(prefix, as.character(hits$name)),
    is_dir = vapply(
      hits$drive_resource,
      function(r) identical(r$mimeType, "application/vnd.google-apps.folder"),
      logical(1L)
    ),
    size  = vapply(
      hits$drive_resource,
      function(r) { s <- r$size; if (is.null(s)) 0 else as.double(s) },
      double(1L)
    ),
    md5   = vapply(
      hits$drive_resource,
      function(r) { m <- r$md5Checksum; if (is.null(m)) NA_character_ else as.character(m) },
      character(1L)
    ),
    mtime = as.POSIXct(vapply(
      hits$drive_resource,
      function(r) { mt <- r$modifiedTime; if (is.null(mt)) NA_character_ else as.character(mt) },
      character(1L)
    ), format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC")
  )
  # nocov end
}

#' Recursively list a Drive folder; returns root-relative paths under prefix
#' @keywords internal
.real_ls_recursive <- function(folder_dribble, prefix = "") {
  # nocov start
  hits <- tryCatch(googledrive::drive_ls(folder_dribble), error = function(e) NULL)
  if (is.null(hits) || nrow(hits) == 0L) {
    return(tibble::tibble(
      path  = character(), is_dir = logical(), size = double(),
      md5   = character(), mtime  = as.POSIXct(character())
    ))
  }
  tbl <- .real_hits_to_tbl(hits, prefix)
  dirs_idx <- which(tbl$is_dir)
  if (length(dirs_idx) == 0L) return(tbl)
  sub_tbls <- lapply(dirs_idx, function(i) {
    .real_ls_recursive(hits[i, ], prefix = paste0(tbl$path[i], "/"))
  })
  do.call(rbind, c(list(tbl), sub_tbls))
  # nocov end
}

#' @keywords internal
.is_trashed <- function(state, path) {
  isTRUE(path %in% names(state$trash))
}
