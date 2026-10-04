#' Synchronisation engine
#'
#' User-invokable sync between Drive and local. Never automatic -- the user
#' decides when to synchronise. Conflict resolution:
#' - Versioned boards: both writes become versions (no loss).
#' - Raw / unversioned: interactive prompt or stop + report.
#'
#' @name sync
NULL

# -- Status engine (shared by init_board/WS3 via gdpins_board_status) ----------

#' Report sync status of a board or raw connection
#'
#' Returns a per-pin/per-file tibble describing drift between Drive and local.
#' Dispatches on the class of `x`:
#'
#' - **`gdpins_board`**: compares the latest version's hash between the Drive
#'   board and the board's one local copy (`local_board`).
#' - **`gdpins_raw_conn`**: compares MD5 checksums between the Drive folder and
#'   the local mirror directory.
#'
#' Differing content is classified against the last-synced baseline (one side
#' changed: that side is ahead; both changed: `"conflict"`), or by
#' timestamp when there is no baseline entry. See the "Sync rules" section of
#' [gdpins_sync()].
#'
#' If `!gdpins_is_online()`, all rows are set to `state = "offline"` and a
#' warning is emitted. No Drive calls are made offline.
#'
#' @param x A `gdpins_board` or `gdpins_raw_conn` object.
#'
#' @return A [tibble::tibble()] with at least columns:
#'   - `name` -- pin/file name (character).
#'   - `state` -- one of `"in_sync"`, `"local_ahead"`, `"drive_ahead"`,
#'     `"conflict"`, `"offline"` (character).
#'   - Additional signal columns differ by object type (see Details).
#'
#' @details
#' **Board signal columns**: `drive_version`, `local_version`, `drive_created`,
#' `local_created`, `drive_hash`, `local_hash`.
#'
#' **Raw connection signal columns**: `drive_md5`, `local_md5`, `drive_mtime`,
#' `local_mtime`.
#'
#' @seealso [gdpins_real_drive()] to create an adapter, [gdpins_init_board()]
#'   and [gdpins_raw_connect()] to create boards/connections,
#'   [gdpins_go_offline()]/[gdpins_go_online()] to temporarily detach a board
#'   or connection from Drive and reconcile it later.
#' @examples
#' # --- Fake adapter board ---
#' adapter <- gdpins_fake_drive()
#' board <- gdpins_init_board(
#'   name       = "data_raw",
#'   drive_path = "my-project/data-raw",
#'   cache_dir  = tempfile("cache_"),
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#' gdpins_board_status(board)
#'
#' # --- Real adapter ---
#' \dontrun{
#' adapter <- gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")
#' board   <- gdpins_init_board(
#'   name       = "data_raw",
#'   drive_path = "my-project/data-raw",
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#' gdpins_board_status(board)
#' }
#' @export
gdpins_board_status <- function(x) {
  UseMethod("gdpins_board_status")
}

#' @export
gdpins_board_status.gdpins_board <- function(x) {
  .board_status_board(x)
}

#' @export
gdpins_board_status.gdpins_raw_conn <- function(x) {
  .board_status_raw(x)
}

#' @export
gdpins_board_status.default <- function(x) {
  cli::cli_abort(c(
    "{.fn gdpins_board_status} requires a {.cls gdpins_board} or {.cls gdpins_raw_conn}.",
    x = "Got {.cls {class(x)[[1L]]}}."
  ))
}

# -- gdpins_sync ---------------------------------------------------------------

#' Synchronise a board or raw connection with Drive
#'
#' Reconciles Drive and local copies bidirectionally. Direction defaults to
#' `"auto"` (the side that changed since the last sync wins). Conflict
#' handling is controlled by `on_conflict`. See "Sync rules" for how each pin
#' or file is classified.
#'
#' @section Sync rules:
#' Each pin (board) or file (raw connection) is compared by content: the
#' latest version's hash for pins, the MD5 checksum for raw files. Equal
#' content is `"in_sync"`. A pin or file present on one side only is ahead on
#' that side.
#'
#' When the content differs, gdpins compares each side with the
#' **last-synced baseline**: what each side held the last time gdpins saw
#' both sides agree. The baseline is recorded by [gdpins_pin_write()],
#' [gdpins_raw_put_object()], [gdpins_raw_put_file()], the connect-time sync
#' of [gdpins_raw_connect()], and by every `gdpins_sync()` for each pin or
#' file it copied, resolved or found in sync.
#' - Only Drive changed since the baseline: `"drive_ahead"`.
#' - Only local changed: `"local_ahead"`.
#' - Both changed: `"conflict"`, whatever the timestamps say, so an edit on
#'   one side is never silently replaced by an edit on the other.
#'
#' Without a baseline entry (pins or files written outside gdpins, or before
#' this rule existed) the newer side wins: pins version `created` time for
#' boards, modification time for raw files; equal or missing times are a
#' conflict. The first `gdpins_sync()` records a baseline for every pin or
#' file it leaves in sync.
#'
#' The baseline is local and owned by gdpins: `<cache_dir>/.gdpins-sync.rds`
#' for a board (invisible to pins), and a file under
#' `getOption("gdpins.cache_dir")` for a raw connection (never inside
#' `local_path`). [gdpins_pin_remove()] and [gdpins_raw_remove()] drop the
#' entry. A missing baseline file means "no baseline"; an unreadable one
#' raises a warning of class `gdpins_warning_baseline_unreadable` and is
#' replaced on the next sync. Boards without a local copy or without Drive,
#' and local-only raw connections, have no baseline.
#'
#' **Conflict handling** (a conflict is a pin or file that differs on both
#' sides with no clear newer side):
#' - Versioned boards: both contents become versions on **both** boards,
#'   with their title, description and metadata. The content with the later
#'   `created` time (tie: Drive) is the latest version on both boards, so the
#'   pin is in sync afterwards. `on_conflict` is ignored.
#' - Unversioned boards: a board with one slot per pin cannot keep both
#'   sides. `"version"` and `"stop"` leave conflicting pins unchanged, copy
#'   the non-conflicting ones, and then abort with an error of class
#'   `gdpins_error_sync_conflict` (plus `gdpins_error_unversioned_conflict`
#'   for `"version"`). `"prompt"` asks which side to keep.
#' - Raw connections with `"version"` (default): the local file is copied to
#'   `<name>.conflict-<UTC timestamp>.<ext>` next to it, then the Drive copy
#'   replaces it, with a warning of class
#'   `gdpins_warning_raw_conflict_backup`. The backup is a normal file in
#'   `local_path`: the next sync uploads it unless you delete it. `"stop"`
#'   aborts (class `gdpins_error_sync_conflict`) and changes no conflicting
#'   file; `"prompt"` asks per file.
#' - **Never silent overwrite.**
#'
#' Writes and syncs are blocked when offline (`gdpins_is_online()` is
#' `FALSE`). An informative error is raised.
#'
#' @param x A `gdpins_board` or `gdpins_raw_conn` object.
#' @param direction Character scalar. One of `c("auto", "to_drive",
#'   "from_drive")`. Default `"auto"`.
#' @param on_conflict Character scalar. One of `c("version", "prompt",
#'   "stop")`. Default `"version"`: keep both sides as versions on a
#'   versioned board, back up the local file and keep Drive's on a raw
#'   connection, and stop (like `"stop"`) on an unversioned board. See
#'   "Conflict handling" above.
#'
#' @return Invisibly `x`. Called for its side effect.
#' @seealso [gdpins_real_drive()], [gdpins_init_board()],
#'   [gdpins_raw_connect()], [gdpins_go_offline()]/[gdpins_go_online()].
#' @examples
#' # --- Fake adapter board ---
#' adapter <- gdpins_fake_drive()
#' board <- gdpins_init_board(
#'   name       = "data_raw",
#'   drive_path = "my-project/data-raw",
#'   cache_dir  = tempfile("cache_"),
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#' gdpins_sync(board)
#'
#' \dontrun{
#' adapter <- gdpins_real_drive("1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms")
#' board   <- gdpins_init_board(
#'   name       = "data_raw",
#'   drive_path = "my-project/data-raw",
#'   adapter    = adapter,
#'   create     = TRUE
#' )
#' gdpins_sync(board, direction = "from_drive")
#' }
#' @export
gdpins_sync <- function(
    x,
    direction   = c("auto", "to_drive", "from_drive"),
    on_conflict = c("version", "prompt", "stop")
) {
  direction   <- match.arg(direction)
  on_conflict <- match.arg(on_conflict)
  UseMethod("gdpins_sync")
}

#' @export
gdpins_sync.gdpins_board <- function(
    x,
    direction   = c("auto", "to_drive", "from_drive"),
    on_conflict = c("version", "prompt", "stop")
) {
  direction   <- match.arg(direction)
  on_conflict <- match.arg(on_conflict)
  .sync_board(x, direction = direction, on_conflict = on_conflict)
}

#' @export
gdpins_sync.gdpins_raw_conn <- function(
    x,
    direction   = c("auto", "to_drive", "from_drive"),
    on_conflict = c("version", "prompt", "stop")
) {
  direction   <- match.arg(direction)
  on_conflict <- match.arg(on_conflict)
  .sync_raw(x, direction = direction, on_conflict = on_conflict)
}

#' @export
gdpins_sync.default <- function(
    x,
    direction   = c("auto", "to_drive", "from_drive"),
    on_conflict = c("version", "prompt", "stop")
) {
  cli::cli_abort(c(
    "{.fn gdpins_sync} requires a {.cls gdpins_board} or {.cls gdpins_raw_conn}.",
    x = "Got {.cls {class(x)[[1L]]}}."
  ))
}

# -- Last-synced baseline (H6) -------------------------------------------------
#
# A baseline records, per pin or raw file, what each side held the last time
# gdpins knew both sides to agree. Status compares each side with its own
# baseline: one side changed -> that side is ahead; both changed -> conflict,
# whatever the timestamps say. No baseline row -> the timestamp rule.
#
# Board:  <cache_dir>/.gdpins-sync.rds, columns name, drive_hash, local_hash
#         (5-char hash prefixes as in pins::pin_versions()$hash, stored per
#         side), synced_at. Dot-named, so pins never lists it.
# Raw:    <getOption("gdpins.cache_dir")>/.gdpins-raw-baselines/<key>.rds,
#         columns name, synced_md5, synced_at. Kept outside local_path so the
#         mirror listings never see it.

.BASELINE_FILE     <- ".gdpins-sync.rds"
.RAW_BASELINE_DIR  <- ".gdpins-raw-baselines"

#' Read a baseline file
#'
#' @param path Character scalar, or `NULL`.
#' @param cols Character vector of required columns.
#' @param quiet Logical. `TRUE` suppresses the unreadable-file warning (used
#'   by writers, which replace such a file anyway).
#'
#' @return A data frame, or `NULL` when there is no usable baseline.
#' @keywords internal
.baseline_read_file <- function(path, cols, quiet = FALSE) {
  if (is.null(path) || !file.exists(path)) return(NULL)
  base <- tryCatch(readRDS(path), error = function(e) NULL,
                   warning = function(w) NULL)
  if (!is.data.frame(base) || !all(cols %in% names(base))) {
    if (!quiet) {
      cli::cli_warn(
        c(
          "!" = "Ignoring unreadable sync baseline {.path {path}}.",
          "i" = paste0(
            "Changes are compared by timestamp until the next ",
            "{.fn gdpins_sync} rewrites it."
          )
        ),
        class = "gdpins_warning_baseline_unreadable"
      )
    }
    return(NULL)
  }
  base[, cols, drop = FALSE]
}

#' Write a baseline file atomically (temp file in the same directory, then move)
#'
#' A failure warns and leaves detection on the timestamp rule; it never aborts
#' the verb that triggered it.
#'
#' @param path Character scalar.
#' @param base A data frame.
#'
#' @return `TRUE` on success, `FALSE` after a warning.
#' @keywords internal
.baseline_write_file <- function(path, base) {
  tryCatch({
    fs::dir_create(dirname(path))
    tmp <- tempfile(".gdpins-baseline-", tmpdir = dirname(path), fileext = ".tmp")
    on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
    saveRDS(base, tmp)
    fs::file_move(tmp, path)
    TRUE
  }, error = function(e) {
    cli::cli_warn(
      c(
        "!" = "Could not write sync baseline {.path {path}}: {conditionMessage(e)}",
        "i" = "Changes are compared by timestamp until a baseline is written."
      ),
      class = "gdpins_warning_baseline_unwritable"
    )
    FALSE
  })
}

#' Upsert rows into a baseline data frame
#' @keywords internal
.baseline_upsert <- function(base, rows) {
  if (is.null(base)) return(rows)
  rbind(base[!base$name %in% rows$name, , drop = FALSE], rows)
}

# ---- Board baseline ----

#' Path of a board's baseline file, or `NULL` when the board has none
#'
#' Only boards with both a Drive board and a local copy have a baseline.
#'
#' @param x A `gdpins_board`.
#' @keywords internal
.baseline_path <- function(x) {
  if (is.null(x$drive_board) || is.null(x$local_board)) return(NULL)
  dir <- x$cache_dir
  if (is.null(dir)) dir <- x$local_board$path
  if (is.null(dir)) return(NULL)
  file.path(dir, .BASELINE_FILE)
}

.BOARD_BASELINE_COLS <- c("name", "drive_hash", "local_hash", "synced_at")

#' Read a board's baseline
#' @param x A `gdpins_board`.
#' @param quiet Passed to `.baseline_read_file()`.
#' @return A data frame or `NULL`.
#' @keywords internal
.baseline_read <- function(x, quiet = FALSE) {
  .baseline_read_file(.baseline_path(x), .BOARD_BASELINE_COLS, quiet = quiet)
}

#' Record that pins are in sync, with each side's latest hash
#'
#' @param x A `gdpins_board`.
#' @param name Character vector of pin names.
#' @param drive_hash,local_hash Character vectors of 5-char hash prefixes, or
#'   `NULL` to read each side's latest version now.
#' @return Invisibly `TRUE` when written.
#' @keywords internal
.baseline_set <- function(x, name, drive_hash = NULL, local_hash = NULL) {
  path <- .baseline_path(x)
  if (is.null(path) || length(name) == 0L) return(invisible(FALSE))
  latest_hash <- function(board, nm) {
    lv <- .latest_version(board, nm)
    if (is.null(lv)) NA_character_ else as.character(lv$hash)
  }
  if (is.null(drive_hash)) {
    drive_hash <- vapply(name, latest_hash, character(1L),
                         board = x$drive_board, USE.NAMES = FALSE)
  }
  if (is.null(local_hash)) {
    local_hash <- vapply(name, latest_hash, character(1L),
                         board = x$local_board, USE.NAMES = FALSE)
  }
  rows <- data.frame(
    name       = as.character(name),
    drive_hash = as.character(drive_hash),
    local_hash = as.character(local_hash),
    synced_at  = rep(as.POSIXct(Sys.time(), tz = "UTC"), length(name)),
    stringsAsFactors = FALSE
  )
  # A pin missing on a side has no baseline to compare against.
  rows <- rows[!is.na(rows$drive_hash) & !is.na(rows$local_hash), , drop = FALSE]
  if (nrow(rows) == 0L) return(invisible(FALSE))
  base <- .baseline_upsert(.baseline_read(x, quiet = TRUE), rows)
  invisible(.baseline_write_file(path, base))
}

#' Drop pins from a board's baseline
#' @param x A `gdpins_board`.
#' @param name Character vector of pin names.
#' @keywords internal
.baseline_drop <- function(x, name) {
  path <- .baseline_path(x)
  base <- .baseline_read(x, quiet = TRUE)
  if (is.null(base) || !any(base$name %in% name)) return(invisible(FALSE))
  invisible(.baseline_write_file(path, base[!base$name %in% name, , drop = FALSE]))
}

# ---- Raw baseline ----

#' Path of a raw connection's baseline file, or `NULL` when it has none
#'
#' Keyed by the Drive root, `drive_path` and the normalised `local_path`, so
#' two connections share a baseline only when they mirror the same folder into
#' the same directory.
#'
#' @param conn A `gdpins_raw_conn` (or a list with `adapter`, `drive_path`,
#'   `local_path`).
#' @param quiet Logical. `TRUE` suppresses the warning for an unset
#'   `gdpins.cache_dir` option.
#' @keywords internal
.raw_baseline_path <- function(conn, quiet = FALSE) {
  adapter <- conn$adapter
  if (is.null(adapter) || identical(conn$config, "local_only")) return(NULL)
  root_dir <- getOption("gdpins.cache_dir")
  if (!is.character(root_dir) || length(root_dir) != 1L || is.na(root_dir) ||
      !nzchar(root_dir)) {
    if (!quiet) {
      cli::cli_warn(
        c(
          "!" = "Option {.code gdpins.cache_dir} is unset: no sync baseline for raw connections.",
          "i" = "Changes are compared by modification time."
        ),
        class = "gdpins_warning_baseline_unreadable"
      )
    }
    return(NULL)
  }
  root <- if (identical(adapter$kind, "real")) adapter$root_id else basename(adapter$root)
  key <- rlang::hash(list(
    root       = root,
    drive_path = conn$drive_path,
    local_path = as.character(fs::path_norm(fs::path_abs(conn$local_path)))
  ))
  file.path(root_dir, .RAW_BASELINE_DIR, paste0(key, ".rds"))
}

.RAW_BASELINE_COLS <- c("name", "synced_md5", "synced_at")

#' Read a raw connection's baseline
#' @keywords internal
.raw_baseline_read <- function(conn, quiet = FALSE) {
  .baseline_read_file(.raw_baseline_path(conn, quiet = quiet),
                      .RAW_BASELINE_COLS, quiet = quiet)
}

#' Record that raw files are in sync
#'
#' @param conn A `gdpins_raw_conn` (or a list with `adapter`, `drive_path`,
#'   `local_path`).
#' @param name Character vector of relative file names.
#' @param md5 Character vector of md5 sums, or `NULL` to hash the local files.
#' @keywords internal
.raw_baseline_set <- function(conn, name, md5 = NULL) {
  path <- .raw_baseline_path(conn, quiet = TRUE)
  if (is.null(path) || length(name) == 0L) return(invisible(FALSE))
  if (is.null(md5)) {
    md5 <- vapply(name, function(nm) {
      f <- file.path(conn$local_path, gsub("/", .Platform$file.sep, nm, fixed = TRUE))
      if (file.exists(f)) unname(tools::md5sum(f)) else NA_character_
    }, character(1L), USE.NAMES = FALSE)
  }
  rows <- data.frame(
    name       = as.character(name),
    synced_md5 = as.character(md5),
    synced_at  = rep(as.POSIXct(Sys.time(), tz = "UTC"), length(name)),
    stringsAsFactors = FALSE
  )
  rows <- rows[!is.na(rows$synced_md5), , drop = FALSE]
  if (nrow(rows) == 0L) return(invisible(FALSE))
  base <- .baseline_upsert(.raw_baseline_read(conn, quiet = TRUE), rows)
  invisible(.baseline_write_file(path, base))
}

#' Drop raw files from a connection's baseline
#' @keywords internal
.raw_baseline_drop <- function(conn, name) {
  path <- .raw_baseline_path(conn, quiet = TRUE)
  base <- .raw_baseline_read(conn, quiet = TRUE)
  if (is.null(base) || !any(base$name %in% name)) return(invisible(FALSE))
  invisible(.baseline_write_file(path, base[!base$name %in% name, , drop = FALSE]))
}

#' Decide a state from each side's change against the baseline
#'
#' @param drive_changed,local_changed Logical scalars.
#' @return A state string.
#' @keywords internal
.baseline_state <- function(drive_changed, local_changed) {
  if (drive_changed && local_changed) "conflict"
  else if (drive_changed) "drive_ahead"
  else if (local_changed) "local_ahead"
  else "in_sync"
}

# -- Board status internals ----------------------------------------------------

#' @keywords internal
.board_status_board <- function(x) {
  # local-only boards have no drive_board -- nothing to compare
  if (is.null(x$drive_board)) {
    return(.empty_board_status_tbl())
  }

  # drive_only boards have no local copy -- nothing to compare
  if (is.null(x$local_board)) {
    cli::cli_inform(c(
      "i" = "Board {.val {x$name}} has no local copy; nothing to compare."
    ))
    return(.empty_board_status_tbl())
  }

  # Offline guard
  if (!gdpins_is_online()) {
    cli::cli_warn(c(
      "!" = "Cannot check sync status: no internet connection.",
      "i" = "All items reported as {.val offline}."
    ))
    return(.offline_board_status_tbl(x))
  }

  drive_board <- x$drive_board
  local_board <- .board_local_side(x)

  drive_pins <- pins::pin_list(drive_board)
  local_pins <- pins::pin_list(local_board)
  all_pins   <- union(drive_pins, local_pins)
  all_pins   <- .drop_invalid_names(all_pins, .check_pin_name, "pin name")

  if (length(all_pins) == 0L) {
    return(.empty_board_status_tbl())
  }

  # Last-synced baseline, read once per call (NULL: timestamp rule only).
  baseline <- .baseline_read(x)

  rows <- lapply(all_pins, function(pin_name) {
    .compare_board_pin(
      pin_name    = pin_name,
      drive_board = drive_board,
      local_board = local_board,
      in_drive    = pin_name %in% drive_pins,
      in_local    = pin_name %in% local_pins,
      baseline    = baseline
    )
  })

  do.call(rbind, rows)
}

#' Compare one pin's latest versions on Drive and local
#'
#' @param pin_name Character scalar.
#' @param drive_board,local_board pins boards.
#' @param in_drive,in_local Logical scalars: is the pin listed on that side.
#' @param baseline A board baseline data frame (see `.baseline_read()`), or
#'   `NULL`. When it has a row for `pin_name`, each side's latest hash is
#'   compared with that side's baseline hash: changed on one side means that
#'   side is ahead, changed on both means conflict. Without a row, the side
#'   with the later `created` time is ahead.
#' @keywords internal
.compare_board_pin <- function(pin_name, drive_board, local_board,
                                in_drive, in_local, baseline = NULL) {
  dv <- if (in_drive) .latest_version(drive_board, pin_name) else NULL
  lv <- if (in_local) .latest_version(local_board, pin_name) else NULL

  drive_version <- if (!is.null(dv)) dv$version  else NA_character_
  drive_created <- if (!is.null(dv)) dv$created  else as.POSIXct(NA)
  drive_hash    <- if (!is.null(dv)) dv$hash      else NA_character_
  local_version <- if (!is.null(lv)) lv$version  else NA_character_
  local_created <- if (!is.null(lv)) lv$created  else as.POSIXct(NA)
  local_hash    <- if (!is.null(lv)) lv$hash      else NA_character_

  state <- if (!in_drive && !in_local) {
    "in_sync"
  } else if (!in_drive) {
    "local_ahead"
  } else if (!in_local) {
    "drive_ahead"
  } else if (!is.na(drive_hash) && !is.na(local_hash) && identical(drive_hash, local_hash)) {
    "in_sync"
  } else if (!is.null(baseline) && pin_name %in% baseline$name) {
    # Different hashes, last synced state known: who moved since then?
    b <- baseline[baseline$name == pin_name, , drop = FALSE][1L, ]
    .baseline_state(
      drive_changed = !identical(as.character(drive_hash), as.character(b$drive_hash)),
      local_changed = !identical(as.character(local_hash), as.character(b$local_hash))
    )
  } else {
    # Different hashes, no baseline -- compare timestamps
    dc <- if (inherits(drive_created, "POSIXct") && !is.na(drive_created)) drive_created else NA
    lc <- if (inherits(local_created, "POSIXct") && !is.na(local_created)) local_created else NA
    if (is.na(dc) || is.na(lc)) {
      "conflict"
    } else if (dc > lc) {
      "drive_ahead"
    } else if (lc > dc) {
      "local_ahead"
    } else {
      # Same timestamp, different hash -- genuine conflict
      "conflict"
    }
  }

  tibble::tibble(
    name          = pin_name,
    state         = state,
    drive_version = drive_version,
    local_version = local_version,
    drive_created = list(drive_created),
    local_created = list(local_created),
    drive_hash    = drive_hash,
    local_hash    = local_hash
  )
}

#' @keywords internal
.latest_version <- function(board, pin_name) {
  v <- pins::pin_versions(board, pin_name)
  if (nrow(v) == 0L) return(NULL)
  v[nrow(v), ]
}

#' @keywords internal
.board_local_side <- function(x) {
  x$local_board
}

#' @keywords internal
.empty_board_status_tbl <- function() {
  tibble::tibble(
    name          = character(),
    state         = character(),
    drive_version = character(),
    local_version = character(),
    drive_created = list(),
    local_created = list(),
    drive_hash    = character(),
    local_hash    = character()
  )
}

#' @keywords internal
.offline_board_status_tbl <- function(x) {
  local_board <- .board_local_side(x)

  local_pins <- if (!is.null(local_board)) {
    tryCatch(pins::pin_list(local_board), error = function(e) character())
  } else {
    character()
  }

  if (length(local_pins) == 0L) {
    return(.empty_board_status_tbl())
  }

  rows <- lapply(local_pins, function(pin_name) {
    tibble::tibble(
      name          = pin_name,
      state         = "offline",
      drive_version = NA_character_,
      local_version = NA_character_,
      drive_created = list(as.POSIXct(NA)),
      local_created = list(as.POSIXct(NA)),
      drive_hash    = NA_character_,
      local_hash    = NA_character_
    )
  })
  do.call(rbind, rows)
}

# -- Raw connection status internals -------------------------------------------

#' @keywords internal
.board_status_raw <- function(x) {
  # local-only has no drive -- nothing to compare
  if (is.null(x$adapter) || x$config == "local_only") {
    return(.empty_raw_status_tbl())
  }

  if (!gdpins_is_online()) {
    cli::cli_warn(c(
      "!" = "Cannot check sync status: no internet connection.",
      "i" = "All items reported as {.val offline}."
    ))
    return(.offline_raw_status_tbl(x))
  }

  # List files on drive side
  drive_files_tbl <- gd_ls(x$adapter, x$drive_path, recursive = TRUE)
  drive_files <- drive_files_tbl |>
    dplyr::filter(!.data$is_dir) |>
    dplyr::mutate(
      rel = .drive_rel(x$adapter, x$drive_path, .data$path)
    )

  # List files in local dir
  local_files <- .list_local_files(x$local_path)

  all_names <- union(drive_files$rel, local_files$rel)

  if (length(all_names) == 0L) {
    return(.empty_raw_status_tbl())
  }

  # Last-synced baseline, read once per call (NULL: mtime rule only).
  baseline <- .raw_baseline_read(x)

  rows <- lapply(all_names, function(fname) {
    in_drive <- fname %in% drive_files$rel
    in_local <- fname %in% local_files$rel

    drv_row <- if (in_drive) drive_files[drive_files$rel == fname, ] else NULL
    loc_row <- if (in_local) local_files[local_files$rel == fname, ] else NULL

    drv_md5   <- if (in_drive) as.character(drv_row$md5[[1L]])  else NA_character_
    drv_mtime <- if (in_drive) drv_row$mtime[[1L]]              else as.POSIXct(NA)
    loc_md5   <- if (in_local) as.character(loc_row$md5[[1L]])  else NA_character_
    loc_mtime <- if (in_local) loc_row$mtime[[1L]]              else as.POSIXct(NA)

    state <- if (!in_drive && !in_local) {
      "in_sync"
    } else if (!in_drive) {
      "local_ahead"
    } else if (!in_local) {
      "drive_ahead"
    } else if (!is.na(drv_md5) && !is.na(loc_md5) && identical(drv_md5, loc_md5)) {
      "in_sync"
    } else if (!is.null(baseline) && fname %in% baseline$name) {
      # Different md5, last synced bytes known: who moved since then?
      synced <- as.character(baseline$synced_md5[baseline$name == fname][[1L]])
      .baseline_state(
        drive_changed = !identical(drv_md5, synced),
        local_changed = !identical(loc_md5, synced)
      )
    } else {
      # Different md5, no baseline -- use mtime tiebreaker
      if (is.na(drv_mtime) || is.na(loc_mtime)) {
        "conflict"
      } else if (drv_mtime > loc_mtime) {
        "drive_ahead"
      } else if (loc_mtime > drv_mtime) {
        "local_ahead"
      } else {
        # Same mtime, different md5 -- genuine conflict
        "conflict"
      }
    }

    tibble::tibble(
      name        = fname,
      state       = state,
      drive_md5   = drv_md5,
      local_md5   = loc_md5,
      drive_mtime = list(drv_mtime),
      local_mtime = list(loc_mtime)
    )
  })

  do.call(rbind, rows)
}

#' @keywords internal
.list_local_files <- function(local_path) {
  if (!dir.exists(local_path)) {
    return(tibble::tibble(
      rel   = character(),
      md5   = character(),
      mtime = as.POSIXct(character())
    ))
  }
  abs_paths <- fs::dir_ls(local_path, recurse = TRUE, type = "file")
  if (length(abs_paths) == 0L) {
    return(tibble::tibble(
      rel   = character(),
      md5   = character(),
      mtime = as.POSIXct(character())
    ))
  }
  # Use fs::path_rel for cross-platform relative path computation
  rel_paths <- vapply(abs_paths, function(p) {
    r <- fs::path_rel(p, local_path)
    # Normalise to forward slashes
    gsub("\\\\", "/", as.character(r))
  }, character(1L), USE.NAMES = FALSE)

  tibble::tibble(
    rel   = rel_paths,
    md5   = vapply(
      abs_paths,
      function(p) unname(tools::md5sum(p)),
      character(1L),
      USE.NAMES = FALSE
    ),
    mtime = file.mtime(as.character(abs_paths))
  )
}

#' @keywords internal
.empty_raw_status_tbl <- function() {
  tibble::tibble(
    name        = character(),
    state       = character(),
    drive_md5   = character(),
    local_md5   = character(),
    drive_mtime = list(),
    local_mtime = list()
  )
}

#' @keywords internal
.offline_raw_status_tbl <- function(x) {
  local_files <- .list_local_files(x$local_path)
  if (nrow(local_files) == 0L) return(.empty_raw_status_tbl())

  rows <- lapply(local_files$rel, function(fname) {
    tibble::tibble(
      name        = fname,
      state       = "offline",
      drive_md5   = NA_character_,
      local_md5   = NA_character_,
      drive_mtime = list(as.POSIXct(NA)),
      local_mtime = list(as.POSIXct(NA))
    )
  })
  do.call(rbind, rows)
}

#' Compute relative file name from a drive ls path entry
#'
#' Handles both real adapters (which return relative names from Drive API)
#' and fake adapters (which return absolute filesystem paths due to the
#' tempdir-backed simulation).
#'
#' @keywords internal
.drive_rel <- function(adapter, drive_path, path) {
  vapply(path, function(p) {
    # Case 1: path starts with drive_path (real adapter -- already relative)
    rel_prefix <- paste0(drive_path, "/")
    if (startsWith(p, rel_prefix)) {
      return(substring(p, nchar(rel_prefix) + 1L))
    }
    # Case 2: absolute path (fake adapter) -- use fs::path_rel
    drive_abs <- if (!is.null(adapter$root)) {
      file.path(adapter$root,
                gsub("/", .Platform$file.sep, drive_path, fixed = TRUE))
    } else {
      drive_path
    }
    r <- tryCatch(
      as.character(fs::path_rel(p, drive_abs)),
      error = function(e) p
    )
    gsub("\\\\", "/", r)
  }, character(1L), USE.NAMES = FALSE)
}

#' @keywords internal
.empty_gd_ls_tbl <- function() {
  tibble::tibble(
    path   = character(),
    is_dir = logical(),
    size   = double(),
    md5    = character(),
    mtime  = as.POSIXct(character())
  )
}

# -- Board sync internals ------------------------------------------------------

#' @keywords internal
.sync_board <- function(x, direction, on_conflict) {
  # local_only boards -- nothing to sync
  if (is.null(x$drive_board)) {
    cli::cli_inform(c("i" = "Board {.val {x$name}} is local-only. Nothing to sync."))
    return(invisible(x))
  }

  # drive_only boards -- no local copy, nothing to sync
  if (is.null(x$local_board)) {
    cli::cli_inform(c(
      "i" = "Board {.val {x$name}} has no local copy ({.code cache_dir = FALSE}). Nothing to sync."
    ))
    return(invisible(x))
  }

  # Offline guard -- blocks all writes
  if (!gdpins_is_online()) {
    cli::cli_abort(c(
      "Cannot sync: no internet connection.",
      "i" = "Connect to the internet and retry."
    ))
  }

  status <- gdpins_board_status(x)

  if (nrow(status) == 0L) {
    cli::cli_inform(c("i" = "Nothing to sync for board {.val {x$name}}."))
    return(invisible(x))
  }

  drive_board <- x$drive_board
  local_board <- .board_local_side(x)

  # New-computer case: local is entirely empty and drive has content
  local_pins <- tryCatch(pins::pin_list(local_board), error = function(e) character())
  if (length(local_pins) == 0L && any(status$state == "drive_ahead")) {
    n_drive <- sum(status$state == "drive_ahead")
    cli::cli_inform(c(
      "i" = "New-computer setup detected: local copy is empty.",
      "v" = "Pulling {n_drive} pin{?s} from Drive -> local."
    ))
  }

  conflicts       <- character()
  unversioned_hit <- FALSE
  n_actions       <- 0L
  # Pins whose two sides agree after this sync: their latest hashes become
  # the last-synced baseline (H6). in_sync rows are recorded too, which
  # bootstraps boards that predate the baseline.
  synced          <- character()
  in_sync_rows    <- status$state == "in_sync"

  for (i in seq_len(nrow(status))) {
    row      <- status[i, ]
    pin_name <- row$name
    state    <- row$state

    effective_dir <- .effective_direction(state, direction)

    if (effective_dir == "skip" || state == "in_sync") next

    if (state == "conflict") {
      if (x$versioned) {
        # Versioned boards: both contents become versions on both boards,
        # the newer one (tie: Drive) is the latest on both -- no loss.
        if (.resolve_versioned_conflict(drive_board, local_board, pin_name)) {
          # Both boards now have the same latest version.
          synced    <- c(synced, pin_name)
          n_actions <- n_actions + 1L
          cli::cli_inform(c(
            "i" = paste0(
              "Board {.val {x$name}}: pin {.val {pin_name}} conflict resolved ",
              "-- both contents kept as versions on Drive and local."
            )
          ))
        }
      } else if (on_conflict == "prompt") {
        choice <- .prompt_conflict(pin_name, row)
        if (choice == "local") {
          if (.copy_pin_to_board(local_board, drive_board, pin_name)) {
            synced    <- c(synced, pin_name)
            n_actions <- n_actions + 1L
            cli::cli_inform(c(
              "v" = "Board {.val {x$name}}: synced {.val {pin_name}} local -> Drive."
            ))
          }
        } else if (choice == "drive") {
          if (.copy_pin_to_board(drive_board, local_board, pin_name)) {
            synced    <- c(synced, pin_name)
            n_actions <- n_actions + 1L
            cli::cli_inform(c(
              "v" = "Board {.val {x$name}}: synced {.val {pin_name}} Drive -> local."
            ))
          }
        }
      } else {
        # "stop", and "version" on an unversioned board: a one-slot board
        # cannot keep both sides, so the conflict is reported, not resolved.
        if (on_conflict == "version") unversioned_hit <- TRUE
        conflicts <- c(conflicts, pin_name)
      }
      next
    }

    # Non-conflict directional copy
    if (effective_dir == "to_drive") {
      if (.copy_pin_to_board(local_board, drive_board, pin_name)) {
        synced    <- c(synced, pin_name)
        n_actions <- n_actions + 1L
        cli::cli_inform(c(
          "v" = "Board {.val {x$name}}: synced {.val {pin_name}} local -> Drive."
        ))
      }
    } else if (effective_dir == "from_drive") {
      if (.copy_pin_to_board(drive_board, local_board, pin_name)) {
        synced    <- c(synced, pin_name)
        n_actions <- n_actions + 1L
        cli::cli_inform(c(
          "v" = "Board {.val {x$name}}: synced {.val {pin_name}} Drive -> local."
        ))
      }
    }
  }

  # Record the baseline before any conflict abort: the pins copied above are
  # in sync even when others are not. Copies re-read each side's latest hash
  # (a copy can re-serialise); in_sync rows reuse the status hashes.
  if (any(in_sync_rows)) {
    .baseline_set(
      x,
      status$name[in_sync_rows],
      drive_hash = status$drive_hash[in_sync_rows],
      local_hash = status$local_hash[in_sync_rows]
    )
  }
  if (length(synced) > 0L) .baseline_set(x, synced)

  # Nothing moved and nothing blocked -- say so, rather than exiting silently.
  if (n_actions == 0L && length(conflicts) == 0L) {
    cli::cli_inform(c(
      "v" = paste0(
        "Board {.val {x$name}}: everything in sync, nothing to reconcile ",
        "({nrow(status)} pin{?s} checked)."
      )
    ))
  }

  # Report conflicts that were stopped -- abort after processing all items
  if (length(conflicts) > 0L) {
    cli::cli_abort(
      c(
        "Sync aborted: {length(conflicts)} conflict{?s} found.",
        "!" = "Conflicting pin{?s}: {.val {conflicts}}.",
        "i" = "Conflicting pins were not changed.",
        "i" = if (unversioned_hit) {
          paste0(
            "Board {.val {x$name}} is unversioned, so it cannot keep both ",
            "sides as versions."
          )
        },
        "i" = paste0(
          "Use {.code on_conflict = \"prompt\"} to choose a side, or write ",
          "the local data under a new pin name first."
        )
      ),
      class = c(
        if (unversioned_hit) "gdpins_error_unversioned_conflict",
        "gdpins_error_sync_conflict",
        "gdpins_error"
      )
    )
  }

  invisible(x)
}

#' @keywords internal
.effective_direction <- function(state, direction) {
  if (state == "in_sync")  return("skip")
  if (state == "conflict") return("conflict")
  if (direction == "to_drive") {
    # Only push local_ahead pins; skip drive_ahead in this mode
    if (state == "local_ahead") return("to_drive")
    return("skip")
  }
  if (direction == "from_drive") {
    # Only pull drive_ahead pins; skip local_ahead in this mode
    if (state == "drive_ahead") return("from_drive")
    return("skip")
  }
  # auto: follow the drift
  if (state == "local_ahead") return("to_drive")
  if (state == "drive_ahead") return("from_drive")
  "skip"
}

#' Copy the latest version of a pin from one board to another
#'
#' Composition of `.snapshot_pin()` and `.write_pin_snapshot()`.
#'
#' @param src_board,dst_board pins boards.
#' @param pin_name Character scalar.
#'
#' @return `TRUE` when the pin was written to `dst_board`, `FALSE` when the
#'   source could not be read (a warning has been raised).
#' @keywords internal
.copy_pin_to_board <- function(src_board, dst_board, pin_name) {
  snap <- .snapshot_pin(src_board, pin_name)
  if (is.null(snap)) return(FALSE)
  .write_pin_snapshot(dst_board, snap, pin_name)
}

#' Read the latest version of a pin into memory, without writing anything
#'
#' Captures the content (file paths for `"file"` pins, the R object
#' otherwise) and the metadata needed to re-create that version on another
#' board: `type`, `title`, `description`, `user`, `tags`, `urls`, plus
#' `pin_hash`, `created` and `version` for the caller.
#'
#' @param src_board A pins board.
#' @param pin_name Character scalar.
#'
#' @return A list, or `NULL` after a warning when the pin cannot be read.
#' @keywords internal
.snapshot_pin <- function(src_board, pin_name) {
  # Backstop: names here come from pin_list(), which on a Drive board lists
  # every Drive item, so a Drive folder named ".." would reach this point.
  .check_pin_name(pin_name)
  tryCatch({
    meta    <- pins::pin_meta(src_board, pin_name)
    version <- meta$local$version
    type    <- meta$type
    type    <- if (length(type) && !is.na(type[[1L]])) type[[1L]] else NULL

    snap <- list(
      type        = type,
      title       = meta$title,
      description = meta$description,
      user        = if (length(meta$user)) meta$user else NULL,
      tags        = meta$tags,
      urls        = meta$urls,
      pin_hash    = meta$pin_hash,
      created     = meta$created,
      version     = version,
      paths       = NULL,
      object      = NULL
    )
    # "file" pins (how gdpins now stores parquet) are copied byte-for-byte with
    # download + upload; pins::pin_read() cannot read them and pin_write()
    # cannot re-emit them. Other pins are read as an object (parquet routed
    # through the arrow engine by .read_from_board) and re-written with their
    # original type.
    if (identical(type, "file")) {
      snap$paths <- as.character(
        pins::pin_download(src_board, pin_name, version = version)
      )
    } else {
      snap["object"] <- list(.read_from_board(src_board, pin_name, version))
    }
    snap
  }, error = function(e) {
    cli::cli_warn(
      "Could not read pin {.val {pin_name}} from source board: {conditionMessage(e)}"
    )
    NULL
  })
}

#' Write a pin snapshot to a board
#'
#' @param dst_board A pins board.
#' @param snap A snapshot from `.snapshot_pin()`.
#' @param pin_name Character scalar.
#'
#' @return `TRUE`, invisibly.
#' @keywords internal
.write_pin_snapshot <- function(dst_board, snap, pin_name) {
  if (identical(snap$type, "file")) {
    suppressMessages(pins::pin_upload(
      dst_board, snap$paths, pin_name,
      title       = snap$title,
      description = snap$description,
      metadata    = snap$user,
      tags        = snap$tags,
      urls        = snap$urls
    ))
  } else {
    suppressMessages(pins::pin_write(
      dst_board, snap$object, pin_name,
      type        = snap$type,
      title       = snap$title,
      description = snap$description,
      metadata    = snap$user,
      tags        = snap$tags,
      urls        = snap$urls
    ))
  }
  invisible(TRUE)
}

#' Wait until a new write to a pin gets a version id after the latest one
#'
#' pins version ids have one-second resolution, and ids in the same second
#' sort by hash prefix, not by write order. A write in the same second as the
#' current latest version may therefore not become the latest, or may land in
#' the existing version directory. Sleeping until the next second avoids both.
#'
#' @param board A pins board.
#' @param pin_name Character scalar.
#'
#' @return `NULL`, invisibly.
#' @keywords internal
.await_new_version_second <- function(board, pin_name) {
  lv <- .latest_version(board, pin_name)
  if (is.null(lv)) return(invisible(NULL))
  created <- lv$created
  if (is.list(created)) created <- created[[1L]]
  if (!inherits(created, "POSIXct") || is.na(created)) return(invisible(NULL))
  wait <- as.numeric(floor(as.numeric(created)) + 1 - as.numeric(Sys.time()))
  # Bounded: a clock far ahead on another machine is caught by the post-check
  # in .resolve_versioned_conflict(), not by sleeping.
  if (wait > 0 && wait <= 2) Sys.sleep(wait)
  invisible(NULL)
}

#' Resolve a conflict on a versioned board without losing either side
#'
#' Both pre-conflict contents become versions on both boards. The snapshot
#' with the later `created` time (tie: Drive) is written last, so it is the
#' latest version on both boards.
#'
#' @param drive_board,local_board pins boards.
#' @param pin_name Character scalar.
#'
#' @return `TRUE` when resolved, `FALSE` when a side could not be read (a
#'   warning has been raised).
#' @keywords internal
.resolve_versioned_conflict <- function(drive_board, local_board, pin_name) {
  drive_snap <- .snapshot_pin(drive_board, pin_name)
  local_snap <- .snapshot_pin(local_board, pin_name)
  if (is.null(drive_snap) || is.null(local_snap)) return(FALSE)

  local_newer <- isTRUE(local_snap$created > drive_snap$created)
  winner <- if (local_newer) local_snap else drive_snap
  loser  <- if (local_newer) drive_snap else local_snap
  # Board that already holds the winner as its latest gets the loser, then
  # the winner again; the other board just gets the winner.
  winner_board <- if (local_newer) local_board else drive_board
  loser_board  <- if (local_newer) drive_board else local_board

  write <- function(board, snap) {
    .await_new_version_second(board, pin_name)
    .write_pin_snapshot(board, snap, pin_name)
  }
  write(loser_board, winner)
  write(winner_board, loser)
  write(winner_board, winner)

  dv <- .latest_version(drive_board, pin_name)
  lv <- .latest_version(local_board, pin_name)
  if (is.null(dv) || is.null(lv) || !identical(dv$hash, lv$hash)) {
    cli::cli_abort(
      c(
        "Internal error: conflict resolution for pin {.val {pin_name}} left different latest versions.",
        i = "Drive: {.val {dv$version}}; local: {.val {lv$version}}. Both contents are kept as versions on both boards."
      ),
      .internal = TRUE
    )
  }
  TRUE
}


#' @keywords internal
.prompt_conflict <- function(pin_name, row) {
  drv_v <- row$drive_version
  loc_v <- row$local_version
  cli::cli_inform(c(
    "!" = "Conflict on pin {.val {pin_name}}.",
    " " = "Drive version:  {drv_v}",
    " " = "Local version:  {loc_v}"
  ))
  choice <- readline(prompt = "Keep [l]ocal, [d]rive, or [s]kip? ")
  choice <- tolower(trimws(choice))
  if (startsWith(choice, "l")) "local"
  else if (startsWith(choice, "d")) "drive"
  else "skip"
}

# -- Raw connection sync internals ---------------------------------------------

#' @keywords internal
.sync_raw <- function(x, direction, on_conflict) {
  # local_only -- nothing to sync
  if (is.null(x$adapter) || x$config == "local_only") {
    cli::cli_inform(c("i" = "Raw connection is local-only. Nothing to sync."))
    return(invisible(x))
  }

  # Offline guard
  if (!gdpins_is_online()) {
    cli::cli_abort(c(
      "Cannot sync: no internet connection.",
      "i" = "Connect to the internet and retry."
    ))
  }

  status <- gdpins_board_status(x)

  if (nrow(status) == 0L) {
    cli::cli_inform(c("i" = "Nothing to sync for raw connection."))
    return(invisible(x))
  }

  # New-computer case: local dir is empty and drive has content
  local_files <- .list_local_files(x$local_path)
  if (nrow(local_files) == 0L && any(status$state == "drive_ahead")) {
    n_drive <- sum(status$state == "drive_ahead")
    cli::cli_inform(c(
      "i" = "New-computer setup detected: local directory is empty.",
      "v" = "Pulling {n_drive} file{?s} from Drive -> local."
    ))
  }

  conflicts  <- character()
  failures   <- character()
  fail_msgs  <- character()
  unreadable <- logical()
  n_actions  <- 0L
  # Files whose two sides agree after this sync: their md5 becomes the
  # last-synced baseline (H6). in_sync rows bootstrap older mirrors.
  synced       <- character()
  in_sync_rows <- status$state == "in_sync"

  # One unreadable/locked file must not abandon the remaining files: each
  # transfer is isolated and its error collected for a summary at the end.
  attempt <- function(fname, expr) {
    tryCatch({
      force(expr)
      TRUE
    }, error = function(e) {
      failures   <<- c(failures, fname)
      fail_msgs  <<- c(fail_msgs, conditionMessage(e))
      unreadable <<- c(unreadable, inherits(e, "gdpins_error_unreadable_file"))
      FALSE
    })
  }

  for (i in seq_len(nrow(status))) {
    row   <- status[i, ]
    fname <- row$name
    state <- row$state

    effective_dir <- .effective_direction(state, direction)

    if (effective_dir == "skip" || state == "in_sync") next

    if (state == "conflict") {
      if (on_conflict == "stop") {
        conflicts <- c(conflicts, fname)
        next
      } else if (on_conflict == "prompt") {
        choice <- .prompt_raw_conflict(fname, row)
        if (choice == "local") {
          if (attempt(fname, .raw_copy_to_drive(x, fname))) {
            synced    <- c(synced, fname)
            n_actions <- n_actions + 1L
          }
        } else if (choice == "drive") {
          if (attempt(fname, .raw_copy_to_local(x, fname))) {
            synced    <- c(synced, fname)
            n_actions <- n_actions + 1L
          }
        }
      } else {
        # on_conflict == "version" on raw: back up the local file, then let
        # Drive win. The backup is a normal file in local_path.
        backup <- NULL
        ok <- attempt(fname, {
          backup <- .raw_conflict_backup(x, fname)
          .raw_copy_to_local(x, fname)
        })
        if (ok) {
          # Drive and local now agree.
          synced    <- c(synced, fname)
          n_actions <- n_actions + 1L
          if (!is.null(backup)) {
            cli::cli_warn(
              c(
                "!" = paste0(
                  "File {.val {fname}}: conflict -- Drive version kept, ",
                  "previous local copy saved as {.path {backup}}."
                ),
                "i" = paste0(
                  "Resolve by reading the backup, or re-run with ",
                  "{.code on_conflict = \"prompt\"}. The backup is uploaded ",
                  "on the next sync unless you delete it."
                )
              ),
              class = "gdpins_warning_raw_conflict_backup"
            )
          } else {
            cli::cli_inform(c(
              "i" = "File {.val {fname}}: conflict -- Drive version kept (no local copy to back up)."
            ))
          }
        }
      }
      next
    }

    if (effective_dir == "to_drive") {
      if (attempt(fname, .raw_copy_to_drive(x, fname))) {
        synced    <- c(synced, fname)
        n_actions <- n_actions + 1L
        cli::cli_inform(c("v" = "Synced {.val {fname}}: local -> Drive."))
      }
    } else if (effective_dir == "from_drive") {
      if (attempt(fname, .raw_copy_to_local(x, fname))) {
        synced    <- c(synced, fname)
        n_actions <- n_actions + 1L
        cli::cli_inform(c("v" = "Synced {.val {fname}}: Drive -> local."))
      }
    }
  }

  # Record the baseline before any conflict abort. Copies are byte-exact, so
  # the local file's md5 is both sides' md5.
  if (any(in_sync_rows)) {
    .raw_baseline_set(x, status$name[in_sync_rows],
                      md5 = status$local_md5[in_sync_rows])
  }
  if (length(synced) > 0L) .raw_baseline_set(x, synced)

  if (length(failures) > 0L) {
    # File names and error messages are arbitrary text that may itself
    # contain "{"/"}" -- pasting them straight into a cli template would make
    # cli re-parse that text as glue and crash (e.g. a file named "a{b}.csv").
    # Referencing them as indexed expressions instead keeps them data: cli
    # substitutes the looked-up value without re-parsing it.
    bullets <- vapply(seq_along(failures), function(i) {
      sprintf("{.val {failures[%d]}}: {fail_msgs[%d]}", i, i)
    }, character(1))
    names(bullets) <- rep("x", length(bullets))

    # The "close the program" hint only applies to the unreadable/locked-file
    # case; showing it for download/auth/network failures is misleading.
    hint <- if (any(unreadable)) {
      c("i" = "Close any program holding these files open, then re-run {.fn gdpins_sync}.")
    } else {
      character()
    }

    cli::cli_warn(c(
      "!" = "{n_actions} file{?s} synced, {length(failures)} failed.",
      bullets,
      hint
    ))
  }

  # Nothing moved and nothing blocked -- say so, rather than exiting silently.
  if (n_actions == 0L && length(conflicts) == 0L && length(failures) == 0L) {
    cli::cli_inform(c(
      "v" = paste0(
        "Raw connection: everything in sync, nothing to reconcile ",
        "({nrow(status)} file{?s} checked)."
      )
    ))
  }

  if (length(conflicts) > 0L) {
    cli::cli_abort(
      c(
        "Sync aborted: {length(conflicts)} conflict{?s} found.",
        "!" = "Conflicting file{?s}: {.val {conflicts}}.",
        "i" = paste0(
          "Nothing was changed. Resolve conflicts manually ",
          "or use {.code on_conflict = 'prompt'}."
        )
      ),
      class = c("gdpins_error_sync_conflict", "gdpins_error")
    )
  }

  invisible(x)
}

#' Test whether a local file can actually be opened for reading
#'
#' `file.exists()` and `file.access()` both consult metadata only, so a file
#' held open by another program (Word, Excel, a running R session) still looks
#' fine. Uploads hand libcurl a *path*, and curl only opens it mid-request --
#' at which point the failure surfaces as an opaque
#' `"read error getting mime data"`. Opening the file up front turns that into
#' an actionable, per-file error -- but on Windows a byte-range lock (as held
#' by Microsoft Office) lets the open succeed while `readBin()` silently
#' returns 0 bytes, so a 1-byte read probe is needed to actually catch it.
#'
#' @param path Character scalar. Path to a local file.
#'
#' @return `TRUE` if the file could be opened and read from.
#' @keywords internal
.file_is_readable <- function(path) {
  tryCatch({
    probe <- .read_first_byte(path)
    if (length(probe) == 0L && isTRUE(file.size(path) > 0)) {
      return(FALSE)
    }
    TRUE
  }, error = function(e) FALSE, warning = function(w) FALSE)
}

#' Read the first byte of a file
#'
#' Isolated as its own function so tests can mock the byte-range-lock failure
#' mode (a read that silently returns 0 bytes) without needing a real
#' cross-process OS-level lock.
#'
#' @param path Character scalar. Path to a local file.
#'
#' @return A raw vector of length 0 or 1.
#' @keywords internal
.read_first_byte <- function(path) {
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  readBin(con, "raw", 1L)
}

#' @keywords internal
.raw_copy_to_drive <- function(conn, rel_name) {
  .check_rel_name(rel_name)
  local_file <- file.path(
    conn$local_path,
    gsub("/", .Platform$file.sep, rel_name, fixed = TRUE)
  )
  .check_local_dest(local_file, conn$local_path)
  drive_path <- paste0(conn$drive_path, "/", rel_name)
  if (!file.exists(local_file)) {
    cli::cli_abort("Local file not found: {.path {local_file}}")
  }
  if (!.file_is_readable(local_file)) {
    cli::cli_abort(
      c(
        "Cannot read local file: {.path {local_file}}",
        "i" = "It is most likely open in another program, or locked by a sync client."
      ),
      class = "gdpins_error_unreadable_file"
    )
  }
  gd_upload(conn$adapter, local_file, drive_path)
  invisible(NULL)
}

#' @keywords internal
.raw_copy_to_local <- function(conn, rel_name) {
  drive_path <- paste0(conn$drive_path, "/", rel_name)
  local_file <- file.path(
    conn$local_path,
    gsub("/", .Platform$file.sep, rel_name, fixed = TRUE)
  )
  .check_local_dest(local_file, conn$local_path)
  fs::dir_create(dirname(local_file))
  gd_download(conn$adapter, drive_path, local_file)
  invisible(NULL)
}

#' Path of the backup file written before Drive overwrites a conflicting file
#'
#' `<dir>/<stem>.conflict-<UTC timestamp>.<ext>`, or
#' `<dir>/<name>.conflict-<UTC timestamp>` when the name has no extension.
#' The timestamp has no `:`, so the name is valid on Windows.
#'
#' @param conn A `gdpins_raw_conn`.
#' @param rel_name Character scalar. Relative file name.
#'
#' @return Character scalar, a local path.
#' @keywords internal
.raw_conflict_backup_path <- function(conn, rel_name) {
  local_file <- file.path(
    conn$local_path,
    gsub("/", .Platform$file.sep, rel_name, fixed = TRUE)
  )
  ts   <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
  base <- basename(local_file)
  ext  <- tools::file_ext(base)
  stem <- tools::file_path_sans_ext(base)
  name <- if (nzchar(ext) && nzchar(stem)) {
    paste0(stem, ".conflict-", ts, ".", ext)
  } else {
    paste0(base, ".conflict-", ts)
  }
  file.path(dirname(local_file), name)
}

#' Back up a conflicting local file before Drive overwrites it
#'
#' @inheritParams .raw_conflict_backup_path
#'
#' @return The backup path, or `NULL` when there is no local file. Errors if
#'   the backup path already exists (never overwrites).
#' @keywords internal
.raw_conflict_backup <- function(conn, rel_name) {
  .check_rel_name(rel_name)
  local_file <- file.path(
    conn$local_path,
    gsub("/", .Platform$file.sep, rel_name, fixed = TRUE)
  )
  .check_local_dest(local_file, conn$local_path)
  if (!file.exists(local_file)) return(NULL)
  backup <- .raw_conflict_backup_path(conn, rel_name)
  fs::file_copy(local_file, backup, overwrite = FALSE)
  backup
}

#' @keywords internal
.prompt_raw_conflict <- function(fname, row) {
  drv_md5 <- row$drive_md5
  loc_md5 <- row$local_md5
  cli::cli_inform(c(
    "!" = "Conflict on file {.val {fname}}.",
    " " = "Drive md5: {drv_md5}",
    " " = "Local md5: {loc_md5}"
  ))
  choice <- readline(prompt = "Keep [l]ocal, [d]rive, or [s]kip? ")
  choice <- tolower(trimws(choice))
  if (startsWith(choice, "l")) "local"
  else if (startsWith(choice, "d")) "drive"
  else "skip"
}
